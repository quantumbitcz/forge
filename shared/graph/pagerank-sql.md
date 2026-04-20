# Repo-Map PageRank — Algorithm Reference

Authoritative reference for `hooks/_py/repomap.py`. Normative spec:
`docs/superpowers/specs/2026-04-19-10-repo-map-pagerank-design.md`.

## 1. Algorithm

Power-iteration PageRank on the SQLite code graph.

    PR(v) = (1 - d) / N  +  d × Σ_{u ∈ in(v)} [ w(u,v) / out_weight(u) ] × PR(u)

- **Damping** `d = 0.85` — the damping factor (Brin & Page 1998; Aider production default).
- **Convergence:** `max(|PR_k - PR_{k-1}|) < 1e-6`, or 100 iterations (cap).
- **Dangling mass:** redistributed uniformly (teleport vector `p = 1/N`).
- **Personalization:** `p` may be biased by keyword overlap; node IDs are
  sorted ascending before matrix construction for determinism.

## 2. Edge weights (table in §4.1 of the spec)

| Edge type | Weight | Rationale |
|---|---|---|
| CALLS | 1.0 | Strongest structural dependency. |
| REFERENCES | 1.0 | Same weight; used where language analyzer can't distinguish. |
| IMPORTS | 0.7 | Module-level signal, weaker than symbol-level call. |
| INHERITS | 0.8 | Strong semantic coupling. |
| IMPLEMENTS | 0.8 | Same class as INHERITS. |
| TESTS | 0.4 | Informative but must not dominate ranking. |
| CONTAINS | 0.3 | Structural glue between File and contained symbols. |

Weights are configurable via `code_graph.prompt_compaction.edge_weights` (expert tuning).

## 3. Per-file scoring

    score(f) = pagerank(f) × recency_multiplier(f) × (1 + keyword_overlap(f, query))

- `pagerank(f)` sums the file-node rank plus ranks of all symbols contained in it (CONTAINS edges).
- `recency_multiplier` linearly decays from 1.5× at age 0 days to 1.0× at `recency_window_days`; flat 1.0× beyond.
- `keyword_overlap(f, query)` = count of query keywords appearing in `path + contained symbol names`, capped at `keyword_overlap_cap` (default 5).

## 4. Cache key (4-tuple)

`(graph_sha, keywords_hash, budget, top_k)`. Each component must match for a hit:

- `graph_sha`: content-derived SHA-256 over `id || '|' || updated_at` for nodes and edges, ordered by id. Stable under no-op SQLite writes (spec-review Issue #3).
- `keywords_hash`: SHA-256 over the sorted keyword list.
- `budget` / `top_k`: the assembly parameters. Different agents have different budgets, so cache hits are scoped per call site.

## 5. Bypass event taxonomy

| Event | Condition | Pipeline effect |
|---|---|---|
| `repomap.bypass.sparse_graph` | `node_count < min_nodes_for_rank` (default 50). | Returns empty pack; orchestrator falls back to full listing. **Expected**; not a failure. |
| `repomap.bypass.missing_graph` | `code-graph.db` absent, unreadable, or malformed. | Same degradation; SC-4 failure metric. |
| `repomap.bypass.solve_diverged` | Power iteration did not converge in 100 iters. | Same; SC-4 failure metric. |
| `repomap.bypass.corrupt_cache` | `.forge/ranked-files-cache.json` invalid JSON or wrong schema. | Cache cleared silently; SC-4 failure metric. |

SC-4 `repomap.bypass.failure` = aggregate of `{missing_graph, solve_diverged, corrupt_cache}`.

## 6. Troubleshooting

- **"Cache never hits."** Check `.forge/ranked-files-cache.json` exists and is valid JSON; `python3 -m hooks._py.repomap cache-clear` resets it. If graph is rebuilt every run from scratch, the content SHA should still be stable across identical content — compare via `python3 -m hooks._py.repomap pagerank --db .forge/code-graph.db`.
- **"Pack keeps degrading."** Inspect stderr for `repomap.bypass.*` event; check `state.json.prompt_compaction.bypass_events`.
- **"Ranks look random."** Likely sparse-graph bypass; check `state.json.prompt_compaction.bypass_events.sparse_graph > 0`. Lower `min_nodes_for_rank` at your own risk.
- **"Cross-platform drift in ranks."** BLAS differs (macOS Accelerate vs Linux OpenBLAS); we assert rank **order**, not absolute values, in tests. If two machines disagree on order, recompute with `tolerance=1e-8`.
