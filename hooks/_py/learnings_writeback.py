"""Retrospective write-back: events → item deltas → atomic frontmatter write.

Call site is fg-700-retrospective's Stage 9 logic. The module is pure I/O
glue around ``memory_decay.apply_success/apply_false_positive/
apply_vindication/archival_floor``.

Format note: we re-serialise frontmatter via a minimal round-tripper
(not PyYAML — we hand-parse the v2 slice, consistent with learnings_io).
"""
from __future__ import annotations

import logging
import os
import re
import tempfile
from datetime import datetime
from pathlib import Path
from typing import Any

from hooks._py import memory_decay

log = logging.getLogger(__name__)

FRONTMATTER_RE = re.compile(r"^---\n(.*?)\n---\n", re.DOTALL)
ITEM_START_RE = re.compile(r"^\s*-\s+id:\s*\"?([^\"\n]+)\"?\s*$", re.MULTILINE)


def _split(raw: str) -> tuple[str, str, str]:
    m = FRONTMATTER_RE.match(raw)
    if not m:
        return ("", "", raw)
    head_end = m.end()
    return (raw[: m.start() + 4], raw[m.start() + 4 : head_end - 4], raw[head_end:])


def _parse_items(block: str) -> list[dict]:
    # Minimal inline parser for the items: section we produce.
    items: list[dict] = []
    current: dict | None = None
    for line in block.splitlines():
        start = ITEM_START_RE.match(line)
        if start:
            if current is not None:
                items.append(current)
            current = {"id": start.group(1).strip()}
            continue
        if current is None:
            continue
        m = re.match(r"^\s{4}(\w+):\s*(.+)$", line)
        if not m:
            continue
        key, raw = m.group(1), m.group(2).strip()
        current[key] = _coerce(raw)
    if current is not None:
        items.append(current)
    return items


def _coerce(value: str) -> Any:
    if value == "null":
        return None
    if value == "true":
        return True
    if value == "false":
        return False
    if value.startswith("[") and value.endswith("]"):
        inner = value[1:-1].strip()
        if not inner:
            return []
        return [x.strip().strip('"').strip("'") for x in inner.split(",")]
    if value.startswith('"') and value.endswith('"'):
        return value[1:-1]
    try:
        return float(value) if "." in value else int(value)
    except ValueError:
        return value


def _render_items(items: list[dict]) -> str:
    def _q(v) -> str:
        if v is None:
            return "null"
        if isinstance(v, bool):
            return "true" if v else "false"
        if isinstance(v, (int, float)):
            return repr(v) if isinstance(v, float) else str(v)
        if isinstance(v, list):
            return "[" + ", ".join(_q(x) for x in v) + "]"
        return f'"{v}"'

    order = (
        "id", "base_confidence", "half_life_days", "applied_count",
        "last_applied", "first_seen", "false_positive_count",
        "last_false_positive_at", "pre_fp_base", "applies_to",
        "domain_tags", "source", "archived", "body_ref",
    )
    out: list[str] = ["items:"]
    for it in items:
        out.append(f"  - id: {_q(it['id'])}")
        for key in order:
            if key == "id":
                continue
            if key in it:
                out.append(f"    {key}: {_q(it[key])}")
    return "\n".join(out)


def _item_to_decay_shape(it: dict, source_path: str) -> dict:
    """Project v2 item dict → the dict shape memory_decay expects."""
    return {
        "id": it["id"],
        "base_confidence": it["base_confidence"],
        "type": it.get("source", "cross-project"),
        "last_success_at": it.get("last_applied") or it.get("first_seen"),
        "source": it.get("source"),
        "source_path": source_path,
        "applied_count": it.get("applied_count", 0),
        "last_applied": it.get("last_applied"),
        "first_seen": it.get("first_seen"),
        "false_positive_count": it.get("false_positive_count", 0),
        "last_false_positive_at": it.get("last_false_positive_at"),
        "pre_fp_base": it.get("pre_fp_base"),
    }


def _merge_back(it: dict, decay_out: dict) -> dict:
    out = dict(it)
    for key in (
        "base_confidence", "applied_count", "last_applied",
        "false_positive_count", "last_false_positive_at", "pre_fp_base",
    ):
        if key in decay_out:
            out[key] = decay_out[key]
    return out


def apply_events_to_file(
    path: Path, events: list[dict], now: datetime
) -> bool:
    raw = path.read_text(encoding="utf-8")
    head, body, tail = _split(raw)
    if not head:
        return False
    items = _parse_items(body)
    changed = False

    by_id: dict[str, dict] = {it["id"]: it for it in items}
    for ev in events:
        iid = ev.get("forge.learning.id")
        if not iid or iid not in by_id:
            continue
        t = ev.get("type")
        proj = _item_to_decay_shape(by_id[iid], str(path))
        match t:
            case "forge.learning.applied":
                by_id[iid] = _merge_back(by_id[iid], memory_decay.apply_success(proj, now))
                changed = True
            case "forge.learning.fp":
                by_id[iid] = _merge_back(
                    by_id[iid], memory_decay.apply_false_positive(proj, now)
                )
                changed = True
            case "forge.learning.vindicated":
                by_id[iid] = _merge_back(
                    by_id[iid], memory_decay.apply_vindication(proj, now)
                )
                changed = True
            case _:
                pass

    # Archival floor for every item (cheap; idempotent).
    for iid, it in list(by_id.items()):
        proj = _item_to_decay_shape(it, str(path))
        archived, _reason = memory_decay.archival_floor(proj, now)
        if archived and not it.get("archived"):
            it["archived"] = True
            changed = True

    if not changed:
        return False

    # Preserve any file-level keys (schema_version and decay_tier etc.) that
    # live above the items: block.
    head_lines: list[str] = []
    for line in body.splitlines():
        if line.strip().startswith("items:"):
            break
        head_lines.append(line)

    rendered = "\n".join(head_lines).rstrip("\n")
    rendered = rendered + "\n" + _render_items(list(by_id.values())) + "\n"
    new_raw = "---\n" + rendered + "---\n" + tail

    _atomic_write(path, new_raw)
    return True


def _atomic_write(path: Path, data: str) -> None:
    tmp_fd, tmp_path_str = tempfile.mkstemp(
        prefix=path.name, dir=str(path.parent)
    )
    try:
        with os.fdopen(tmp_fd, "w", encoding="utf-8") as fh:
            fh.write(data)
            fh.flush()
            os.fsync(fh.fileno())
        os.replace(tmp_path_str, path)
    except Exception:
        if os.path.exists(tmp_path_str):
            os.unlink(tmp_path_str)
        raise
