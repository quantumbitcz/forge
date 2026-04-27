"""Contract test: every agents/fg-*.md carries a complete ui: block.

Parse first --- fenced YAML block in each agent file, validate against a
strict pydantic model. ui: MUST be a mapping with exactly {tasks, ask, plan_mode}
as booleans — no extra keys, no missing keys, no non-bool values.

Enforces shared/agents.md §19 "Implicit Tier-4-by-omission is no longer
accepted" and Phase 2 design spec Component 1.

Run in CI only (no local test runs per user memory).
"""
from __future__ import annotations

from pathlib import Path

import pytest
import yaml
from pydantic import BaseModel, ValidationError

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
AGENTS_DIR = REPO_ROOT / "agents"


class UiBlock(BaseModel, extra="forbid"):
    tasks: bool
    ask: bool
    plan_mode: bool


class AgentFrontmatter(BaseModel, extra="allow"):
    name: str
    ui: UiBlock


def _parse_frontmatter(path: Path) -> dict:
    text = path.read_text(encoding="utf-8")
    # CRLF-safe: Windows checkouts may have \r\n line endings. splitlines()
    # discards both \n and \r\n; then strip any stray trailing \r on the
    # opening fence before comparing.
    lines = text.splitlines()
    if not lines or lines[0].rstrip("\r") != "---":
        raise ValueError(f"{path}: no frontmatter opening fence")
    try:
        # Find closing fence (second line that is exactly "---").
        end_idx = next(
            i for i, ln in enumerate(lines[1:], start=1) if ln.rstrip("\r") == "---"
        )
    except StopIteration as exc:
        raise ValueError(f"{path}: no frontmatter closing fence") from exc
    return yaml.safe_load("\n".join(lines[1:end_idx])) or {}


def _agent_files() -> list[Path]:
    return sorted(AGENTS_DIR.glob("fg-*.md"))


@pytest.mark.parametrize("agent_path", _agent_files(), ids=lambda p: p.name)
def test_agent_has_valid_ui_block(agent_path: Path) -> None:
    try:
        fm = _parse_frontmatter(agent_path)
    except ValueError as exc:
        pytest.fail(f"{agent_path.name}: frontmatter parse error: {exc}")
    try:
        AgentFrontmatter(**fm)
    except ValidationError as exc:
        pytest.fail(f"{agent_path.name}: frontmatter validation error:\n{exc}")


def test_all_48_agents_discovered() -> None:
    """Sanity: the glob must find the expected roster count."""
    files = _agent_files()
    assert len(files) >= 48, f"expected >= 48 fg-*.md agents, got {len(files)}"
