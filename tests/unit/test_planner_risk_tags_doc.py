"""Phase 7 F36 — fg-200-planner risk_tags emission documentation."""
from pathlib import Path

A = (Path(__file__).parent.parent.parent / "agents" / "fg-200-planner.md").read_text()


def test_risk_tags_vocabulary_documented():
    for tag in ("high", "data-mutation", "auth", "payment", "concurrency", "migration"):
        assert f"`{tag}`" in A, f"tag {tag} missing from planner doc"


def test_risk_tag_emission_section_present():
    assert "Risk Tag Emission" in A
    assert "risk_tags" in A
