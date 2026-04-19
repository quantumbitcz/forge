from __future__ import annotations

import io
import json
from pathlib import Path

from hooks._py.check_engine import feedback_capture, session_start


def test_feedback_capture_no_forge_dir(tmp_path: Path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    stdin = io.StringIO("{}")
    assert feedback_capture.main(stdin=stdin) == 0


def test_feedback_capture_writes_event(tmp_path: Path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    (tmp_path / ".forge").mkdir()
    stdin = io.StringIO(json.dumps({"transcript_path": "t.json", "stop_hook_active": False}))
    assert feedback_capture.main(stdin=stdin) == 0
    events = tmp_path / ".forge" / "events.jsonl"
    assert events.exists()
    entry = json.loads(events.read_text().strip().splitlines()[-1])
    assert entry["kind"] == "session_stop"


def test_session_start_no_forge_dir(tmp_path: Path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    stdin = io.StringIO("{}")
    assert session_start.main(stdin=stdin) == 0


def test_session_start_writes_event(tmp_path: Path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    (tmp_path / ".forge").mkdir()
    stdin = io.StringIO(json.dumps({"session_id": "abc-123"}))
    assert session_start.main(stdin=stdin) == 0
    events = tmp_path / ".forge" / "events.jsonl"
    assert events.exists()
    entry = json.loads(events.read_text().strip().splitlines()[-1])
    assert entry["kind"] == "session_start"
    assert entry.get("session_id") == "abc-123"
