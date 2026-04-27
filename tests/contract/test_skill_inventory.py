"""Contract test: skill count is exactly 28; /forge-help is absent.

Also sweeps the repo for stale forge-help references in .md and .bats files.
Excludes CHANGELOG.md (historical), docs/superpowers/{plans,specs}/ (frozen
design docs), and the test file itself (mentions the string for documentation).
"""
from __future__ import annotations

from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
SKILLS_DIR = REPO_ROOT / "skills"

# Directories whose contents are excluded from the forge-help reference sweep.
# - CHANGELOG entries are historical and immutable.
# - docs/superpowers/{plans,specs} are frozen design artefacts.
# - Build/cache dirs and the kanban/state areas under .forge/ never count.
_EXCLUDED_DIRS = {
    ".git",
    ".forge",
    ".venv",
    "node_modules",
    "__pycache__",
    "tests/contract/__pycache__",
}
_EXCLUDED_PATH_PARTS = (
    ("docs", "superpowers", "plans"),
    ("docs", "superpowers", "specs"),
)
_EXCLUDED_FILES = {
    "CHANGELOG.md",
    # The contract test itself references the string for documentation.
    "tests/contract/test_skill_inventory.py",
}


def _is_excluded(path: Path) -> bool:
    rel = path.relative_to(REPO_ROOT)
    parts = rel.parts
    if any(seg in _EXCLUDED_DIRS for seg in parts):
        return True
    for prefix in _EXCLUDED_PATH_PARTS:
        if len(parts) >= len(prefix) and parts[: len(prefix)] == prefix:
            return True
    if str(rel) in _EXCLUDED_FILES:
        return True
    return False


def _sweep_targets() -> list[Path]:
    targets: list[Path] = []
    for ext in ("*.md", "*.bats"):
        for path in REPO_ROOT.rglob(ext):
            if path.is_file() and not _is_excluded(path):
                targets.append(path)
    return sorted(targets)


def test_skill_count_is_28() -> None:
    dirs = [p for p in SKILLS_DIR.iterdir() if p.is_dir() and (p / "SKILL.md").exists()]
    assert len(dirs) == 28, f"expected 28 skills, got {len(dirs)}: {sorted(p.name for p in dirs)}"


def test_forge_help_directory_is_gone() -> None:
    assert not (SKILLS_DIR / "forge-help").exists(), "skills/forge-help must be deleted"


@pytest.mark.parametrize("path", _sweep_targets(), ids=lambda p: str(p.relative_to(REPO_ROOT)))
def test_no_stale_forge_help_references(path: Path) -> None:
    text = path.read_text(encoding="utf-8")
    assert "forge-help" not in text, (
        f"{path.relative_to(REPO_ROOT)} still references forge-help"
    )


def test_skill_contract_lists_forge_handoff() -> None:
    path = REPO_ROOT / "shared" / "skill-contract.md"
    text = path.read_text(encoding="utf-8")
    assert "forge-handoff" in text, "shared/skill-contract.md must list forge-handoff in writes"
    assert "**Total: 28.**" in text, "shared/skill-contract.md §4 header must read Total: 28"
