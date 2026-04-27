"""Public OTel GenAI semconv emitter.

Durability contract:
  - Live stream is BEST-EFFORT. ``BatchSpanProcessor`` flushes every
    ``flush_interval_seconds`` or when ``batch_size`` is reached. A hard crash
    (SIGKILL, OOM, power loss) drops the in-memory batch.
  - ``replay()`` is the AUTHORITATIVE recovery path. It rebuilds spans from
    ``.forge/events.jsonl`` and re-emits them deterministically. Event log
    writes are fsync'd by Phase F07 (``state_write.py``), so replay is the
    source of truth. Schedule ``replay`` in CI failure handlers.
"""

from __future__ import annotations

import contextlib
import dataclasses
import logging
import threading
from typing import Any, Iterator

from hooks._py import otel_attributes as A

log = logging.getLogger(__name__)


@dataclasses.dataclass
class EmitterState:
    enabled: bool = False
    tracer: Any = None
    provider: Any = None
    cfg: dict = dataclasses.field(default_factory=dict)


_STATE = EmitterState()
_LOCK = threading.Lock()
# span_id -> pending result, set by record_agent_result and applied at agent_span close
_TOTAL_RESULT: dict[int, dict] = {}


def _build_processor(cfg: dict):
    from opentelemetry.sdk.trace.export import BatchSpanProcessor

    from hooks._py.otel_exporters import build_exporter

    exporter = build_exporter(
        kind=cfg.get("exporter", "grpc"),
        endpoint=cfg.get("endpoint", ""),
    )
    return BatchSpanProcessor(
        exporter,
        max_export_batch_size=int(cfg.get("batch_size", 32)),
        schedule_delay_millis=int(
            float(cfg.get("flush_interval_seconds", 2)) * 1000
        ),
    )


def init(config: dict, parent_traceparent: str | None = None) -> EmitterState:
    """Initialise emitter. Returns a no-op state when disabled or on import error."""
    global _STATE
    with _LOCK:
        if not config.get("enabled", False):
            _STATE = EmitterState(enabled=False, cfg=config)
            return _STATE
        try:
            from opentelemetry import trace
            from opentelemetry.sdk.resources import SERVICE_NAME, Resource
            from opentelemetry.sdk.trace import TracerProvider

            from hooks._py.otel_context import build_sampler
        except ImportError:
            log.warning("opentelemetry not installed -- OTel export disabled")
            _STATE = EmitterState(enabled=False, cfg=config)
            return _STATE

        resource = Resource.create(
            {SERVICE_NAME: config.get("service_name", "forge-pipeline")}
        )
        sampler = build_sampler(
            sample_rate=float(config.get("sample_rate", 1.0))
        )
        provider = TracerProvider(resource=resource, sampler=sampler)
        provider.add_span_processor(_build_processor(config))
        trace.set_tracer_provider(provider)
        tracer = provider.get_tracer("forge.pipeline")
        _STATE = EmitterState(
            enabled=True, tracer=tracer, provider=provider, cfg=config
        )
        return _STATE


def shutdown() -> None:
    """Flush pending spans and tear down the provider."""
    with _LOCK:
        if _STATE.provider is not None:
            _STATE.provider.shutdown()


@contextlib.contextmanager
def pipeline_span(*, run_id: str, mode: str) -> Iterator[Any]:
    """Open the root pipeline span. Span name is bounded: ``pipeline``."""
    if not _STATE.enabled:
        yield None
        return
    with _STATE.tracer.start_as_current_span("pipeline") as span:
        span.set_attribute(A.GEN_AI_AGENT_NAME, "forge-pipeline")
        span.set_attribute(A.GEN_AI_OPERATION_NAME, A.OP_INVOKE_AGENT)
        span.set_attribute(A.FORGE_RUN_ID, run_id)
        span.set_attribute(A.FORGE_MODE, mode)
        yield span


@contextlib.contextmanager
def stage_span(name: str) -> Iterator[Any]:
    """Open a stage span. Span name is bounded: ``stage.<STAGE>``."""
    if not _STATE.enabled:
        yield None
        return
    with _STATE.tracer.start_as_current_span(f"stage.{name}") as span:
        span.set_attribute(A.FORGE_STAGE, name)
        yield span


@contextlib.contextmanager
def agent_span(
    *, name: str, model: str, description: str
) -> Iterator[Any]:
    """Open an agent span. Span name is bounded: ``agent.<agent_name>``."""
    if not _STATE.enabled:
        yield None
        return
    with _STATE.tracer.start_as_current_span(f"agent.{name}") as span:
        span.set_attribute(A.GEN_AI_AGENT_NAME, name)
        span.set_attribute(A.GEN_AI_AGENT_DESCRIPTION, description)
        span.set_attribute(A.GEN_AI_OPERATION_NAME, A.OP_INVOKE_AGENT)
        span.set_attribute(A.GEN_AI_REQUEST_MODEL, model)
        if _STATE.cfg.get("openinference_compat", False):
            span.set_attribute("openinference.span.kind", "AGENT")
            span.set_attribute("llm.model_name", model)
            span.set_attribute("agent.name", name)
        sid = span.get_span_context().span_id
        _TOTAL_RESULT[sid] = {}
        try:
            yield span
        finally:
            result = _TOTAL_RESULT.pop(sid, {})
            if result:
                _apply_agent_result(span, result)


def _apply_agent_result(span: Any, r: dict) -> None:
    ti = int(r.get("tokens_input", 0))
    to = int(r.get("tokens_output", 0))
    span.set_attribute(A.GEN_AI_TOKENS_INPUT, ti)
    span.set_attribute(A.GEN_AI_TOKENS_OUTPUT, to)
    span.set_attribute(A.GEN_AI_TOKENS_TOTAL, ti + to)
    if "cost_usd" in r and r["cost_usd"] is not None:
        span.set_attribute(A.GEN_AI_COST_USD, float(r["cost_usd"]))
    else:
        span.set_attribute(A.FORGE_COST_UNKNOWN, True)
    if "tool_calls" in r and r["tool_calls"] is not None:
        span.set_attribute(A.GEN_AI_TOOL_CALLS, int(r["tool_calls"]))
    if "finish_reasons" in r and r["finish_reasons"]:
        span.set_attribute(
            A.GEN_AI_RESPONSE_FINISH_REASONS, tuple(r["finish_reasons"])
        )
    if "agent_id" in r:
        span.set_attribute(A.GEN_AI_AGENT_ID, str(r["agent_id"]))
    if _STATE.cfg.get("openinference_compat", False):
        span.set_attribute("llm.token_count.prompt", ti)
        span.set_attribute("llm.token_count.completion", to)
        span.set_attribute("llm.token_count.total", ti + to)


@contextlib.contextmanager
def tool_span(*, name: str, call_id: str | None = None) -> Iterator[Any]:
    """Open a tool span. Span name is bounded: ``tool.<tool_name>``."""
    if not _STATE.enabled:
        yield None
        return
    with _STATE.tracer.start_as_current_span(f"tool.{name}") as span:
        span.set_attribute(A.GEN_AI_OPERATION_NAME, A.OP_EXECUTE_TOOL)
        span.set_attribute(A.GEN_AI_TOOL_NAME, name)
        if call_id:
            span.set_attribute(A.GEN_AI_TOOL_CALL_ID, call_id)
        yield span


def record_agent_result(result: dict) -> None:
    """Attach result to the currently active agent span.

    Phase 6 keys honored on `result` (all optional; default 0/empty):
      - budget_total_usd          -> forge.run.budget_total_usd
      - budget_remaining_usd      -> forge.run.budget_remaining_usd
      - tier_estimate_usd         -> forge.agent.tier_estimate_usd
      - tier_original             -> forge.agent.tier_original
      - tier_used                 -> forge.agent.tier_used
      - throttle_reason           -> forge.cost.throttle_reason
    """
    if not _STATE.enabled:
        return
    from opentelemetry import trace

    span = trace.get_current_span()
    if span is None:
        return

    # Phase 6 cost attributes (best-effort; never raise).
    for src, attr in (
        ("budget_total_usd", A.FORGE_RUN_BUDGET_TOTAL_USD),
        ("budget_remaining_usd", A.FORGE_RUN_BUDGET_REMAINING_USD),
        ("tier_estimate_usd", A.FORGE_AGENT_TIER_ESTIMATE_USD),
        ("tier_original", A.FORGE_AGENT_TIER_ORIGINAL),
        ("tier_used", A.FORGE_AGENT_TIER_USED),
        ("throttle_reason", A.FORGE_COST_THROTTLE_REASON),
    ):
        if src in result:
            try:
                span.set_attribute(attr, result[src])
            except Exception:
                pass

    sid = span.get_span_context().span_id
    # If we are inside an agent_span, buffer the result so _apply_agent_result
    # picks it up at span close; otherwise apply immediately.
    if sid in _TOTAL_RESULT:
        _TOTAL_RESULT[sid] = result
    else:
        _apply_agent_result(span, result)


def emit_event_mirror(event: dict) -> None:
    """Mirror a state-write event onto the active span as attributes.

    Called by ``hooks/_py/state_write.py`` after every event append to keep
    spans in lockstep with the event log. Unknown keys pass through as span
    attributes; the ``type`` key is stripped (it duplicates the span name).
    Failures are swallowed so OTel never blocks state writes.
    """
    if not _STATE.enabled:
        return
    from opentelemetry import trace

    span = trace.get_current_span()
    if span is None:
        return
    for k, v in event.items():
        if k == "type":
            continue
        try:
            span.set_attribute(k, v)
        except Exception:  # noqa: BLE001 - attribute errors are non-fatal
            log.debug("failed to set attribute %s=%r", k, v)


def dispatch_env(base_env: dict[str, str]) -> dict[str, str]:
    """Return a copy of ``base_env`` augmented with TRACEPARENT/TRACESTATE.

    The orchestrator calls this immediately before a Task-tool dispatch to
    give the subagent process the current span context. The original dict is
    not mutated. When OTel is disabled, returns a plain copy.
    """
    env = dict(base_env)
    if not _STATE.enabled:
        return env
    from hooks._py.otel_context import inject_traceparent_env

    inject_traceparent_env(env)
    return env


def replay(*, events_path: str, config: dict) -> int:
    """Authoritative recovery path.

    Rebuilds spans from the event-sourced log (``.forge/events.jsonl``) and
    exports them via the configured exporter. Use this when a run crashed
    before the live stream flushed -- the event log is fsync'd and is the
    source of truth. Returns the number of spans emitted.
    """
    if not config.get("enabled", False):
        return 0
    from hooks._py.event_to_span import replay_events  # Task 10

    return replay_events(events_path=events_path, config=config)
