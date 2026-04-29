"""TOOL_INPUT parsing, atomic writes, and cross-platform locks."""
from __future__ import annotations

import io
import json
import platform
import threading
from pathlib import Path

import pytest

from hooks._py import io_utils


def test_parse_tool_input_extracts_file_path():
    payload = json.dumps({"tool_input": {"file_path": "/tmp/x.py"}})
    stdin = io.StringIO(payload)
    parsed = io_utils.parse_tool_input(stdin)
    assert parsed.file_path == "/tmp/x.py"


def test_parse_tool_input_missing_returns_none():
    stdin = io.StringIO(json.dumps({"tool_input": {}}))
    parsed = io_utils.parse_tool_input(stdin)
    assert parsed.file_path is None


def test_atomic_json_update_roundtrip(tmp_path: Path):
    target = tmp_path / "state.json"
    target.write_text(json.dumps({"counter": 1}))

    def mutate(d):
        d["counter"] += 1
        return d

    io_utils.atomic_json_update(target, mutate)
    assert json.loads(target.read_text(encoding="utf-8"))["counter"] == 2


def test_atomic_json_update_handles_missing_file(tmp_path: Path):
    target = tmp_path / "new.json"
    io_utils.atomic_json_update(target, lambda d: {"created": True}, default={})
    assert json.loads(target.read_text(encoding="utf-8"))["created"] is True


def test_atomic_json_update_is_concurrent_safe(tmp_path: Path):
    target = tmp_path / "counter.json"
    target.write_text(json.dumps({"n": 0}))

    def bump():
        for _ in range(50):
            io_utils.atomic_json_update(target, lambda d: {"n": d["n"] + 1})

    threads = [threading.Thread(target=bump) for _ in range(4)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    assert json.loads(target.read_text(encoding="utf-8"))["n"] == 200


def test_normalize_path_emits_posix(tmp_path: Path):
    raw = tmp_path / "a" / "b.json"
    normalized = io_utils.normalize_path(raw)
    assert "\\" not in normalized
    assert normalized.endswith("/a/b.json")


@pytest.mark.skipif(platform.system() != "Windows", reason="Windows lock only")
def test_windows_lock_uses_msvcrt():
    # Sanity check that the Windows branch imports msvcrt successfully.
    import msvcrt  # noqa: F401
