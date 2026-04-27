#!/usr/bin/env python3
"""PostToolUse(Edit|Write) entry — check engine + automation trigger."""
from __future__ import annotations

import io
import sys
import time
import traceback
from pathlib import Path

_HOOKS = Path(__file__).resolve().parent
sys.path.insert(0, str(_HOOKS.parent))
sys.path.insert(0, str(_HOOKS))

from _py.check_engine.engine import run_post_tool_use  # noqa: E402
from _py.check_engine.automation_trigger import main as fire_automation  # noqa: E402
from _py.failure_log import record_failure  # noqa: E402

HOOK_NAME = "post_tool_use.py"
MATCHER = "Edit|Write"


def _run() -> int:
    started = time.monotonic()
    try:
        buf = sys.stdin.read()
        code = run_post_tool_use(stdin=io.StringIO(buf))
        fire_automation(stdin=io.StringIO(buf))
        if code != 0:
            dur = int((time.monotonic() - started) * 1000)
            record_failure(HOOK_NAME, MATCHER, code, "", dur, str(Path.cwd()))
            return 0
        return 0
    except BaseException:  # noqa: BLE001
        dur = int((time.monotonic() - started) * 1000)
        record_failure(HOOK_NAME, MATCHER, 1, traceback.format_exc(), dur, str(Path.cwd()))
        return 0


if __name__ == "__main__":
    sys.exit(_run())
