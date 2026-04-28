"""Writer integration — state → rendered file → state update → alert."""
from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path

import pytest

from hooks._py.handoff.writer import WriteRequest, write_handoff


def _seed_state(forge_dir: Path, run_id: str) -> Path:
    run_dir = forge_dir / "runs" / run_id
    run_dir.mkdir(parents=True, exist_ok=True)
    state = {
        "run_id": run_id,
        "story_state": "REVIEWING",
        "mode": "standard",
        "autonomous": False,
        "background": False,
        "requirement": "Add /health endpoint",
        "score": 82,
        "score_history": [45, 61, 74, 82],
        "convergence": {
            "phase": "perfection",
            "total_iterations": 7,
            "phase_iterations": 3,
            "verify_fix_count": 1,
        },
        "head_checkpoint": "7af9c3d",
        "branch_name": "feat/health",
        "handoff": {
            "chain": [],
            "soft_triggers_this_run": 0,
            "hard_triggers_this_run": 0,
            "milestone_triggers_this_run": 0,
            "suppressed_by_rate_limit": 0,
        },
    }
    (forge_dir / "state.json").write_text(json.dumps(state))
    (run_dir / "handoffs").mkdir(exist_ok=True)
    return forge_dir


def test_writer_produces_valid_file(tmp_path):
    forge_dir = _seed_state(tmp_path / ".forge", "20260421-a3f2")
    req = WriteRequest(
        run_id="20260421-a3f2",
        level="soft",
        reason="context_soft_50pct",
        trigger_threshold_pct=52,
        trigger_tokens=104000,
        variant="light",
        now=datetime(2026, 4, 21, 14, 30, 22, tzinfo=timezone.utc),
    )
    result = write_handoff(req, forge_dir=forge_dir)
    assert result.path.exists()
    content = result.path.read_text()
    assert content.startswith("---\n")
    assert "schema_version: 1.0" in content
    assert "trigger:" in content
    assert "## RESUME PROMPT" in content


def test_writer_updates_state_chain(tmp_path):
    forge_dir = _seed_state(tmp_path / ".forge", "20260421-a3f2")
    req = WriteRequest(
        run_id="20260421-a3f2",
        level="milestone",
        reason="stage_transition",
        variant="light",
        now=datetime(2026, 4, 21, 14, 30, 22, tzinfo=timezone.utc),
    )
    write_handoff(req, forge_dir=forge_dir)
    state = json.loads((forge_dir / "state.json").read_text())
    assert len(state["handoff"]["chain"]) == 1
    assert state["handoff"]["milestone_triggers_this_run"] == 1


def test_writer_emits_alert(tmp_path):
    forge_dir = _seed_state(tmp_path / ".forge", "20260421-a3f2")
    req = WriteRequest(
        run_id="20260421-a3f2",
        level="hard",
        reason="context_hard_70pct",
        variant="full",
        now=datetime(2026, 4, 21, 14, 30, 22, tzinfo=timezone.utc),
    )
    write_handoff(req, forge_dir=forge_dir)
    alerts = json.loads((forge_dir / "alerts.json").read_text())
    assert any(a["type"] == "HANDOFF_WRITTEN" and a["level"] == "hard" for a in alerts)


def test_writer_rate_limits(tmp_path):
    forge_dir = _seed_state(tmp_path / ".forge", "20260421-a3f2")
    base = datetime(2026, 4, 21, 14, 30, 22, tzinfo=timezone.utc)
    req1 = WriteRequest(run_id="20260421-a3f2", level="soft", reason="context_soft_50pct", variant="light", now=base)
    write_handoff(req1, forge_dir=forge_dir)
    # Second soft within 15 min → suppressed
    req2 = WriteRequest(
        run_id="20260421-a3f2",
        level="soft",
        reason="context_soft_50pct",
        variant="light",
        now=base.replace(minute=35),
    )
    result = write_handoff(req2, forge_dir=forge_dir)
    assert result.suppressed is True
    state = json.loads((forge_dir / "state.json").read_text())
    assert state["handoff"]["suppressed_by_rate_limit"] == 1


def test_terminal_ignores_rate_limit(tmp_path):
    forge_dir = _seed_state(tmp_path / ".forge", "20260421-a3f2")
    base = datetime(2026, 4, 21, 14, 30, 22, tzinfo=timezone.utc)
    req1 = WriteRequest(run_id="20260421-a3f2", level="soft", reason="context_soft_50pct", variant="light", now=base)
    write_handoff(req1, forge_dir=forge_dir)
    req2 = WriteRequest(run_id="20260421-a3f2", level="terminal", reason="ship", variant="full", now=base.replace(minute=35))
    result = write_handoff(req2, forge_dir=forge_dir)
    assert result.suppressed is False


def test_size_cap_light(tmp_path):
    forge_dir = _seed_state(tmp_path / ".forge", "20260421-a3f2")
    req = WriteRequest(run_id="20260421-a3f2", level="soft", reason="x", variant="light",
                       now=datetime(2026, 4, 21, 14, 30, 22, tzinfo=timezone.utc))
    result = write_handoff(req, forge_dir=forge_dir)
    assert result.path.stat().st_size <= 12 * 1024  # 3K tokens ~= 12KB


def test_resume_prompt_block_present(tmp_path):
    forge_dir = _seed_state(tmp_path / ".forge", "20260421-a3f2")
    req = WriteRequest(run_id="20260421-a3f2", level="manual", reason="manual", variant="full",
                       now=datetime(2026, 4, 21, 14, 30, 22, tzinfo=timezone.utc))
    result = write_handoff(req, forge_dir=forge_dir)
    content = result.path.read_text()
    assert "## RESUME PROMPT (copy everything below this line)" in content
    assert "/forge-admin handoff resume" in content


def test_size_cap_triggers_truncation(tmp_path):
    forge_dir = _seed_state(tmp_path / ".forge", "20260421-big")
    # Inject enough content to blow past the 12KB light-variant cap. Active
    # findings and critical_files are slice-capped by the renderer, so pad the
    # long fields that actually flow through unmodified: requirement,
    # next_action, open_questions, and the per-finding message on the top-5
    # findings that survive the light-variant slice.
    import json as _json
    state_path = forge_dir / "state.json"
    state = _json.loads(state_path.read_text())
    big_msg = "Padding message to inflate handoff body size. " * 80
    state["requirement"] = "Resume context demo — " + big_msg
    state["next_action"] = big_msg
    state["open_questions"] = [big_msg for _ in range(5)]
    state["active_findings"] = [
        {
            "file": f"src/module_{i}.py",
            "line": i,
            "category": "DOC-MISSING",
            "severity": "WARNING",
            "message": big_msg,
        }
        for i in range(500)
    ]
    state["critical_files"] = [f"src/module_{i}.py" for i in range(500)]
    state_path.write_text(_json.dumps(state))

    req = WriteRequest(
        run_id="20260421-big",
        level="soft",
        reason="x",
        variant="light",
        now=datetime(2026, 4, 21, 14, 30, 22, tzinfo=timezone.utc),
    )
    result = write_handoff(req, forge_dir=forge_dir)

    assert result.path.exists()
    size = result.path.stat().st_size
    assert size <= 12 * 1024, f"file {size} > 12KB cap"
    content = result.path.read_text(encoding="utf-8")  # must decode cleanly
    assert "<!-- TRUNCATED at cap -->" in content


def test_writer_initializes_handoff_subobject_when_missing(tmp_path):
    forge_dir = tmp_path / ".forge"
    (forge_dir / "runs" / "20260421-fresh" / "handoffs").mkdir(parents=True)
    # State without the handoff sub-object — simulates first handoff of a new run
    state = {
        "run_id": "20260421-fresh",
        "story_state": "PLANNING",
        "mode": "standard",
        "autonomous": False,
        "requirement": "fresh run",
        "score": 0,
        "score_history": [],
        "convergence": {"phase": "correctness", "total_iterations": 0},
    }
    (forge_dir / "state.json").write_text(json.dumps(state))
    req = WriteRequest(
        run_id="20260421-fresh",
        level="manual",
        reason="first-handoff",
        variant="light",
        now=datetime(2026, 4, 21, 14, 30, 22, tzinfo=timezone.utc),
    )
    result = write_handoff(req, forge_dir=forge_dir)
    assert result.suppressed is False
    state_after = json.loads((forge_dir / "state.json").read_text())
    assert "handoff" in state_after
    assert len(state_after["handoff"]["chain"]) == 1


def test_writer_skips_on_malformed_state_json(tmp_path):
    forge_dir = tmp_path / ".forge"
    forge_dir.mkdir()
    (forge_dir / "state.json").write_text("this is not valid json {{{")
    req = WriteRequest(
        run_id="20260421-bad",
        level="manual",
        reason="x",
        variant="light",
        now=datetime(2026, 4, 21, 14, 30, 22, tzinfo=timezone.utc),
    )
    result = write_handoff(req, forge_dir=forge_dir)
    assert result.suppressed is True
    assert result.reason == "no_state_json"


def test_writer_skips_when_state_absent(tmp_path):
    forge_dir = tmp_path / ".forge"
    forge_dir.mkdir()
    req = WriteRequest(
        run_id="20260421-none",
        level="manual",
        reason="x",
        variant="light",
        now=datetime(2026, 4, 21, 14, 30, 22, tzinfo=timezone.utc),
    )
    result = write_handoff(req, forge_dir=forge_dir)
    assert result.suppressed is True
    assert result.reason == "no_state_json"


def test_rotation_archives_past_chain_limit(tmp_path, monkeypatch):
    """Archive oldest handoffs once chain exceeds chain_limit."""
    from datetime import datetime, timezone, timedelta

    forge_dir = tmp_path / ".forge"
    forge_dir.mkdir()
    monkeypatch.setenv("FORGE_HANDOFF_CHAIN_LIMIT", "3")

    (forge_dir / "state.json").write_text(json.dumps({
        "run_id": "r",
        "story_state": "X",
        "requirement": "t",
        "handoff": {
            "chain": [],
            "soft_triggers_this_run": 0,
            "hard_triggers_this_run": 0,
            "milestone_triggers_this_run": 0,
            "suppressed_by_rate_limit": 0,
        },
    }))
    (forge_dir / "runs" / "r" / "handoffs").mkdir(parents=True)

    base = datetime(2026, 4, 21, tzinfo=timezone.utc)
    for i in range(5):
        req = WriteRequest(
            run_id="r",
            level="manual",
            reason=f"t{i}",
            variant="light",
            now=base + timedelta(minutes=30 * i),
        )
        write_handoff(req, forge_dir=forge_dir)

    handoff_dir = forge_dir / "runs" / "r" / "handoffs"
    archive = handoff_dir / "archive"
    active_md = [f for f in handoff_dir.glob("*.md") if f.parent == handoff_dir]
    assert len(active_md) == 3  # chain_limit
    assert archive.exists()
    archived_md = list(archive.glob("*.md"))
    assert len(archived_md) == 2  # 5 written - 3 kept
