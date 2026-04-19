#!/usr/bin/env python3
"""PostToolUse(Edit|Write) entry — check engine + automation trigger."""
from __future__ import annotations
import io
import sys
from pathlib import Path
_HOOKS = Path(__file__).resolve().parent
sys.path.insert(0, str(_HOOKS.parent))  # project root for 'hooks.*' imports
sys.path.insert(0, str(_HOOKS))          # hooks dir for '_py.*' imports
from _py.check_engine.engine import run_post_tool_use  # noqa: E402
from _py.check_engine.automation_trigger import main as fire_automation  # noqa: E402
if __name__ == "__main__":
    # Read stdin once, tee to both consumers (each gets a fresh StringIO).
    buf = sys.stdin.read()
    code = run_post_tool_use(stdin=io.StringIO(buf))
    # Automation trigger must fire even if engine returned non-zero (hook contract).
    fire_automation(stdin=io.StringIO(buf))
    sys.exit(code)
