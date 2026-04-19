"""PostToolUse(Agent) compaction hint — replaces shared/forge-compact-check.sh."""
from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import IO

from hooks._py.platform_support import forge_dir

# Threshold matches the legacy shell implementation.
SUGGEST_THRESHOLD_TOKENS = 180_000


def main(stdin: IO[str] | None = None) -> int:
    stdin = stdin or sys.stdin
    _ = stdin.read()  # drain the pipe; agent payload isn't needed for the hint
    fdir = forge_dir()
    if not fdir.exists():
        return 0
    state = fdir / "state.json"
    if not state.exists():
        return 0
    try:
        doc = json.loads(state.read_text())
    except json.JSONDecodeError:
        return 0
    total = ((doc.get("tokens") or {}).get("total") or {})
    used = int(total.get("prompt", 0)) + int(total.get("completion", 0))
    if used >= SUGGEST_THRESHOLD_TOKENS:
        print(
            f"forge: context at {used:,} tokens — consider /compact to free room",
            file=sys.stderr,
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
