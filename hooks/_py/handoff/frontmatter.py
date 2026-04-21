"""Frontmatter builder + parser. Pure, deterministic, no I/O."""
from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any, Literal

from shared.config_validator import parse_yaml_subset

SCHEMA_VERSION = "1.0"
HANDOFF_VERSION = "1.0"

TriggerLevel = Literal["soft", "hard", "milestone", "terminal", "manual"]


@dataclass
class FrontmatterInput:
    run_id: str
    parent_run_id: str | None
    stage: str
    substage: str | None
    mode: str
    autonomous: bool
    background: bool
    score: int
    score_history: list[int]
    convergence_phase: str
    convergence_counters: dict[str, int]
    checkpoint_sha: str | None
    checkpoint_path: str | None
    branch_name: str | None
    worktree_path: str | None
    git_head: str | None
    commits_since_base: int
    open_askuserquestion: str | None
    previous_handoff: str | None
    trigger_level: TriggerLevel
    trigger_reason: str
    trigger_threshold_pct: int | None
    trigger_tokens: int | None
    created_at: datetime


@dataclass
class ParsedFrontmatter:
    schema_version: str
    handoff_version: str
    run_id: str
    stage: str
    mode: str
    autonomous: bool
    score: int
    score_history: list[int]
    checkpoint_sha: str | None
    branch_name: str | None
    git_head: str | None
    commits_since_base: int
    trigger_level: str
    trigger_reason: str
    created_at: str
    raw: dict[str, Any]


def _iso8601(dt: datetime) -> str:
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def build_frontmatter(inp: FrontmatterInput) -> str:
    """Render a frontmatter block. Stable key ordering, deterministic output."""
    lines: list[str] = ["---"]
    lines.append(f"schema_version: {SCHEMA_VERSION}")
    lines.append(f"handoff_version: {HANDOFF_VERSION}")
    lines.append(f"run_id: {inp.run_id}")
    lines.append(f"parent_run_id: {inp.parent_run_id or 'null'}")
    lines.append(f"stage: {inp.stage}")
    lines.append(f"substage: {inp.substage or 'null'}")
    lines.append(f"mode: {inp.mode}")
    lines.append(f"autonomous: {str(inp.autonomous).lower()}")
    lines.append(f"background: {str(inp.background).lower()}")
    lines.append(f"score: {inp.score}")
    lines.append(f"score_history: [{', '.join(str(s) for s in inp.score_history)}]")
    lines.append(f"convergence_phase: {inp.convergence_phase}")
    lines.append("convergence_counters:")
    for k in sorted(inp.convergence_counters):
        lines.append(f"  {k}: {inp.convergence_counters[k]}")
    lines.append(f"checkpoint_sha: {inp.checkpoint_sha or 'null'}")
    lines.append(f"checkpoint_path: {inp.checkpoint_path or 'null'}")
    lines.append(f"branch_name: {inp.branch_name or 'null'}")
    lines.append(f"worktree_path: {inp.worktree_path or 'null'}")
    lines.append(f"git_head: {inp.git_head or 'null'}")
    lines.append(f"commits_since_base: {inp.commits_since_base}")
    lines.append(f"open_askuserquestion: {inp.open_askuserquestion or 'null'}")
    lines.append(f"previous_handoff: {inp.previous_handoff or 'null'}")
    lines.append("trigger:")
    lines.append(f"  level: {inp.trigger_level}")
    lines.append(f"  reason: {inp.trigger_reason}")
    lines.append(f"  threshold_pct: {inp.trigger_threshold_pct if inp.trigger_threshold_pct is not None else 'null'}")
    lines.append(f"  tokens: {inp.trigger_tokens if inp.trigger_tokens is not None else 'null'}")
    lines.append(f"created_at: {_iso8601(inp.created_at)}")
    lines.append("---")
    return "\n".join(lines) + "\n"


def parse_frontmatter(text: str) -> ParsedFrontmatter:
    """Parse a frontmatter block. Raises ValueError on unknown schema_version."""
    if not text.startswith("---\n"):
        raise ValueError("frontmatter must start with '---\\n'")
    end = text.find("\n---\n", 4)
    if end == -1:
        end = text.find("\n---", 4)
    if end == -1:
        raise ValueError("frontmatter missing closing '---'")
    body = text[4:end]
    data = parse_yaml_subset(body)
    if not isinstance(data, dict):
        raise ValueError("frontmatter body must parse to a mapping")
    sv = str(data.get("schema_version", ""))
    if sv != SCHEMA_VERSION:
        raise ValueError(f"unsupported schema_version: {sv!r}")
    trigger = data.get("trigger") or {}
    return ParsedFrontmatter(
        schema_version=sv,
        handoff_version=str(data.get("handoff_version", "")),
        run_id=str(data.get("run_id", "")),
        stage=str(data.get("stage", "")),
        mode=str(data.get("mode", "")),
        autonomous=bool(data.get("autonomous", False)),
        score=int(data.get("score", 0)),
        score_history=[int(s) for s in (data.get("score_history") or [])],
        checkpoint_sha=(data.get("checkpoint_sha") or None),
        branch_name=(data.get("branch_name") or None),
        git_head=(data.get("git_head") or None),
        commits_since_base=int(data.get("commits_since_base", 0)),
        trigger_level=str(trigger.get("level", "")),
        trigger_reason=str(trigger.get("reason", "")),
        created_at=str(data.get("created_at", "")),
        raw=data,
    )
