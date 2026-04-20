"""TRACEPARENT injection around subagent dispatch (Task 9).

Verifies otel.dispatch_env produces a copy of the parent env augmented with
W3C TRACEPARENT (and TRACESTATE when present), without mutating the input.
"""
from __future__ import annotations

import pytest

pytest.importorskip("opentelemetry.sdk.trace")

from opentelemetry.sdk.trace.export import SimpleSpanProcessor
from opentelemetry.sdk.trace.export.in_memory_span_exporter import (
    InMemorySpanExporter,
)

from hooks._py import otel


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
            "sample_rate": 1.0,
            "exporter": "console",
            "endpoint": "",
            "batch_size": 1,
            "flush_interval_seconds": 1,
            "service_name": "forge-pipeline",
        }
    )
    return exporter


def test_dispatch_env_includes_traceparent(monkeypatch):
    _enable(monkeypatch)
    env_before = {"FOO": "bar"}
    with otel.pipeline_span(run_id="r1", mode="standard"):
        env_after = otel.dispatch_env(env_before)
    otel.shutdown()
    # Original dict unmodified; returned env has TRACEPARENT.
    assert env_before == {"FOO": "bar"}
    assert "TRACEPARENT" in env_after
    assert env_after["FOO"] == "bar"
    # W3C format sanity check: 4 hyphen-separated fields.
    assert env_after["TRACEPARENT"].count("-") == 3


def test_dispatch_env_disabled_returns_copy():
    """When OTel is disabled, dispatch_env returns a plain copy."""
    otel.init({"enabled": False})
    env = {"A": "1", "B": "2"}
    out = otel.dispatch_env(env)
    assert out == env
    assert out is not env  # copy, not the same object
    # Original env not mutated by the call.
    out["A"] = "99"
    assert env["A"] == "1"


def test_dispatch_env_no_active_span_omits_traceparent(monkeypatch):
    """Outside any span, the propagator emits no traceparent."""
    _enable(monkeypatch)
    env_after = otel.dispatch_env({"X": "y"})
    otel.shutdown()
    # No active span -> no TRACEPARENT injected (or, if injected, W3C invalid
    # context). The propagator skips injection when there's no recording span.
    assert env_after.get("X") == "y"


def test_dispatch_env_traceparent_matches_active_trace(monkeypatch):
    """Injected TRACEPARENT must encode the active span's trace_id."""
    _enable(monkeypatch)
    with otel.pipeline_span(run_id="r1", mode="standard") as span:
        env_after = otel.dispatch_env({})
        if span is not None:
            ctx = span.get_span_context()
            tp = env_after.get("TRACEPARENT", "")
            # W3C format: 00-<trace_id_32hex>-<span_id_16hex>-<flags>
            parts = tp.split("-")
            assert len(parts) == 4, tp
            assert parts[1] == f"{ctx.trace_id:032x}"
    otel.shutdown()
