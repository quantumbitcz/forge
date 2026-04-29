"""Unit test: fg-101-worktree-manager detect-stale covers .forge/votes/*."""
from __future__ import annotations

from pathlib import Path

REPO_ROOT = Path(__file__).parent.parent.parent
AGENT = (REPO_ROOT / "agents" / "fg-101-worktree-manager.md").read_text(encoding="utf-8")


def test_detect_stale_references_votes_dir():
    assert ".forge/votes/" in AGENT or ".forge/votes/*/sample_*" in AGENT


def test_vote_subworktree_lifecycle_documented():
    assert "vote sub-worktree" in AGENT.lower() or "Vote sub-worktree" in AGENT
