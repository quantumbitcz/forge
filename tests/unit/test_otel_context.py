import pytest

pytest.importorskip("opentelemetry.trace")

from opentelemetry import trace  # noqa: E402
from opentelemetry.sdk.trace import TracerProvider  # noqa: E402
from opentelemetry.sdk.trace.sampling import ALWAYS_ON  # noqa: E402

from hooks._py.otel_context import (  # noqa: E402
    TRACEPARENT_ENV,
    extract_parent_from_env,
    inject_traceparent_env,
)


def _provider():
    return TracerProvider(sampler=ALWAYS_ON)


def test_inject_sets_traceparent_env(monkeypatch):
    monkeypatch.delenv(TRACEPARENT_ENV, raising=False)
    p = _provider()
    trace.set_tracer_provider(p)
    tracer = p.get_tracer("t")
    with tracer.start_as_current_span("root") as span:
        env: dict[str, str] = {}
        inject_traceparent_env(env)
        assert TRACEPARENT_ENV in env
        tp = env[TRACEPARENT_ENV]
        # W3C format: {version}-{trace_id:32}-{span_id:16}-{flags:2}
        parts = tp.split("-")
        assert len(parts) == 4
        assert parts[0] == "00"
        assert len(parts[1]) == 32
        assert len(parts[2]) == 16
        assert len(parts[3]) == 2
        # trace_id matches active span
        ctx = span.get_span_context()
        assert parts[1] == format(ctx.trace_id, "032x")


def test_extract_rehydrates_parent(monkeypatch):
    tp = "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"
    monkeypatch.setenv(TRACEPARENT_ENV, tp)
    ctx = extract_parent_from_env()
    assert ctx is not None
    span = trace.get_current_span(ctx)
    sc = span.get_span_context()
    assert format(sc.trace_id, "032x") == "4bf92f3577b34da6a3ce929d0e0e4736"
    assert format(sc.span_id, "016x") == "00f067aa0ba902b7"
    assert sc.trace_flags == 0x01


def test_extract_respects_sampled_zero(monkeypatch):
    # Inbound parent with sampled=0 -> child must propagate that decision.
    tp = "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-00"
    monkeypatch.setenv(TRACEPARENT_ENV, tp)
    ctx = extract_parent_from_env()
    sc = trace.get_current_span(ctx).get_span_context()
    assert sc.trace_flags == 0x00


def test_extract_missing_env_returns_none(monkeypatch):
    monkeypatch.delenv(TRACEPARENT_ENV, raising=False)
    assert extract_parent_from_env() is None
