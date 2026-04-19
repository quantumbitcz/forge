#!/usr/bin/env python3
"""Stop entry — feedback capture."""
from __future__ import annotations
import sys
from pathlib import Path
_HOOKS = Path(__file__).resolve().parent
sys.path.insert(0, str(_HOOKS.parent))  # project root for 'hooks.*' imports
sys.path.insert(0, str(_HOOKS))          # hooks dir for '_py.*' imports
from _py.check_engine.feedback_capture import main  # noqa: E402
if __name__ == "__main__":
    sys.exit(main())
