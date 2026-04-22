"""Resumer: parse → staleness check → seed state → delegation."""
from __future__ import annotations

import json
from pathlib import Path

from hooks._py.handoff.resumer import (
    ResumeRequest,
    ResumeResult,
    resume_from_handoff,
)


def _write_handoff(path: Path, git_head: str, checkpoint_sha: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(f"""---
schema_version: 1.0
handoff_version: 1.0
run_id: 20260421-x
parent_run_id: null
stage: REVIEWING
substage: null
mode: standard
autonomous: false
background: false
score: 82
score_history: [45, 82]
convergence_phase: perfection
convergence_counters:
  total_iterations: 7
  phase_iterations: 3
  verify_fix_count: 0
checkpoint_sha: {checkpoint_sha}
checkpoint_path: .forge/runs/20260421-x/checkpoints/{checkpoint_sha}
branch_name: feat/test
worktree_path: .forge/worktree
git_head: {git_head}
commits_since_base: 0
open_askuserquestion: null
previous_handoff: null
trigger:
  level: manual
  reason: test
  threshold_pct: null
  tokens: null
created_at: 2026-04-21T14:30:22Z
---

## Goal
test goal
""")


def test_clean_resume_returns_ok(tmp_path, monkeypatch):
    path = tmp_path / ".forge" / "runs" / "20260421-x" / "handoffs" / "test.md"
    # git_head=null means the handoff has no git-drift constraint — matches _git_head_matches's
    # "no constraint" branch (`if not expected: return True`). This is the clean-resume path.
    _write_handoff(path, git_head="null", checkpoint_sha="7af9c3d")
    (tmp_path / ".forge" / "runs" / "20260421-x" / "checkpoints").mkdir(parents=True)
    (tmp_path / ".forge" / "runs" / "20260421-x" / "checkpoints" / "7af9c3d").write_text("checkpoint")
    monkeypatch.chdir(tmp_path)

    req = ResumeRequest(handoff_path=path, autonomous=False, force=False)
    result = resume_from_handoff(req, forge_dir=tmp_path / ".forge")
    assert result.status == "ok"
    assert result.run_id == "20260421-x"

    # Verify state.json was actually seeded
    state = json.loads((tmp_path / ".forge" / "state.json").read_text())
    assert state["run_id"] == "20260421-x"
    assert state["story_state"] == "REVIEWING"
    assert state["mode"] == "standard"
    assert state["head_checkpoint"] == "7af9c3d"
    assert state["branch_name"] == "feat/test"
    # Chain entry is the handoff path, not a stringified dict
    assert state["handoff"]["chain"] == [str(path)]
    assert state["handoff"]["last_resumed_from"] == str(path)
    assert "last_resumed_at" in state["handoff"]


def test_stale_autonomous_refuses(tmp_path, monkeypatch):
    path = tmp_path / ".forge" / "runs" / "20260421-x" / "handoffs" / "test.md"
    _write_handoff(path, git_head="deadbeef", checkpoint_sha="7af9c3d")
    monkeypatch.chdir(tmp_path)

    req = ResumeRequest(handoff_path=path, autonomous=True, force=False)
    result = resume_from_handoff(req, forge_dir=tmp_path / ".forge")
    assert result.status == "stale_refused"


def test_force_bypasses_staleness(tmp_path, monkeypatch):
    path = tmp_path / ".forge" / "runs" / "20260421-x" / "handoffs" / "test.md"
    _write_handoff(path, git_head="deadbeef", checkpoint_sha="7af9c3d")
    (tmp_path / ".forge" / "runs" / "20260421-x" / "checkpoints").mkdir(parents=True)
    (tmp_path / ".forge" / "runs" / "20260421-x" / "checkpoints" / "7af9c3d").write_text("")
    monkeypatch.chdir(tmp_path)

    req = ResumeRequest(handoff_path=path, autonomous=True, force=True)
    result = resume_from_handoff(req, forge_dir=tmp_path / ".forge")
    assert result.status == "ok_forced"

    # Verify force-resume also seeded state correctly
    state = json.loads((tmp_path / ".forge" / "state.json").read_text())
    assert state["run_id"] == "20260421-x"
    assert state["handoff"]["chain"] == [str(path)]


def test_missing_handoff_file_returns_parse_error(tmp_path):
    req = ResumeRequest(handoff_path=tmp_path / "nonexistent.md", autonomous=False, force=False)
    result = resume_from_handoff(req, forge_dir=tmp_path / ".forge")
    assert result.status == "parse_error"


def test_missing_checkpoint_returns_missing_checkpoint(tmp_path, monkeypatch):
    path = tmp_path / ".forge" / "runs" / "20260421-x" / "handoffs" / "test.md"
    # git_head=null means the handoff has no git-drift constraint — matches _git_head_matches's
    # "no constraint" branch (`if not expected: return True`). This is the clean-resume path.
    _write_handoff(path, git_head="null", checkpoint_sha="nonexistent-sha")
    # Do NOT create the checkpoint file
    monkeypatch.chdir(tmp_path)

    req = ResumeRequest(handoff_path=path, autonomous=False, force=False)
    result = resume_from_handoff(req, forge_dir=tmp_path / ".forge")
    assert result.status == "missing_checkpoint"


def test_real_git_head_match(tmp_path, monkeypatch):
    """Integration: when cwd is a real git repo with matching HEAD, clean resume works."""
    import subprocess as sp
    sp.check_call(["git", "init", "-q", str(tmp_path)])
    sp.check_call(["git", "-C", str(tmp_path), "config", "user.email", "test@example.com"])
    sp.check_call(["git", "-C", str(tmp_path), "config", "user.name", "Test"])
    sp.check_call(["git", "-C", str(tmp_path), "commit", "--allow-empty", "-q", "-m", "init"])
    head = sp.check_output(
        ["git", "-C", str(tmp_path), "rev-parse", "--short", "HEAD"]
    ).decode().strip()

    path = tmp_path / ".forge" / "runs" / "20260421-x" / "handoffs" / "test.md"
    _write_handoff(path, git_head=head, checkpoint_sha="7af9c3d")
    (tmp_path / ".forge" / "runs" / "20260421-x" / "checkpoints").mkdir(parents=True)
    (tmp_path / ".forge" / "runs" / "20260421-x" / "checkpoints" / "7af9c3d").write_text("checkpoint")
    monkeypatch.chdir(tmp_path)

    req = ResumeRequest(handoff_path=path, autonomous=False, force=False)
    result = resume_from_handoff(req, forge_dir=tmp_path / ".forge")
    assert result.status == "ok"


def test_malformed_frontmatter_returns_parse_error(tmp_path):
    """Corrupt or unsupported frontmatter → parse_error, no state mutation."""
    path = tmp_path / ".forge" / "runs" / "20260421-bad" / "handoffs" / "broken.md"
    path.parent.mkdir(parents=True)
    # Missing closing --- marker
    path.write_text("---\nschema_version: 1.0\nrun_id: 20260421-bad\n")

    req = ResumeRequest(handoff_path=path, autonomous=False, force=False)
    result = resume_from_handoff(req, forge_dir=tmp_path / ".forge")
    assert result.status == "parse_error"


def test_unsupported_schema_version_returns_parse_error(tmp_path):
    """Unknown schema_version → parse_error (no backcompat)."""
    path = tmp_path / ".forge" / "runs" / "20260421-v2" / "handoffs" / "future.md"
    path.parent.mkdir(parents=True)
    path.write_text("---\nschema_version: 2.0\nrun_id: 20260421-v2\n---\n")

    req = ResumeRequest(handoff_path=path, autonomous=False, force=False)
    result = resume_from_handoff(req, forge_dir=tmp_path / ".forge")
    assert result.status == "parse_error"
    assert "schema_version" in result.reason
