"""benchmark README documents the four operator workflows."""

from __future__ import annotations

from pathlib import Path

README = Path(__file__).resolve().parents[2] / "tests" / "evals" / "benchmark" / "README.md"


def test_covers_workflows() -> None:
    text = README.read_text()
    for phrase in (
        "curate",
        "runner",
        "render_scorecard",
        "refresh_baseline",
        "PHASE_8_CORPUS_GATE",
        "SCORECARD.md",
    ):
        assert phrase in text
