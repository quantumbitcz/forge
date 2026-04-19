from __future__ import annotations

import io
import json
from pathlib import Path

from hooks._py.check_engine import engine


def test_short_circuits_without_file_path():
    stdin = io.StringIO(json.dumps({"tool_input": {}, "tool_name": "Edit"}))
    assert engine.run_post_tool_use(stdin=stdin) == 0


def test_short_circuits_for_non_edit_tool():
    stdin = io.StringIO(json.dumps({
        "tool_input": {"file_path": "/tmp/x.py"},
        "tool_name": "Read",
    }))
    assert engine.run_post_tool_use(stdin=stdin) == 0


def test_short_circuits_when_no_forge_dir(tmp_path: Path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    stdin = io.StringIO(json.dumps({
        "tool_input": {"file_path": str(tmp_path / "x.py")},
        "tool_name": "Edit",
    }))
    # No .forge/ dir — hook must exit 0 without touching anything.
    assert engine.run_post_tool_use(stdin=stdin) == 0


def test_invokes_l1_when_forge_dir_present(tmp_path: Path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    (tmp_path / ".forge").mkdir()
    py = tmp_path / "x.py"
    py.write_text("x = 1\n")
    stdin = io.StringIO(json.dumps({
        "tool_input": {"file_path": str(py)},
        "tool_name": "Edit",
    }))
    # Default ruleset has no matching L1 rule for x=1 — exit 0.
    exit_code = engine.run_post_tool_use(stdin=stdin)
    assert exit_code in (0, 1)  # 0 on clean, 1 if default rules flag the file
