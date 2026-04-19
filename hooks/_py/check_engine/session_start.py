"""SessionStart hook — seeds events log (was hooks/session-start.sh)."""
from __future__ import annotations

import json
import sys
from datetime import datetime, timezone
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
    entry = {
        "kind": "session_start",
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "session_id": payload.get("session_id"),
    }
    with open(fdir / "events.jsonl", "a", encoding="utf-8") as fp:
        fp.write(json.dumps(entry) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
