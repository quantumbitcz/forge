"""Emit a benchmark.regression learning row into .forge/run-history.db.

Called by aggregator when two consecutive weekly runs show solved->failed.
Row fields match shared/run-history/migrations/001-initial.sql:learnings.
"""

from __future__ import annotations

import sqlite3
from pathlib import Path


def emit_regression(db_path: Path, *, run_id: str, entry_id: str, domain: str, week: int) -> None:
    db_path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(str(db_path))
    try:
        conn.execute(
            "INSERT INTO learnings (run_id, type, content, domain, confidence, source_agent, applied_count) "
            "VALUES (?, 'benchmark.regression', ?, ?, 'HIGH', 'fg-aggregator', 0)",
            (run_id, f"Entry {entry_id} regressed on week {week}", domain),
        )
        conn.commit()
    finally:
        conn.close()
