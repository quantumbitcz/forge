"""Phase 7 Wave 7 Task 37 — CLAUDE.md agent count + F35/F36 callsites.

Asserts the agent rollover (48 → 50 → 51) landed and the Phase 7 features are
surfaced. The `\\b51 agents\\b` token only appears in the prose-form callsite
("All 51 agents"); the §Agents heading uses the form `Agents (51,` which is
not word-boundary-flanked. So the assertion is one prose match + zero stale
`\\b48` references — that captures the intent without false-positive on
differently-formatted callsites elsewhere.
"""
from __future__ import annotations

import re
from pathlib import Path

CM = (Path(__file__).parent.parent.parent / "CLAUDE.md").read_text(encoding="utf-8")


def test_no_48_agents_references() -> None:
    assert not re.search(r"\b(48 agents|48 total)\b", CM)


def test_50_agents_callsite_present() -> None:
    assert re.search(r"\b51 agents\b", CM), (
        "expected at least one prose `51 agents` callsite in CLAUDE.md"
    )


def test_f35_row_present() -> None:
    assert "F35" in CM or "Intent Verification Gate" in CM
    assert "fg-540-intent-verifier" in CM


def test_f36_row_present() -> None:
    assert "F36" in CM or "Implementer Voting" in CM
    assert "fg-302-diff-judge" in CM
