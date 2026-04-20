"""Opt-in OpenInference compatibility attribute mirroring (Phase 09 Task 11)."""

from __future__ import annotations

import pytest

pytest.importorskip("opentelemetry.sdk.trace")

from opentelemetry.sdk.trace.export import SimpleSpanProcessor
from opentelemetry.sdk.trace.export.in_memory_span_exporter import (
    InMemorySpanExporter,
)

from hooks._py import otel


def _enable(monkeypatch, openinference: bool):
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
            "sample_rate": 1.0,
            "exporter": "console",
            "endpoint": "",
            "batch_size": 1,
            "flush_interval_seconds": 1,
            "openinference_compat": openinference,
        }
    )
    return exporter


def test_openinference_off_emits_only_gen_ai(monkeypatch):
    exporter = _enable(monkeypatch, openinference=False)
    with otel.pipeline_span(run_id="r1", mode="standard"):
        with otel.agent_span(
            name="fg-100-orchestrator",
            model="sonnet",
            description="Coordinator",
        ):
            pass
    otel.shutdown()
    agent = next(
        s for s in exporter.get_finished_spans() if s.name.startswith("agent.")
    )
    assert "openinference.span.kind" not in agent.attributes


def test_openinference_on_emits_duplicate_attrs(monkeypatch):
    exporter = _enable(monkeypatch, openinference=True)
    with otel.pipeline_span(run_id="r1", mode="standard"):
        with otel.agent_span(
            name="fg-100-orchestrator",
            model="sonnet",
            description="Coordinator",
        ):
            otel.record_agent_result(
                {
                    "tokens_input": 10,
                    "tokens_output": 20,
                    "cost_usd": 0.001,
                    "tool_calls": 0,
                }
            )
    otel.shutdown()
    agent = next(
        s for s in exporter.get_finished_spans() if s.name.startswith("agent.")
    )
    # OpenInference mirrors.
    assert agent.attributes["openinference.span.kind"] == "AGENT"
    assert agent.attributes["llm.token_count.prompt"] == 10
    assert agent.attributes["llm.token_count.completion"] == 20
    assert agent.attributes["llm.token_count.total"] == 30
