from pathlib import Path


def test_changelog_3_8_0_entry() -> None:
    text = (Path(__file__).resolve().parents[2] / "CHANGELOG.md").read_text()
    assert "[6.0.0]" in text
    lowered = text.lower()
    for phrase in ("benchmark", "scorecard.md", "weekly"):
        assert phrase in lowered
