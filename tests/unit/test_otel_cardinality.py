"""Span-name cardinality budget enforcement (Task 6).

Backends meter unique span names; only BOUNDED_ATTRS values may appear in
names. This test asserts run_id and other unbounded values never leak into
span names.
"""

from __future__ import annotations

import inspect

import pytest

pytest.importorskip("opentelemetry.sdk.trace")

from opentelemetry.sdk.trace.export import SimpleSpanProcessor
from opentelemetry.sdk.trace.export.in_memory_span_exporter import (
    InMemorySpanExporter,
)

from hooks._py import otel
from hooks._py import otel_attributes as A


def _enable(monkeypatch):
    exporter = InMemorySpanExporter()
    monkeypatch.setattr(
        otel,
        "_build_processor",
        lambda cfg: SimpleSpanProcessor(exporter),
        raising=False,
    )
    otel.init(
        {
            "enabled": True,
            "service_name": "forge-pipeline",
            "sample_rate": 1.0,
            "exporter": "console",
            "endpoint": "",
            "batch_size": 1,
            "flush_interval_seconds": 1,
        }
    )
    return exporter


def test_run_id_never_appears_in_span_names(monkeypatch):
    exporter = _enable(monkeypatch)
    run_id = "e8b3e1c4-ffee-4f0b-9a42-7d6dcf6cb1d0"
    with (
        otel.pipeline_span(run_id=run_id, mode="standard"),
        otel.stage_span("EXPLORING"),
        otel.agent_span(
            name="fg-100-orchestrator",
            model="claude-sonnet-4-7",
            description="Coordinator",
        ),
    ):
        pass
    otel.shutdown()
    for span in exporter.get_finished_spans():
        # Span NAME must never contain a high-cardinality attribute.
        assert run_id not in span.name, f"run_id leaked into span name: {span.name}"
    # run_id must still be present as an attribute on the pipeline span.
    pipeline = next(s for s in exporter.get_finished_spans() if s.name == "pipeline")
    assert pipeline.attributes[A.FORGE_RUN_ID] == run_id


def test_span_names_are_enumerable():
    """Expected span-name set is bounded + deterministic.

    Allowed prefixes: pipeline, stage., agent., tool., batch.
    """
    allowed_prefixes = ("pipeline", "stage.", "agent.", "tool.", "batch.")
    src = inspect.getsource(otel)
    for prefix in allowed_prefixes:
        # The prefix must appear in the otel source as a span-name template.
        assert prefix in src, f"expected span-name prefix {prefix!r} in otel.py source"


def test_no_unbounded_attribute_value_in_span_names(monkeypatch):
    """Tool call IDs (UUIDs) and agent IDs must never reach span names."""
    exporter = _enable(monkeypatch)
    call_id = "tool-call-3e2f81a4-9c7c-4f2a-bb85-71e1aaaaaaaa"
    with (
        otel.pipeline_span(run_id="r-x", mode="standard"),
        otel.tool_span(name="Read", call_id=call_id),
    ):
        pass
    otel.shutdown()
    for span in exporter.get_finished_spans():
        assert call_id not in span.name, f"tool call_id leaked into span name: {span.name}"
    tool = next(s for s in exporter.get_finished_spans() if s.name.startswith("tool."))
    assert tool.attributes[A.GEN_AI_TOOL_CALL_ID] == call_id


def test_agent_name_is_bounded_and_used_in_span_name(monkeypatch):
    """gen_ai.agent.name is BOUNDED -- safe to use as span-name suffix."""
    exporter = _enable(monkeypatch)
    with (
        otel.pipeline_span(run_id="r1", mode="standard"),
        otel.agent_span(
            name="fg-200-planner",
            model="claude-sonnet-4-7",
            description="planner",
        ),
    ):
        pass
    otel.shutdown()
    names = {s.name for s in exporter.get_finished_spans()}
    assert "agent.fg-200-planner" in names
    # Sanity: agent name attribute matches the suffix.
    a = next(s for s in exporter.get_finished_spans() if s.name.startswith("agent."))
    assert a.attributes[A.GEN_AI_AGENT_NAME] == "fg-200-planner"
