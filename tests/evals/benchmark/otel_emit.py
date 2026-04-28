"""OTel GenAI-semconv emitter for benchmark runs.

Delegates to hooks/_py/otel.replay for authoritative emission (per shared/observability.md).
Falls back to no-op when OTel is unavailable (dep-gated).
"""
from __future__ import annotations
from typing import Any


def _replay(name: str, attrs: dict[str, Any]) -> None:
    try:
        from hooks._py.otel import replay  # type: ignore
        replay(name, attrs)
    except Exception:
        # Dep-gated: opentelemetry not installed. Spec §Docs says OTel is optional.
        return


def emit_benchmark_span(*, entry_id: str, os: str, model: str, solved: bool,
                        duration_s: int, cost_usd: float) -> None:
    attrs: dict[str, Any] = {
        "forge.benchmark.entry_id": entry_id,
        "forge.benchmark.os": os,
        "forge.benchmark.model": model,
        "forge.benchmark.solved": bool(solved),
        "forge.benchmark.duration_s": int(duration_s),
        "forge.benchmark.cost_usd": float(cost_usd),
    }
    _replay("forge.benchmark.run", attrs)
