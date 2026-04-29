"""Filesystem wrapper for learnings schema v2.

Walks directories, parses frontmatter slice (hand-rolled, no PyYAML),
computes ``confidence_now`` via ``memory_decay.effective_confidence``,
and returns ``LearningItem`` records. Side-effecting; the selector is pure.

Supported frontmatter value types
---------------------------------
The hand-rolled parser (``_coerce``) recognizes a deliberate subset of YAML
scalars — sufficient for the v2 learnings schema, but **not** a general
YAML implementation. Anything outside this list is returned as a bare
string (when ``int``/``float`` parsing fails) or silently dropped (when a
field doesn't match ``FIELD_RE``):

- ``null``                            → ``None``
- ``true`` / ``false``                → ``bool``
- Inline list ``[a, b, "c"]``         → ``list[str]`` (commas split, quotes stripped)
- Double-quoted scalar ``"text"``     → ``str``
- Decimal numeric (contains ``.``)    → ``float``
- Integer numeric                     → ``int``
- Anything else                       → bare ``str`` (unquoted fallback)

Explicitly **not supported**: block scalars (``|`` / ``>``), nested maps
beyond the four-space ``  - id: …`` item shape, multi-line lists, anchors
and aliases, type tags (``!!str`` etc.), single-quoted strings, ``yes`` /
``no`` / ``on`` / ``off`` boolean spellings, hex/octal/scientific numerics,
and timestamps. Files relying on these forms must be migrated; v2 fixtures
under ``tests/fixtures/learnings/`` are the authoritative shape reference.
"""
from __future__ import annotations

import logging
import re
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable

from hooks._py import memory_decay
from hooks._py.learnings_selector import LearningItem

log = logging.getLogger(__name__)

FRONTMATTER_RE = re.compile(r"^---\n(.*?)\n---\n", re.DOTALL)
ITEM_START_RE = re.compile(r"^\s*-\s+id:\s*\"?([^\"\n]+)\"?\s*$")
FIELD_RE = re.compile(r"^\s{4}(\w+):\s*(.+)$")


def _coerce(value: str):
    v = value.strip()
    if v == "null":
        return None
    if v in ("true", "false"):
        return v == "true"
    if v.startswith("[") and v.endswith("]"):
        inner = v[1:-1].strip()
        if not inner:
            return []
        return [x.strip().strip('"').strip("'") for x in inner.split(",")]
    if v.startswith('"') and v.endswith('"'):
        return v[1:-1]
    try:
        if "." in v:
            return float(v)
        return int(v)
    except ValueError:
        return v


def _parse_frontmatter(raw: str) -> dict | None:
    m = FRONTMATTER_RE.match(raw)
    if not m:
        return None
    fm_text = m.group(1)
    result: dict = {"items": []}
    current: dict | None = None
    for line in fm_text.splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        start = ITEM_START_RE.match(line)
        if start:
            if current is not None:
                result["items"].append(current)
            current = {"id": start.group(1).strip()}
            continue
        if current is not None:
            m2 = FIELD_RE.match(line)
            if m2:
                current[m2.group(1)] = _coerce(m2.group(2))
                continue
        if ":" in line and not line.startswith(" "):
            key, _, val = line.partition(":")
            key = key.strip()
            if key == "items":
                # 'items:' is a list header — actual entries are parsed via
                # ITEM_START_RE on subsequent lines; do not stomp the list.
                continue
            result[key] = _coerce(val)
    if current is not None:
        result["items"].append(current)
    return result


def _body_slice(raw: str, anchor: str, limit: int = 400) -> str:
    """Slice prose body following an HTML anchor in the post-frontmatter region.

    ``anchor`` may be a bare id (preferred) or a legacy ``#id`` form; the
    leading ``#`` is stripped. The search is restricted to ``raw[fm_end:]``
    so YAML frontmatter (which contains the ``body_ref`` field itself) can
    never satisfy the match. The anchor is matched as ``id="<X>"`` to align
    with the ``<a id="X"></a>`` markers emitted by the migration.
    """
    if not anchor:
        return ""
    anchor = anchor.lstrip("#")
    if not anchor:
        return ""
    m = FRONTMATTER_RE.match(raw)
    body_region = raw[m.end():] if m else raw
    needle = f'id="{anchor}"'
    idx = body_region.find(needle)
    if idx < 0:
        return ""
    # Skip past the opening anchor tag, then optional closing </a>, so the
    # slice starts on actual prose rather than HTML scaffolding.
    start = body_region.find(">", idx)
    start = start + 1 if start >= 0 else idx + len(needle)
    rest = body_region[start:].lstrip()
    if rest.startswith("</a>"):
        rest = rest[4:].lstrip()
    slice_ = rest[:limit * 2]
    if len(slice_) <= limit:
        return slice_
    cut = slice_.rfind(" ", 0, limit)
    return slice_[: cut if cut > 0 else limit].rstrip() + "…"


def parse_file(path: Path, now: datetime | None = None) -> list[LearningItem]:
    now = now or datetime.now(tz=timezone.utc)
    raw = path.read_text(encoding="utf-8")
    fm = _parse_frontmatter(raw)
    if fm is None or fm.get("schema_version") != 2:
        log.warning(
            "learnings: v1 file at %s — rerun scripts/migrate_learnings_schema.py",
            path,
        )
        return []
    items: list[LearningItem] = []
    for it in fm.get("items", []):
        if it.get("archived"):
            continue
        pseudo = {
            "id": it["id"],
            "base_confidence": it["base_confidence"],
            "type": it.get("source", "cross-project"),
            "last_success_at": it.get("last_applied") or it.get("first_seen"),
            "source": it.get("source", "cross-project"),
            "source_path": str(path),
        }
        confidence_now = memory_decay.effective_confidence(pseudo, now)
        body = _body_slice(raw, it.get("body_ref", ""))
        items.append(LearningItem(
            id=it["id"],
            source_path=str(path),
            body=body,
            base_confidence=float(it["base_confidence"]),
            confidence_now=confidence_now,
            half_life_days=int(it["half_life_days"]),
            applied_count=int(it.get("applied_count", 0)),
            last_applied=it.get("last_applied"),
            applies_to=tuple(it.get("applies_to") or ()),
            domain_tags=tuple(it.get("domain_tags") or ()),
            archived=bool(it.get("archived", False)),
        ))
    return items


def load_all(
    roots: Iterable[Path], now: datetime | None = None
) -> list[LearningItem]:
    out: list[LearningItem] = []
    for root in roots:
        if not root.is_dir():
            continue
        for md in sorted(root.glob("*.md")):
            if md.name == "README.md":
                continue
            out.extend(parse_file(md, now=now))
    return out
