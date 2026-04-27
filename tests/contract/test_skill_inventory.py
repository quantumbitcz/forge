"""Contract test: skill count is exactly 28; /forge-help is absent.

Also greps CLAUDE.md, README.md, and shared/* for stale forge-help references.
Excludes CHANGELOG.md (historical), docs/superpowers/ (specs + plans), and
shared/feature-lifecycle.md (which uses forge-example placeholders, never
forge-help).
"""
from __future__ import annotations

from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
SKILLS_DIR = REPO_ROOT / "skills"


def test_skill_count_is_28() -> None:
    dirs = [p for p in SKILLS_DIR.iterdir() if p.is_dir() and (p / "SKILL.md").exists()]
    assert len(dirs) == 28, f"expected 28 skills, got {len(dirs)}: {sorted(p.name for p in dirs)}"


def test_forge_help_directory_is_gone() -> None:
    assert not (SKILLS_DIR / "forge-help").exists(), "skills/forge-help must be deleted"


@pytest.mark.parametrize(
    "relpath",
    [
        "CLAUDE.md",
        "README.md",
        "shared/skill-contract.md",
        "shared/skill-grammar.md",
        "shared/agents.md",
        "shared/agent-philosophy.md",
        "shared/feature-matrix.md",
    ],
    ids=lambda s: s,
)
def test_no_stale_forge_help_references(relpath: str) -> None:
    path = REPO_ROOT / relpath
    if not path.exists():
        pytest.skip(f"{relpath} missing (expected for shared/skill-grammar.md before Commit 3 lands)")
    text = path.read_text(encoding="utf-8")
    assert "forge-help" not in text, f"{relpath} still references forge-help"


def test_skill_contract_lists_forge_handoff() -> None:
    path = REPO_ROOT / "shared" / "skill-contract.md"
    text = path.read_text(encoding="utf-8")
    assert "forge-handoff" in text, "shared/skill-contract.md must list forge-handoff in writes"
    assert "**Total: 28.**" in text, "shared/skill-contract.md §4 header must read Total: 28"
