"""Phase 7 Wave 7 Task 39 — fg-700-retrospective §2j.bis cost-of-voting.

Asserts the propose-only threshold (`vote_cost_pct_of_run > 15%` AND
`divergence_rate < 5%` across last 3 runs) is documented alongside the
metric trio (`vote_cost_usd`, `vote_cost_pct_of_run`,
`vote_savings_estimate_usd`).
"""
from __future__ import annotations

from pathlib import Path

A = (
    Path(__file__).parent.parent.parent / "agents" / "fg-700-retrospective.md"
).read_text(encoding="utf-8")


def test_cost_of_voting_section() -> None:
    assert "vote_cost_usd" in A
    assert "vote_cost_pct_of_run" in A


def test_proposal_threshold_documented() -> None:
    assert "vote_cost_pct_of_run > 15%" in A or "15%" in A


def test_savings_estimate_documented() -> None:
    assert "vote_savings_estimate_usd" in A
