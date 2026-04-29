"""OTel GenAI-semconv emitter for benchmark runs.

Wires through to OpenTelemetry when available; falls back to a no-op when the
SDK is not installed (dep-gated). Tests monkey-patch ``_replay`` to capture
spans without requiring opentelemetry on the runner.
"""

from __future__ import annotations

from typing import Any


def _replay(name: str, attrs: dict[str, Any]) -> None:
    try:
        from opentelemetry import trace  # type: ignore[import-not-found]
    except ImportError:
        # Dep-gated: opentelemetry not installed. Spec §Docs says OTel is optional.
        return
    tracer = trace.get_tracer("forge.benchmark")
    with tracer.start_as_current_span(name) as span:
        for key, value in attrs.items():
            span.set_attribute(key, value)


def emit_benchmark_span(
    *, entry_id: str, os: str, model: str, solved: bool, duration_s: int, cost_usd: float
) -> None:
    attrs: dict[str, Any] = {
        "forge.benchmark.entry_id": entry_id,
        "forge.benchmark.os": os,
        "forge.benchmark.model": model,
        "forge.benchmark.solved": bool(solved),
        "forge.benchmark.duration_s": int(duration_s),
        "forge.benchmark.cost_usd": float(cost_usd),
    }
    _replay("forge.benchmark.run", attrs)
