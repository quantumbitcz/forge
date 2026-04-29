"""Authoritative replay + CLI (Task 10).

Verifies otel.replay() rebuilds the canonical span hierarchy from a fsync'd
event log, and that the ``python -m hooks._py.otel_cli replay`` entry point
runs end-to-end with a console exporter.
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

import pytest

pytest.importorskip("opentelemetry.sdk.trace")

from opentelemetry.sdk.trace.export import SimpleSpanProcessor
from opentelemetry.sdk.trace.export.in_memory_span_exporter import (
    InMemorySpanExporter,
)

from hooks._py import otel

FIXTURE = Path(__file__).parent.parent / "fixtures" / "events-sample.jsonl"


def test_replay_emits_deterministic_spans(monkeypatch):
    exporter = InMemorySpanExporter()
    monkeypatch.setattr(
        otel,
        "_build_processor",
        lambda cfg: SimpleSpanProcessor(exporter),
        raising=False,
    )
    n = otel.replay(
        events_path=str(FIXTURE),
        config={
            "enabled": True,
            "sample_rate": 1.0,
            "exporter": "console",
            "endpoint": "",
            "batch_size": 1,
            "flush_interval_seconds": 1,
            "service_name": "forge-pipeline",
        },
    )
    assert n == 3  # pipeline + stage + agent
    spans = exporter.get_finished_spans()
    names = sorted(s.name for s in spans)
    assert names == ["agent.fg-200-planner", "pipeline", "stage.PLANNING"]
    trace_ids = {s.context.trace_id for s in spans}
    assert len(trace_ids) == 1  # one trace, three spans


def test_replay_disabled_returns_zero(tmp_path):
    n = otel.replay(events_path=str(FIXTURE), config={"enabled": False})
    assert n == 0


def test_replay_propagates_agent_close_attrs(monkeypatch):
    """Tokens, cost, and finish reasons land on the agent span."""
    exporter = InMemorySpanExporter()
    monkeypatch.setattr(
        otel,
        "_build_processor",
        lambda cfg: SimpleSpanProcessor(exporter),
        raising=False,
    )
    otel.replay(
        events_path=str(FIXTURE),
        config={
            "enabled": True,
            "sample_rate": 1.0,
            "exporter": "console",
            "endpoint": "",
            "batch_size": 1,
            "flush_interval_seconds": 1,
            "service_name": "forge-pipeline",
        },
    )
    a = next(s for s in exporter.get_finished_spans() if s.name == "agent.fg-200-planner")
    assert a.attributes["gen_ai.tokens.input"] == 1200
    assert a.attributes["gen_ai.tokens.output"] == 800
    assert a.attributes["gen_ai.tokens.total"] == 2000
    assert a.attributes["gen_ai.cost.usd"] == pytest.approx(0.018)
    assert a.attributes["gen_ai.tool.calls"] == 5


def test_replay_cli_runs(tmp_path):
    """Running the CLI as a module prints a one-line success summary."""
    out = subprocess.run(
        [
            sys.executable,
            "-m",
            "hooks._py.otel_cli",
            "replay",
            "--from-events",
            str(FIXTURE),
            "--exporter",
            "console",
            "--sample-rate",
            "1.0",
        ],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert out.returncode == 0, out.stderr
    assert "replayed" in out.stdout.lower()
    # The fixture exercises 3 spans (pipeline + stage + agent).
    assert "3 spans" in out.stdout


def test_replay_cli_requires_subcommand():
    out = subprocess.run(
        [sys.executable, "-m", "hooks._py.otel_cli"],
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert out.returncode != 0
    assert "required" in out.stderr.lower() or "usage" in out.stderr.lower()
