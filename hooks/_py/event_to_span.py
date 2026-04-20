"""Translate ``.forge/events.jsonl`` rows into OTel span open/close operations.

The event log (Phase F07) is fsync'd per row. This module is the
authoritative-replay translator -- live emission (otel.py) and replay emit
the same spans byte-for-byte except for timestamps.
"""

from __future__ import annotations

import dataclasses
import json
from typing import Iterator

from hooks._py import otel_attributes as A


@dataclasses.dataclass(frozen=True)
class EventOp:
    kind: str  # "open" | "close"
    name: str  # span name (bounded)
    attrs: dict[str, object]  # semconv attributes


def _event_to_op(ev: dict) -> EventOp | None:
    t = ev.get("type")
    if t == "pipeline.open":
        return EventOp(
            "open",
            "pipeline",
            {
                A.GEN_AI_AGENT_NAME: "forge-pipeline",
                A.GEN_AI_OPERATION_NAME: A.OP_INVOKE_AGENT,
                A.FORGE_RUN_ID: ev["run_id"],
                A.FORGE_MODE: ev.get("mode", "standard"),
            },
        )
    if t == "pipeline.close":
        return EventOp("close", "pipeline", {A.FORGE_RUN_ID: ev["run_id"]})
    if t == "stage.open":
        return EventOp(
            "open", f"stage.{ev['stage']}", {A.FORGE_STAGE: ev["stage"]}
        )
    if t == "stage.close":
        return EventOp(
            "close", f"stage.{ev['stage']}", {A.FORGE_STAGE: ev["stage"]}
        )
    if t == "agent.open":
        return EventOp(
            "open",
            f"agent.{ev['agent_name']}",
            {
                A.GEN_AI_AGENT_NAME: ev["agent_name"],
                A.GEN_AI_AGENT_DESCRIPTION: ev.get("description", ""),
                A.GEN_AI_OPERATION_NAME: A.OP_INVOKE_AGENT,
                A.GEN_AI_REQUEST_MODEL: ev.get("model", "unknown"),
            },
        )
    if t == "agent.close":
        ti = int(ev.get("tokens_input", 0))
        to = int(ev.get("tokens_output", 0))
        attrs: dict[str, object] = {
            A.GEN_AI_AGENT_NAME: ev["agent_name"],
            A.GEN_AI_TOKENS_INPUT: ti,
            A.GEN_AI_TOKENS_OUTPUT: to,
            A.GEN_AI_TOKENS_TOTAL: ti + to,
        }
        if "cost_usd" in ev:
            attrs[A.GEN_AI_COST_USD] = float(ev["cost_usd"])
        else:
            attrs[A.FORGE_COST_UNKNOWN] = True
        if "tool_calls" in ev:
            attrs[A.GEN_AI_TOOL_CALLS] = int(ev["tool_calls"])
        if "finish_reasons" in ev:
            attrs[A.GEN_AI_RESPONSE_FINISH_REASONS] = tuple(
                ev["finish_reasons"]
            )
        return EventOp("close", f"agent.{ev['agent_name']}", attrs)
    return None  # unknown event types are ignored


def iter_span_ops(events_path: str) -> Iterator[EventOp]:
    """Yield ordered span open/close operations from an events.jsonl file."""
    with open(events_path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            ev = json.loads(line)
            op = _event_to_op(ev)
            if op is not None:
                yield op


def replay_events(*, events_path: str, config: dict) -> int:
    """Rebuild spans from an event log and emit via the configured exporter.

    This is the AUTHORITATIVE recovery path -- idempotent and deterministic
    when given the same event log (modulo timestamps). The live stream is
    best-effort; this is the source of truth.

    Returns the number of spans opened (and closed).
    """
    from hooks._py import otel as _otel

    _otel.init(config)
    if not _otel._STATE.enabled:
        return 0
    stack: list[str] = []  # names of currently open spans
    cms: list = []  # active context managers (to close in reverse)
    count = 0
    try:
        for op in iter_span_ops(events_path):
            if op.kind == "open":
                name = op.name
                if name == "pipeline":
                    cm = _otel.pipeline_span(
                        run_id=str(op.attrs.get(A.FORGE_RUN_ID, "unknown")),
                        mode=str(op.attrs.get(A.FORGE_MODE, "standard")),
                    )
                elif name.startswith("stage."):
                    cm = _otel.stage_span(name.split(".", 1)[1])
                elif name.startswith("agent."):
                    cm = _otel.agent_span(
                        name=str(
                            op.attrs.get(
                                A.GEN_AI_AGENT_NAME, name.split(".", 1)[1]
                            )
                        ),
                        model=str(
                            op.attrs.get(A.GEN_AI_REQUEST_MODEL, "unknown")
                        ),
                        description=str(
                            op.attrs.get(A.GEN_AI_AGENT_DESCRIPTION, "")
                        ),
                    )
                else:
                    continue
                cm.__enter__()
                cms.append(cm)
                stack.append(name)
                count += 1
            elif op.kind == "close":
                # Apply close-time attributes (tokens, cost, tool calls)
                # before exiting so they land on the same span.
                if op.name.startswith("agent."):
                    result: dict[str, object] = {
                        "tokens_input": op.attrs.get(A.GEN_AI_TOKENS_INPUT, 0),
                        "tokens_output": op.attrs.get(
                            A.GEN_AI_TOKENS_OUTPUT, 0
                        ),
                    }
                    if A.GEN_AI_COST_USD in op.attrs:
                        result["cost_usd"] = op.attrs[A.GEN_AI_COST_USD]
                    if A.GEN_AI_TOOL_CALLS in op.attrs:
                        result["tool_calls"] = op.attrs[A.GEN_AI_TOOL_CALLS]
                    if A.GEN_AI_RESPONSE_FINISH_REASONS in op.attrs:
                        result["finish_reasons"] = list(
                            op.attrs[A.GEN_AI_RESPONSE_FINISH_REASONS]
                        )
                    _otel.record_agent_result(result)
                if stack and stack[-1] == op.name:
                    cms.pop().__exit__(None, None, None)
                    stack.pop()
    finally:
        # Close any still-open spans (malformed log).
        while cms:
            cms.pop().__exit__(None, None, None)
        _otel.shutdown()
    return count
