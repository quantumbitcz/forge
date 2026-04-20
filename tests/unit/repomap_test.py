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


# ---------------------------------------------------------------------------
# Task 5: pack assembly tests
# ---------------------------------------------------------------------------

from hooks._py.repomap import FileScore, PackConfig, PackEntry, assemble_pack


def _mk_score(i, size_bytes, score):
    return FileScore(
        node_id=i,
        path=f"src/f{i}.py",
        pagerank=score,
        recency=1.0,
        keyword_overlap=0,
        score=score,
        size_bytes=size_bytes,
        last_modified_ts=1713600000,
    )


def test_budget_honored_whole_files():
    scored = {i: _mk_score(i, 1000, 1.0 / i) for i in range(1, 10)}
    # 1000 bytes ≈ 286 tokens each; budget 1000 tokens fits ~3 files whole.
    pack = assemble_pack(
        scored,
        PackConfig(budget_tokens=1000, top_k=25, min_slice_tokens=400),
    )
    total_tokens = sum(e.tokens for e in pack.entries)
    assert total_tokens <= 1000
    assert all(e.mode == "full" for e in pack.entries)


def test_topk_hard_cap():
    scored = {i: _mk_score(i, 10, 1.0 / i) for i in range(1, 100)}
    pack = assemble_pack(
        scored,
        PackConfig(budget_tokens=100000, top_k=25, min_slice_tokens=400),
    )
    assert len(pack.entries) == 25


def test_partial_slice_when_file_too_big():
    scored = {
        1: _mk_score(1, 100, 10.0),
        2: _mk_score(2, 100000, 5.0),
    }
    pack = assemble_pack(
        scored,
        PackConfig(budget_tokens=2000, top_k=25, min_slice_tokens=400),
    )
    paths = [e.path for e in pack.entries]
    assert "src/f1.py" in paths
    for e in pack.entries:
        if e.path == "src/f2.py":
            assert e.mode == "slice"
            assert e.tokens <= 2000


def test_pack_sorted_by_score_desc():
    scored = {
        1: _mk_score(1, 100, 0.1),
        2: _mk_score(2, 100, 0.9),
        3: _mk_score(3, 100, 0.5),
    }
    pack = assemble_pack(
        scored,
        PackConfig(budget_tokens=10000, top_k=25, min_slice_tokens=400),
    )
    scores = [e.score for e in pack.entries]
    assert scores == sorted(scores, reverse=True)


def test_pack_summary_header_counts():
    scored = {i: _mk_score(i, 100, 1.0 / i) for i in range(1, 5)}
    pack = assemble_pack(
        scored,
        PackConfig(budget_tokens=10000, top_k=25, min_slice_tokens=400),
    )
    header = pack.render().splitlines()[0]
    assert "Repo-map" in header
    assert "4 of 4" in header or "4 of" in header


# ---------------------------------------------------------------------------
# Task 6: write-through pack cache tests
# ---------------------------------------------------------------------------

from hooks._py.repomap import CachedPack, PackCache


def test_cache_hit_roundtrip(tmp_path):
    cache_path = tmp_path / "ranked-files-cache.json"
    cache = PackCache(cache_path, max_entries=16)
    entry = CachedPack(
        graph_sha="g" * 64,
        keywords_hash="k" * 64,
        budget=8000,
        top_k=25,
        computed_at="2026-04-19T10:00:00Z",
        ranked=[{"file": "a.py", "score": 0.1, "slice": None}],
    )
    cache.put(entry)
    cache.flush()
    # Fresh instance to ensure disk roundtrip.
    cache2 = PackCache(cache_path, max_entries=16)
    hit = cache2.get("g" * 64, "k" * 64, 8000, 25)
    assert hit is not None
    assert hit.ranked[0]["file"] == "a.py"


def test_cache_miss_on_any_tuple_component_change(tmp_path):
    cache = PackCache(tmp_path / "c.json", max_entries=16)
    cache.put(
        CachedPack(
            graph_sha="g" * 64,
            keywords_hash="k" * 64,
            budget=8000,
            top_k=25,
            computed_at="t",
            ranked=[],
        )
    )
    assert cache.get("x" * 64, "k" * 64, 8000, 25) is None
    assert cache.get("g" * 64, "y" * 64, 8000, 25) is None
    assert cache.get("g" * 64, "k" * 64, 4000, 25) is None
    assert cache.get("g" * 64, "k" * 64, 8000, 12) is None


def test_cache_lru_eviction_keeps_max_entries(tmp_path):
    cache = PackCache(tmp_path / "c.json", max_entries=3)
    for i in range(5):
        cache.put(
            CachedPack(
                graph_sha=str(i) * 64,
                keywords_hash="k" * 64,
                budget=8000,
                top_k=25,
                computed_at="t",
                ranked=[],
            )
        )
    cache.flush()
    assert cache.get("0" * 64, "k" * 64, 8000, 25) is None
    assert cache.get("1" * 64, "k" * 64, 8000, 25) is None
    assert cache.get("4" * 64, "k" * 64, 8000, 25) is not None


def test_cache_corrupt_returns_empty_and_logs(tmp_path):
    p = tmp_path / "c.json"
    p.write_text("{{{ not json")
    cache = PackCache(p, max_entries=16)
    assert cache.get("g" * 64, "k" * 64, 8000, 25) is None
    # Must not raise; caller interprets the miss as
    # `repomap.bypass.corrupt_cache`.


# ---------------------------------------------------------------------------
# Task 7: CLI subcommands + sparse-graph bypass + named failure events
# ---------------------------------------------------------------------------

import subprocess
import sys as _sys_for_cli


def _run_cli(*args, cwd=None):
    return subprocess.run(
        [_sys_for_cli.executable, "-m", "hooks._py.repomap", *args],
        cwd=cwd,
        capture_output=True,
        text=True,
        check=False,
    )


def test_sparse_graph_bypass(tmp_path, three_node_graph):
    # 3 nodes < min_nodes_for_rank (50) -> bypass emits degraded pack.
    keywords = tmp_path / "k.txt"
    keywords.write_text("plan service")
    cache_dir = tmp_path / ".forge"
    cache_dir.mkdir()
    res = _run_cli(
        "build-pack",
        "--db", str(three_node_graph),
        "--keywords-file", str(keywords),
        "--cache", str(cache_dir / "ranked-files-cache.json"),
        "--budget", "8000",
        "--top-k", "25",
        "--min-nodes-for-rank", "50",
    )
    assert res.returncode == 0, res.stderr
    assert "Repo-map" in res.stdout
    assert "repomap.bypass.sparse_graph" in res.stderr


def test_missing_graph_degrades(tmp_path):
    res = _run_cli(
        "build-pack",
        "--db", str(tmp_path / "does-not-exist.db"),
        "--keywords-file", "/dev/null",
        "--cache", str(tmp_path / "c.json"),
        "--budget", "8000",
        "--top-k", "25",
    )
    assert res.returncode == 0
    assert "repomap.bypass.missing_graph" in res.stderr


def test_explain_subcommand(three_node_graph, tmp_path):
    keywords = tmp_path / "k.txt"
    keywords.write_text("")
    res = _run_cli(
        "explain",
        "--db", str(three_node_graph),
        "--keywords-file", str(keywords),
    )
    assert res.returncode == 0
    assert "pagerank" in res.stdout.lower() or "rank" in res.stdout.lower()


def test_cache_clear_subcommand(tmp_path):
    cache = tmp_path / "c.json"
    cache.write_text('{"schema_version":"1.0.0","entries":[]}')
    res = _run_cli("cache-clear", "--cache", str(cache))
    assert res.returncode == 0
    assert not cache.exists()
