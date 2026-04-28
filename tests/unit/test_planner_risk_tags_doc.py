"""Phase 7 F36 — fg-200-planner risk_tags emission documentation."""
from pathlib import Path

from hooks._py.risk_tags import BASE_RISK_TAGS

A = (Path(__file__).parent.parent.parent / "agents" / "fg-200-planner.md").read_text()


def test_risk_tags_vocabulary_documented():
    for tag in ("high", "data-mutation", "auth", "payment", "concurrency", "migration"):
        assert f"`{tag}`" in A, f"tag {tag} missing from planner doc"


def test_risk_tag_emission_section_present():
    assert "Risk Tag Emission" in A
    assert "risk_tags" in A


def test_all_canonical_tags_in_planner_doc():
    """Every tag in BASE_RISK_TAGS must appear in the planner doc as a backticked token."""
    for tag in BASE_RISK_TAGS:
        assert f"`{tag}`" in A, f"canonical tag {tag} missing from planner doc"
