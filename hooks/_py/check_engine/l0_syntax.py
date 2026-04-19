"""L0 pre-edit syntax validation (replaces validate-syntax.sh)."""
from __future__ import annotations

import ast
import json
import sys
from pathlib import Path
from typing import IO

SUPPORTED_EDIT_TOOLS = {"Edit", "Write", "MultiEdit"}


def _check_python(content: str) -> str | None:
    try:
        ast.parse(content)
        return None
    except SyntaxError as e:
        # PEP-657-style error location when available.
        line = getattr(e, "lineno", "?")
        col = getattr(e, "offset", "?")
        return f"SyntaxError at line {line}, col {col}: {e.msg}"


def _check_json(content: str) -> str | None:
    try:
        json.loads(content)
        return None
    except json.JSONDecodeError as e:
        return f"JSON parse error at line {e.lineno}, col {e.colno}: {e.msg}"


CHECKERS = {
    ".py":   _check_python,
    ".json": _check_json,
}


def validate_stream(stream: IO[str] | None = None) -> tuple[int, str]:
    """Return (exit_code, message). 0 = allow, 2 = block edit."""
    stream = stream or sys.stdin
    try:
        payload = json.loads(stream.read() or "{}")
    except json.JSONDecodeError:
        return 0, ""
    if payload.get("tool_name") not in SUPPORTED_EDIT_TOOLS:
        return 0, ""
    tool_input = payload.get("tool_input") or {}
    file_path = tool_input.get("file_path")
    content = tool_input.get("content") or ""
    if not file_path or not content:
        return 0, ""
    ext = Path(file_path).suffix.lower()
    checker = CHECKERS.get(ext)
    if checker is None:
        return 0, ""
    error = checker(content)
    if error is None:
        return 0, ""
    return 2, f"L0 blocked {file_path}: {error}"


def main() -> int:
    code, msg = validate_stream()
    if msg:
        print(msg, file=sys.stderr)
    return code


if __name__ == "__main__":
    sys.exit(main())
