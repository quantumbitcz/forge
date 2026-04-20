"""Atomic JSON state writes with _seq versioning (replaces forge-state-write.sh).

Also exposes ``append_event`` -- the fsync'd writer for the Phase F07
event-sourced log (``.forge/events.jsonl``). Every append mirrors onto the
active OTel span via ``hooks._py.otel.emit_event_mirror`` (Phase 09 Task 8).
The mirror call is best-effort and never blocks the state write.
"""
from __future__ import annotations

import contextlib
import json
import os
from pathlib import Path
from typing import Any

from .io_utils import _locked, atomic_json_update


def _bump_seq(doc: dict[str, Any]) -> dict[str, Any]:
    doc["_seq"] = int(doc.get("_seq", 0)) + 1
    return doc


def write_state(path: Path, new_doc: dict[str, Any]) -> None:
    """Replace state file contents with new_doc, incrementing _seq."""
    def _mutate(current: dict) -> dict:
        doc = dict(new_doc)
        doc["_seq"] = int(current.get("_seq", 0)) + 1
        return doc
    atomic_json_update(path, _mutate, default={})


def _deep_merge(a: dict, b: dict, depth: int) -> dict:
    if depth <= 0:
        return b
    out = dict(a)
    for k, v in b.items():
        if k in out and isinstance(out[k], dict) and isinstance(v, dict):
            out[k] = _deep_merge(out[k], v, depth - 1)
        else:
            out[k] = v
    return out


def update_state(
    path: Path, patch: dict[str, Any], *, merge_depth: int = 1
) -> None:
    """Merge patch into the existing state and bump _seq."""
    def _mutate(current: dict) -> dict:
        merged = _deep_merge(current, patch, merge_depth)
        return _bump_seq(merged)
    atomic_json_update(path, _mutate, default={})


def append_event(path: Path, event: dict[str, Any]) -> None:
    """Append a single JSON event to ``path`` (one row, fsync'd).

    Phase F07 contract: each event is a self-contained JSON object on its
    own line. The append runs under an exclusive lock to serialize concurrent
    writers, and the file handle is fsync'd before close so the event is on
    disk before we return.

    After the append, ``hooks._py.otel.emit_event_mirror`` is called to
    project event keys onto the active OTel span as attributes (Phase 09
    Task 8). Mirror failures are swallowed -- OTel must never block state
    writes.
    """
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    lock_path = path.with_suffix(path.suffix + ".lock")
    payload = json.dumps(event, sort_keys=True) + "\n"

    with open(lock_path, "a+b") as lock_fp:
        with _locked(lock_fp):
            with open(path, "a", encoding="utf-8") as fp:
                fp.write(payload)
                fp.flush()
                with contextlib.suppress(OSError):
                    os.fsync(fp.fileno())

    # Best-effort OTel mirror -- never let it block or break state writes.
    try:
        from hooks._py import otel as _otel

        _otel.emit_event_mirror(event)
    except Exception:  # noqa: BLE001 - OTel mirror is optional
        pass
