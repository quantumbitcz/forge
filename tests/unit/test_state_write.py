from __future__ import annotations

import json
from pathlib import Path

from hooks._py import state_write


def test_write_state_creates_file_with_seq(tmp_path: Path):
    state = tmp_path / "state.json"
    state_write.write_state(state, {"stage": "PREFLIGHT"})
    data = json.loads(state.read_text(encoding="utf-8"))
    assert data["stage"] == "PREFLIGHT"
    assert data["_seq"] == 1


def test_write_state_increments_seq(tmp_path: Path):
    state = tmp_path / "state.json"
    state_write.write_state(state, {"stage": "PREFLIGHT"})
    state_write.write_state(state, {"stage": "EXPLORING"})
    data = json.loads(state.read_text(encoding="utf-8"))
    assert data["stage"] == "EXPLORING"
    assert data["_seq"] == 2


def test_update_state_merges(tmp_path: Path):
    state = tmp_path / "state.json"
    state_write.write_state(state, {"stage": "PLANNING", "score": 90})
    state_write.update_state(state, {"score": 95})
    data = json.loads(state.read_text(encoding="utf-8"))
    assert data["stage"] == "PLANNING"
    assert data["score"] == 95
    assert data["_seq"] == 2


def test_update_state_nested_merge(tmp_path: Path):
    state = tmp_path / "state.json"
    state_write.write_state(state, {"tokens": {"prompt": 100}})
    state_write.update_state(state, {"tokens": {"completion": 50}}, merge_depth=2)
    data = json.loads(state.read_text(encoding="utf-8"))
    assert data["tokens"] == {"prompt": 100, "completion": 50}
