"""Verify real OTel span emission with semconv attributes.

Tasks 5 + 6: end-to-end span open/close with bounded names and gen_ai.*
attributes. Uses the in-memory exporter to avoid network I/O.
"""

from __future__ import annotations

import pytest

pytest.importorskip("opentelemetry.sdk.trace")

from opentelemetry.sdk.trace.export import SimpleSpanProcessor
from opentelemetry.sdk.trace.export.in_memory_span_exporter import (
    InMemorySpanExporter,
)

from hooks._py import otel
from hooks._py import otel_attributes as A


def _enable_with_memory_exporter(monkeypatch):
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


def test_pipeline_span_carries_semconv_attrs(monkeypatch):
    exporter = _enable_with_memory_exporter(monkeypatch)
    with otel.pipeline_span(run_id="r-emit-1", mode="standard"):
        pass
    otel.shutdown()
    spans = exporter.get_finished_spans()
    assert len(spans) == 1
    s = spans[0]
    assert s.name == "pipeline"
    assert s.attributes[A.GEN_AI_AGENT_NAME] == "forge-pipeline"
    assert s.attributes[A.GEN_AI_OPERATION_NAME] == A.OP_INVOKE_AGENT
    assert s.attributes[A.FORGE_RUN_ID] == "r-emit-1"
    assert s.attributes[A.FORGE_MODE] == "standard"


def test_nested_stage_and_agent_spans(monkeypatch):
    exporter = _enable_with_memory_exporter(monkeypatch)
    with (
        otel.pipeline_span(run_id="r1", mode="standard"),
        otel.stage_span("EXPLORING"),
        otel.agent_span(
            name="fg-100-orchestrator",
            model="claude-sonnet-4-7",
            description="Coordinator",
        ),
    ):
        otel.record_agent_result(
            {
                "tokens_input": 100,
                "tokens_output": 200,
                "cost_usd": 0.005,
                "tool_calls": 3,
                "finish_reasons": ["stop"],
            }
        )
    otel.shutdown()
    by_name = {s.name: s for s in exporter.get_finished_spans()}
    assert set(by_name) == {
        "pipeline",
        "stage.EXPLORING",
        "agent.fg-100-orchestrator",
    }
    a = by_name["agent.fg-100-orchestrator"]
    assert a.attributes[A.GEN_AI_AGENT_NAME] == "fg-100-orchestrator"
    assert a.attributes[A.GEN_AI_REQUEST_MODEL] == "claude-sonnet-4-7"
    assert a.attributes[A.GEN_AI_TOKENS_INPUT] == 100
    assert a.attributes[A.GEN_AI_TOKENS_OUTPUT] == 200
    assert a.attributes[A.GEN_AI_TOKENS_TOTAL] == 300
    assert a.attributes[A.GEN_AI_COST_USD] == 0.005
    assert a.attributes[A.GEN_AI_TOOL_CALLS] == 3
    # Parent/child hierarchy: all three share trace_id.
    trace_ids = {s.context.trace_id for s in exporter.get_finished_spans()}
    assert len(trace_ids) == 1


def test_tool_span_uses_execute_tool_op(monkeypatch):
    exporter = _enable_with_memory_exporter(monkeypatch)
    with (
        otel.pipeline_span(run_id="r1", mode="standard"),
        otel.tool_span(name="Read", call_id="call-abc-123"),
    ):
        pass
    otel.shutdown()
    by_name = {s.name: s for s in exporter.get_finished_spans()}
    t = by_name["tool.Read"]
    assert t.attributes[A.GEN_AI_OPERATION_NAME] == A.OP_EXECUTE_TOOL
    assert t.attributes[A.GEN_AI_TOOL_NAME] == "Read"
    assert t.attributes[A.GEN_AI_TOOL_CALL_ID] == "call-abc-123"


def test_record_agent_result_marks_unknown_cost(monkeypatch):
    exporter = _enable_with_memory_exporter(monkeypatch)
    with (
        otel.pipeline_span(run_id="r1", mode="standard"),
        otel.agent_span(
            name="fg-200-planner",
            model="unknown-model",
            description="planner",
        ),
    ):
        otel.record_agent_result({"tokens_input": 5, "tokens_output": 10})
    otel.shutdown()
    a = next(s for s in exporter.get_finished_spans() if s.name.startswith("agent."))
    assert a.attributes.get(A.FORGE_COST_UNKNOWN) is True
    assert A.GEN_AI_COST_USD not in a.attributes
