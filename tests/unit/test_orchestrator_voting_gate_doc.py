"""Phase 7 F36 — fg-100-orchestrator voting gate pseudocode documentation."""
from pathlib import Path

A = (Path(__file__).parent.parent.parent / "agents" / "fg-100-orchestrator.md").read_text(encoding="utf-8")


def test_voting_gate_pseudocode_present():
    assert "should_vote" in A
    assert "dispatch_with_voting" in A
    assert "skip_if_budget_remaining_below_pct" in A


def test_cost_skip_uses_phase6_fields():
    # Must use remaining_usd / ceiling_usd, NOT pct_consumed (which Phase 6
    # exposes elsewhere — the orchestrator's voting gate computes the
    # remaining fraction explicitly for clarity).
    idx = A.find("should_vote")
    section = A[idx:idx + 2000]
    assert "remaining_usd" in section
    assert "ceiling_usd" in section
    assert "pct_consumed" not in section  # strict — no phantom field
