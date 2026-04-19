"""Atomic JSON state writes with _seq versioning (replaces forge-state-write.sh)."""
from __future__ import annotations

from pathlib import Path
from typing import Any

from .io_utils import atomic_json_update


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
