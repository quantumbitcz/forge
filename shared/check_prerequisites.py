#!/usr/bin/env python3
"""Enforce Python 3.10+ before forge init writes any config.

Exit codes:
  0 - Python version meets floor.
  1 - Python version is below the floor.

Usage:
  python3 shared/check_prerequisites.py [--simulate-version X.Y.Z]
"""
from __future__ import annotations

import argparse
import platform
import sys

FLOOR = (3, 10)


def _parse_version(s: str) -> tuple[int, ...]:
    return tuple(int(p) for p in s.split("."))


def _upgrade_hint() -> str:
    system = platform.system().lower()
    if system == "darwin":
        return "  macOS:   brew install python@3.11"
    if system == "linux":
        return "  Linux:   sudo apt install python3.11  (or your distro equivalent)"
    if system == "windows":
        return "  Windows: winget install Python.Python.3.11"
    return "  Install Python 3.10 or newer from https://www.python.org/downloads/"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--simulate-version", default=None)
    args = ap.parse_args()
    if args.simulate_version:
        version = _parse_version(args.simulate_version)
        version_str = args.simulate_version
    else:
        version = sys.version_info[:3]
        version_str = ".".join(str(p) for p in version)
    if version[:2] < FLOOR:
        print(
            f"ERROR: forge plugin requires Python 3.10 or later (found {version_str}).\n"
            f"Upgrade options:\n{_upgrade_hint()}\nExit code: 1",
            file=sys.stderr,
        )
        return 1
    print(f"OK: Python {version_str} detected (platform: {platform.system().lower()})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
