"""Writer orchestration: state → rendered markdown → atomic file write → state + alert updates."""
from __future__ import annotations

import json
import os
import re
import subprocess
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Literal

from hooks._py.handoff import alerts, sections
from hooks._py.handoff.frontmatter import FrontmatterInput, build_frontmatter
from hooks._py.handoff.redaction import redact_handoff_text
from hooks._py.io_utils import atomic_json_update

Level = Literal["soft", "hard", "milestone", "terminal", "manual"]
Variant = Literal["light", "full"]

SIZE_CAP_BYTES = {"light": 12 * 1024, "full": 60 * 1024}
RATE_LIMIT_MINUTES = 15


@dataclass
class WriteRequest:
    run_id: str
    level: Level
    reason: str
    variant: Variant = "full"
    trigger_threshold_pct: int | None = None
    trigger_tokens: int | None = None
    slug_override: str | None = None
    now: datetime = field(default_factory=lambda: datetime.now(timezone.utc))


@dataclass
class WriteResult:
    path: Path
    suppressed: bool
    reason: str = ""


def write_handoff(req: WriteRequest, forge_dir: Path) -> WriteResult:
    """Render and atomically write a handoff artefact for the given run.

    Reads state from ``<forge_dir>/state.json``, renders the frontmatter + body +
    resume-prompt block, pipes through redaction (fail-closed: any redactor
    exception propagates and NO file is written), enforces the size cap, writes
    atomically via ``.tmp`` + ``Path.replace()``, updates ``state.json.handoff.*``
    via ``atomic_json_update``, and emits a ``HANDOFF_WRITTEN`` alert.

    Rate limit: writes within ``RATE_LIMIT_MINUTES`` of the last one are suppressed
    and bump ``state.json.handoff.suppressed_by_rate_limit``. ``terminal`` and
    ``manual`` levels bypass the rate limit.

    Returns ``WriteResult(path=Path(), suppressed=True, reason=<...>)`` without
    writing a file if: state.json is missing/malformed, rate limit applies, or
    filename collision exhaustion.
    """
    state = _read_state(forge_dir)
    if state is None:
        return WriteResult(path=Path(), suppressed=True, reason="no_state_json")

    # Rate-limit check (terminal and manual always fire)
    if req.level not in ("terminal", "manual") and _rate_limited(state, req.now):
        _bump_suppressed(forge_dir)
        return WriteResult(path=Path(), suppressed=True, reason="rate_limited")

    slug = req.slug_override or _default_slug(state)
    timestamp = req.now.strftime("%Y-%m-%d-%H%M%S")
    filename = f"{timestamp}-{req.level}-{slug}.md"
    handoffs_dir = forge_dir / "runs" / req.run_id / "handoffs"
    handoffs_dir.mkdir(parents=True, exist_ok=True)
    target = handoffs_dir / filename
    target = _resolve_collision(target)
    if target is None:
        return WriteResult(path=Path(), suppressed=True, reason="collision_exhausted")

    # Render content
    fm_input = _build_frontmatter_input(req, state)
    body = _render_body(req, state)
    resume_block = _render_resume_block(req, target, state)
    raw_text = build_frontmatter(fm_input) + "\n" + body + "\n---\n\n" + resume_block

    # Redact (fail-closed)
    redacted = redact_handoff_text(raw_text)

    # Enforce size cap
    enforced = _enforce_size_cap(redacted, SIZE_CAP_BYTES[req.variant])

    # Atomic write — file first, state update after.
    # Rationale: a handoff file without a chain entry is recoverable (the resumer
    # can scan the handoffs/ directory); a chain entry without a file is not.
    # If _update_state_chain fails, the orphaned file can still be resumed from.
    tmp = target.with_suffix(target.suffix + ".tmp")
    tmp.write_text(enforced, encoding="utf-8")
    tmp.replace(target)

    # State chain update
    _update_state_chain(forge_dir, req, target)

    chain_limit = int(os.environ.get("FORGE_HANDOFF_CHAIN_LIMIT", "50"))
    _rotate_if_needed(forge_dir, req.run_id, chain_limit)

    # Build a signal-dense preview from state (not the resume-block header)
    preview = (
        f"{state.get('story_state', 'unknown')} "
        f"score={state.get('score', 0)}: "
        f"{str(state.get('requirement', ''))[:80]}"
    )
    alerts.emit_handoff_written(
        forge_dir=forge_dir,
        run_id=req.run_id,
        level=req.level,
        path=str(target),
        reason=req.reason,
        resume_prompt_preview=preview,
        created_at=req.now,
    )

    # Index into FTS5 run-history.db (best-effort)
    try:
        from hooks._py.handoff.search import index_handoff
        index_handoff(
            db_path=forge_dir / "run-history.db",
            run_id=req.run_id,
            path=str(target),
            content=enforced,
        )
    except Exception:
        pass  # FTS failure should not fail the write

    return WriteResult(path=target, suppressed=False)


def _read_state(forge_dir: Path) -> dict[str, Any] | None:
    p = forge_dir / "state.json"
    if not p.is_file():
        return None
    try:
        return json.loads(p.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return None


def _rate_limited(state: dict[str, Any], now: datetime) -> bool:
    last = (state.get("handoff") or {}).get("last_written_at")
    if not last:
        return False
    try:
        last_dt = datetime.strptime(last, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
    except ValueError:
        # Fail-open: a malformed timestamp should not prevent a handoff. Better
        # to write an extra handoff than silently skip one when state.json has
        # been manually edited or migrated from an older schema.
        return False
    return (now - last_dt) < timedelta(minutes=RATE_LIMIT_MINUTES)


def _default_slug(state: dict[str, Any]) -> str:
    req_text = str(state.get("requirement") or state.get("story_state") or "run").lower()
    slug = re.sub(r"[^a-z0-9]+", "-", req_text).strip("-")
    return (slug[:40] or "run").rstrip("-")


def _resolve_collision(path: Path) -> Path | None:
    if not path.exists():
        return path
    for i in range(2, 11):
        candidate = path.with_stem(f"{path.stem}-{i}")
        if not candidate.exists():
            return candidate
    return None


def _build_frontmatter_input(req: WriteRequest, state: dict[str, Any]) -> FrontmatterInput:
    conv = state.get("convergence") or {}
    return FrontmatterInput(
        run_id=req.run_id,
        parent_run_id=state.get("parent_run_id"),
        stage=str(state.get("story_state", "")),
        substage=state.get("substage"),
        mode=str(state.get("mode", "standard")),
        autonomous=bool(state.get("autonomous", False)),
        background=bool(state.get("background", False)),
        score=int(state.get("score", 0)),
        score_history=[int(s) for s in (state.get("score_history") or [])],
        convergence_phase=str(conv.get("phase", "")),
        convergence_counters={
            "total_iterations": int(conv.get("total_iterations", 0)),
            "phase_iterations": int(conv.get("phase_iterations", 0)),
            "verify_fix_count": int(conv.get("verify_fix_count", 0)),
        },
        checkpoint_sha=state.get("head_checkpoint"),
        checkpoint_path=(f".forge/runs/{req.run_id}/checkpoints/{state.get('head_checkpoint')}" if state.get("head_checkpoint") else None),
        branch_name=state.get("branch_name"),
        worktree_path=state.get("worktree_path", ".forge/worktree"),
        git_head=_git_head(),
        commits_since_base=_commits_since_base(),
        open_askuserquestion=state.get("open_askuserquestion"),
        previous_handoff=((state.get("handoff") or {}).get("last_path")),
        trigger_level=req.level,
        trigger_reason=req.reason,
        trigger_threshold_pct=req.trigger_threshold_pct,
        trigger_tokens=req.trigger_tokens,
        created_at=req.now,
    )


def _render_body(req: WriteRequest, state: dict[str, Any]) -> str:
    inp = _build_section_inputs(state)
    parts = [
        sections.render_goal(inp, req.variant),
        "",
        sections.render_progress(inp, req.variant),
        "",
        sections.render_active_findings(inp, req.variant),
        "",
        sections.render_acceptance_criteria(inp, req.variant),
        "",
        sections.render_key_decisions(inp, req.variant),
        "",
        sections.render_do_not_touch(inp, req.variant),
        "",
        sections.render_next_action(inp, req.variant),
        "",
        sections.render_convergence_trajectory(inp, req.variant),
        "",
        sections.render_critical_files(inp, req.variant),
        "",
        sections.render_open_questions(inp, req.variant),
        "",
        sections.render_user_directive(inp, req.variant),
    ]
    return "\n".join(p for p in parts if p)


def _build_section_inputs(state: dict[str, Any]) -> sections.SectionInputs:
    # Tag extraction note: in production this reads from F08 retention tags
    # captured in state or from event log; for initial implementation we read
    # directly from state.json fields populated by orchestrator. Fields that
    # are not yet populated by the orchestrator default to empty collections.
    return sections.SectionInputs(
        requirement=str(state.get("requirement", "")),
        completed_acs=state.get("completed_acs") or [],
        implemented_files=state.get("implemented_files") or [],
        test_status=state.get("test_status") or {},
        active_findings=state.get("active_findings") or [],
        acceptance_criteria=state.get("acceptance_criteria") or [],
        decisions=state.get("decisions") or [],
        preempt_items=state.get("preempt_items") or [],
        user_dont_statements=state.get("user_dont_statements") or [],
        next_action_description=str(state.get("next_action") or ""),
        convergence_trajectory=state.get("convergence_trajectory") or [],
        critical_files=state.get("critical_files") or [],
        open_questions=state.get("open_questions") or [],
    )


def _render_resume_block(req: WriteRequest, path: Path, state: dict[str, Any]) -> str:
    return (
        "## RESUME PROMPT (copy everything below this line)\n\n"
        "I'm resuming a forge run from a handoff.\n\n"
        "**Preferred (if forge is installed in this session):**\n"
        f"/forge-handoff resume {path}\n\n"
        "**Manual fallback (no forge):**\n"
        f"- Run: {req.run_id}\n"
        f"- Branch: {state.get('branch_name') or '(none)'}\n"
        f"- Stage: {state.get('story_state')}, score {state.get('score', 0)}\n"
        f"- Requirement: {state.get('requirement', '')}\n"
        "\nStart by reading `.forge/state.json` and the Critical Files listed above, then proceed with Next Action.\n"
    )


def _enforce_size_cap(text: str, cap_bytes: int) -> str:
    data = text.encode("utf-8")
    if len(data) <= cap_bytes:
        return text
    truncated = data[: cap_bytes - 64].decode("utf-8", errors="ignore")
    return truncated + "\n\n<!-- TRUNCATED at cap -->\n"


def _update_state_chain(forge_dir: Path, req: WriteRequest, path: Path) -> None:
    def mutate(current: dict[str, Any]) -> dict[str, Any]:
        h = current.setdefault("handoff", {
            "chain": [],
            "soft_triggers_this_run": 0,
            "hard_triggers_this_run": 0,
            "milestone_triggers_this_run": 0,
            "suppressed_by_rate_limit": 0,
        })
        h["last_written_at"] = req.now.strftime("%Y-%m-%dT%H:%M:%SZ")
        h["last_path"] = str(path)
        h.setdefault("chain", []).append(str(path))
        if req.level == "soft":
            h["soft_triggers_this_run"] = h.get("soft_triggers_this_run", 0) + 1
        elif req.level == "hard":
            h["hard_triggers_this_run"] = h.get("hard_triggers_this_run", 0) + 1
        elif req.level == "milestone":
            h["milestone_triggers_this_run"] = h.get("milestone_triggers_this_run", 0) + 1
        return current

    atomic_json_update(forge_dir / "state.json", mutate, default={})


def _bump_suppressed(forge_dir: Path) -> None:
    def mutate(current: dict[str, Any]) -> dict[str, Any]:
        h = current.setdefault("handoff", {})
        h["suppressed_by_rate_limit"] = h.get("suppressed_by_rate_limit", 0) + 1
        return current

    atomic_json_update(forge_dir / "state.json", mutate, default={})


def _rotate_if_needed(forge_dir: Path, run_id: str, chain_limit: int) -> None:
    handoff_dir = forge_dir / "runs" / run_id / "handoffs"
    archive = handoff_dir / "archive"
    files = sorted([f for f in handoff_dir.glob("*.md") if f.parent == handoff_dir])
    if len(files) <= chain_limit:
        return
    archive.mkdir(exist_ok=True)
    for stale in files[:-chain_limit]:
        stale.rename(archive / stale.name)


def _git_head() -> str | None:
    try:
        out = subprocess.check_output(["git", "rev-parse", "--short", "HEAD"], stderr=subprocess.DEVNULL)
        return out.decode().strip()
    except (subprocess.CalledProcessError, FileNotFoundError, OSError, ValueError):
        return None


def _commits_since_base() -> int:
    for base in ("main", "master", "develop"):
        try:
            out = subprocess.check_output(
                ["git", "rev-list", "--count", "HEAD", f"^{base}"],
                stderr=subprocess.DEVNULL,
            )
            return int(out.decode().strip())
        except (subprocess.CalledProcessError, FileNotFoundError, OSError, ValueError):
            continue
    return 0
