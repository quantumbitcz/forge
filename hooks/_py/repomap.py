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


import numpy as np

DEFAULT_EDGE_WEIGHTS: dict[str, float] = {
    "CALLS": 1.0,
    "REFERENCES": 1.0,
    "IMPORTS": 0.7,
    "INHERITS": 0.8,
    "IMPLEMENTS": 0.8,
    "TESTS": 0.4,
    "CONTAINS": 0.3,
}

_DAMPING = 0.85
_TOLERANCE = 1e-6
_MAX_ITERS = 100


def run_pagerank(
    db_path: Path | str,
    edge_weights: dict[str, float],
    personalization: dict[int, float] | None = None,
) -> dict[int, float]:
    """Power-iteration PageRank over (nodes, edges) in the SQLite graph.

    Returns {node_id: rank}. Ranks sum to 1.0. Deterministic:
    nodes are sorted by id; dangling mass is redistributed uniformly.
    Raises RuntimeError if iteration did not converge in _MAX_ITERS
    (caller emits `repomap.bypass.solve_diverged`).
    """
    conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
    try:
        node_ids = [r[0] for r in conn.execute(
            "SELECT id FROM nodes ORDER BY id"
        )]
        if not node_ids:
            return {}
        idx = {nid: i for i, nid in enumerate(node_ids)}
        n = len(node_ids)
        # Weighted transition matrix M[i, j] = w(j->i) / out_weight(j).
        M = np.zeros((n, n), dtype=np.float64)
        out_weight = np.zeros(n, dtype=np.float64)
        for src, dst, etype in conn.execute(
            "SELECT src, dst, edge_type FROM edges"
        ):
            if src not in idx or dst not in idx:
                continue
            w = edge_weights.get(etype, 0.0)
            if w <= 0:
                continue
            i, j = idx[dst], idx[src]
            M[i, j] += w
            out_weight[j] += w
        # Normalize columns; dangling (out_weight==0) cols handled by teleport.
        nonzero = out_weight > 0
        M[:, nonzero] /= out_weight[nonzero]
        # Personalization vector p (uniform if None); must sum to 1.
        if personalization:
            p = np.zeros(n, dtype=np.float64)
            for nid, v in personalization.items():
                if nid in idx:
                    p[idx[nid]] = v
            s = p.sum()
            p = (p / s) if s > 0 else np.ones(n) / n
        else:
            p = np.ones(n, dtype=np.float64) / n
    finally:
        conn.close()

    pr = np.ones(n, dtype=np.float64) / n
    for _ in range(_MAX_ITERS):
        dangling = pr[~nonzero].sum() if (~nonzero).any() else 0.0
        new_pr = _DAMPING * (M @ pr + dangling * p) + (1 - _DAMPING) * p
        if np.max(np.abs(new_pr - pr)) < _TOLERANCE:
            pr = new_pr
            break
        pr = new_pr
    else:
        raise RuntimeError("repomap.bypass.solve_diverged")
    # Final normalization guard against numerical drift.
    pr = pr / pr.sum()
    return {nid: float(pr[idx[nid]]) for nid in node_ids}
