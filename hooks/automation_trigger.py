#!/usr/bin/env python3
"""Standalone CLI entry shim — invoked by /forge-automation skill directly."""
from __future__ import annotations

import sys
from pathlib import Path

# Put project root on sys.path so `hooks._py...` absolute imports resolve.
_HOOKS = Path(__file__).resolve().parent
sys.path.insert(0, str(_HOOKS.parent))
sys.path.insert(0, str(_HOOKS))

from _py.automation_trigger_cli import main  # noqa: E402

if __name__ == "__main__":
    sys.exit(main())
