"""events.jsonl -> OTel span translator (Task 7).

Verifies the parser yields ordered open/close ops with semconv attributes.
"""
from __future__ import annotations

from pathlib import Path

import pytest

pytest.importorskip("opentelemetry.sdk.trace")

from hooks._py.event_to_span import iter_span_ops

FIXTURE = Path(__file__).parent.parent / "fixtures" / "events-sample.jsonl"


def test_fixture_parses_to_ordered_ops():
    """Expected sequence: 6 events -> 6 ordered open/close ops."""
    ops = list(iter_span_ops(str(FIXTURE)))
    kinds = [(o.kind, o.name) for o in ops]
    assert kinds == [
        ("open", "pipeline"),
        ("open", "stage.PLANNING"),
        ("open", "agent.fg-200-planner"),
        ("close", "agent.fg-200-planner"),
        ("close", "stage.PLANNING"),
        ("close", "pipeline"),
    ]


def test_op_carries_attributes():
    ops = list(iter_span_ops(str(FIXTURE)))
    agent_open = next(
        o
        for o in ops
        if o.kind == "open" and o.name == "agent.fg-200-planner"
    )
    assert agent_open.attrs["gen_ai.agent.name"] == "fg-200-planner"
    assert agent_open.attrs["gen_ai.request.model"] == "claude-sonnet-4-7"
    assert agent_open.attrs["gen_ai.agent.description"] == "Pipeline planner"

    agent_close = next(
        o
        for o in ops
        if o.kind == "close" and o.name == "agent.fg-200-planner"
    )
    assert agent_close.attrs["gen_ai.tokens.input"] == 1200
    assert agent_close.attrs["gen_ai.tokens.output"] == 800
    assert agent_close.attrs["gen_ai.tokens.total"] == 2000
    assert agent_close.attrs["gen_ai.cost.usd"] == pytest.approx(0.018)
    assert agent_close.attrs["gen_ai.tool.calls"] == 5
    assert agent_close.attrs["gen_ai.response.finish_reasons"] == ("stop",)


def test_pipeline_open_carries_run_id_and_mode():
    ops = list(iter_span_ops(str(FIXTURE)))
    pipeline_open = next(
        o for o in ops if o.kind == "open" and o.name == "pipeline"
    )
    assert pipeline_open.attrs["forge.run_id"] == "r-sample"
    assert pipeline_open.attrs["forge.mode"] == "standard"
    assert pipeline_open.attrs["gen_ai.agent.name"] == "forge-pipeline"


def test_stage_close_carries_stage_attr():
    ops = list(iter_span_ops(str(FIXTURE)))
    stage_close = next(
        o for o in ops if o.kind == "close" and o.name == "stage.PLANNING"
    )
    assert stage_close.attrs["forge.stage"] == "PLANNING"


def test_agent_close_without_cost_marks_unknown(tmp_path):
    """agent.close without cost_usd field flags forge.cost.unknown=True."""
    log = tmp_path / "ev.jsonl"
    log.write_text(
        '{"type": "agent.close", "agent_name": "fg-x", '
        '"tokens_input": 1, "tokens_output": 2}\n'
    )
    ops = list(iter_span_ops(str(log)))
    assert len(ops) == 1
    assert ops[0].attrs.get("forge.cost.unknown") is True
    assert "gen_ai.cost.usd" not in ops[0].attrs


def test_unknown_event_type_is_ignored(tmp_path):
    log = tmp_path / "ev.jsonl"
    log.write_text(
        '{"type": "unknown.event", "garbage": true}\n'
        '{"type": "pipeline.open", "run_id": "r-y", "mode": "bugfix"}\n'
    )
    ops = list(iter_span_ops(str(log)))
    assert len(ops) == 1
    assert ops[0].name == "pipeline"


def test_blank_lines_are_skipped(tmp_path):
    log = tmp_path / "ev.jsonl"
    log.write_text(
        "\n\n"
        '{"type": "pipeline.open", "run_id": "r-blank", "mode": "standard"}\n'
        "\n"
    )
    ops = list(iter_span_ops(str(log)))
    assert [(o.kind, o.name) for o in ops] == [("open", "pipeline")]
