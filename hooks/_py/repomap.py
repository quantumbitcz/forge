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
from dataclasses import dataclass, field
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


# ---------------------------------------------------------------------------
# Task 5: pack assembly (FileScore, PackConfig, PackEntry, Pack, assemble_pack)
# ---------------------------------------------------------------------------

_BYTES_PER_TOKEN = 3.5


@dataclass
class FileScore:
    """Per-file score aggregated from PageRank, recency, and keyword overlap.

    Consumed by :func:`assemble_pack` which orders by ``score`` descending.
    """

    node_id: int
    path: str
    pagerank: float
    recency: float
    keyword_overlap: int
    score: float
    size_bytes: int
    last_modified_ts: int = 0


@dataclass(frozen=True)
class PackConfig:
    """Pack assembly configuration.

    ``budget_tokens`` bounds the sum of per-entry token costs.
    ``top_k`` hard-caps entries.
    ``min_slice_tokens`` is the minimum remaining budget for which a partial
    slice is still worth emitting (else the file is skipped).
    """

    budget_tokens: int = 8000
    top_k: int = 25
    min_slice_tokens: int = 400


@dataclass
class PackEntry:
    path: str
    mode: str  # "full" | "slice"
    tokens: int
    score: float
    recency: float
    slice_ranges: list[tuple[int, int]] = field(default_factory=list)

    def render(self) -> str:
        recent_flag = "yes" if self.recency > 1.0 else "no"
        if self.mode == "full":
            return (
                f"{self.path:<52} [full]   rank={self.score:.4f} "
                f"recent={recent_flag}"
            )
        lines = ",".join(f"{a}-{b}" for a, b in self.slice_ranges) or "none"
        return (
            f"{self.path:<52} [slice]  rank={self.score:.4f} "
            f"recent={recent_flag} lines={lines}"
        )


@dataclass
class Pack:
    entries: list[PackEntry]
    total_files_in_graph: int
    budget_tokens: int
    pack_tokens: int

    def render(self) -> str:
        header = (
            f"## Repo-map (top {len(self.entries)} of "
            f"{self.total_files_in_graph} files, "
            f"budget {self.pack_tokens}/{self.budget_tokens} tokens)"
        )
        return "\n".join([header, *(e.render() for e in self.entries)])


def _estimate_tokens(size_bytes: int) -> int:
    """Approximate token count for a byte payload (ceil division)."""
    if size_bytes <= 0:
        return 0
    return max(1, int(-(-size_bytes // 1) / _BYTES_PER_TOKEN))


def assemble_pack(
    scored: dict[int, FileScore],
    cfg: PackConfig,
    *,
    slice_fetcher=None,
) -> Pack:
    """Walk files in score-descending order.

    For each file: include whole if it fits the remaining budget; else include
    a partial slice if at least ``min_slice_tokens`` remain; else skip. Always
    caps at ``cfg.top_k`` entries.

    ``slice_fetcher(node_id, remaining_tokens)`` may return ``(ranges, cost)``
    where ``ranges`` is a list of ``(start_line, end_line)`` tuples and
    ``cost`` is the estimated token cost. When ``None``, a conservative stub
    emits a single window proportional to the remaining budget.
    """
    total_files = len(scored)
    ordered = sorted(scored.values(), key=lambda s: s.score, reverse=True)
    entries: list[PackEntry] = []
    remaining = cfg.budget_tokens

    for s in ordered:
        if len(entries) >= cfg.top_k:
            break
        full_cost = _estimate_tokens(s.size_bytes)
        if full_cost > 0 and remaining >= full_cost:
            entries.append(
                PackEntry(
                    path=s.path,
                    mode="full",
                    tokens=full_cost,
                    score=s.score,
                    recency=s.recency,
                )
            )
            remaining -= full_cost
            continue
        if remaining >= cfg.min_slice_tokens:
            if slice_fetcher:
                ranges, cost = slice_fetcher(s.node_id, remaining)
            else:
                window_lines = min(80, max(10, remaining // 4))
                ranges = [(1, window_lines)]
                cost = min(remaining, cfg.min_slice_tokens)
            if cost > remaining or cost < cfg.min_slice_tokens:
                continue
            entries.append(
                PackEntry(
                    path=s.path,
                    mode="slice",
                    tokens=cost,
                    score=s.score,
                    recency=s.recency,
                    slice_ranges=ranges,
                )
            )
            remaining -= cost
        # else skip.

    return Pack(
        entries=entries,
        total_files_in_graph=total_files,
        budget_tokens=cfg.budget_tokens,
        pack_tokens=cfg.budget_tokens - remaining,
    )
