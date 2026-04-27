"""Contract test: fg-540-intent-verifier frontmatter excludes Bash/Edit/Write."""
from __future__ import annotations

import re
from pathlib import Path

REPO_ROOT = Path(__file__).parent.parent.parent
AGENT = (REPO_ROOT / "agents" / "fg-540-intent-verifier.md").read_text()


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
    for forbidden in (
        "Bash", "Edit", "Write", "Agent", "Task",
        "TaskCreate", "TaskUpdate", "NotebookEdit",
    ):
        assert forbidden not in fm, f"{forbidden} present in fg-540 frontmatter"


def test_ui_tier_3():
    fm = _frontmatter(AGENT)
    assert "tasks: true" in fm
    assert "ask: false" in fm
    assert "plan_mode: false" in fm


def test_context_exclusion_clause_present():
    assert "Context Exclusion Contract" in AGENT
    assert "INTENT-CONTRACT-VIOLATION" in AGENT
