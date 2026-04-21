#!/usr/bin/env python3
"""Validate a single finding line against shared/checks/output-format.md spec.

Python port of validate-finding.sh.

Format:
  file:line | CATEGORY-CODE | SEVERITY | message | fix_hint [| confidence:LEVEL]

Exit:
  0 = valid
  1 = invalid (reason on stderr)

Usage:
  echo 'src/foo.py:42 | SEC-001 | CRITICAL | hardcoded secret | rotate key' \\
    | python3 -m shared.validate_finding
  python3 -m shared.validate_finding 'src/foo.py:42 | SEC-001 | ...'
"""
from __future__ import annotations

import re
import sys

_FILE_LINE = re.compile(r"^[^:]+:[0-9]+$")
_CATEGORY = re.compile(r"^[A-Z][A-Z0-9]+-[A-Z0-9_-]+$")
_CONFIDENCE = re.compile(r"^confidence:(HIGH|MEDIUM|LOW)$")
_VALID_SEVERITIES = {"CRITICAL", "WARNING", "INFO"}

_PIPE_SENTINEL = "\x00ESC_PIPE\x00"


def split_fields(line: str) -> list[str]:
    """Split on ` | `, preserving escaped pipes (\\|)."""
    escaped = line.replace(r"\|", _PIPE_SENTINEL)
    fields = [f.strip().replace(_PIPE_SENTINEL, r"\|") for f in escaped.split(" | ")]
    return fields


def validate(line: str) -> tuple[int, str | None]:
    """Return (exit_code, error_message_or_None)."""
    if not line:
        return 1, "empty finding line"

    fields = split_fields(line)
    n = len(fields)
    if n < 5 or n > 6:
        return 1, f"expected 5 or 6 fields, got {n}"

    file_line, category, severity, message = fields[0], fields[1], fields[2], fields[3]

    if not _FILE_LINE.match(file_line):
        return 1, f"field 1 (file:line) must match 'file:number', got: {file_line}"
    if not _CATEGORY.match(category):
        return 1, (f"field 2 (CATEGORY-CODE) must match 'PREFIX-CODE' uppercase pattern, "
                   f"got: {category}")
    if severity not in _VALID_SEVERITIES:
        return 1, f"field 3 (SEVERITY) must be CRITICAL, WARNING, or INFO, got: {severity}"
    if not message:
        return 1, "field 4 (message) must be non-empty"

    if n == 6:
        confidence = fields[5]
        if not _CONFIDENCE.match(confidence):
            return 1, (f"field 6 (confidence) must match 'confidence:(HIGH|MEDIUM|LOW)', "
                       f"got: {confidence}")

    return 0, None


def main(argv: list[str] | None = None) -> int:
    args = argv if argv is not None else sys.argv[1:]
    line = args[0] if args else sys.stdin.readline().rstrip("\n")
    exit_code, err = validate(line)
    if err:
        print(f"ERROR: {err}", file=sys.stderr)
    return exit_code


if __name__ == "__main__":
    sys.exit(main())
