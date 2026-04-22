import sqlite3
from pathlib import Path

from hooks._py.handoff.search import ensure_fts_schema, index_handoff, search_handoffs


def test_index_and_search(tmp_path):
    db = tmp_path / "run-history.db"
    ensure_fts_schema(db)
    path = tmp_path / "h.md"
    path.write_text("Pipeline reached REVIEWING at score 82 for feature health endpoint.")
    index_handoff(db, run_id="r1", path=str(path), content=path.read_text())
    hits = search_handoffs(db, query="health endpoint")
    assert len(hits) == 1
    assert hits[0].path == str(path)


def test_reindex_replaces_existing(tmp_path):
    """Re-indexing the same path overwrites prior content (no duplicates)."""
    db = tmp_path / "run-history.db"
    ensure_fts_schema(db)
    index_handoff(db, run_id="r1", path="h1.md", content="original content about foo")
    index_handoff(db, run_id="r1", path="h1.md", content="revised content about bar")
    hits_foo = search_handoffs(db, query="foo")
    hits_bar = search_handoffs(db, query="bar")
    assert len(hits_foo) == 0
    assert len(hits_bar) == 1


def test_search_no_table_ok(tmp_path):
    """Calling search_handoffs on a fresh db auto-creates table, returns empty."""
    db = tmp_path / "run-history.db"
    # Do NOT call ensure_fts_schema first — verify auto-create
    hits = search_handoffs(db, query="anything")
    assert hits == []


def test_malformed_query_returns_empty(tmp_path):
    """FTS5 syntax errors in user queries must not crash search."""
    db = tmp_path / "run-history.db"
    ensure_fts_schema(db)
    index_handoff(db, run_id="r1", path="x.md", content="normal content")

    # Unbalanced quote — would trigger FTS5 OperationalError without escaping
    hits = search_handoffs(db, query='unterminated "quote')
    assert isinstance(hits, list)
    # Trailing operator — would also crash
    hits2 = search_handoffs(db, query="foo AND ")
    assert isinstance(hits2, list)
    # Empty query
    hits3 = search_handoffs(db, query="")
    assert hits3 == []
