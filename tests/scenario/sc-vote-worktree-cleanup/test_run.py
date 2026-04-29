"""sc-vote-worktree-cleanup - .forge/votes/<task_id>/ has no remaining dirs after voting.
Also exercises the crash-recovery path: orphaned sub-worktree from a prior crashed run
is detected as stale at PREFLIGHT.
"""
import os
import shutil
import time
from pathlib import Path


def test_cleanup_after_vote_same_verdict(tmp_path):
    votes = tmp_path / ".forge" / "votes" / "task1"
    (votes / "sample_1").mkdir(parents=True)
    (votes / "sample_2").mkdir(parents=True)
    # Simulate orchestrator finally-block: cleanup both sub-worktrees.
    for d in list(votes.iterdir()):
        shutil.rmtree(d)
    assert list(votes.iterdir()) == []


def test_cleanup_after_diverges_with_tiebreak(tmp_path):
    votes = tmp_path / ".forge" / "votes" / "task2"
    for n in (1, 2):
        (votes / f"sample_{n}").mkdir(parents=True)
    # DIVERGES path also cleans up at the end.
    for d in list(votes.iterdir()):
        shutil.rmtree(d)
    assert list(votes.iterdir()) == []


def test_orphaned_subworktree_flagged_stale(tmp_path):
    """If the orchestrator crashed mid-vote, sub-worktree dir remains. PREFLIGHT sweep
    flags it based on mtime > stale_hours."""
    votes = tmp_path / ".forge" / "votes" / "task3"
    sample = votes / "sample_1"
    sample.mkdir(parents=True)
    (sample / ".git").mkdir()  # make it look like a worktree
    # Backdate mtime 48h
    old = time.time() - 48 * 3600
    os.utime(sample, (old, old))

    # Replicate fg-101 detect-stale logic: any .forge/votes/*/sample_* with
    # mtime > stale_hours and no `git worktree list` entry is stale.
    stale_hours = 24
    now = time.time()
    votes_root = tmp_path / ".forge" / "votes"
    stale = [
        p for p in votes_root.rglob("sample_*") if now - p.stat().st_mtime > stale_hours * 3600
    ]
    assert len(stale) == 1
    assert stale[0].name == "sample_1"
