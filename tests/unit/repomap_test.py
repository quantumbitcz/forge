import hashlib
import sqlite3
from pathlib import Path

import pytest

from hooks._py.repomap import compute_graph_sha, compute_keywords_hash


@pytest.fixture
def sample_db(tmp_path: Path) -> Path:
    db = tmp_path / "code-graph.db"
    conn = sqlite3.connect(db)
    conn.executescript(
        """
        CREATE TABLE nodes (id INTEGER PRIMARY KEY, kind TEXT, path TEXT, updated_at TEXT);
        CREATE TABLE edges (id INTEGER PRIMARY KEY, src INTEGER, dst INTEGER,
                            edge_type TEXT, updated_at TEXT);
        INSERT INTO nodes VALUES (1,'File','a.py','2026-04-19T10:00:00Z');
        INSERT INTO nodes VALUES (2,'File','b.py','2026-04-19T10:00:00Z');
        INSERT INTO edges VALUES (1,1,2,'IMPORTS','2026-04-19T10:00:00Z');
        """
    )
    conn.commit()
    conn.close()
    return db


def test_graph_sha_is_content_derived_stable_under_noop_touch(sample_db, tmp_path):
    sha1 = compute_graph_sha(sample_db)
    # Simulate an incremental rebuild that rewrites the same rows (no content change).
    conn = sqlite3.connect(sample_db)
    conn.execute("UPDATE nodes SET updated_at = updated_at WHERE id = 1")
    conn.commit()
    conn.close()
    sha2 = compute_graph_sha(sample_db)
    assert sha1 == sha2, "SHA must be stable under no-op update"


def test_graph_sha_changes_when_content_changes(sample_db):
    sha1 = compute_graph_sha(sample_db)
    conn = sqlite3.connect(sample_db)
    conn.execute("UPDATE nodes SET updated_at = '2026-05-01T00:00:00Z' WHERE id = 1")
    conn.commit()
    conn.close()
    sha2 = compute_graph_sha(sample_db)
    assert sha1 != sha2, "SHA must change when row content changes"


def test_keywords_hash_is_order_independent_and_deterministic():
    h1 = compute_keywords_hash(["plan", "service", "validate"])
    h2 = compute_keywords_hash(["validate", "plan", "service"])
    assert h1 == h2
    assert len(h1) == 64  # sha256 hex


def test_keywords_hash_empty():
    assert compute_keywords_hash([]) == hashlib.sha256(b"").hexdigest()
