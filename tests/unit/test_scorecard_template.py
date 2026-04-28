"""SCORECARD.md exists, uses the expected section markers, and README+CLAUDE.md link to it."""
from __future__ import annotations
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def test_scorecard_template_exists() -> None:
    sc = ROOT / "SCORECARD.md"
    assert sc.is_file()
    text = sc.read_text()
    for marker in ("<!-- section:header -->", "<!-- section:this-week -->",
                   "<!-- section:last-12-weeks -->", "<!-- section:regressions -->",
                   "<!-- section:cost-per-solve -->", "<!-- section:vs-peers -->"):
        assert marker in text


def test_readme_links_to_scorecard() -> None:
    readme = (ROOT / "README.md").read_text()
    assert "SCORECARD.md" in readme
    assert "Measured" in readme   # Badge text


def test_claude_md_links_to_scorecard() -> None:
    claude = (ROOT / "CLAUDE.md").read_text()
    assert "SCORECARD.md" in claude
