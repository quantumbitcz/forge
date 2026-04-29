"""Phase 7 Wave 7 Task 38 — shared/stage-contract.md intent additions.

Stage 5 §5.B substep dispatches `fg-540-intent-verifier`; Stage 8 (codebase
numbers SHIP as 8, not 9 as the plan body suggested) entry-condition addition
gates on `INTENT-MISSED` and `verified_pct`.
"""
from __future__ import annotations

from pathlib import Path

SC = (
    Path(__file__).parent.parent.parent / "shared" / "stage-contract.md"
).read_text(encoding="utf-8")


def test_stage_5_intent_substep() -> None:
    assert "Intent verification" in SC or "5.B" in SC
    assert "fg-540-intent-verifier" in SC


def test_stage_8_intent_entry() -> None:
    assert "INTENT-MISSED" in SC
    assert "verified_pct" in SC
