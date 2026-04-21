"""Frontmatter builder + parser. Pure, deterministic, no I/O."""
from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any, Literal

from shared.config_validator import parse_yaml_subset

SCHEMA_VERSION = "1.0"
HANDOFF_VERSION = "1.0"

TriggerLevel = Literal["soft", "hard", "milestone", "terminal", "manual"]

# Characters that, when they begin a scalar, force YAML to interpret the value
# specially (list marker, mapping, flow collection, comment, anchor, alias,
# tag, literal/folded block, verbatim, reserved). We conservatively quote if
# any of these appears as the first non-space character.
_YAML_INDICATOR_PREFIXES = ("-", ":", "[", "{", "}", "]", "#", "&", "*", "!", "|", ">", "@", "`")


def _safe_yaml_scalar(v: str) -> str:
    """Return a YAML-safe rendering of a string scalar.

    Bare (unquoted) for ordinary values; double-quoted (with escapes) whenever
    the value contains characters that could break the frontmatter framing or
    be misinterpreted by the parser. This prevents newline-based injection of
    phantom keys or premature `---` terminators.
    """
    needs_quote = False
    if v == "" or v == "null":
        needs_quote = True
    elif any(c in v for c in ("\n", "\r", '"')):
        needs_quote = True
    else:
        stripped = v.lstrip()
        if stripped.startswith("---") or (stripped and stripped[0] in _YAML_INDICATOR_PREFIXES):
            needs_quote = True
    if not needs_quote:
        return v
    escaped = (
        v.replace("\\", "\\\\")
         .replace('"', '\\"')
         .replace("\n", "\\n")
         .replace("\r", "\\r")
    )
    return f'"{escaped}"'


def _opt_scalar(v: str | None) -> str:
    """Render an optional string field: literal ``null`` when None, else a safe scalar."""
    if v is None:
        return "null"
    return _safe_yaml_scalar(v)


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
    lines.append(f"run_id: {_safe_yaml_scalar(inp.run_id)}")
    lines.append(f"parent_run_id: {_opt_scalar(inp.parent_run_id)}")
    lines.append(f"stage: {_safe_yaml_scalar(inp.stage)}")
    lines.append(f"substage: {_opt_scalar(inp.substage)}")
    lines.append(f"mode: {_safe_yaml_scalar(inp.mode)}")
    lines.append(f"autonomous: {str(inp.autonomous).lower()}")
    lines.append(f"background: {str(inp.background).lower()}")
    lines.append(f"score: {inp.score}")
    lines.append(f"score_history: [{', '.join(str(s) for s in inp.score_history)}]")
    lines.append(f"convergence_phase: {inp.convergence_phase}")
    lines.append("convergence_counters:")
    for k in sorted(inp.convergence_counters):
        lines.append(f"  {k}: {inp.convergence_counters[k]}")
    lines.append(f"checkpoint_sha: {_opt_scalar(inp.checkpoint_sha)}")
    lines.append(f"checkpoint_path: {_opt_scalar(inp.checkpoint_path)}")
    lines.append(f"branch_name: {_opt_scalar(inp.branch_name)}")
    lines.append(f"worktree_path: {_opt_scalar(inp.worktree_path)}")
    lines.append(f"git_head: {_opt_scalar(inp.git_head)}")
    lines.append(f"commits_since_base: {inp.commits_since_base}")
    lines.append(f"open_askuserquestion: {_opt_scalar(inp.open_askuserquestion)}")
    lines.append(f"previous_handoff: {_opt_scalar(inp.previous_handoff)}")
    lines.append("trigger:")
    lines.append(f"  level: {_safe_yaml_scalar(inp.trigger_level)}")
    lines.append(f"  reason: {_safe_yaml_scalar(inp.trigger_reason)}")
    lines.append(f"  threshold_pct: {inp.trigger_threshold_pct if inp.trigger_threshold_pct is not None else 'null'}")
    lines.append(f"  tokens: {inp.trigger_tokens if inp.trigger_tokens is not None else 'null'}")
    lines.append(f"created_at: {_iso8601(inp.created_at)}")
    lines.append("---")
    return "\n".join(lines) + "\n"


def parse_frontmatter(text: str) -> ParsedFrontmatter:
    """Parse a frontmatter block. Raises ValueError on unknown schema_version."""
    if not text.startswith("---\n"):
        raise ValueError("frontmatter must start with '---\\n'")
    # Start search at the newline that terminates the opening '---' so an
    # empty body (``"---\n---\n"``) still matches the closing marker.
    end = text.find("\n---\n", 3)
    if end == -1:
        end = text.find("\n---", 3)
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
