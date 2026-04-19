"""PostToolUse(Edit|Write) automation-trigger wrapper (was automation-trigger-hook.sh)."""
from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import IO

from hooks._py.automation_trigger_cli import run as dispatch
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
    tool_input = payload.get("tool_input") or {}
    file_path = tool_input.get("file_path")
    if not file_path:
        return 0
    config = Path(".claude") / "forge-config.md"
    dispatch(
        trigger="file_changed",
        payload={"file": file_path},
        forge_dir=fdir,
        config_path=config,
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
