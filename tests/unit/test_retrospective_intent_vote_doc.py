"""Phase 7 Wave 5 Task 23 — fg-700-retrospective §2j Intent & Vote Analytics doc."""
from pathlib import Path

A = (Path(__file__).parent.parent.parent / "agents" / "fg-700-retrospective.md").read_text()


def test_analytics_section_present():
    assert "Intent & Vote Analytics" in A


def test_verified_and_unverifiable_rows_separate():
    assert "verified_pct" in A
    assert "unverifiable_pct" in A
    # Spec requirement: rendered as separate rows
    assert "separate rows" in A or "separate row" in A


def test_rule_11_documented():
    assert "Rule 11" in A
    assert "living_specs.strict_mode" in A
