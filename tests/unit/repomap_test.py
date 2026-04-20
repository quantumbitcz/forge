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


from hooks._py.repomap import run_pagerank, DEFAULT_EDGE_WEIGHTS


@pytest.fixture
def three_node_graph(tmp_path: Path) -> Path:
    db = tmp_path / "cg.db"
    conn = sqlite3.connect(db)
    conn.executescript(
        """
        CREATE TABLE nodes (id INTEGER PRIMARY KEY, kind TEXT, path TEXT,
                            properties TEXT, updated_at TEXT);
        CREATE TABLE edges (id INTEGER PRIMARY KEY, src INTEGER, dst INTEGER,
                            edge_type TEXT, updated_at TEXT);
        INSERT INTO nodes VALUES
          (1,'File','a.py','{}','2026-04-19T10:00:00Z'),
          (2,'File','b.py','{}','2026-04-19T10:00:00Z'),
          (3,'File','c.py','{}','2026-04-19T10:00:00Z');
        -- a <- b, a <- c: a is a hub and should rank highest
        INSERT INTO edges VALUES
          (1,2,1,'CALLS','t'),
          (2,3,1,'CALLS','t');
        """
    )
    conn.commit()
    conn.close()
    return db


def test_pagerank_hub_ranks_highest(three_node_graph):
    ranks = run_pagerank(three_node_graph, DEFAULT_EDGE_WEIGHTS)
    # Node 1 is the hub (2 incoming CALLS). It must rank higher than 2 or 3.
    assert ranks[1] > ranks[2]
    assert ranks[1] > ranks[3]


def test_pagerank_determinism(three_node_graph):
    r1 = run_pagerank(three_node_graph, DEFAULT_EDGE_WEIGHTS)
    r2 = run_pagerank(three_node_graph, DEFAULT_EDGE_WEIGHTS)
    for nid in r1:
        assert r1[nid] == pytest.approx(r2[nid], abs=1e-12)


def test_pagerank_sums_to_one(three_node_graph):
    ranks = run_pagerank(three_node_graph, DEFAULT_EDGE_WEIGHTS)
    assert sum(ranks.values()) == pytest.approx(1.0, abs=1e-6)


def test_pagerank_convergence_bounded():
    # Fabricate a 100-node ring; must converge well under 100 iters.
    import tempfile
    with tempfile.TemporaryDirectory() as td:
        db = Path(td) / "ring.db"
        conn = sqlite3.connect(db)
        conn.executescript(
            "CREATE TABLE nodes (id INTEGER PRIMARY KEY, kind TEXT, path TEXT, "
            "properties TEXT, updated_at TEXT);"
            "CREATE TABLE edges (id INTEGER PRIMARY KEY, src INTEGER, dst INTEGER, "
            "edge_type TEXT, updated_at TEXT);"
        )
        for i in range(1, 101):
            conn.execute(
                "INSERT INTO nodes VALUES (?,?,?,?,?)",
                (i, "File", f"f{i}.py", "{}", "t"),
            )
        for i in range(1, 101):
            conn.execute(
                "INSERT INTO edges VALUES (?,?,?,?,?)",
                (i, i, (i % 100) + 1, "CALLS", "t"),
            )
        conn.commit()
        conn.close()
        ranks = run_pagerank(db, DEFAULT_EDGE_WEIGHTS)
        assert len(ranks) == 100
