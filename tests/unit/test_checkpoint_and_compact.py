from __future__ import annotations

import io
import json
from pathlib import Path

from hooks._py.check_engine import checkpoint, compact_check


def test_checkpoint_no_forge_dir_is_noop(tmp_path: Path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    stdin = io.StringIO(json.dumps({"tool_name": "Skill", "tool_input": {"skill_name": "forge-run"}}))
    assert checkpoint.main(stdin=stdin) == 0


def test_checkpoint_writes_entry(tmp_path: Path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    (tmp_path / ".forge").mkdir()
    stdin = io.StringIO(json.dumps({"tool_name": "Skill", "tool_input": {"skill_name": "forge-run"}}))
    assert checkpoint.main(stdin=stdin) == 0
    ckpt = tmp_path / ".forge" / "checkpoints.jsonl"
    assert ckpt.exists()
    line = json.loads(ckpt.read_text(encoding="utf-8").strip().splitlines()[-1])
    assert line["skill"] == "forge-run"
    assert "timestamp" in line


def test_compact_check_no_forge_dir(tmp_path: Path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    stdin = io.StringIO("{}")
    assert compact_check.main(stdin=stdin) == 0


def test_compact_check_suggests_when_tokens_high(tmp_path: Path, monkeypatch, capsys):
    monkeypatch.chdir(tmp_path)
    (tmp_path / ".forge").mkdir()
    state = tmp_path / ".forge" / "state.json"
    state.write_text(json.dumps({"tokens": {"total": {"prompt": 150_000, "completion": 50_000}}}))
    stdin = io.StringIO("{}")
    assert compact_check.main(stdin=stdin) == 0
    captured = capsys.readouterr()
    assert "compact" in (captured.out + captured.err).lower()
