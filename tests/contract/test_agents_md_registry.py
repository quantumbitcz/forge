"""Phase 7 Wave 5 Task 27 — shared/agents.md registry covers fg-540 + fg-302."""
import re
from pathlib import Path

A = (Path(__file__).parent.parent.parent / "shared" / "agents.md").read_text(encoding="utf-8")


def test_fg540_in_registry():
    assert "fg-540-intent-verifier" in A
    # Tier 4 (no UI capabilities — fresh-context probes only). Phase 7 originally
    # placed fg-540 at Tier 3, but the contract evolved: fg-540 must not surface
    # task tracker entries (which would imply TaskCreate/TaskUpdate tools, in
    # turn forbidden by test_fg540_frontmatter.test_forbidden_tools_absent).
    assert re.search(r"fg-540-intent-verifier.*\b4\b", A)


def test_fg302_in_registry():
    assert "fg-302-diff-judge" in A
    assert re.search(r"fg-302-diff-judge.*\b4\b", A)


def test_no_48_references():
    # Grep gate: no "48 agents" or "48 total"
    assert not re.search(r"\b(48 agents|48 total)\b", A)
