"""Resumer: parse handoff, staleness check, seed state, delegate."""
from __future__ import annotations

import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import Literal

from hooks._py.handoff import alerts
from hooks._py.handoff.frontmatter import parse_frontmatter
from hooks._py.io_utils import atomic_json_update

Status = Literal["ok", "ok_forced", "stale_refused", "missing_checkpoint", "parse_error"]


@dataclass
class ResumeRequest:
    handoff_path: Path
    autonomous: bool
    force: bool


@dataclass
class ResumeResult:
    status: Status
    run_id: str = ""
    reason: str = ""


def resume_from_handoff(req: ResumeRequest, forge_dir: Path) -> ResumeResult:
    """Parse a handoff file, check staleness, seed state.json, return status.

    Staleness matrix (behaviour summary):

    | git_head | checkpoint | autonomous | force | result                |
    |----------|------------|------------|-------|-----------------------|
    | match    | present    | any        | any   | ok                    |
    | mismatch | present    | true       | false | stale_refused + alert |
    | mismatch | present    | any        | true  | ok_forced             |
    | mismatch | present    | false      | false | stale_refused         |
    | match    | missing    | any        | any   | missing_checkpoint    |
    """
    if not req.handoff_path.is_file():
        return ResumeResult("parse_error", reason="handoff file not found")
    text = req.handoff_path.read_text(encoding="utf-8")
    try:
        fm = parse_frontmatter(text)
    except ValueError as e:
        return ResumeResult("parse_error", reason=str(e))

    head_match = _git_head_matches(fm.git_head)
    checkpoint_ok = _checkpoint_exists(forge_dir, fm.run_id, fm.checkpoint_sha)

    if head_match and checkpoint_ok:
        _seed_state(forge_dir, fm)
        return ResumeResult("ok", run_id=fm.run_id)

    if not head_match:
        if req.force:
            _seed_state(forge_dir, fm)
            return ResumeResult("ok_forced", run_id=fm.run_id, reason="forced_over_drift")
        if req.autonomous:
            alerts.emit_handoff_stale(
                forge_dir=forge_dir,
                run_id=fm.run_id,
                path=str(req.handoff_path),
                reason="git_head_drift",
            )
            return ResumeResult("stale_refused", run_id=fm.run_id, reason="git_head_drift")
        return ResumeResult("stale_refused", run_id=fm.run_id, reason="git_head_drift_interactive_unhandled")

    # head matches but checkpoint missing
    return ResumeResult("missing_checkpoint", run_id=fm.run_id, reason="checkpoint_file_absent")


def _git_head_matches(expected: str | None) -> bool:
    if not expected:
        return True  # no constraint
    try:
        current = subprocess.check_output(
            ["git", "rev-parse", "--short", "HEAD"], stderr=subprocess.DEVNULL
        ).decode().strip()
        return current.startswith(expected) or expected.startswith(current)
    except (subprocess.CalledProcessError, FileNotFoundError, OSError):
        return False


def _checkpoint_exists(forge_dir: Path, run_id: str, sha: str | None) -> bool:
    if not sha:
        return True
    return (forge_dir / "runs" / run_id / "checkpoints" / sha).exists()


def _seed_state(forge_dir: Path, fm) -> None:
    def mutate(current: dict) -> dict:
        current["run_id"] = fm.run_id
        current["story_state"] = fm.stage
        current["mode"] = fm.mode
        current["score"] = fm.score
        current["score_history"] = fm.score_history
        current["head_checkpoint"] = fm.checkpoint_sha
        current["branch_name"] = fm.branch_name
        handoff = current.setdefault("handoff", {"chain": []})
        handoff.setdefault("chain", []).append(str(fm.raw.get("trigger", {})))
        return current

    atomic_json_update(forge_dir / "state.json", mutate, default={})
