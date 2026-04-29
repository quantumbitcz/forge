"""Phase 7 Wave 5 Task 26 — living-specifications + confidence-scoring cross-refs."""
from pathlib import Path

LS = (Path(__file__).parent.parent.parent / "shared" / "living-specifications.md").read_text(encoding="utf-8")
CS = (Path(__file__).parent.parent.parent / "shared" / "confidence-scoring.md").read_text(encoding="utf-8")


def test_living_specs_references_fg540():
    assert "fg-540-intent-verifier" in LS
    assert "Intent Verification Integration" in LS


def test_confidence_scoring_references_voting():
    assert "impl_voting.trigger_on_confidence_below" in CS
    assert "Voting Gate" in CS
