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

import argparse
import hashlib
import json
import sqlite3
import sys
import time as _time
from collections import OrderedDict
from dataclasses import asdict, dataclass, field
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


# ---------------------------------------------------------------------------
# Task 6: write-through pack cache with 4-tuple key + LRU eviction
# ---------------------------------------------------------------------------

CACHE_SCHEMA_VERSION = "1.0.0"


@dataclass
class CachedPack:
    graph_sha: str
    keywords_hash: str
    budget: int
    top_k: int
    computed_at: str
    ranked: list[dict]
    baseline_tokens_estimate: int = 0
    baseline_source: str = "estimated"  # "estimated" | "measured"


class PackCache:
    """Write-through JSON cache keyed on the 4-tuple
    ``(graph_sha, keywords_hash, budget, top_k)`` with LRU eviction at
    ``max_entries``.

    On-disk format (JSON)::

        {"schema_version": "1.0.0", "entries": [ {...CachedPack...}, ... ]}

    Corrupt JSON yields an empty in-memory cache (callers interpret the miss
    as ``repomap.bypass.corrupt_cache``). Writes are atomic (``tmp + replace``).
    """

    def __init__(self, path: Path | str, max_entries: int = 16):
        self.path = Path(path)
        self.max_entries = max_entries
        self._entries: OrderedDict[tuple, CachedPack] = OrderedDict()
        self._load()

    @staticmethod
    def _key(graph_sha, keywords_hash, budget, top_k) -> tuple:
        return (graph_sha, keywords_hash, int(budget), int(top_k))

    def _load(self) -> None:
        if not self.path.exists():
            return
        try:
            data = json.loads(self.path.read_text())
            if not isinstance(data, dict):
                return
            if data.get("schema_version") != CACHE_SCHEMA_VERSION:
                return
            for raw in data.get("entries", []):
                cp = CachedPack(**raw)
                self._entries[
                    self._key(
                        cp.graph_sha, cp.keywords_hash, cp.budget, cp.top_k
                    )
                ] = cp
        except (json.JSONDecodeError, TypeError, KeyError, ValueError):
            self._entries.clear()

    def get(self, graph_sha, keywords_hash, budget, top_k) -> CachedPack | None:
        k = self._key(graph_sha, keywords_hash, budget, top_k)
        if k not in self._entries:
            return None
        self._entries.move_to_end(k)
        return self._entries[k]

    def put(self, entry: CachedPack) -> None:
        k = self._key(
            entry.graph_sha, entry.keywords_hash, entry.budget, entry.top_k
        )
        self._entries[k] = entry
        self._entries.move_to_end(k)
        while len(self._entries) > self.max_entries:
            self._entries.popitem(last=False)

    def flush(self) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        payload = {
            "schema_version": CACHE_SCHEMA_VERSION,
            "entries": [asdict(e) for e in self._entries.values()],
        }
        tmp = self.path.with_suffix(self.path.suffix + ".tmp")
        tmp.write_text(json.dumps(payload, indent=2))
        tmp.replace(self.path)

    def clear(self) -> None:
        self._entries.clear()
        if self.path.exists():
            self.path.unlink()


# ---------------------------------------------------------------------------
# Task 7: CLI subcommands + sparse-graph bypass + named failure events
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class RecencyConfig:
    """Configuration for the recency multiplier in :func:`score_files`."""

    window_days: int = 30
    boost_max: float = 1.5


def _load_file_rows(
    db_path: Path | str,
) -> list[tuple[int, str, int, int]]:
    """Return ``[(node_id, path, size_bytes, last_modified_ts), ...]``.

    Tolerant of both the production schema (``file_path`` column, ``properties``
    JSON carrying ``size_bytes`` / ``last_modified_ts``) and the simplified
    fixture schema used by unit tests (``path`` column, no property blob).
    Missing fields default to ``0`` so the recency multiplier stays neutral.
    """
    conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
    try:
        cols = {row[1] for row in conn.execute("PRAGMA table_info(nodes)")}
        path_col = "file_path" if "file_path" in cols else "path"
        has_props = "properties" in cols
        select = f"SELECT id, {path_col}"
        select += ", COALESCE(properties, '{}')" if has_props else ", '{}'"
        select += " FROM nodes"
        if "kind" in cols:
            select += " WHERE kind='File' OR kind IS NULL"
        rows: list[tuple[int, str, int, int]] = []
        for nid, path, props in conn.execute(select):
            try:
                p = json.loads(props or "{}") if props else {}
            except (json.JSONDecodeError, TypeError):
                p = {}
            size = int(p.get("size_bytes") or 0)
            lmt = int(p.get("last_modified_ts") or 0)
            rows.append((int(nid), str(path), size, lmt))
        return rows
    finally:
        conn.close()


def score_files(
    db_path: Path | str,
    keywords: list[str],
    edge_weights: dict[str, float],
    recency_cfg: RecencyConfig,
    *,
    keyword_overlap_cap: int = 5,
) -> dict[int, FileScore]:
    """Aggregate PageRank × recency × (1 + overlap/cap) into per-file scores.

    Any ``RuntimeError`` from :func:`run_pagerank` propagates so callers can
    emit ``repomap.bypass.solve_diverged``.
    """
    ranks = run_pagerank(db_path, edge_weights)
    rows = _load_file_rows(db_path)
    now = int(_time.time())
    window_secs = max(1, recency_cfg.window_days * 86400)
    kw_lc = [k.lower() for k in keywords]
    scored: dict[int, FileScore] = {}
    for nid, path, size, lmt in rows:
        pr = float(ranks.get(nid, 0.0))
        if lmt > 0:
            age = max(0, now - lmt)
            decay = max(0.0, 1.0 - (age / window_secs))
            recency = 1.0 + decay * (recency_cfg.boost_max - 1.0)
        else:
            recency = 1.0
        overlap = 0
        path_lc = path.lower()
        for k in kw_lc:
            if k and k in path_lc:
                overlap += 1
                if overlap >= keyword_overlap_cap:
                    break
        overlap_mult = 1.0 + (overlap / max(1, keyword_overlap_cap))
        scored[nid] = FileScore(
            node_id=nid,
            path=path,
            pagerank=pr,
            recency=recency,
            keyword_overlap=overlap,
            score=pr * recency * overlap_mult,
            size_bytes=size,
            last_modified_ts=lmt,
        )
    return scored


def _log_bypass(event: str) -> None:
    print(event, file=sys.stderr)


def _degraded_pack(db_path: Path, budget: int, top_k: int) -> Pack:
    """Empty pack used when PageRank cannot run (missing/sparse/diverged)."""
    return Pack(
        entries=[],
        total_files_in_graph=0,
        budget_tokens=budget,
        pack_tokens=0,
    )


def _estimate_baseline_tokens(db_path: Path) -> int:
    """Analytical baseline: sum of File-node ``size_bytes`` / bytes-per-token."""
    if not Path(db_path).exists():
        return 0
    try:
        conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
        try:
            cols = {row[1] for row in conn.execute("PRAGMA table_info(nodes)")}
            if "properties" not in cols:
                return 0
            total = 0
            query = "SELECT COALESCE(properties,'{}') FROM nodes"
            if "kind" in cols:
                query += " WHERE kind='File'"
            for (props,) in conn.execute(query):
                try:
                    total += int((json.loads(props) or {}).get("size_bytes") or 0)
                except (json.JSONDecodeError, TypeError, ValueError):
                    pass
            return int(total / _BYTES_PER_TOKEN)
        finally:
            conn.close()
    except sqlite3.DatabaseError:
        return 0


def _node_count(db_path: Path) -> int:
    conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
    try:
        (n,) = conn.execute("SELECT COUNT(*) FROM nodes").fetchone()
        return int(n)
    finally:
        conn.close()


def _read_keywords(path: str | None) -> list[str]:
    if not path:
        return []
    p = Path(path)
    if not p.exists():
        return []
    try:
        text = p.read_text()
    except OSError:
        return []
    try:
        from hooks._py.keyword_extract import extract_keywords

        return extract_keywords(text)
    except ImportError:
        return [tok for tok in text.split() if tok]


def _cmd_build_pack(args) -> int:
    db = Path(args.db)

    if not db.exists():
        _log_bypass("repomap.bypass.missing_graph")
        print(_degraded_pack(db, args.budget, args.top_k).render())
        return 0

    try:
        graph_sha = compute_graph_sha(db)
    except sqlite3.DatabaseError:
        _log_bypass("repomap.bypass.missing_graph")
        print(_degraded_pack(db, args.budget, args.top_k).render())
        return 0

    # Detect a corrupt cache before handing the file to PackCache so we can
    # emit the named bypass event. PackCache itself recovers to an empty map.
    cache_path = Path(args.cache)
    if cache_path.exists():
        try:
            json.loads(cache_path.read_text())
        except (json.JSONDecodeError, OSError):
            _log_bypass("repomap.bypass.corrupt_cache")
    cache = PackCache(cache_path, max_entries=args.cache_max_entries)

    keywords = _read_keywords(args.keywords_file)
    kh = compute_keywords_hash(keywords)

    cached = cache.get(graph_sha, kh, args.budget, args.top_k)
    if cached is not None:
        entries = [
            PackEntry(
                path=r["file"],
                mode=r.get("mode", "full"),
                tokens=int(r.get("tokens", 0)),
                score=float(r.get("score", 0.0)),
                recency=float(r.get("recency", 1.0)),
                slice_ranges=[tuple(x) for x in r.get("slice_ranges", [])],
            )
            for r in cached.ranked
        ]
        pack_tokens = sum(e.tokens for e in entries)
        pack = Pack(
            entries=entries,
            total_files_in_graph=len(cached.ranked),
            budget_tokens=args.budget,
            pack_tokens=pack_tokens,
        )
        print(pack.render())
        return 0

    try:
        nodes = _node_count(db)
    except sqlite3.DatabaseError:
        _log_bypass("repomap.bypass.missing_graph")
        print(_degraded_pack(db, args.budget, args.top_k).render())
        return 0
    if nodes < args.min_nodes_for_rank:
        _log_bypass("repomap.bypass.sparse_graph")
        print(_degraded_pack(db, args.budget, args.top_k).render())
        return 0

    try:
        scored = score_files(
            db,
            keywords,
            DEFAULT_EDGE_WEIGHTS,
            RecencyConfig(
                window_days=args.recency_window_days,
                boost_max=args.recency_boost_max,
            ),
            keyword_overlap_cap=args.keyword_overlap_cap,
        )
    except RuntimeError as e:
        if "solve_diverged" in str(e):
            _log_bypass("repomap.bypass.solve_diverged")
            print(_degraded_pack(db, args.budget, args.top_k).render())
            return 0
        raise

    pack = assemble_pack(
        scored,
        PackConfig(
            budget_tokens=args.budget,
            top_k=args.top_k,
            min_slice_tokens=args.min_slice_tokens,
        ),
    )
    baseline = _estimate_baseline_tokens(db)
    cache.put(
        CachedPack(
            graph_sha=graph_sha,
            keywords_hash=kh,
            budget=args.budget,
            top_k=args.top_k,
            computed_at=_time.strftime("%Y-%m-%dT%H:%M:%SZ", _time.gmtime()),
            ranked=[
                {
                    "file": e.path,
                    "score": e.score,
                    "recency": e.recency,
                    "mode": e.mode,
                    "tokens": e.tokens,
                    "slice_ranges": list(e.slice_ranges),
                }
                for e in pack.entries
            ],
            baseline_tokens_estimate=baseline,
            baseline_source="estimated",
        )
    )
    cache.flush()
    print(pack.render())
    return 0


def _cmd_pagerank(args) -> int:
    try:
        ranks = run_pagerank(args.db, DEFAULT_EDGE_WEIGHTS)
    except sqlite3.DatabaseError:
        _log_bypass("repomap.bypass.missing_graph")
        return 0
    except RuntimeError as e:
        if "solve_diverged" in str(e):
            _log_bypass("repomap.bypass.solve_diverged")
            return 0
        raise
    for nid, r in sorted(ranks.items(), key=lambda kv: -kv[1]):
        print(f"{nid}\t{r:.6f}")
    return 0


def _cmd_cache_clear(args) -> int:
    PackCache(args.cache, max_entries=1).clear()
    return 0


def _cmd_explain(args) -> int:
    db = Path(args.db)
    if not db.exists():
        _log_bypass("repomap.bypass.missing_graph")
        return 0
    keywords = _read_keywords(args.keywords_file)
    try:
        scored = score_files(
            db,
            keywords,
            DEFAULT_EDGE_WEIGHTS,
            RecencyConfig(),
            keyword_overlap_cap=args.keyword_overlap_cap,
        )
    except RuntimeError as e:
        if "solve_diverged" in str(e):
            _log_bypass("repomap.bypass.solve_diverged")
            return 0
        raise
    except sqlite3.DatabaseError:
        _log_bypass("repomap.bypass.missing_graph")
        return 0
    print(f"{'path':<60}\tpagerank\trecency\toverlap\tscore")
    for s in sorted(scored.values(), key=lambda x: -x.score)[:50]:
        print(
            f"{s.path:<60}\t{s.pagerank:.4f}\t{s.recency:.2f}"
            f"\t{s.keyword_overlap}\t{s.score:.4f}"
        )
    return 0


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(prog="repomap")
    sub = p.add_subparsers(dest="cmd", required=True)
    for name, fn in [
        ("build-pack", _cmd_build_pack),
        ("pagerank", _cmd_pagerank),
        ("cache-clear", _cmd_cache_clear),
        ("explain", _cmd_explain),
    ]:
        sp = sub.add_parser(name)
        sp.add_argument("--db", default=".forge/code-graph.db")
        sp.add_argument("--cache", default=".forge/ranked-files-cache.json")
        sp.add_argument("--keywords-file", default=".forge/current-keywords.txt")
        sp.add_argument("--budget", type=int, default=8000)
        sp.add_argument("--top-k", type=int, default=25)
        sp.add_argument("--min-slice-tokens", type=int, default=400)
        sp.add_argument("--min-nodes-for-rank", type=int, default=50)
        sp.add_argument("--recency-window-days", type=int, default=30)
        sp.add_argument("--recency-boost-max", type=float, default=1.5)
        sp.add_argument("--keyword-overlap-cap", type=int, default=5)
        sp.add_argument("--cache-max-entries", type=int, default=16)
        sp.set_defaults(func=fn)
    ns = p.parse_args(argv)
    return ns.func(ns)


if __name__ == "__main__":
    raise SystemExit(main())
