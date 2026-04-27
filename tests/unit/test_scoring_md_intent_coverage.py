"""Phase 7 Wave 1 Task 2b — scoring.md narrative mirrors registry for INTENT-* + IMPL-VOTE-*."""

from __future__ import annotations

from pathlib import Path

DOC_PATH = (
    Path(__file__).parent.parent.parent
    / "shared"
    / "scoring.md"
)
DOC = DOC_PATH.read_text(encoding="utf-8")


def test_intent_wildcard_row_present_or_narrative_removed():
    """Either scoring.md names INTENT-* in its category table, OR it has
    been restructured to not enumerate categories at all. Fail if the table
    still enumerates wildcards (e.g. REFLECT-*, AI-LOGIC-*) but omits
    INTENT-*."""
    has_other_wildcards = "`REFLECT-*`" in DOC and "`AI-LOGIC-*`" in DOC
    has_intent = "`INTENT-*`" in DOC or "INTENT-MISSED" in DOC
    assert (not has_other_wildcards) or has_intent, (
        "scoring.md enumerates other wildcards but omits INTENT-* — drift."
    )


def test_impl_vote_coverage_or_narrative_removed():
    has_other_wildcards = "`REFLECT-*`" in DOC and "`AI-LOGIC-*`" in DOC
    has_impl_vote = "`IMPL-VOTE-*`" in DOC or "IMPL-VOTE-TRIGGERED" in DOC
    assert (not has_other_wildcards) or has_impl_vote, (
        "scoring.md enumerates other wildcards but omits IMPL-VOTE-* — drift."
    )
