"""Stage-transition + terminal-state handoff callbacks."""
from __future__ import annotations

from datetime import datetime, timezone
from pathlib import Path

from hooks._py.handoff.writer import WriteRequest, write_handoff


def on_stage_transition(
    forge_dir: Path,
    run_id: str,
    from_stage: str,
    to_stage: str,
    now: datetime | None = None,
) -> None:
    """Dispatch a light milestone handoff on orchestrator stage transition."""
    req = WriteRequest(
        run_id=run_id,
        level="milestone",
        reason=f"stage_transition:{from_stage}->{to_stage}",
        variant="light",
        now=now or datetime.now(timezone.utc),
    )
    write_handoff(req, forge_dir=forge_dir)


def on_terminal(
    forge_dir: Path,
    run_id: str,
    outcome: str,
    now: datetime | None = None,
) -> None:
    """Dispatch a full terminal handoff at SHIP / ABORT / FAIL (bypasses rate limit)."""
    req = WriteRequest(
        run_id=run_id,
        level="terminal",
        reason=outcome,
        variant="full",
        now=now or datetime.now(timezone.utc),
    )
    write_handoff(req, forge_dir=forge_dir)


def on_feedback_escalation(
    forge_dir: Path,
    run_id: str,
    count: int,
    now: datetime | None = None,
) -> None:
    """Dispatch a full milestone handoff when feedback_loop_count escalates."""
    req = WriteRequest(
        run_id=run_id,
        level="milestone",
        reason=f"feedback_escalation:count={count}",
        variant="full",
        now=now or datetime.now(timezone.utc),
    )
    write_handoff(req, forge_dir=forge_dir)
