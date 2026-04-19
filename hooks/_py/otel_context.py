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
from opentelemetry.trace.propagation.tracecontext import (
    TraceContextTextMapPropagator,
)

TRACEPARENT_ENV = "TRACEPARENT"
TRACESTATE_ENV = "TRACESTATE"

_PROPAGATOR = TraceContextTextMapPropagator()


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


# --- W3C Trace Context propagation ----------------------------------------


def inject_traceparent_env(env: dict[str, str]) -> None:
    """Serialize the active span context into the given env dict.

    Called before dispatching a subagent via the Task tool. The Task tool
    inherits parent env, so writing ``TRACEPARENT`` into the child env is
    sufficient for propagation.
    """
    _PROPAGATOR.inject(env)  # writes 'traceparent' (lowercase) per W3C
    # Promote to uppercase env-var form expected by subagent init.
    if "traceparent" in env:
        env[TRACEPARENT_ENV] = env.pop("traceparent")
    if "tracestate" in env:
        env[TRACESTATE_ENV] = env.pop("tracestate")


def extract_parent_from_env():
    """Rehydrate a parent span context from TRACEPARENT in the environment.

    Returns ``None`` when the env var is absent. The returned ``Context``
    must be passed to
    ``TracerProvider.get_tracer(...).start_as_current_span(ctx=...)`` so the
    first local span becomes a child of the external parent.

    Respects ``sampled=0`` in the inbound traceparent: when the parent was
    not sampled, the ``ParentBased`` sampler yields a non-recording span in
    the child, which is the correct behaviour for distributed tracing.
    """
    import os as _os

    tp = _os.environ.get(TRACEPARENT_ENV)
    if not tp:
        return None
    carrier = {"traceparent": tp}
    ts = _os.environ.get(TRACESTATE_ENV)
    if ts:
        carrier["tracestate"] = ts
    return _PROPAGATOR.extract(carrier)
