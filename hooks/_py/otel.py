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
from typing import Any, Iterator


@dataclasses.dataclass
class EmitterState:
    enabled: bool = False
    tracer: Any = None
    provider: Any = None


_STATE = EmitterState()


def init(config: dict, parent_traceparent: str | None = None) -> EmitterState:
    """Initialise emitter. Returns a no-op state when disabled or on import error."""
    global _STATE
    if not config.get("enabled", False):
        _STATE = EmitterState(enabled=False)
        return _STATE
    # Real init wired in Task 5.
    _STATE = EmitterState(enabled=False)
    return _STATE


def shutdown() -> None:
    """Flush pending spans and tear down the provider."""
    if _STATE.provider is not None:
        _STATE.provider.shutdown()


@contextlib.contextmanager
def pipeline_span(*, run_id: str, mode: str) -> Iterator[Any]:
    yield None


@contextlib.contextmanager
def stage_span(name: str) -> Iterator[Any]:
    yield None


@contextlib.contextmanager
def agent_span(*, name: str, model: str, description: str) -> Iterator[Any]:
    yield None


@contextlib.contextmanager
def tool_span(*, name: str, call_id: str | None = None) -> Iterator[Any]:
    yield None


def record_agent_result(result: dict) -> None:
    """No-op when disabled. Real impl in Task 5."""
    return None


def replay(*, events_path: str, config: dict) -> int:
    """Authoritative recovery path.

    Rebuilds spans from the event-sourced log (``.forge/events.jsonl``) and
    exports them via the configured exporter. Use this when a run crashed
    before the live stream flushed -- the event log is fsync'd and is the
    source of truth. Returns the number of spans emitted.
    """
    if not config.get("enabled", False):
        return 0
    # Real impl in Task 10.
    return 0
