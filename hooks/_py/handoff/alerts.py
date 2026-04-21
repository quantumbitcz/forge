"""Alert emission for HANDOFF_WRITTEN and HANDOFF_STALE."""
from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from hooks._py.io_utils import atomic_json_update


def _now_iso() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def emit_handoff_written(
    forge_dir: Path,
    run_id: str,
    level: str,
    path: str,
    reason: str,
    resume_prompt_preview: str,
    created_at: datetime | None = None,
) -> None:
    alert: dict[str, Any] = {
        "type": "HANDOFF_WRITTEN",
        "level": level,
        "run_id": run_id,
        "path": path,
        "reason": reason,
        "created_at": (created_at or datetime.now(timezone.utc)).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "resume_prompt_preview": resume_prompt_preview,
    }
    _append_alert(forge_dir / "alerts.json", alert)


def emit_handoff_stale(forge_dir: Path, run_id: str, path: str, reason: str) -> None:
    alert = {
        "type": "HANDOFF_STALE",
        "run_id": run_id,
        "path": path,
        "reason": reason,
        "created_at": _now_iso(),
    }
    _append_alert(forge_dir / "alerts.json", alert)


def _append_alert(alerts_path: Path, alert: dict[str, Any]) -> None:
    def mutate(current: Any) -> list[dict[str, Any]]:
        if not isinstance(current, list):
            current = []
        current.append(alert)
        return current

    atomic_json_update(alerts_path, mutate, default=[])
