"""Automation trigger hook (STUB — full port in Task 10).

Accepts TOOL_INPUT on stdin, exits 0. Real implementation lands in Task 10
(306-LOC bash port: file-change event matching + cooldown + dispatch).
"""
from __future__ import annotations

import sys
from typing import IO


def main(stdin: IO[str] | None = None) -> int:
    stdin = stdin or sys.stdin
    _ = stdin.read()  # drain
    return 0


if __name__ == "__main__":
    sys.exit(main())
