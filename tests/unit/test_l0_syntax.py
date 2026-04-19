from __future__ import annotations

import io
import json
from pathlib import Path

from hooks._py.check_engine import l0_syntax


def _tool_input(file_path: str, content: str) -> io.StringIO:
    return io.StringIO(json.dumps({
        "tool_input": {"file_path": file_path, "content": content},
        "tool_name": "Write",
    }))


def test_valid_python_passes(tmp_path):
    stdin = _tool_input(str(tmp_path / "x.py"), "def foo(): return 1\n")
    exit_code, msg = l0_syntax.validate_stream(stdin)
    assert exit_code == 0
    assert msg == ""


def test_invalid_python_blocks(tmp_path):
    stdin = _tool_input(str(tmp_path / "x.py"), "def foo(: return 1\n")
    exit_code, msg = l0_syntax.validate_stream(stdin)
    assert exit_code == 2
    assert "SyntaxError" in msg or "syntax" in msg.lower()


def test_valid_json_passes(tmp_path):
    stdin = _tool_input(str(tmp_path / "x.json"), '{"a": 1}')
    assert l0_syntax.validate_stream(stdin)[0] == 0


def test_invalid_json_blocks(tmp_path):
    stdin = _tool_input(str(tmp_path / "x.json"), '{"a": 1')
    assert l0_syntax.validate_stream(stdin)[0] == 2


def test_unknown_extension_passes(tmp_path):
    stdin = _tool_input(str(tmp_path / "x.xyz"), "garbage @@")
    assert l0_syntax.validate_stream(stdin)[0] == 0


def test_non_edit_tool_passes(tmp_path):
    stdin = io.StringIO(json.dumps({
        "tool_input": {"file_path": str(tmp_path / "x.py"), "content": "!!"},
        "tool_name": "Read",
    }))
    assert l0_syntax.validate_stream(stdin)[0] == 0
