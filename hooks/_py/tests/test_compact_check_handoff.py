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
