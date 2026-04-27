"""Phase 7 Wave 5 Task 27 — shared/agents.md registry covers fg-540 + fg-302."""
import re
from pathlib import Path

A = (Path(__file__).parent.parent.parent / "shared" / "agents.md").read_text()


def test_fg540_in_registry():
    assert "fg-540-intent-verifier" in A
    # Tier 3
    assert re.search(r"fg-540-intent-verifier.*\b3\b", A)


def test_fg302_in_registry():
    assert "fg-302-diff-judge" in A
    assert re.search(r"fg-302-diff-judge.*\b4\b", A)


def test_no_48_references():
    # Grep gate: no "48 agents" or "48 total"
    assert not re.search(r"\b(48 agents|48 total)\b", A)
