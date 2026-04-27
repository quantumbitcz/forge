"""Atomic writer for .forge/progress/status.json.

Invoked by hooks/post_tool_use_agent.py on every subagent completion event.
Reads the tail of .forge/events.jsonl and a snapshot of .forge/state.json to
assemble a single advisory "what's happening right now" view. Never raises —
the hook wrapper catches any escape.
"""
from __future__ import annotations

import json
import os
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Optional

WRITER = "post_tool_use_agent.py"
DEFAULT_STAGE_TIMEOUT_MS = 600_000


def _iso_now() -> str:
    n = datetime.now(timezone.utc)
    return n.strftime("%Y-%m-%dT%H:%M:%S.") + f"{n.microsecond // 1000:03d}Z"


def _parse_iso(value: Optional[str]) -> Optional[datetime]:
    if not value:
        return None
    try:
        v = value.replace("Z", "+00:00")
        return datetime.fromisoformat(v)
    except ValueError:
        return None


def _tail_event(events_path: Path) -> Optional[dict]:
    if not events_path.exists():
        return None
    try:
        size = events_path.stat().st_size
        with events_path.open("rb") as fh:
            seek_to = max(0, size - 8192)
            fh.seek(seek_to)
            chunk = fh.read().decode("utf-8", errors="ignore")
    except OSError:
        return None
    last_line = ""
    for line in chunk.splitlines():
        line = line.strip()
        if line:
            last_line = line
    if not last_line:
        return None
    try:
        return json.loads(last_line)
    except json.JSONDecodeError:
        return None


def _load_state(state_path: Path) -> dict:
    if not state_path.exists():
        return {}
    try:
        return json.loads(state_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}


def _elapsed_ms(stage_entered_at: Optional[str]) -> int:
    dt = _parse_iso(stage_entered_at)
    if dt is None:
        return 0
    now = datetime.now(timezone.utc)
    return max(0, int((now - dt).total_seconds() * 1000))


def _next_expected_at(stage_entered_at: Optional[str], timeout_ms: int) -> Optional[str]:
    dt = _parse_iso(stage_entered_at)
    if dt is None:
        return None
    return (dt + timedelta(milliseconds=timeout_ms)).strftime("%Y-%m-%dT%H:%M:%SZ")


def write_status_from_hook(cwd: Optional[str] = None) -> None:
    """Compose status and write atomically. No-op if .forge missing."""
    base = Path(cwd) if cwd else Path.cwd()
    forge = base / ".forge"
    if not forge.exists():
        return
    progress_dir = forge / "progress"
    try:
        progress_dir.mkdir(parents=True, exist_ok=True)
    except OSError as exc:
        sys.stderr.write(f"[progress] cannot create {progress_dir}: {exc}\n")
        return
    state = _load_state(forge / "state.json")
    event = _tail_event(forge / "events.jsonl") or {}
    run_id = state.get("run_id") or event.get("run_id")
    if not run_id:
        # No active run — don't write a stale/empty status that downstream
        # tooling could merge into trend rollups. See review #12.
        return
    stage = state.get("stage") or event.get("stage") or "UNKNOWN"
    agent = event.get("agent") if event.get("type") == "agent_dispatch" else None
    timeout_ms = int(state.get("stage_timeout_ms") or DEFAULT_STAGE_TIMEOUT_MS)
    stage_entered_at = state.get("stage_entered_at")
    status = {
        "run_id": run_id,
        "stage": stage,
        "agent_active": agent,
        "elapsed_ms_in_stage": _elapsed_ms(stage_entered_at),
        "timeout_ms": timeout_ms,
        "last_event": {
            "ts": event.get("ts") or _iso_now(),
            "type": event.get("type", "unknown"),
            "detail": event.get("detail", ""),
        },
        "next_expected_at": _next_expected_at(stage_entered_at, timeout_ms),
        "updated_at": _iso_now(),
        "writer": WRITER,
    }
    target = progress_dir / "status.json"
    tmp = target.with_suffix(".json.tmp")
    try:
        tmp.write_text(json.dumps(status, separators=(",", ":")), encoding="utf-8")
        os.replace(tmp, target)
    except OSError as exc:
        sys.stderr.write(f"[progress] write failed: {exc}\n")
        tmp.unlink(missing_ok=True)
