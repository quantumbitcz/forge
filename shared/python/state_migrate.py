#!/usr/bin/env python3
"""State schema migration: disabled under no-backcompat policy.

v1.x state files are auto-invalidated on load (see shared/python/state_init.py
load_or_reinit). No migration shim exists. Per feedback_no_backcompat.
"""
import sys


def migrate_disallowed():
    """Always raises. State migrations are disabled."""
    raise RuntimeError("state migrations disabled per no-backcompat policy")


if __name__ == '__main__':
    print(
        "ERROR: state migrations disabled per no-backcompat policy.\n"
        "v1.x state.json files are auto-invalidated on load by state_init.load_or_reinit.",
        file=sys.stderr,
    )
    sys.exit(2)
