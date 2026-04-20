"""Repo-map PageRank + token-budgeted context pack assembly.

CLI entry: `python3 -m hooks._py.repomap <subcommand> [flags]`

Subcommands (added in later tasks):
  pagerank, build-pack, cache-clear, explain.

Graceful-degradation events (logged as INFO to stderr):
  repomap.bypass.sparse_graph     — node_count < min_nodes_for_rank
  repomap.bypass.missing_graph    — code-graph.db absent or unreadable
  repomap.bypass.solve_diverged   — power iteration did not converge in 100 iters
  repomap.bypass.corrupt_cache    — ranked-files-cache.json invalid JSON / schema
SC-4's `repomap.bypass.failure` = {missing_graph, solve_diverged, corrupt_cache}.
"""
from __future__ import annotations

import hashlib
import sqlite3
from pathlib import Path


def compute_graph_sha(db_path: Path | str) -> str:
    """Content-derived SHA-256 over nodes + edges projections.

    Stable under no-op incremental writes (addresses spec-review Issue #3).
    Projection: `id || '|' || updated_at` ordered by id, for nodes then edges.
    """
    conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
    try:
        h = hashlib.sha256()
        for row in conn.execute(
            "SELECT id, COALESCE(updated_at, '') FROM nodes ORDER BY id"
        ):
            h.update(f"N{row[0]}|{row[1]}\n".encode("utf-8"))
        for row in conn.execute(
            "SELECT id, COALESCE(updated_at, '') FROM edges ORDER BY id"
        ):
            h.update(f"E{row[0]}|{row[1]}\n".encode("utf-8"))
        return h.hexdigest()
    finally:
        conn.close()


def compute_keywords_hash(keywords: list[str]) -> str:
    """Order-independent SHA-256 of sorted keyword list."""
    payload = "\n".join(sorted(keywords)).encode("utf-8") if keywords else b""
    return hashlib.sha256(payload).hexdigest()
