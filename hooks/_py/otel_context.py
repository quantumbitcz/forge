"""W3C trace-context helpers + sampler factory.

Sampler: ``ParentBased(TraceIdRatioBased(sample_rate))``.

Why ParentBased? With distributed tracing (TRACEPARENT propagation to
subagents), each child process must honour the root decision. Otherwise
children make independent sampling decisions and produce orphan partial
traces, breaking Phase 09 success criterion 3 ("every subagent span shares
the pipeline's trace_id").
"""

from __future__ import annotations

from opentelemetry.sdk.trace.sampling import (
    ALWAYS_OFF,
    ALWAYS_ON,
    ParentBased,
    Sampler,
    TraceIdRatioBased,
)


def build_sampler(*, sample_rate: float) -> Sampler:
    """Return a ParentBased sampler honouring the configured root rate."""
    if not isinstance(sample_rate, (int, float)) or isinstance(sample_rate, bool):
        raise TypeError(
            f"sample_rate must be a number, got {type(sample_rate).__name__}"
        )
    if not 0.0 <= float(sample_rate) <= 1.0:
        raise ValueError(f"sample_rate must be in [0.0, 1.0], got {sample_rate}")
    rate = float(sample_rate)
    if rate == 1.0:
        root: Sampler = ALWAYS_ON
    elif rate == 0.0:
        root = ALWAYS_OFF
    else:
        root = TraceIdRatioBased(rate)
    return ParentBased(root=root)
