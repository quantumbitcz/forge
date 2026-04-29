"""Render ``## Relevant Learnings`` block from a ``list[LearningItem]``.

The ONLY emitter of the injection format — contract tests in
tests/contract/learnings_injection_format.bats assert on this output byte-for-byte.

``render()`` returns the bare markdown block (no envelope). The
``<untrusted source="learnings">`` wrapper required by
``shared/untrusted-envelope.md`` is applied by the caller (the orchestrator's
§0.6.1 dispatch-context builder in ``agents/fg-100-orchestrator.md``). Keeping
``render()`` pure means the contract tests can pin the inner format
byte-for-byte, while the envelope is documented at the dispatch seam.
"""
from __future__ import annotations

from hooks._py.learnings_selector import LearningItem

MAX_ITEMS = 6
BODY_LIMIT = 300

HEADER = (
    "## Relevant Learnings (from prior runs)\n\n"
    "The following patterns recurred in this codebase. Consider them during your\n"
    "work, but verify each — they are priors, not rules.\n\n"
)


def _sanitize(body: str) -> str:
    """Strip control bytes so untrusted body text cannot break the block.

    Newlines (``\\n``, U+000A) are preserved because the renderer joins
    multi-line bodies. All other control bytes below ASCII 32 are
    stripped — including tab (``\\t``, U+0009), carriage return
    (``\\r``, U+000D), and form feed (``\\f``, U+000C). Tabs in
    particular are NOT preserved; if a learning's prose used tabs for
    indentation they collapse to nothing here.
    """
    return "".join(ch for ch in body if ch == "\n" or ch >= " ")


def _truncate(body: str, limit: int = BODY_LIMIT) -> str:
    if len(body) <= limit:
        return body
    cut = body.rfind(" ", 0, limit)
    if cut < 0:
        cut = limit
    return body[:cut].rstrip() + "…"


def _fmt_item(idx: int, item: LearningItem) -> str:
    confidence = f"{item.confidence_now:.2f}"
    if item.applied_count > 0:
        badge = f"[confidence {confidence}, {item.applied_count}× applied]"
    else:
        badge = f"[confidence {confidence}]"
    body = _truncate(_sanitize(item.body))
    lines = [f"{idx}. {badge} {body}"]
    lines.append(f"   - Source: {item.source_path}")
    decay = f"   - Decay: {item.half_life_days}d half-life"
    if item.last_applied:
        date = item.last_applied.split("T")[0]
        decay += f", last applied {date}"
    lines.append(decay)
    return "\n".join(lines)


def render(items: list[LearningItem]) -> str:
    """Return the full markdown block (with header) or empty string."""
    if not items:
        return ""
    capped = items[:MAX_ITEMS]
    body = "\n\n".join(_fmt_item(i + 1, it) for i, it in enumerate(capped))
    return HEADER + body + "\n"
