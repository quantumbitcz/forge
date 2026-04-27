"""Phase 7 F35 — fg-590 pre-ship intent clearance documentation."""
from pathlib import Path

A = (Path(__file__).parent.parent.parent / "agents" / "fg-590-pre-ship-verifier.md").read_text()


def test_intent_clauses_present():
    assert "open_intent_critical" in A
    assert "verified_pct" in A
    assert "strict_ac_required_pct" in A


def test_block_reasons_enumerated():
    for reason in ("intent-missed:", "intent-threshold:", "intent-unreachable-runtime:"):
        assert reason in A


def test_vacuous_pass_documented():
    # verified_pct is None path must be explicit
    assert "verified_pct is None" in A
    assert "vacuous" in A.lower()


def test_no_acs_strict_mode_documented():
    assert "intent-no-acs-strict" in A or "living_specs.strict_mode" in A
