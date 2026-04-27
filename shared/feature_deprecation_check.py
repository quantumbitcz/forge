#!/usr/bin/env python3
"""Propose removal of features that have zero usage for >= 180 days.

Cross-platform, pure Python 3.10+. Exits 0 on success (including "no candidates").
CI can wire this to a scheduled workflow; for Phase 2 it is installed but not
yet triggered on any schedule.

Usage:
    python shared/feature_deprecation_check.py
    python shared/feature_deprecation_check.py --dry-run   (don't open PR)
"""
from __future__ import annotations

import argparse
import sqlite3
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
DB_PATH = REPO_ROOT / ".forge" / "run-history.db"

# Ensure sibling script import works regardless of cwd. `shared/` is added
# explicitly so `from feature_matrix_generator import FEATURES` resolves when
# this script is invoked as `python shared/feature_deprecation_check.py` OR
# when imported from a test harness with a different cwd.
_HERE = Path(__file__).resolve().parent
if str(_HERE) not in sys.path:
    sys.path.insert(0, str(_HERE))

from feature_matrix_generator import FEATURES  # noqa: E402  (sys.path setup above)


def load_feature_ids() -> list[str]:
    return [fid for fid, _, _ in FEATURES]


def candidates_for_removal(window_days: int = 180) -> list[str]:
    if not DB_PATH.exists():
        return []
    try:
        conn = sqlite3.connect(str(DB_PATH))
        cur = conn.cursor()
        cur.execute(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='feature_usage'"
        )
        if cur.fetchone() is None:
            conn.close()
            return []
        # Probe total row count in the same connection — skip if DB is empty so
        # new installs (no runs yet) don't flag every feature as a candidate.
        cur.execute("SELECT COUNT(*) FROM feature_usage")
        total = cur.fetchone()[0]
        if total == 0:
            conn.close()
            return []
        cutoff = (datetime.now(timezone.utc) - timedelta(days=window_days)).isoformat()
        cur.execute(
            "SELECT DISTINCT feature_id FROM feature_usage WHERE ts >= ?",
            (cutoff,),
        )
        active = {row[0] for row in cur.fetchall()}
        conn.close()
    except sqlite3.Error as exc:
        print(f"feature_deprecation_check: sqlite error: {exc}", file=sys.stderr)
        return []
    all_ids = set(load_feature_ids())
    return sorted(all_ids - active)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args(argv)

    candidates = candidates_for_removal(window_days=180)
    if not candidates:
        print("feature_deprecation_check: no candidates for removal")
        return 0

    print("Candidates for removal (180d zero usage):")
    for fid in candidates:
        print(f"  {fid}")
    if args.dry_run:
        return 0

    # PR-opening left as a placeholder; Phase 2 does not schedule this job yet.
    # When scheduled, shell out to gh CLI here. For now, the listed candidates
    # above are the actionable output; the caller decides what to do with them.
    return 0


if __name__ == "__main__":
    sys.exit(main())
