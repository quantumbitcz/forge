"""PostToolUse(Skill) checkpoint — replaces hooks/forge-checkpoint.sh."""
from __future__ import annotations

import json
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import IO

from hooks._py.platform_support import forge_dir


def main(stdin: IO[str] | None = None) -> int:
    stdin = stdin or sys.stdin
    try:
        payload = json.loads(stdin.read() or "{}")
    except json.JSONDecodeError:
        return 0
    fdir = forge_dir()
    if not fdir.exists():
        return 0
    ckpt = fdir / "checkpoints.jsonl"
    entry = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "skill": (payload.get("tool_input") or {}).get("skill_name", ""),
        "tool": payload.get("tool_name", "Skill"),
    }
    with open(ckpt, "a", encoding="utf-8") as fp:
        fp.write(json.dumps(entry) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
