"""compact_check integration — threshold → writer is invoked."""
from __future__ import annotations

import io
import json
from pathlib import Path

import pytest


def test_threshold_crossed_invokes_writer(tmp_path, monkeypatch):
    forge = tmp_path / ".forge"
    forge.mkdir()
    (forge / "state.json").write_text(json.dumps({
        "run_id": "20260421-test",
        "tokens": {"total": {"prompt": 150_000, "completion": 0}},
        "autonomous": False,
        "story_state": "REVIEWING",
        "requirement": "integration-test",
    }))
    (forge / "runs" / "20260421-test" / "handoffs").mkdir(parents=True)

    # forge_dir() reads from cwd relative path — chdir into tmp_path so .forge/ resolves here
    monkeypatch.chdir(tmp_path)

    from hooks._py.check_engine import compact_check

    rc = compact_check.main(stdin=io.StringIO(""))
    assert rc == 0
    handoffs = list((forge / "runs" / "20260421-test" / "handoffs").glob("*.md"))
    assert len(handoffs) == 1


def test_below_threshold_does_not_invoke_writer(tmp_path, monkeypatch):
    forge = tmp_path / ".forge"
    forge.mkdir()
    (forge / "state.json").write_text(json.dumps({
        "run_id": "20260421-small",
        "tokens": {"total": {"prompt": 50_000, "completion": 0}},
        "autonomous": False,
        "story_state": "PLANNING",
    }))
    (forge / "runs" / "20260421-small" / "handoffs").mkdir(parents=True)
    monkeypatch.chdir(tmp_path)

    from hooks._py.check_engine import compact_check

    rc = compact_check.main(stdin=io.StringIO(""))
    assert rc == 0
    handoffs = list((forge / "runs" / "20260421-small" / "handoffs").glob("*.md"))
    assert len(handoffs) == 0


def test_writer_exception_does_not_crash_hook(tmp_path, monkeypatch, capsys):
    """Fail-soft: writer exceptions are caught, hook returns 0, message to stderr."""
    forge = tmp_path / ".forge"
    forge.mkdir()
    (forge / "state.json").write_text(json.dumps({
        "run_id": "20260421-boom",
        "tokens": {"total": {"prompt": 150_000, "completion": 0}},
        "autonomous": False,
        "story_state": "REVIEWING",
        "requirement": "trigger writer failure",
    }))
    (forge / "runs" / "20260421-boom" / "handoffs").mkdir(parents=True)
    monkeypatch.chdir(tmp_path)

    from hooks._py.check_engine import compact_check

    def boom(req, forge_dir):
        raise RuntimeError("simulated writer failure")

    monkeypatch.setattr(compact_check, "write_handoff", boom)

    rc = compact_check.main(stdin=io.StringIO(""))
    assert rc == 0
    captured = capsys.readouterr()
    assert "handoff writer failed" in captured.err
    assert "simulated writer failure" in captured.err
