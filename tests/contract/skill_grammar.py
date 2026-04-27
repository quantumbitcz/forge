"""Contract test: SKILL.md frontmatter + body conform to shared/skill-grammar.md.

Rules:
1. Frontmatter top-level keys ⊆ {name, description, allowed-tools, disable-model-invocation, ui}.
2. `description:` starts with `[read-only]` or `[writes]`.
3. `allowed-tools` entries are in the known-tools allow-set (warning on unknown,
   error on Levenshtein ≤ 2 typos).
4. [read-only] skills MUST NOT contain a `## Subcommands` heading.
5. ui: (if present) parses to {tasks, ask, plan_mode} booleans exactly.
6. forge-status contains `## Config validation summary` and `## Recent hook failures`.
7. forge-verify does not mention `--config` anywhere.
"""
from __future__ import annotations

from pathlib import Path

import pytest
import warnings
import yaml
from pydantic import BaseModel, ValidationError

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
SKILLS_DIR = REPO_ROOT / "skills"

KNOWN_TOOLS: set[str] = {
    "Read", "Edit", "Write", "Glob", "Grep", "Bash",
    "Task", "TaskCreate", "TaskUpdate",
    "AskUserQuestion", "EnterPlanMode", "ExitPlanMode",
    "Agent", "WebFetch", "WebSearch",
    "neo4j-mcp", "playwright-mcp", "linear-mcp", "slack-mcp",
    "context7-mcp", "figma-mcp", "excalidraw-mcp",
    "mcp__plugin_context7_context7__resolve-library-id",
    "mcp__plugin_context7_context7__query-docs",
}

FRONTMATTER_ALLOW = {"name", "description", "allowed-tools", "disable-model-invocation", "ui"}


class UiBlock(BaseModel, extra="forbid"):
    tasks: bool
    ask: bool
    plan_mode: bool


def _levenshtein(a: str, b: str) -> int:
    if a == b:
        return 0
    if len(a) < len(b):
        a, b = b, a
    if len(b) == 0:
        return len(a)
    prev = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        curr = [i]
        for j, cb in enumerate(b, 1):
            curr.append(min(curr[-1] + 1, prev[j] + 1, prev[j - 1] + (ca != cb)))
        prev = curr
    return prev[-1]


def _parse_skill(path: Path) -> tuple[dict, str]:
    text = path.read_text(encoding="utf-8")
    # CRLF-safe: Windows checkouts may have \r\n line endings. splitlines()
    # handles both uniformly. Compare each fence line after stripping \r.
    lines = text.splitlines()
    assert lines and lines[0].rstrip("\r") == "---", f"{path}: missing frontmatter fence"
    end_idx = next(
        i for i, ln in enumerate(lines[1:], start=1) if ln.rstrip("\r") == "---"
    )
    fm = yaml.safe_load("\n".join(lines[1:end_idx])) or {}
    body = "\n".join(lines[end_idx + 1:])
    return fm, body


def _skill_files() -> list[Path]:
    return sorted(p for p in SKILLS_DIR.glob("*/SKILL.md"))


@pytest.mark.parametrize("skill_path", _skill_files(), ids=lambda p: p.parent.name)
def test_frontmatter_keys_allowed(skill_path: Path) -> None:
    fm, _ = _parse_skill(skill_path)
    extra = set(fm.keys()) - FRONTMATTER_ALLOW
    assert not extra, f"{skill_path.parent.name}: unknown frontmatter keys: {sorted(extra)}"


@pytest.mark.parametrize("skill_path", _skill_files(), ids=lambda p: p.parent.name)
def test_description_prefix(skill_path: Path) -> None:
    fm, _ = _parse_skill(skill_path)
    desc = fm.get("description", "")
    assert desc.startswith("[read-only]") or desc.startswith("[writes]"), (
        f"{skill_path.parent.name}: description must start with [read-only] or [writes]"
    )


@pytest.mark.parametrize("skill_path", _skill_files(), ids=lambda p: p.parent.name)
def test_allowed_tools_values(skill_path: Path) -> None:
    fm, _ = _parse_skill(skill_path)
    tools = fm.get("allowed-tools", []) or []
    typos: list[tuple[str, str]] = []
    for t in tools:
        if t in KNOWN_TOOLS:
            continue
        for known in KNOWN_TOOLS:
            if 0 < _levenshtein(t, known) <= 2:
                typos.append((t, known))
                break
        else:
            warnings.warn(f"{skill_path.parent.name}: unknown tool '{t}' (not a typo)")
    assert not typos, f"{skill_path.parent.name}: likely typos: {typos}"


@pytest.mark.parametrize("skill_path", _skill_files(), ids=lambda p: p.parent.name)
def test_readonly_skill_has_no_subcommands_heading(skill_path: Path) -> None:
    fm, body = _parse_skill(skill_path)
    if fm.get("description", "").startswith("[read-only]"):
        assert "\n## Subcommands" not in body, (
            f"{skill_path.parent.name}: [read-only] skill must not carry a ## Subcommands heading"
        )


@pytest.mark.parametrize("skill_path", _skill_files(), ids=lambda p: p.parent.name)
def test_ui_block_shape(skill_path: Path) -> None:
    fm, _ = _parse_skill(skill_path)
    if "ui" in fm:
        try:
            UiBlock(**fm["ui"])
        except ValidationError as exc:
            pytest.fail(f"{skill_path.parent.name}: ui block invalid:\n{exc}")


def test_forge_status_has_required_sections() -> None:
    _, body = _parse_skill(SKILLS_DIR / "forge-status" / "SKILL.md")
    assert "\n## Config validation summary" in body, "forge-status missing Config validation summary"
    assert "\n## Recent hook failures" in body, "forge-status missing Recent hook failures"


def test_forge_verify_has_no_config_references() -> None:
    path = SKILLS_DIR / "forge-verify" / "SKILL.md"
    text = path.read_text(encoding="utf-8")
    assert "--config" not in text, "forge-verify must not mention --config (removed in Phase 2)"
    assert "Subcommand: config" not in text, "forge-verify must not have Subcommand: config section"
