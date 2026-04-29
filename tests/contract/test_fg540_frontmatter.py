"""Contract test: fg-540-intent-verifier frontmatter excludes Bash/Edit/Write."""
from __future__ import annotations

import re
from pathlib import Path

import yaml

REPO_ROOT = Path(__file__).parent.parent.parent
AGENT = (REPO_ROOT / "agents" / "fg-540-intent-verifier.md").read_text(encoding="utf-8")


def _frontmatter(text: str) -> str:
    m = re.match(r"^---\n(.*?)\n---\n", text, re.DOTALL)
    assert m, "no frontmatter"
    return m.group(1)


def test_name_matches_filename():
    assert re.search(r"^name: fg-540-intent-verifier$", _frontmatter(AGENT), re.MULTILINE)


def test_tools_are_exactly_four():
    fm = _frontmatter(AGENT)
    m = re.search(r"^tools:\s*\[([^\]]+)\]", fm, re.MULTILINE)
    assert m, "tools not inline-list"
    tools = {t.strip().strip("'\"") for t in m.group(1).split(",")}
    assert tools == {"Read", "Grep", "Glob", "WebFetch"}


def test_forbidden_tools_absent():
    fm = _frontmatter(AGENT)
    data = yaml.safe_load(fm)
    tools = set(data.get("tools", []))
    forbidden = {"Bash", "Edit", "Write", "Agent", "Task", "TaskCreate", "TaskUpdate", "NotebookEdit"}
    assert tools.isdisjoint(forbidden), f"forbidden tools present: {tools & forbidden}"


def test_ui_tier_4():
    """fg-540 is Tier 4 (no UI capabilities) — it operates fresh-context and
    must not surface in the user-facing task tracker. Adding TaskCreate/
    TaskUpdate would also conflict with the forbidden-tools assertion above.
    """
    fm = _frontmatter(AGENT)
    assert "tasks: false" in fm
    assert "ask: false" in fm
    assert "plan_mode: false" in fm


def test_context_exclusion_clause_present():
    assert "Context Exclusion Contract" in AGENT
    assert "INTENT-CONTRACT-VIOLATION" in AGENT
