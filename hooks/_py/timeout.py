"""Pipeline timeout check (replaces shared/forge-timeout.sh)."""
from __future__ import annotations

import json
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path


@dataclass
class TimeoutResult:
    exceeded: bool
    warning: bool
    elapsed_seconds: float


def check(state_path: Path, *, max_seconds: int = 7200) -> TimeoutResult:
    """Return TimeoutResult given the pipeline's state.json and a budget.

    Missing/invalid state → no exceed, no warning.
    """
    try:
        doc = json.loads(state_path.read_text())
    except (FileNotFoundError, json.JSONDecodeError):
        return TimeoutResult(False, False, 0.0)
    iso = (doc.get("stage_timestamps") or {}).get("preflight") or ""
    if not iso:
        return TimeoutResult(False, False, 0.0)
    try:
        start = datetime.fromisoformat(iso.replace("Z", "+00:00"))
    except ValueError:
        return TimeoutResult(False, False, 0.0)
    if start.tzinfo is None:
        start = start.replace(tzinfo=timezone.utc)
    elapsed = (datetime.now(timezone.utc) - start).total_seconds()
    return TimeoutResult(
        exceeded=elapsed > max_seconds,
        warning=elapsed >= max_seconds * 0.8,
        elapsed_seconds=elapsed,
    )
