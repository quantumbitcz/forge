#!/usr/bin/env python3
"""Test runner shim used by tests/unit/mcp-response-filter.bats.

Exposes 3 sub-commands:
  wrap <source> <content>          — invoke filter_response, print result JSON
  expect-unmapped <source>         — assert UnmappedSourceError on the given source
  const <NAME>                     — print value of a module-level constant

Reads $EVENTS_FILE from env to override the forensic log path.
"""
from __future__ import annotations

import json
import os
import pathlib
import sys

REPO = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO))

from hooks._py import mcp_response_filter as f  # noqa: E402

events_file = os.environ.get("EVENTS_FILE")
if events_file:
    f.EVENTS_PATH = pathlib.Path(events_file)


def cmd_wrap(argv: list[str]) -> int:
    if len(argv) != 2:
        print("usage: wrap <source> <content>", file=sys.stderr)
        return 2
    source, content = argv
    result = f.filter_response(
        source=source, origin=None, content=content,
        run_id="bats-r1", agent="fg-100-orchestrator",
    )
    json.dump(result, sys.stdout, indent=2)
    return 0


def cmd_expect_unmapped(argv: list[str]) -> int:
    if len(argv) != 1:
        print("usage: expect-unmapped <source>", file=sys.stderr)
        return 2
    try:
        f.filter_response(
            source=argv[0], origin=None, content="x",
            run_id="r", agent="a",
        )
    except f.UnmappedSourceError as e:
        print(f"OK: {e}")
        return 0
    print("SHOULD_HAVE_RAISED", file=sys.stderr)
    return 1


def cmd_const(argv: list[str]) -> int:
    if len(argv) != 1:
        print("usage: const <NAME>", file=sys.stderr)
        return 2
    print(getattr(f, argv[0]))
    return 0


def main(argv: list[str] | None = None) -> int:
    args = sys.argv[1:] if argv is None else argv
    if not args:
        print("usage: _mcp_filter_runner.py {wrap|expect-unmapped|const} ...",
              file=sys.stderr)
        return 2
    cmd, rest = args[0], args[1:]
    handlers = {
        "wrap": cmd_wrap,
        "expect-unmapped": cmd_expect_unmapped,
        "const": cmd_const,
    }
    handler = handlers.get(cmd)
    if not handler:
        print(f"unknown command: {cmd}", file=sys.stderr)
        return 2
    return handler(rest)


if __name__ == "__main__":
    sys.exit(main())
