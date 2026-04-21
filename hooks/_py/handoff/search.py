"""FTS5 index for handoffs. Writes to run-history.db handoff_fts virtual table."""
from __future__ import annotations

import sqlite3
from dataclasses import dataclass
from pathlib import Path


@dataclass
class Hit:
    path: str
    run_id: str
    snippet: str


def ensure_fts_schema(db_path: Path) -> None:
    conn = sqlite3.connect(str(db_path))
    try:
        conn.execute("""
            CREATE VIRTUAL TABLE IF NOT EXISTS handoff_fts USING fts5(
                run_id UNINDEXED,
                path UNINDEXED,
                content
            )
        """)
        conn.commit()
    finally:
        conn.close()


def index_handoff(db_path: Path, run_id: str, path: str, content: str) -> None:
    ensure_fts_schema(db_path)
    conn = sqlite3.connect(str(db_path))
    try:
        conn.execute("DELETE FROM handoff_fts WHERE path = ?", (path,))
        conn.execute(
            "INSERT INTO handoff_fts (run_id, path, content) VALUES (?, ?, ?)",
            (run_id, path, content),
        )
        conn.commit()
    finally:
        conn.close()


def search_handoffs(db_path: Path, query: str, limit: int = 20) -> list[Hit]:
    ensure_fts_schema(db_path)
    conn = sqlite3.connect(str(db_path))
    try:
        rows = conn.execute(
            "SELECT run_id, path, snippet(handoff_fts, 2, '[', ']', '...', 12) "
            "FROM handoff_fts WHERE handoff_fts MATCH ? LIMIT ?",
            (query, limit),
        ).fetchall()
        return [Hit(path=p, run_id=r, snippet=s) for r, p, s in rows]
    finally:
        conn.close()
