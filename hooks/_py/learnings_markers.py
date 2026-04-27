"""Parse LEARNING_* and PREEMPT_* markers out of stage notes / agent output.

Contract (Phase 4 §3.1):
  - LEARNING_APPLIED: <id>                         → ('applied', id, None)
  - LEARNING_FP: <id> reason=<text>                → ('fp', id, text)
  - LEARNING_VINDICATED: <id> reason=<text>        → ('vindicated', id, text)
  - PREEMPT_APPLIED: <id>                          → ('applied', id, None)
  - PREEMPT_SKIPPED: <id> reason=<text>            → ('fp', id, text)
  - PREEMPT_SKIPPED: <id>                          → ('fp', id, None)

Every other line is ignored.
"""
from __future__ import annotations

import re

Marker = tuple[str, str, str | None]

_LINE_RE = re.compile(
    r"^(?P<keyword>LEARNING_APPLIED|LEARNING_FP|LEARNING_VINDICATED|"
    r"PREEMPT_APPLIED|PREEMPT_SKIPPED):\s*"
    r"(?P<id>[A-Za-z0-9._\-]+)"
    r"(?:\s+reason=(?P<reason>.*))?$"
)

_KEYWORD_TO_KIND = {
    "LEARNING_APPLIED": "applied",
    "LEARNING_FP": "fp",
    "LEARNING_VINDICATED": "vindicated",
    "PREEMPT_APPLIED": "applied",
    "PREEMPT_SKIPPED": "fp",
}


def parse_markers(text: str) -> list[Marker]:
    """Return a list of ``(kind, id, reason_or_None)`` tuples in source order."""
    out: list[Marker] = []
    for line in text.splitlines():
        m = _LINE_RE.match(line.strip())
        if not m:
            continue
        kind = _KEYWORD_TO_KIND[m.group("keyword")]
        out.append((kind, m.group("id"), m.group("reason")))
    return out
