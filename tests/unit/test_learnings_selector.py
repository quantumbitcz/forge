"""Selector pure-function tests. CI-only."""
from __future__ import annotations

from datetime import datetime, timedelta, timezone

import pytest

from hooks._py.learnings_selector import (
    LearningItem,
    _is_cross_project,
    select_for_dispatch,
)


UTC = timezone.utc
NOW = datetime(2026, 4, 22, 12, 0, 0, tzinfo=UTC)


def _mk(
    id: str,
    applies_to=("implementer",),
    domain_tags=("spring",),
    base=0.80,
    half_life=30,
    applied=3,
    last_applied_iso: str | None = "2026-04-18T00:00:00Z",
    archived: bool = False,
    source_path: str = "shared/learnings/spring.md",
) -> LearningItem:
    return LearningItem(
        id=id,
        source_path=source_path,
        body="body",
        base_confidence=base,
        confidence_now=base,  # pre-set by I/O layer; selector reuses
        half_life_days=half_life,
        applied_count=applied,
        last_applied=last_applied_iso,
        applies_to=tuple(applies_to),
        domain_tags=tuple(domain_tags),
        archived=archived,
    )


def test_role_filter_excludes_unmatched():
    items = [_mk("only-planner", applies_to=("planner",))]
    out = select_for_dispatch(
        agent="fg-300-implementer", stage="IMPLEMENT",
        domain_tags=["spring"], component="api",
        candidates=items, now=NOW,
    )
    assert out == []


def test_role_filter_keeps_matched():
    items = [_mk("impl-ok", applies_to=("implementer",))]
    out = select_for_dispatch(
        agent="fg-300-implementer", stage="IMPLEMENT",
        domain_tags=["spring"], component="api",
        candidates=items, now=NOW,
    )
    assert [i.id for i in out] == ["impl-ok"]


def test_reviewer_role_prefix_matched():
    items = [_mk("sec-1", applies_to=("reviewer.security",))]
    out = select_for_dispatch(
        agent="fg-411-security-reviewer", stage="REVIEW",
        domain_tags=["spring"], component="api",
        candidates=items, now=NOW,
    )
    assert [i.id for i in out] == ["sec-1"]


def test_archived_skipped():
    items = [_mk("old", archived=True)]
    out = select_for_dispatch(
        agent="fg-300-implementer", stage="IMPLEMENT",
        domain_tags=["spring"], component=None,
        candidates=items, now=NOW,
    )
    assert out == []


def test_min_confidence_floor():
    items = [_mk("lowc", base=0.30)]
    # Pre-set confidence_now below default floor 0.4:
    items[0] = LearningItem(**{**items[0].__dict__, "confidence_now": 0.30})
    out = select_for_dispatch(
        agent="fg-300-implementer", stage="IMPLEMENT",
        domain_tags=["spring"], component=None,
        candidates=items, now=NOW, min_confidence=0.4,
    )
    assert out == []


def test_max_items_truncation():
    items = [
        _mk(f"id-{n}", base=0.80 + n * 0.001)  # stable ordering by id tiebreak
        for n in range(20)
    ]
    for i in items:
        i_dict = dict(i.__dict__); i_dict["confidence_now"] = i.base_confidence
    out = select_for_dispatch(
        agent="fg-300-implementer", stage="IMPLEMENT",
        domain_tags=["spring"], component=None,
        candidates=items, now=NOW, max_items=6,
    )
    assert len(out) == 6


def test_recency_bonus_tiers():
    recent = _mk("r", last_applied_iso="2026-04-18T00:00:00Z")  # <30d
    mid = _mk("m", last_applied_iso="2026-02-01T00:00:00Z")     # 30-90d
    stale = _mk("s", last_applied_iso="2025-10-01T00:00:00Z")   # >90d
    never = _mk("n", last_applied_iso=None)
    out = select_for_dispatch(
        agent="fg-300-implementer", stage="IMPLEMENT",
        domain_tags=["spring"], component=None,
        candidates=[stale, mid, never, recent], now=NOW,
    )
    assert [i.id for i in out[:2]] == ["r", "m"]  # recent wins


def test_tiebreak_by_id_ascending():
    a = _mk("a-item")
    b = _mk("b-item")
    out = select_for_dispatch(
        agent="fg-300-implementer", stage="IMPLEMENT",
        domain_tags=["spring"], component=None,
        candidates=[b, a], now=NOW,
    )
    assert [i.id for i in out] == ["a-item", "b-item"]


def test_domain_intersection_weight():
    strong = _mk("strong", domain_tags=("spring", "persistence"))
    weak = _mk("weak", domain_tags=("spring",))
    out = select_for_dispatch(
        agent="fg-300-implementer", stage="IMPLEMENT",
        domain_tags=["spring", "persistence"], component=None,
        candidates=[weak, strong], now=NOW,
    )
    assert out[0].id == "strong"


def test_empty_domain_tags_falls_back_to_half_weight():
    one = _mk("one", domain_tags=("spring",))
    out = select_for_dispatch(
        agent="fg-300-implementer", stage="IMPLEMENT",
        domain_tags=[], component=None,
        candidates=[one], now=NOW,
    )
    assert [i.id for i in out] == ["one"]


def test_unknown_agent_returns_empty():
    items = [_mk("impl-ok")]
    out = select_for_dispatch(
        agent="fg-999-nope", stage="IMPLEMENT",
        domain_tags=["spring"], component=None,
        candidates=items, now=NOW,
    )
    assert out == []


def test_is_cross_project_path_components_only():
    """Substring match is too loose: only exact path components count."""
    # Canonical layout
    assert _is_cross_project("/Users/x/.claude/forge-learnings/spring.md")
    assert _is_cross_project("/home/x/.claude/forge-learnings/general.md")
    # Sibling directory must NOT match (this is the bug M10 fixes)
    assert not _is_cross_project("/Users/x/forge-learnings-tools/spring.md")
    assert not _is_cross_project("/tmp/my-forge-learnings/spring.md")
    # In-repo learnings (the common local case)
    assert not _is_cross_project("shared/learnings/spring.md")
    assert not _is_cross_project("/repo/shared/learnings/spring.md")
