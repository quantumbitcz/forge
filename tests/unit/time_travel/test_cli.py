"""CLI tests for Phase 14 time-travel checkpoint dispatch.

Phase 14 Task 5 — the orchestrator invokes the time-travel module as
``python3 -m hooks._py.time_travel <op> <args...>``. Exit codes are the
contract surfaced to ``/forge-recover`` (see SKILL.md exit-codes table).
"""
from __future__ import annotations

import json
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT))

from hooks._py.time_travel.cas import CheckpointStore


def _init_git(dir_: pathlib.Path) -> str:
    subprocess.run(["git", "init", "-q", str(dir_)], check=True)
    subprocess.run(["git", "-C", str(dir_), "config", "user.email", "a@b"], check=True)
    subprocess.run(["git", "-C", str(dir_), "config", "user.name", "a"], check=True)
    (dir_ / "f.txt").write_text("v1\n")
    subprocess.run(["git", "-C", str(dir_), "add", "."], check=True)
    subprocess.run(["git", "-C", str(dir_), "commit", "-q", "-m", "init"], check=True)
    return subprocess.check_output(
        ["git", "-C", str(dir_), "rev-parse", "HEAD"]
    ).decode().strip()


def test_cli_list_checkpoints_json(tmp_path):
    forge = tmp_path / ".forge" / "runs" / "r1"
    forge.mkdir(parents=True)
    wt = tmp_path / "wt"
    wt.mkdir()
    _init_git(wt)
    store = CheckpointStore(run_dir=forge, worktree_dir=wt)
    store.write_checkpoint("A.-.001", "PLANNING", "-", {"x": 1}, [], {})
    result = subprocess.run(
        [sys.executable, "-m", "hooks._py.time_travel",
         "list-checkpoints", "--run-dir", str(forge), "--worktree", str(wt), "--json"],
        check=True, capture_output=True, text=True, cwd=str(ROOT),
    )
    payload = json.loads(result.stdout)
    assert payload["HEAD"]
    assert len(payload["nodes"]) == 1


def test_cli_list_checkpoints_human_shows_head_marker(tmp_path):
    forge = tmp_path / ".forge" / "runs" / "r1"
    forge.mkdir(parents=True)
    wt = tmp_path / "wt"
    wt.mkdir()
    _init_git(wt)
    store = CheckpointStore(run_dir=forge, worktree_dir=wt)
    store.write_checkpoint("A.-.001", "PLANNING", "-", {"x": 1}, [], {})
    result = subprocess.run(
        [sys.executable, "-m", "hooks._py.time_travel",
         "list-checkpoints", "--run-dir", str(forge), "--worktree", str(wt)],
        check=True, capture_output=True, text=True, cwd=str(ROOT),
    )
    assert "A.-.001" in result.stdout
    assert "<-- HEAD" in result.stdout


def test_cli_rewind_unknown_id_returns_exit_6(tmp_path):
    forge = tmp_path / ".forge" / "runs" / "r1"
    forge.mkdir(parents=True)
    wt = tmp_path / "wt"
    wt.mkdir()
    _init_git(wt)
    store = CheckpointStore(run_dir=forge, worktree_dir=wt)
    store.write_checkpoint("A.-.001", "PLANNING", "-", {"x": 1}, [], {})
    result = subprocess.run(
        [sys.executable, "-m", "hooks._py.time_travel", "rewind",
         "--run-dir", str(forge), "--worktree", str(wt),
         "--to", "f" * 64, "--run-id", "r1"],
        capture_output=True, text=True, cwd=str(ROOT),
    )
    assert result.returncode == 6


def test_cli_rewind_missing_args_returns_exit_2(tmp_path):
    forge = tmp_path / ".forge" / "runs" / "r1"
    forge.mkdir(parents=True)
    wt = tmp_path / "wt"
    wt.mkdir()
    _init_git(wt)
    result = subprocess.run(
        [sys.executable, "-m", "hooks._py.time_travel", "rewind",
         "--run-dir", str(forge), "--worktree", str(wt)],
        capture_output=True, text=True, cwd=str(ROOT),
    )
    assert result.returncode == 2


def test_cli_gc_returns_json(tmp_path):
    forge = tmp_path / ".forge" / "runs" / "r1"
    forge.mkdir(parents=True)
    wt = tmp_path / "wt"
    wt.mkdir()
    _init_git(wt)
    store = CheckpointStore(run_dir=forge, worktree_dir=wt)
    store.write_checkpoint("A.-.001", "PLANNING", "-", {"x": 1}, [], {})
    result = subprocess.run(
        [sys.executable, "-m", "hooks._py.time_travel", "gc",
         "--run-dir", str(forge), "--worktree", str(wt),
         "--retention-days", "7", "--max-per-run", "100"],
        check=True, capture_output=True, text=True, cwd=str(ROOT),
    )
    payload = json.loads(result.stdout)
    assert "removed" in payload
    assert isinstance(payload["removed"], list)
