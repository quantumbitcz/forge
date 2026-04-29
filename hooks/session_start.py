#!/usr/bin/env python3
"""SessionStart entry — session seed + rotate failure log."""
from __future__ import annotations

import sys
import time
import traceback
from pathlib import Path

_HOOKS = Path(__file__).resolve().parent
sys.path.insert(0, str(_HOOKS.parent))
sys.path.insert(0, str(_HOOKS))

from _py.check_engine.session_start import main as _target  # noqa: E402
from _py.failure_log import record_failure, rotate  # noqa: E402

HOOK_NAME = "session_start.py"
MATCHER = "SessionStart"


def _run() -> int:
    started = time.monotonic()
    try:
        rc = _target()
    except BaseException:
        dur = int((time.monotonic() - started) * 1000)
        record_failure(HOOK_NAME, MATCHER, 1, traceback.format_exc(), dur, str(Path.cwd()))
        return 0
    try:
        rotate()
    except BaseException:
        dur = int((time.monotonic() - started) * 1000)
        record_failure(HOOK_NAME, MATCHER + ":rotate", 1, traceback.format_exc(), dur, str(Path.cwd()))
    if rc != 0:
        dur = int((time.monotonic() - started) * 1000)
        record_failure(HOOK_NAME, MATCHER, rc, "", dur, str(Path.cwd()))
        return 0
    return 0


if __name__ == "__main__":
    sys.exit(_run())
