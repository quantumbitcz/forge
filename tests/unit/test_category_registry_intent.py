"""Phase 7 Wave 1 Task 2 — INTENT-* + IMPL-VOTE-* registry coverage."""

from __future__ import annotations

import json
from pathlib import Path

REGISTRY_PATH = (
    Path(__file__).parent.parent.parent
    / "shared"
    / "checks"
    / "category-registry.json"
)
REG = json.loads(REGISTRY_PATH.read_text(encoding="utf-8"))["categories"]
INTENT = [k for k in REG if k.startswith("INTENT-")]


def test_seven_intent_categories():
    assert set(INTENT) == {
        "INTENT-MISSED",
        "INTENT-PARTIAL",
        "INTENT-AMBIGUOUS",
        "INTENT-UNVERIFIABLE",
        "INTENT-CONTRACT-VIOLATION",
        "INTENT-NO-ACS",
        "INTENT-CONTEXT-LEAK",
    }


def test_intent_categories_have_required_fields():
    for k in INTENT:
        e = REG[k]
        assert set(e) >= {"description", "agents", "wildcard", "priority", "affinity"}
        assert e["wildcard"] is False
        agents_or_affinity = list(e["affinity"]) + list(e["agents"])
        assert (
            "fg-540-intent-verifier" in agents_or_affinity
            or k == "INTENT-CONTEXT-LEAK"
        )


def test_impl_vote_categories_present():
    for k in (
        "IMPL-VOTE-TRIGGERED",
        "IMPL-VOTE-DEGRADED",
        "IMPL-VOTE-UNRESOLVED",
        "IMPL-VOTE-TIMEOUT",
        "IMPL-VOTE-WORKTREE-FAIL",
        "COST-SKIP-VOTE",
    ):
        assert k in REG
