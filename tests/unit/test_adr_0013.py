"""ADR 0013 exists and covers the Phase 8 decisions listed in the spec."""

from __future__ import annotations

from pathlib import Path

ADR = Path(__file__).resolve().parents[2] / "docs" / "adr" / "0013-weekly-benchmark-extension.md"


def test_adr_exists() -> None:
    assert ADR.is_file()


def test_adr_covers_decisions() -> None:
    text = ADR.read_text()
    for phrase in (
        "extend-in-place",
        "0.9",
        "10pp",
        "6-cell matrix",
        "bot-commit",
        "personal tool",
        "SWE-bench",
    ):
        assert phrase in text, f"ADR missing decision: {phrase}"
