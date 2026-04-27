"""Phase 7 F36 — fg-300-implementer voting mode dispatch documentation."""
from pathlib import Path

A = (Path(__file__).parent.parent.parent / "agents" / "fg-300-implementer.md").read_text()


def test_voting_mode_section_present():
    assert "Voting Mode" in A
    assert "vote_sample" in A
    assert "vote_tiebreak" in A


def test_reflect_skipped_under_vote_sample():
    idx = A.find("Voting Mode")
    section = A[idx:idx + 4000]
    assert "skip" in section.lower()
    assert "REFLECT" in section
