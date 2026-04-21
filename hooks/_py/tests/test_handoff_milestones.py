"""Milestone trigger dispatch on stage transitions and terminal states."""
from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path

from hooks._py.handoff.milestones import on_stage_transition, on_terminal, on_feedback_escalation


def _seed(forge: Path, run_id: str, autonomous: bool = False):
    forge.mkdir(parents=True, exist_ok=True)
    (forge / "state.json").write_text(json.dumps({
        "run_id": run_id,
        "story_state": "REVIEWING",
        "autonomous": autonomous,
        "requirement": "Test",
        "handoff": {"chain": []},
    }))
    (forge / "runs" / run_id / "handoffs").mkdir(parents=True)


def test_stage_transition_writes_milestone(tmp_path):
    forge = tmp_path / ".forge"
    _seed(forge, "20260421-x")
    on_stage_transition(
        forge_dir=forge,
        run_id="20260421-x",
        from_stage="EXPLORING",
        to_stage="PLANNING",
        now=datetime(2026, 4, 21, 14, 30, 22, tzinfo=timezone.utc),
    )
    files = list((forge / "runs" / "20260421-x" / "handoffs").glob("*-milestone-*.md"))
    assert len(files) == 1
    content = files[0].read_text()
    assert "stage_transition:EXPLORING->PLANNING" in content


def test_terminal_writes_terminal_and_bypasses_rate_limit(tmp_path):
    forge = tmp_path / ".forge"
    _seed(forge, "20260421-x")
    base = datetime(2026, 4, 21, 14, 30, 22, tzinfo=timezone.utc)
    on_stage_transition(forge_dir=forge, run_id="20260421-x", from_stage="A", to_stage="B", now=base)
    on_terminal(forge_dir=forge, run_id="20260421-x", outcome="ship", now=base.replace(minute=32))
    files = list((forge / "runs" / "20260421-x" / "handoffs").glob("*-terminal-*.md"))
    assert len(files) == 1
    state = json.loads((forge / "state.json").read_text())
    # Terminal bypass proof: suppressed_by_rate_limit stayed at 0 despite being within the 15-min window.
    # (Writer lazy-initializes the counter only on _bump_suppressed; absent key == never bumped == 0.)
    assert state["handoff"].get("suppressed_by_rate_limit", 0) == 0


def test_feedback_escalation_writes_milestone_full_variant(tmp_path):
    forge = tmp_path / ".forge"
    _seed(forge, "20260421-esc")
    from hooks._py.handoff.milestones import on_feedback_escalation
    on_feedback_escalation(
        forge_dir=forge,
        run_id="20260421-esc",
        count=2,
        now=datetime(2026, 4, 21, 14, 30, 22, tzinfo=timezone.utc),
    )
    files = list((forge / "runs" / "20260421-esc" / "handoffs").glob("*-milestone-*.md"))
    assert len(files) == 1
    # Verify reason format captured in file content
    content = files[0].read_text()
    assert "feedback_escalation:count=2" in content
