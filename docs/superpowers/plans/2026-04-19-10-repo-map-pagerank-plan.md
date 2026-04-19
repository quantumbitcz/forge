# Phase 10 — Repo-Map PageRank Dynamic Prompt Context — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rank files in the existing SQLite code graph with biased PageRank (structure × recency × keyword overlap) and assemble token-budgeted context packs that replace full-directory listings in `fg-100-orchestrator`, `fg-200-planner`, and `fg-300-implementer` dispatch prompts — cutting stage prompt tokens 30–50 % with no measurable score regression.

**Architecture:** New Python module `hooks/_py/repomap.py` (stdlib + NumPy, Phase 02) exposes `pagerank`, `build-pack`, `cache-clear`, `explain` subcommands. Power iteration (d=0.85, 1e-6 tolerance) over `nodes`/`edges`; per-file score = `pagerank × recency_multiplier × (1 + keyword_overlap)`. Whole-file → partial-slice → skip pack assembly honors a configurable token budget and top-K cap. A write-through JSON cache keyed on the 4-tuple `(graph_sha, keywords_hash, budget, top_k)` — where `graph_sha` is content-derived from nodes+edges (not file SHA) — guards against recompute storms under incremental graph updates. Dispatch templates substitute a `{{REPO_MAP_PACK}}` placeholder. Sparse-graph bypass, baseline-token bootstrap via analytical estimate (`sum(size_bytes)/3.5`), and named `repomap.bypass.*` failure events give graceful degradation. Phase 01 eval harness A/Bs compaction OFF vs ON; CI matrix gate fails PRs if the ON run drops > 2 composite points. Opt-in default OFF; 20-run graduation gate flips the default in `plugin.json`.

**Tech Stack:** Python 3.10+ (Phase 02 runtime), NumPy (Phase 02 dep), `sqlite3` (stdlib), pytest (Phase 02 test runner), bats-core (contract tests), GitHub Actions matrix (Phase 01 eval harness), forge SQLite code graph (`shared/graph/code-graph-schema.sql`).

**Review-issue resolutions (per `docs/superpowers/reviews/2026-04-19-10-repo-map-pagerank-spec-review.md`):**

- **Issue #1 — Cache-key copy inconsistency.** This plan standardizes on the 4-tuple `(graph_sha, keywords_hash, budget, top_k)` everywhere (code, tests, docs, config, spec edit in Task 13). `graph_sha` is a content-derived hash (see Issue #3). The two-tuple phrasing in spec §3 is corrected in Task 13.
- **Issue #2 — `baseline_tokens_estimate` bootstrap.** This plan picks the **analytical estimate** option: on first compaction call per stage, sum `size_bytes` over the files that would have been in the full listing, divide by 3.5 tokens/byte, and write `baseline_source: "estimated"` alongside the estimate in `state.json`. No second "dry pass" run required. Implemented in Task 6; state schema update in Task 11.
- **Issue #3 — Graph-SHA thrash on incremental writes.** This plan uses a **content-derived hash** computed as SHA-256 over `group_concat(id || '|' || updated_at ORDER BY id)` from `nodes` concatenated with the same projection from `edges`. This hash is stable under no-op incremental writes (sqlite may touch file metadata without changing row contents) and invalidates only when node/edge contents actually change. Implemented in Task 4; tested in Task 5.
- **Issue #4 — `repomap.bypass.failure` event taxonomy.** This plan enumerates three named sub-events (`repomap.bypass.missing_graph`, `repomap.bypass.solve_diverged`, `repomap.bypass.corrupt_cache`) in Task 7 and defines SC-4's `repomap.bypass.failure` as their aggregate (spec edit in Task 13).
- **Issue #5 — Implementer budget compounding on parallel dispatch.** This plan resolves to **per-task packs** (option b) and acknowledges the parallel-fan-out cost in the SC-1 framing (spec edit in Task 13). Per-task is chosen because ranking relevance collapses when a shared pack must serve disjoint task contexts; the token cost is the correct price for quality.

---

## File Structure

**New files (5):**

| Path | Responsibility |
|---|---|
| `hooks/_py/repomap.py` | Core module. CLI + importable library. Subcommands: `pagerank`, `build-pack`, `cache-clear`, `explain`. Pure stdlib + NumPy. |
| `hooks/_py/keyword_extract.py` | Deterministic keyword extraction. Embedded 180-word stopwords list. No NLTK/spaCy. |
| `shared/graph/pagerank-sql.md` | Algorithm reference, weighting table, SQL recipes, troubleshooting. |
| `tests/unit/repomap_test.py` | pytest unit tests (determinism, budget, cache, slice assembly, degradation). |
| `tests/evals/pipeline/scenarios/10-repo-map-ab/scenario.yaml` | Phase 01 eval scenario: same prompt run twice (OFF / ON). |

**Modified files (7):**

| Path | Change |
|---|---|
| `shared/graph/code-graph-schema.sql` | Add `ranked_files_cache` table + `idx_nodes_last_modified` index. Bump schema to 1.1.0. |
| `agents/fg-100-orchestrator.md` | Replace directory listing + docs-index dump blocks with `{{REPO_MAP_PACK:BUDGET=8000:TOPK=25}}`. |
| `agents/fg-200-planner.md` | Replace explore-cache `file_index` dump with `{{REPO_MAP_PACK:BUDGET=10000:TOPK=25}}`. |
| `agents/fg-300-implementer.md` | Replace convention-stack listing with `{{REPO_MAP_PACK:BUDGET=4000:TOPK=25}}` per task. |
| `shared/state-schema.md` | Document `prompt_compaction` field + `baseline_source`. Bump to 1.7.0. |
| `shared/preflight-constraints.md` | Add validation: `code_graph.prompt_compaction.enabled` requires `code_graph.enabled`. |
| `CLAUDE.md` | One-line entry under Supporting systems + new row in the v2.0 features table. |
| `.github/workflows/evals.yml` | Add `compaction: [off, on]` matrix axis + composite-delta gate. |
| `docs/superpowers/specs/2026-04-19-10-repo-map-pagerank-design.md` | Fix 3 known issues (cache key copy, baseline bootstrap, bypass event taxonomy, parallel implementer note). |

**Reasoning for split:** `repomap.py` is the algorithm + assembly + cache layer; `keyword_extract.py` is isolated because it's dependency-free string work with its own stopwords table and is unit-tested in isolation. Tests live alongside (`tests/unit/repomap_test.py`) per forge pytest convention. The eval scenario is a Phase 01 artifact. Agent `.md` edits are per-file because each agent's dispatch context differs.

---

## Task 1: Scaffold `keyword_extract.py` with stopwords and tokenizer

**Files:**
- Create: `hooks/_py/keyword_extract.py`
- Test: `tests/unit/keyword_extract_test.py`

- [ ] **Step 1: Write the failing test**

```python
# tests/unit/keyword_extract_test.py
import pytest
from hooks._py.keyword_extract import extract_keywords


def test_lowercases_and_strips_punctuation():
    out = extract_keywords("Fix NullPointer in PlanService.validate()!")
    assert "nullpointer" in out
    assert "planservice" in out
    assert "validate" in out


def test_drops_stopwords_short_and_numeric():
    out = extract_keywords("the and it 42 go ok foobar")
    assert out == ["foobar"]


def test_top_20_by_frequency_ties_by_first_occurrence():
    text = "alpha beta alpha gamma beta delta " + " ".join(f"w{i}" for i in range(25))
    out = extract_keywords(text)
    assert len(out) == 20
    assert out[0] == "alpha"
    assert out[1] == "beta"


def test_deterministic():
    text = "plan service validate null pointer repository controller"
    assert extract_keywords(text) == extract_keywords(text)


def test_empty_input_returns_empty_list():
    assert extract_keywords("") == []
    assert extract_keywords("   ") == []
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python3 -m pytest tests/unit/keyword_extract_test.py -v`
Expected: `ModuleNotFoundError: No module named 'hooks._py.keyword_extract'`

- [ ] **Step 3: Implement `keyword_extract.py`**

```python
# hooks/_py/keyword_extract.py
"""Deterministic keyword extraction from requirement text.

No NLTK, spaCy, or other NLP deps. Embedded stopwords list.
"""
from __future__ import annotations

import re
from collections import OrderedDict

# Hard-coded English stopwords. ~180 words. Intentionally inline (no external file).
_STOPWORDS = frozenset("""
a about above after again against all am an and any are as at be because been before being
below between both but by could did do does doing down during each few for from further had
has have having he her here hers herself him himself his how i if in into is it its itself
just me more most my myself no nor not now of off on once only or other our ours ourselves
out over own same she should so some such than that the their theirs them themselves then
there these they this those through to too under until up very was we were what when where
which while who whom why will with you your yours yourself yourselves also can would might
may must shall should need needs needed make makes making made get gets got getting go goes
went going come comes came coming see sees saw seeing know knows knew want wants wanted
take takes took taken give gives gave given use uses used using say says said tell tells told
think thinks thought find finds found thing things way ways lot lots new old big small
""".split())

_TOKEN_RE = re.compile(r"[a-z0-9]+")


def extract_keywords(text: str, top_n: int = 20) -> list[str]:
    """Return up to `top_n` keywords by frequency, ties broken by first occurrence.

    Pipeline: lowercase -> tokenize on [a-z0-9]+ -> drop stopwords,
    len<3, and pure numerics -> keep top-N by (count desc, first-pos asc).
    """
    if not text or not text.strip():
        return []
    tokens = _TOKEN_RE.findall(text.lower())
    counts: OrderedDict[str, int] = OrderedDict()
    for t in tokens:
        if len(t) < 3:
            continue
        if t.isdigit():
            continue
        if t in _STOPWORDS:
            continue
        counts[t] = counts.get(t, 0) + 1
    # Sort by (-count, first-occurrence-index). OrderedDict preserves insertion order.
    ranked = sorted(counts.items(), key=lambda kv: (-kv[1], list(counts).index(kv[0])))
    return [k for k, _ in ranked[:top_n]]
```

- [ ] **Step 4: Run test to verify it passes**

Run: `python3 -m pytest tests/unit/keyword_extract_test.py -v`
Expected: 5 passed

- [ ] **Step 5: Commit**

```bash
git add hooks/_py/keyword_extract.py tests/unit/keyword_extract_test.py
git commit -m "feat(phase10): add deterministic keyword extractor for repo-map"
```

---

## Task 2: Implement content-derived `graph_sha` and keyword hash helpers

**Files:**
- Create: `hooks/_py/repomap.py` (partial — helpers only)
- Test: `tests/unit/repomap_test.py` (partial)

- [ ] **Step 1: Write the failing test**

```python
# tests/unit/repomap_test.py
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python3 -m pytest tests/unit/repomap_test.py -v`
Expected: `ModuleNotFoundError: No module named 'hooks._py.repomap'`

- [ ] **Step 3: Implement helpers in `repomap.py`**

```python
# hooks/_py/repomap.py
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `python3 -m pytest tests/unit/repomap_test.py -v`
Expected: 4 passed

- [ ] **Step 5: Commit**

```bash
git add hooks/_py/repomap.py tests/unit/repomap_test.py
git commit -m "feat(phase10): add content-derived graph_sha and keywords_hash"
```

---

## Task 3: Implement PageRank power iteration over SQLite graph

**Files:**
- Modify: `hooks/_py/repomap.py`
- Modify: `tests/unit/repomap_test.py`

- [ ] **Step 1: Write the failing tests**

Append to `tests/unit/repomap_test.py`:

```python
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `python3 -m pytest tests/unit/repomap_test.py -v -k pagerank`
Expected: `ImportError: cannot import name 'run_pagerank'`

- [ ] **Step 3: Implement PageRank in `repomap.py`**

Append to `hooks/_py/repomap.py`:

```python
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `python3 -m pytest tests/unit/repomap_test.py -v -k pagerank`
Expected: 4 passed

- [ ] **Step 5: Commit**

```bash
git add hooks/_py/repomap.py tests/unit/repomap_test.py
git commit -m "feat(phase10): add PageRank power iteration over code graph"
```

---

## Task 4: Aggregate symbol ranks to file-level + apply recency and keyword overlap

**Files:**
- Modify: `hooks/_py/repomap.py`
- Modify: `tests/unit/repomap_test.py`

- [ ] **Step 1: Write the failing tests**

Append to `tests/unit/repomap_test.py`:

```python
from hooks._py.repomap import score_files, RecencyConfig


def test_recency_multiplier_bounds():
    from hooks._py.repomap import recency_multiplier
    cfg = RecencyConfig(window_days=30, boost_max=1.5)
    import time
    now = int(time.time())
    day = 86400
    assert recency_multiplier(now, now, cfg) == pytest.approx(1.5)
    assert recency_multiplier(now - 15 * day, now, cfg) == pytest.approx(1.25, abs=1e-3)
    assert recency_multiplier(now - 30 * day, now, cfg) == pytest.approx(1.0, abs=1e-3)
    assert recency_multiplier(now - 90 * day, now, cfg) == pytest.approx(1.0)
    # Never below 1.0, never above boost_max.
    for delta in (-1, 0, 1, 365):
        m = recency_multiplier(now - delta * day, now, cfg)
        assert 1.0 <= m <= 1.5


def test_keyword_overlap_cap(three_node_graph, tmp_path):
    # File path and symbols contain 'plan' multiple times; cap=5 -> count never exceeds 5.
    conn = sqlite3.connect(three_node_graph)
    conn.execute(
        "UPDATE nodes SET path = 'plan_plan_plan_plan_plan_plan_plan.py' WHERE id = 1"
    )
    conn.commit()
    conn.close()
    scored = score_files(
        three_node_graph,
        keywords=["plan"],
        edge_weights=DEFAULT_EDGE_WEIGHTS,
        recency_cfg=RecencyConfig(window_days=30, boost_max=1.5),
        keyword_overlap_cap=5,
        now_ts=1713600000,
    )
    # Score(f1) = pagerank * recency * (1 + min(7, 5)) = pr * rec * 6.
    # We can't easily assert exact, but ensure cap applies: raise cap to 10, rerun,
    # score should strictly increase.
    scored_uncapped = score_files(
        three_node_graph,
        keywords=["plan"],
        edge_weights=DEFAULT_EDGE_WEIGHTS,
        recency_cfg=RecencyConfig(window_days=30, boost_max=1.5),
        keyword_overlap_cap=10,
        now_ts=1713600000,
    )
    assert scored_uncapped[1].score > scored[1].score


def test_score_files_aggregates_symbols_to_file(tmp_path):
    db = tmp_path / "cg.db"
    conn = sqlite3.connect(db)
    conn.executescript(
        """
        CREATE TABLE nodes (id INTEGER PRIMARY KEY, kind TEXT, path TEXT,
                            properties TEXT, updated_at TEXT);
        CREATE TABLE edges (id INTEGER PRIMARY KEY, src INTEGER, dst INTEGER,
                            edge_type TEXT, updated_at TEXT);
        INSERT INTO nodes VALUES
          (1,'File','hub.py','{}','t'),
          (2,'Function','hub.fn','{"file_id":1}','t'),
          (3,'File','leaf.py','{}','t');
        INSERT INTO edges VALUES
          (1,1,2,'CONTAINS','t'),
          (2,3,2,'CALLS','t');
        """
    )
    conn.commit()
    conn.close()
    scored = score_files(
        db,
        keywords=[],
        edge_weights=DEFAULT_EDGE_WEIGHTS,
        recency_cfg=RecencyConfig(window_days=30, boost_max=1.5),
        keyword_overlap_cap=5,
        now_ts=1713600000,
    )
    # hub.py rank = file-node rank + its CONTAINed function's rank.
    assert 1 in scored
    assert scored[1].path == "hub.py"
    assert scored[1].pagerank > 0
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `python3 -m pytest tests/unit/repomap_test.py -v -k "recency or overlap or aggregate"`
Expected: `ImportError: cannot import name 'score_files'`

- [ ] **Step 3: Implement scoring aggregation**

Append to `hooks/_py/repomap.py`:

```python
import json
import time as _time
from dataclasses import dataclass


@dataclass(frozen=True)
class RecencyConfig:
    window_days: int = 30
    boost_max: float = 1.5


@dataclass
class FileScore:
    node_id: int
    path: str
    pagerank: float
    recency: float
    keyword_overlap: int
    score: float
    size_bytes: int
    last_modified_ts: int


def recency_multiplier(mtime_ts: int, now_ts: int, cfg: RecencyConfig) -> float:
    """1.5 at mtime == now, linear decay to 1.0 at window boundary, then flat 1.0."""
    age_days = max(0, (now_ts - mtime_ts) / 86400.0)
    if age_days >= cfg.window_days:
        return 1.0
    slope = cfg.boost_max - 1.0
    return cfg.boost_max - slope * (age_days / cfg.window_days)


def _count_keyword_hits(text: str, keywords: list[str], cap: int) -> int:
    if not keywords or not text:
        return 0
    lo = text.lower()
    hits = sum(1 for k in keywords if k in lo)
    return min(hits, cap)


def score_files(
    db_path: Path | str,
    keywords: list[str],
    edge_weights: dict[str, float],
    recency_cfg: RecencyConfig,
    keyword_overlap_cap: int,
    now_ts: int | None = None,
) -> dict[int, FileScore]:
    """Run PageRank, aggregate symbol ranks into their parent File, apply
    recency multiplier and keyword-overlap factor. Returns {file_node_id: FileScore}.
    """
    now_ts = int(now_ts if now_ts is not None else _time.time())
    ranks = run_pagerank(db_path, edge_weights)
    if not ranks:
        return {}

    conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
    try:
        # 1. Identify File nodes + metadata.
        file_meta: dict[int, dict] = {}
        for nid, kind, path, props, updated_at in conn.execute(
            "SELECT id, kind, path, COALESCE(properties,'{}'), COALESCE(updated_at,'') FROM nodes"
        ):
            if kind != "File":
                continue
            try:
                p = json.loads(props) if props else {}
            except json.JSONDecodeError:
                p = {}
            last_mod = int(p.get("last_modified_ts") or 0) or now_ts
            size_b = int(p.get("size_bytes") or 0)
            file_meta[nid] = {
                "path": path or "",
                "size_bytes": size_b,
                "last_modified_ts": last_mod,
                "symbols_text": "",
            }
        # 2. Aggregate symbol ranks into parent File via CONTAINS edges.
        contains: dict[int, list[int]] = {fid: [fid] for fid in file_meta}
        for src, dst, etype in conn.execute(
            "SELECT src, dst, edge_type FROM edges WHERE edge_type = 'CONTAINS'"
        ):
            if src in file_meta:
                contains.setdefault(src, [src]).append(dst)
        # 3. Gather symbol-name text per file (for keyword overlap).
        sym_text: dict[int, list[str]] = {fid: [file_meta[fid]["path"]] for fid in file_meta}
        for nid, kind, path in conn.execute(
            "SELECT id, kind, path FROM nodes WHERE kind != 'File'"
        ):
            # Attribute this symbol's name to any File that contains it.
            for fid, members in contains.items():
                if nid in members:
                    sym_text[fid].append(path or "")
                    break
    finally:
        conn.close()

    result: dict[int, FileScore] = {}
    for fid, meta in file_meta.items():
        pr = sum(ranks.get(n, 0.0) for n in contains.get(fid, [fid]))
        rec = recency_multiplier(meta["last_modified_ts"], now_ts, recency_cfg)
        overlap = _count_keyword_hits(
            " ".join(sym_text.get(fid, [])), keywords, keyword_overlap_cap
        )
        score = pr * rec * (1 + overlap)
        result[fid] = FileScore(
            node_id=fid,
            path=meta["path"],
            pagerank=pr,
            recency=rec,
            keyword_overlap=overlap,
            score=score,
            size_bytes=meta["size_bytes"],
            last_modified_ts=meta["last_modified_ts"],
        )
    return result
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `python3 -m pytest tests/unit/repomap_test.py -v -k "recency or overlap or aggregate"`
Expected: 3 passed

- [ ] **Step 5: Commit**

```bash
git add hooks/_py/repomap.py tests/unit/repomap_test.py
git commit -m "feat(phase10): aggregate symbol ranks to files with recency + keyword overlap"
```

---

## Task 5: Implement pack assembly (whole file → partial slice → skip) with token budget

**Files:**
- Modify: `hooks/_py/repomap.py`
- Modify: `tests/unit/repomap_test.py`

- [ ] **Step 1: Write the failing tests**

Append to `tests/unit/repomap_test.py`:

```python
from hooks._py.repomap import assemble_pack, PackConfig, PackEntry


def _mk_score(i, size_bytes, score):
    return FileScore(
        node_id=i, path=f"src/f{i}.py", pagerank=score, recency=1.0,
        keyword_overlap=0, score=score, size_bytes=size_bytes,
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
    scored = {i: _mk_score(i, 10, 1.0 / i) for i in range(1, 100)}  # 99 tiny files
    pack = assemble_pack(
        scored,
        PackConfig(budget_tokens=100000, top_k=25, min_slice_tokens=400),
    )
    assert len(pack.entries) == 25


def test_partial_slice_when_file_too_big():
    scored = {
        1: _mk_score(1, 100, 10.0),            # small, fits whole
        2: _mk_score(2, 100000, 5.0),          # huge, must slice
    }
    pack = assemble_pack(
        scored,
        PackConfig(budget_tokens=2000, top_k=25, min_slice_tokens=400),
    )
    paths = [e.path for e in pack.entries]
    assert "src/f1.py" in paths
    # f2 either fits as slice or is skipped, but if included must be slice mode.
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `python3 -m pytest tests/unit/repomap_test.py -v -k "budget or topk or slice or sorted or summary"`
Expected: `ImportError: cannot import name 'assemble_pack'`

- [ ] **Step 3: Implement pack assembly**

Append to `hooks/_py/repomap.py`:

```python
from dataclasses import dataclass, field

_BYTES_PER_TOKEN = 3.5


@dataclass(frozen=True)
class PackConfig:
    budget_tokens: int = 8000
    top_k: int = 25
    min_slice_tokens: int = 400


@dataclass
class PackEntry:
    path: str
    mode: str                 # "full" | "slice"
    tokens: int
    score: float
    recency: float
    slice_ranges: list[tuple[int, int]] = field(default_factory=list)

    def render(self) -> str:
        recent_flag = "yes" if self.recency > 1.0 else "no"
        if self.mode == "full":
            return (
                f"{self.path:<52} [full]   rank={self.score:.4f} recent={recent_flag}"
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
            f"## Repo-map (top {len(self.entries)} of {self.total_files_in_graph} files, "
            f"budget {self.pack_tokens}/{self.budget_tokens} tokens)"
        )
        return "\n".join([header, *(e.render() for e in self.entries)])


def _estimate_tokens(size_bytes: int) -> int:
    return max(1, int(-(-size_bytes // 1) / _BYTES_PER_TOKEN))


def assemble_pack(
    scored: dict[int, FileScore],
    cfg: PackConfig,
    *,
    slice_fetcher=None,
) -> Pack:
    """Walk files in score-descending order, include whole if it fits,
    else a partial slice if >= min_slice_tokens remain, else skip.
    Always caps at cfg.top_k files.

    `slice_fetcher(node_id)` optionally returns [(start,end), ...] line ranges
    and their estimated token cost. When None, a conservative stub emits
    a single (1, min(80, size_bytes//60)) window.
    """
    total_files = len(scored)
    ordered = sorted(scored.values(), key=lambda s: s.score, reverse=True)
    entries: list[PackEntry] = []
    remaining = cfg.budget_tokens

    for s in ordered:
        if len(entries) >= cfg.top_k:
            break
        full_cost = _estimate_tokens(s.size_bytes)
        if remaining >= full_cost and full_cost > 0:
            entries.append(PackEntry(
                path=s.path, mode="full", tokens=full_cost,
                score=s.score, recency=s.recency,
            ))
            remaining -= full_cost
            continue
        if remaining >= cfg.min_slice_tokens:
            # Stub slicer: emit one window proportional to budget, capped at 80 lines.
            if slice_fetcher:
                ranges, cost = slice_fetcher(s.node_id, remaining)
            else:
                window_lines = min(80, max(10, remaining // 4))
                ranges = [(1, window_lines)]
                cost = min(remaining, cfg.min_slice_tokens)
            if cost > remaining or cost < cfg.min_slice_tokens:
                continue
            entries.append(PackEntry(
                path=s.path, mode="slice", tokens=cost,
                score=s.score, recency=s.recency, slice_ranges=ranges,
            ))
            remaining -= cost
        # else skip.

    pack_tokens = cfg.budget_tokens - remaining
    return Pack(
        entries=entries,
        total_files_in_graph=total_files,
        budget_tokens=cfg.budget_tokens,
        pack_tokens=pack_tokens,
    )
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `python3 -m pytest tests/unit/repomap_test.py -v -k "budget or topk or slice or sorted or summary"`
Expected: 5 passed

- [ ] **Step 5: Commit**

```bash
git add hooks/_py/repomap.py tests/unit/repomap_test.py
git commit -m "feat(phase10): assemble token-budgeted context pack with slice fallback"
```

---

## Task 6: Implement write-through cache with 4-tuple key + LRU eviction

**Files:**
- Modify: `hooks/_py/repomap.py`
- Modify: `tests/unit/repomap_test.py`

- [ ] **Step 1: Write the failing tests**

Append to `tests/unit/repomap_test.py`:

```python
from hooks._py.repomap import PackCache, CachedPack


def test_cache_hit_roundtrip(tmp_path):
    cache_path = tmp_path / "ranked-files-cache.json"
    cache = PackCache(cache_path, max_entries=16)
    entry = CachedPack(
        graph_sha="g" * 64, keywords_hash="k" * 64, budget=8000, top_k=25,
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
    cache.put(CachedPack(
        graph_sha="g" * 64, keywords_hash="k" * 64, budget=8000, top_k=25,
        computed_at="t", ranked=[],
    ))
    # Each differing component must miss.
    assert cache.get("x" * 64, "k" * 64, 8000, 25) is None
    assert cache.get("g" * 64, "y" * 64, 8000, 25) is None
    assert cache.get("g" * 64, "k" * 64, 4000, 25) is None
    assert cache.get("g" * 64, "k" * 64, 8000, 12) is None


def test_cache_lru_eviction_keeps_max_entries(tmp_path):
    cache = PackCache(tmp_path / "c.json", max_entries=3)
    for i in range(5):
        cache.put(CachedPack(
            graph_sha=str(i) * 64, keywords_hash="k" * 64,
            budget=8000, top_k=25, computed_at="t", ranked=[],
        ))
    cache.flush()
    # Only the 3 most recent remain.
    assert cache.get("0" * 64, "k" * 64, 8000, 25) is None
    assert cache.get("1" * 64, "k" * 64, 8000, 25) is None
    assert cache.get("4" * 64, "k" * 64, 8000, 25) is not None


def test_cache_corrupt_returns_empty_and_logs(tmp_path, caplog):
    p = tmp_path / "c.json"
    p.write_text("{{{ not json")
    cache = PackCache(p, max_entries=16)
    assert cache.get("g" * 64, "k" * 64, 8000, 25) is None
    # Should not raise; caller interprets miss as `repomap.bypass.corrupt_cache`.
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `python3 -m pytest tests/unit/repomap_test.py -v -k cache`
Expected: `ImportError: cannot import name 'PackCache'`

- [ ] **Step 3: Implement the cache**

Append to `hooks/_py/repomap.py`:

```python
from collections import OrderedDict
from dataclasses import asdict, dataclass, field

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
    baseline_source: str = "estimated"   # "estimated" | "measured"


class PackCache:
    """Write-through JSON cache, keyed on 4-tuple `(graph_sha, keywords_hash,
    budget, top_k)`. LRU eviction at `max_entries`. Corrupt JSON -> empty cache,
    caller emits `repomap.bypass.corrupt_cache`.
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
            if data.get("schema_version") != CACHE_SCHEMA_VERSION:
                return
            for raw in data.get("entries", []):
                cp = CachedPack(**raw)
                self._entries[self._key(
                    cp.graph_sha, cp.keywords_hash, cp.budget, cp.top_k
                )] = cp
        except (json.JSONDecodeError, TypeError, KeyError, ValueError):
            self._entries.clear()

    def get(self, graph_sha, keywords_hash, budget, top_k) -> CachedPack | None:
        k = self._key(graph_sha, keywords_hash, budget, top_k)
        if k not in self._entries:
            return None
        self._entries.move_to_end(k)
        return self._entries[k]

    def put(self, entry: CachedPack) -> None:
        k = self._key(entry.graph_sha, entry.keywords_hash, entry.budget, entry.top_k)
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
        tmp = self.path.with_suffix(".json.tmp")
        tmp.write_text(json.dumps(payload, indent=2))
        tmp.replace(self.path)

    def clear(self) -> None:
        self._entries.clear()
        if self.path.exists():
            self.path.unlink()
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `python3 -m pytest tests/unit/repomap_test.py -v -k cache`
Expected: 4 passed

- [ ] **Step 5: Commit**

```bash
git add hooks/_py/repomap.py tests/unit/repomap_test.py
git commit -m "feat(phase10): write-through pack cache with 4-tuple key + LRU"
```

---

## Task 7: Wire CLI subcommands + sparse-graph bypass + named failure events

**Files:**
- Modify: `hooks/_py/repomap.py`
- Modify: `tests/unit/repomap_test.py`

- [ ] **Step 1: Write the failing tests**

Append to `tests/unit/repomap_test.py`:

```python
import subprocess
import sys


def _run_cli(*args, cwd=None):
    return subprocess.run(
        [sys.executable, "-m", "hooks._py.repomap", *args],
        cwd=cwd, capture_output=True, text=True, check=False,
    )


def test_sparse_graph_bypass(tmp_path, three_node_graph):
    # 3 nodes < min_nodes_for_rank (50) -> bypass emits full listing.
    keywords = tmp_path / "k.txt"
    keywords.write_text("plan service")
    cache_dir = tmp_path / ".forge"
    cache_dir.mkdir()
    res = _run_cli(
        "build-pack",
        "--db", str(three_node_graph),
        "--keywords-file", str(keywords),
        "--cache", str(cache_dir / "ranked-files-cache.json"),
        "--budget", "8000", "--top-k", "25",
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
        "--budget", "8000", "--top-k", "25",
    )
    # Exit code 0 (graceful); stderr names the bypass event.
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
    # explain prints per-node breakdown even for sparse graphs.
    assert res.returncode == 0
    assert "pagerank" in res.stdout.lower() or "rank" in res.stdout.lower()


def test_cache_clear_subcommand(tmp_path):
    cache = tmp_path / "c.json"
    cache.write_text('{"schema_version":"1.0.0","entries":[]}')
    res = _run_cli("cache-clear", "--cache", str(cache))
    assert res.returncode == 0
    assert not cache.exists()
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `python3 -m pytest tests/unit/repomap_test.py -v -k "cli or bypass or degrades or explain or cache_clear"`
Expected: multiple failures, CLI not yet wired.

- [ ] **Step 3: Implement the CLI entry**

Append to `hooks/_py/repomap.py`:

```python
import argparse
import sys as _sys


def _log_bypass(event: str) -> None:
    print(event, file=_sys.stderr)


def _degraded_pack(db_path: Path, budget: int, top_k: int) -> Pack:
    """Fallback when PageRank can't run: return an empty pack with header only.
    Upstream callers that need a full listing inject it separately; the pack
    is only empty so the model sees a harmless placeholder."""
    return Pack(entries=[], total_files_in_graph=0,
                budget_tokens=budget, pack_tokens=0)


def _estimate_baseline_tokens(db_path: Path) -> int:
    """Analytical baseline (spec-review Issue #2 resolution, option a):
    sum of size_bytes over all File nodes, divided by 3.5 bytes/token.
    """
    if not Path(db_path).exists():
        return 0
    try:
        conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
        total = 0
        for (props,) in conn.execute(
            "SELECT COALESCE(properties,'{}') FROM nodes WHERE kind='File'"
        ):
            try:
                total += int((json.loads(props) or {}).get("size_bytes") or 0)
            except json.JSONDecodeError:
                pass
        conn.close()
        return int(total / _BYTES_PER_TOKEN)
    except sqlite3.DatabaseError:
        return 0


def _cmd_build_pack(args) -> int:
    db = Path(args.db)
    cache = PackCache(args.cache, max_entries=args.cache_max_entries)
    keywords: list[str] = []
    if args.keywords_file and Path(args.keywords_file).exists():
        from hooks._py.keyword_extract import extract_keywords
        keywords = extract_keywords(Path(args.keywords_file).read_text())

    if not db.exists():
        _log_bypass("repomap.bypass.missing_graph")
        pack = _degraded_pack(db, args.budget, args.top_k)
        print(pack.render())
        return 0

    try:
        graph_sha = compute_graph_sha(db)
    except sqlite3.DatabaseError:
        _log_bypass("repomap.bypass.missing_graph")
        print(_degraded_pack(db, args.budget, args.top_k).render())
        return 0

    kh = compute_keywords_hash(keywords)
    cached = cache.get(graph_sha, kh, args.budget, args.top_k)
    if cached is not None:
        # Rehydrate Pack from cached entries without recomputing.
        entries = [PackEntry(
            path=r["file"], mode=r.get("mode", "full"),
            tokens=int(r.get("tokens", 0)), score=float(r.get("score", 0.0)),
            recency=float(r.get("recency", 1.0)),
            slice_ranges=[tuple(x) for x in r.get("slice_ranges", [])],
        ) for r in cached.ranked]
        pack_tokens = sum(e.tokens for e in entries)
        pack = Pack(entries=entries,
                    total_files_in_graph=len(cached.ranked),
                    budget_tokens=args.budget, pack_tokens=pack_tokens)
        print(pack.render())
        return 0

    # Sparse-graph bypass.
    conn = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
    (node_count,) = conn.execute("SELECT COUNT(*) FROM nodes").fetchone()
    conn.close()
    if node_count < args.min_nodes_for_rank:
        _log_bypass("repomap.bypass.sparse_graph")
        print(_degraded_pack(db, args.budget, args.top_k).render())
        return 0

    try:
        scored = score_files(
            db, keywords, DEFAULT_EDGE_WEIGHTS,
            RecencyConfig(window_days=args.recency_window_days,
                          boost_max=args.recency_boost_max),
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
        PackConfig(budget_tokens=args.budget, top_k=args.top_k,
                   min_slice_tokens=args.min_slice_tokens),
    )
    # Write cache.
    baseline = _estimate_baseline_tokens(db)
    cache.put(CachedPack(
        graph_sha=graph_sha, keywords_hash=kh,
        budget=args.budget, top_k=args.top_k,
        computed_at=_time.strftime("%Y-%m-%dT%H:%M:%SZ", _time.gmtime()),
        ranked=[{
            "file": e.path, "score": e.score, "recency": e.recency,
            "mode": e.mode, "tokens": e.tokens,
            "slice_ranges": e.slice_ranges,
        } for e in pack.entries],
        baseline_tokens_estimate=baseline,
        baseline_source="estimated",
    ))
    cache.flush()
    print(pack.render())
    return 0


def _cmd_pagerank(args) -> int:
    ranks = run_pagerank(args.db, DEFAULT_EDGE_WEIGHTS)
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
    keywords: list[str] = []
    if args.keywords_file and Path(args.keywords_file).exists():
        from hooks._py.keyword_extract import extract_keywords
        keywords = extract_keywords(Path(args.keywords_file).read_text())
    scored = score_files(
        db, keywords, DEFAULT_EDGE_WEIGHTS,
        RecencyConfig(), keyword_overlap_cap=5,
    )
    print(f"{'path':<60}\tpagerank\trecency\toverlap\tscore")
    for s in sorted(scored.values(), key=lambda x: -x.score)[:50]:
        print(f"{s.path:<60}\t{s.pagerank:.4f}\t{s.recency:.2f}"
              f"\t{s.keyword_overlap}\t{s.score:.4f}")
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `python3 -m pytest tests/unit/repomap_test.py -v`
Expected: all tests pass (including earlier tasks). ~20 tests green.

- [ ] **Step 5: Commit**

```bash
git add hooks/_py/repomap.py tests/unit/repomap_test.py
git commit -m "feat(phase10): wire repomap CLI with sparse/missing/diverged bypass events"
```

---

## Task 8: Add graph-schema additions (cache table + index) and bump schema version

**Files:**
- Modify: `shared/graph/code-graph-schema.sql`
- Create: `tests/contract/repomap_schema.bats`

- [ ] **Step 1: Write the failing contract test**

```bash
# tests/contract/repomap_schema.bats
#!/usr/bin/env bats

load "${BATS_TEST_DIRNAME}/../lib/bats-support/load"
load "${BATS_TEST_DIRNAME}/../lib/bats-assert/load"

@test "code-graph-schema.sql declares ranked_files_cache with 4-col PK" {
  grep -q "CREATE TABLE.*ranked_files_cache" "${BATS_TEST_DIRNAME}/../../shared/graph/code-graph-schema.sql"
  grep -q "PRIMARY KEY *( *graph_sha *, *keywords_hash *, *budget *, *top_k *)" \
    "${BATS_TEST_DIRNAME}/../../shared/graph/code-graph-schema.sql"
}

@test "code-graph-schema.sql declares idx_nodes_last_modified" {
  grep -q "CREATE INDEX.*idx_nodes_last_modified" \
    "${BATS_TEST_DIRNAME}/../../shared/graph/code-graph-schema.sql"
}

@test "code-graph-schema.sql version bumped to 1.1.0" {
  grep -q "schema_version.*1\.1\.0" \
    "${BATS_TEST_DIRNAME}/../../shared/graph/code-graph-schema.sql"
}

@test "schema applies cleanly in a fresh sqlite DB" {
  local tmpdb="$(mktemp -u).db"
  sqlite3 "$tmpdb" < "${BATS_TEST_DIRNAME}/../../shared/graph/code-graph-schema.sql"
  run sqlite3 "$tmpdb" ".schema ranked_files_cache"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ranked_files_cache"* ]]
  rm -f "$tmpdb"
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./tests/lib/bats-core/bin/bats tests/contract/repomap_schema.bats`
Expected: 4 failures (table/index/version not yet declared).

- [ ] **Step 3: Append to `shared/graph/code-graph-schema.sql`**

```sql
-- === Phase 10: Repo-Map PageRank Cache (schema 1.1.0) ===
-- Durable mirror of .forge/ranked-files-cache.json. 4-tuple PK matches the
-- JSON cache key. The JSON file is primary; this table is an optional audit
-- mirror populated by repomap.py when PACK_CACHE_DB_MIRROR=1.
CREATE TABLE IF NOT EXISTS ranked_files_cache (
    graph_sha TEXT NOT NULL,
    keywords_hash TEXT NOT NULL,
    budget INTEGER NOT NULL,
    top_k INTEGER NOT NULL,
    ranked_json TEXT NOT NULL,
    computed_at TEXT NOT NULL,
    PRIMARY KEY (graph_sha, keywords_hash, budget, top_k)
);

-- Index powers the recency_multiplier lookup in score_files().
CREATE INDEX IF NOT EXISTS idx_nodes_last_modified
    ON nodes (json_extract(properties, '$.last_modified_ts'));

-- Bump schema version row.
INSERT OR REPLACE INTO schema_metadata(key, value)
VALUES ('schema_version', '1.1.0');
```

- [ ] **Step 4: Run contract tests to verify they pass**

Run: `./tests/lib/bats-core/bin/bats tests/contract/repomap_schema.bats`
Expected: 4 passed.

- [ ] **Step 5: Commit**

```bash
git add shared/graph/code-graph-schema.sql tests/contract/repomap_schema.bats
git commit -m "feat(phase10): add ranked_files_cache table + mtime index (schema 1.1.0)"
```

---

## Task 9: Add `code_graph.prompt_compaction` config block + PREFLIGHT validation

**Files:**
- Modify: `shared/preflight-constraints.md`
- Create: `tests/contract/prompt_compaction_config.bats`
- Modify: `modules/frameworks/*/forge-config-template.md` (defaults section only — add the new block under `code_graph:`)

- [ ] **Step 1: Write the failing test**

```bash
# tests/contract/prompt_compaction_config.bats
#!/usr/bin/env bats

@test "preflight-constraints documents prompt_compaction dependency" {
  grep -q "code_graph.prompt_compaction.enabled" \
    "${BATS_TEST_DIRNAME}/../../shared/preflight-constraints.md"
  grep -q "requires.*code_graph.enabled" \
    "${BATS_TEST_DIRNAME}/../../shared/preflight-constraints.md"
}

@test "at least one framework template declares the new block" {
  local found=0
  for f in "${BATS_TEST_DIRNAME}/../../modules/frameworks/"*"/forge-config-template.md"; do
    if grep -q "prompt_compaction:" "$f"; then
      found=1
      break
    fi
  done
  [ "$found" -eq 1 ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./tests/lib/bats-core/bin/bats tests/contract/prompt_compaction_config.bats`
Expected: 2 failures.

- [ ] **Step 3: Add validation to `shared/preflight-constraints.md`**

Append the section:

```markdown
## Repo-map prompt compaction (Phase 10)

**Rule:** If `code_graph.prompt_compaction.enabled: true`, then `code_graph.enabled: true` MUST also hold.

**Rationale:** The repo-map ranker reads `.forge/code-graph.db`; disabling the graph while enabling compaction yields permanent degraded packs and hides graph-build misconfiguration.

**PREFLIGHT action when violated:** Emit CRITICAL `CONFIG-PROMPT-COMPACTION-REQUIRES-GRAPH`, halt with message:

> "code_graph.prompt_compaction.enabled is true but code_graph.enabled is false. Enable the graph or set prompt_compaction.enabled: false."

**Defaults snapshot (Phase 10 landing):**

- `prompt_compaction.enabled: false` (opt-in)
- `top_k: 25`
- `token_budget: 8000`
- `recency_window_days: 30`
- `min_slice_tokens: 400`
- `recency_boost_max: 1.5`
- `keyword_overlap_cap: 5`
- `cache_max_entries: 16`
- `min_nodes_for_rank: 50`
- `edge_weights: {CALLS:1.0, REFERENCES:1.0, IMPORTS:0.7, INHERITS:0.8, IMPLEMENTS:0.8, TESTS:0.4, CONTAINS:0.3}`
```

- [ ] **Step 4: Add config block to one framework template**

Modify `modules/frameworks/spring/forge-config-template.md` (or first alphabetically present) under the `code_graph:` section:

```yaml
code_graph:
  enabled: true
  backend: auto
  prompt_compaction:
    enabled: false              # Phase 10: opt-in; flips to true after 20-run gate
    top_k: 25
    token_budget: 8000
    recency_window_days: 30
    min_slice_tokens: 400
    recency_boost_max: 1.5
    keyword_overlap_cap: 5
    cache_max_entries: 16
    min_nodes_for_rank: 50
    edge_weights:
      CALLS: 1.0
      REFERENCES: 1.0
      IMPORTS: 0.7
      INHERITS: 0.8
      IMPLEMENTS: 0.8
      TESTS: 0.4
      CONTAINS: 0.3
```

- [ ] **Step 5: Run contract tests to verify they pass**

Run: `./tests/lib/bats-core/bin/bats tests/contract/prompt_compaction_config.bats`
Expected: 2 passed.

- [ ] **Step 6: Commit**

```bash
git add shared/preflight-constraints.md modules/frameworks/spring/forge-config-template.md \
        tests/contract/prompt_compaction_config.bats
git commit -m "feat(phase10): add prompt_compaction config block + PREFLIGHT validation"
```

---

## Task 10: Integrate `{{REPO_MAP_PACK}}` placeholder in orchestrator, planner, implementer

**Files:**
- Modify: `agents/fg-100-orchestrator.md`
- Modify: `agents/fg-200-planner.md`
- Modify: `agents/fg-300-implementer.md`
- Create: `tests/contract/repomap_placeholder.bats`

- [ ] **Step 1: Write the failing contract test**

```bash
# tests/contract/repomap_placeholder.bats
#!/usr/bin/env bats

@test "fg-100-orchestrator references {{REPO_MAP_PACK}} with BUDGET=8000" {
  grep -q "{{REPO_MAP_PACK:BUDGET=8000" \
    "${BATS_TEST_DIRNAME}/../../agents/fg-100-orchestrator.md"
}

@test "fg-200-planner references {{REPO_MAP_PACK}} with BUDGET=10000" {
  grep -q "{{REPO_MAP_PACK:BUDGET=10000" \
    "${BATS_TEST_DIRNAME}/../../agents/fg-200-planner.md"
}

@test "fg-300-implementer references {{REPO_MAP_PACK}} with BUDGET=4000 per task" {
  grep -q "{{REPO_MAP_PACK:BUDGET=4000" \
    "${BATS_TEST_DIRNAME}/../../agents/fg-300-implementer.md"
}

@test "each integrated agent mentions prompt_compaction.enabled gate" {
  for a in fg-100-orchestrator fg-200-planner fg-300-implementer; do
    grep -q "prompt_compaction" \
      "${BATS_TEST_DIRNAME}/../../agents/${a}.md"
  done
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `./tests/lib/bats-core/bin/bats tests/contract/repomap_placeholder.bats`
Expected: 4 failures.

- [ ] **Step 3: Edit `agents/fg-100-orchestrator.md`**

Locate the section that currently does a full-directory listing / docs-index dump for subagent dispatch. Replace the block with:

```markdown
### Repo-map pack (Phase 10, opt-in)

If `code_graph.prompt_compaction.enabled: true`, the orchestrator emits the
placeholder `{{REPO_MAP_PACK:BUDGET=8000:TOPK=25}}` wherever it previously
pasted a full directory listing or PREFLIGHT docs-index dump. The pre-dispatch
hook resolves the placeholder by invoking:

    python3 ${CLAUDE_PLUGIN_ROOT}/hooks/_py/repomap.py build-pack \
      --db .forge/code-graph.db \
      --cache .forge/ranked-files-cache.json \
      --keywords-file .forge/current-keywords.txt \
      --budget 8000 --top-k 25

and substituting stdout into the template. If the hook exits non-zero or emits
`repomap.bypass.*` on stderr, the orchestrator logs INFO and falls back to the
prior full listing (graceful degradation).

When `prompt_compaction.enabled: false`, the placeholder is ignored and the
orchestrator retains its current full-listing behavior.
```

- [ ] **Step 4: Edit `agents/fg-200-planner.md`**

In the EXPLORE-entry context block where `file_index` from explore-cache is currently dumped, add:

```markdown
### Repo-map pack (Phase 10, opt-in)

When `code_graph.prompt_compaction.enabled: true`, replace the explore-cache
`file_index` dump with `{{REPO_MAP_PACK:BUDGET=10000:TOPK=25}}` — a larger
budget than the orchestrator because the planner needs broader architectural
visibility. Resolution is identical to fg-100; see the orchestrator's
repo-map pack section. The explore cache itself is still written and read;
only the prompt-blob is compacted.
```

- [ ] **Step 5: Edit `agents/fg-300-implementer.md`**

Where the convention-stack listing + touched-files list currently live, add:

```markdown
### Repo-map pack (Phase 10, opt-in — per-task)

When `code_graph.prompt_compaction.enabled: true`, each task dispatch embeds
its own `{{REPO_MAP_PACK:BUDGET=4000:TOPK=25}}`. Per-task (not shared) packs
are emitted because ranking relevance collapses when a single pack must serve
disjoint task contexts in parallel dispatch; the per-task cost is the right
trade for quality (see spec §4.4, review Issue #5).

Resolution invokes:

    python3 ${CLAUDE_PLUGIN_ROOT}/hooks/_py/repomap.py build-pack \
      --budget 4000 --top-k 25

Keywords are taken from the task description (`.forge/current-task-keywords.txt`
rather than the run-level keywords file). If the file is missing, falls back
to run-level keywords.
```

- [ ] **Step 6: Run contract tests to verify they pass**

Run: `./tests/lib/bats-core/bin/bats tests/contract/repomap_placeholder.bats`
Expected: 4 passed.

- [ ] **Step 7: Commit**

```bash
git add agents/fg-100-orchestrator.md agents/fg-200-planner.md agents/fg-300-implementer.md \
        tests/contract/repomap_placeholder.bats
git commit -m "feat(phase10): add {{REPO_MAP_PACK}} placeholder to three context-hungry agents"
```

---

## Task 11: State schema bump (1.7.0) with `prompt_compaction` field + `baseline_source`

**Files:**
- Modify: `shared/state-schema.md`
- Create: `tests/contract/state_schema_prompt_compaction.bats`

- [ ] **Step 1: Write the failing test**

```bash
# tests/contract/state_schema_prompt_compaction.bats
#!/usr/bin/env bats

@test "state-schema.md bumped to 1.7.0" {
  grep -q "v1\.7\.0\|version.*1\.7\.0\|1\.7\.0" \
    "${BATS_TEST_DIRNAME}/../../shared/state-schema.md"
}

@test "state-schema.md documents prompt_compaction.stages.*.ratio" {
  grep -q "prompt_compaction" "${BATS_TEST_DIRNAME}/../../shared/state-schema.md"
  grep -q "pack_tokens" "${BATS_TEST_DIRNAME}/../../shared/state-schema.md"
  grep -q "baseline_source" "${BATS_TEST_DIRNAME}/../../shared/state-schema.md"
  grep -q "overall_ratio" "${BATS_TEST_DIRNAME}/../../shared/state-schema.md"
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./tests/lib/bats-core/bin/bats tests/contract/state_schema_prompt_compaction.bats`
Expected: 2 failures (or mismatches).

- [ ] **Step 3: Append to `shared/state-schema.md`**

```markdown
## v1.7.0 — prompt_compaction (Phase 10)

Added: top-level `prompt_compaction` object written by the orchestrator when
`code_graph.prompt_compaction.enabled: true`. Purely observational; absence
implies the feature is off.

```json
{
  "prompt_compaction": {
    "enabled": true,
    "stages": {
      "orchestrator_preflight": {"budget": 8000, "pack_tokens": 6420, "files": 25, "ratio": 0.38},
      "planner_explore":        {"budget": 10000, "pack_tokens": 8930, "files": 25, "ratio": 0.42},
      "implementer_task_3":     {"budget": 4000, "pack_tokens": 3210, "files": 12, "ratio": 0.51}
    },
    "baseline_tokens_estimate": 22500,
    "baseline_source": "estimated",
    "compacted_tokens_total": 18560,
    "overall_ratio": 0.18,
    "bypass_events": {
      "sparse_graph": 0,
      "missing_graph": 0,
      "solve_diverged": 0,
      "corrupt_cache": 0
    }
  }
}
```

**Field semantics:**

- `ratio` per stage = `(baseline_tokens_estimate_for_stage - pack_tokens) / baseline_tokens_estimate_for_stage`.
- `baseline_source`:
  - `"estimated"` — computed analytically from `sum(size_bytes)/3.5` (default, always available; spec-review Issue #2 resolution).
  - `"measured"` — sourced from `.forge/run-history.db` averages once the run count ≥ 5.
- `overall_ratio` = `(baseline_tokens_estimate - compacted_tokens_total) / baseline_tokens_estimate`; 0 if baseline is 0.
- `bypass_events` counts per run; SC-4's `repomap.bypass.failure` = sum of `missing_graph + solve_diverged + corrupt_cache` (excludes the legitimate `sparse_graph` path).
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `./tests/lib/bats-core/bin/bats tests/contract/state_schema_prompt_compaction.bats`
Expected: 2 passed.

- [ ] **Step 5: Commit**

```bash
git add shared/state-schema.md tests/contract/state_schema_prompt_compaction.bats
git commit -m "feat(phase10): add prompt_compaction block to state schema (v1.7.0)"
```

---

## Task 12: Write algorithm reference doc `shared/graph/pagerank-sql.md`

**Files:**
- Create: `shared/graph/pagerank-sql.md`
- Create: `tests/contract/pagerank_doc.bats`

- [ ] **Step 1: Write the failing test**

```bash
# tests/contract/pagerank_doc.bats
#!/usr/bin/env bats

@test "pagerank-sql.md exists with algorithm description" {
  local f="${BATS_TEST_DIRNAME}/../../shared/graph/pagerank-sql.md"
  [ -f "$f" ]
  grep -q "damping" "$f"
  grep -q "0\.85" "$f"
  grep -q "recency_multiplier" "$f"
  grep -q "keyword_overlap" "$f"
}

@test "pagerank-sql.md lists all 7 edge-type weights" {
  local f="${BATS_TEST_DIRNAME}/../../shared/graph/pagerank-sql.md"
  for w in CALLS REFERENCES IMPORTS INHERITS IMPLEMENTS TESTS CONTAINS; do
    grep -q "$w" "$f"
  done
}

@test "pagerank-sql.md documents bypass event taxonomy" {
  local f="${BATS_TEST_DIRNAME}/../../shared/graph/pagerank-sql.md"
  grep -q "sparse_graph" "$f"
  grep -q "missing_graph" "$f"
  grep -q "solve_diverged" "$f"
  grep -q "corrupt_cache" "$f"
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./tests/lib/bats-core/bin/bats tests/contract/pagerank_doc.bats`
Expected: 3 failures.

- [ ] **Step 3: Write `shared/graph/pagerank-sql.md`**

```markdown
# Repo-Map PageRank — Algorithm Reference

Authoritative reference for `hooks/_py/repomap.py`. Normative spec:
`docs/superpowers/specs/2026-04-19-10-repo-map-pagerank-design.md`.

## 1. Algorithm

Power-iteration PageRank on the SQLite code graph.

    PR(v) = (1 - d) / N  +  d × Σ_{u ∈ in(v)} [ w(u,v) / out_weight(u) ] × PR(u)

- **Damping** `d = 0.85` (Brin & Page 1998; Aider production default).
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `./tests/lib/bats-core/bin/bats tests/contract/pagerank_doc.bats`
Expected: 3 passed.

- [ ] **Step 5: Commit**

```bash
git add shared/graph/pagerank-sql.md tests/contract/pagerank_doc.bats
git commit -m "docs(phase10): add PageRank algorithm + bypass taxonomy reference"
```

---

## Task 13: Fix the three known minor issues in the spec

**Files:**
- Modify: `docs/superpowers/specs/2026-04-19-10-repo-map-pagerank-design.md`

- [ ] **Step 1: Spec edit — Issue #1 (cache key copy) in §3**

Change the in-scope bullet from:

> Write-through cache `.forge/ranked-files-cache.json` keyed on `(graph_sha, keywords_hash)` so the PageRank solve runs at most once per pipeline run per query.

to:

> Write-through cache `.forge/ranked-files-cache.json` keyed on `(graph_sha, keywords_hash, budget, top_k)` — the 4-tuple matches the durable mirror table in §5.2 and prevents cache collisions across per-agent budgets (orchestrator 8 000 vs implementer 4 000). The PageRank solve runs at most once per pipeline run per query per budget.

- [ ] **Step 2: Spec edit — Issue #2 (baseline bootstrap) in §6.2**

Replace the sentence beginning `` `baseline_tokens_estimate` is computed on the *first* run by temporarily disabling compaction for a dry pass `` with:

> `baseline_tokens_estimate` is computed **analytically** as `sum(size_bytes for every File node) / 3.5` each time the pack is rendered. This is deterministic, requires no extra pipeline run, and makes `ratio` defined from the first compacted run. State-level field `baseline_source` records the origin:
>
> - `"estimated"` — analytical formula above (the default, always available).
> - `"measured"` — averaged from `.forge/run-history.db` once `run_count ≥ 5` for the project.
>
> The earlier "dry pass" option is removed.

- [ ] **Step 3: Spec edit — Issue #3 (graph SHA thrash) in §10 Risk #4**

Replace the mitigation clause with:

> *Mitigation:* `graph_sha` is **not** `sha256(file(code-graph.db))` (which would change on every SQLite write even for no-op updates). Instead, it is a content-derived SHA-256 over `id || '|' || updated_at` for all rows in `nodes` followed by all rows in `edges`, ordered by `id`. This is stable under no-op or metadata-only writes and invalidates the cache only when row contents actually change. Incremental graph updates that touch a single file re-SHA that file's rows but leave the other 999 files' contributions unchanged — so cross-cache-entry invalidation is eliminated except where the user's dispatch keywords intersect the updated rows.

- [ ] **Step 4: Spec edit — Issue #4 (bypass event taxonomy) in §5.3**

Replace the failure-branch paragraph ("On any failure … never block the pipeline") with:

> On any failure, the pre-dispatch hook logs INFO to stderr using one of the following named bypass events, emits a degraded pack (empty entries; upstream caller supplies the prior full listing), and the pipeline proceeds:
>
> - `repomap.bypass.missing_graph` — `code-graph.db` absent, unreadable, or malformed.
> - `repomap.bypass.solve_diverged` — power iteration did not converge in 100 iters.
> - `repomap.bypass.corrupt_cache` — `.forge/ranked-files-cache.json` invalid.
> - `repomap.bypass.sparse_graph` — `node_count < min_nodes_for_rank` (expected; tracked separately).
>
> SC-4's `repomap.bypass.failure` aggregates `{missing_graph, solve_diverged, corrupt_cache}`. `sparse_graph` is excluded (it is a legitimate pre-populated-graph state, not a fault).

- [ ] **Step 5: Spec edit — Issue #5 (parallel implementer) add paragraph to §4.4**

After the table in §4.4, add:

> **Parallel implementer dispatch:** Each implementer task receives its **own** pack (per-task, not shared across parallel tasks at the same IMPLEMENT stage). Per-task packs are chosen because a shared pack must serve disjoint task contexts — its ranking relevance collapses in the common case where parallel tasks touch unrelated subsystems. The total-token cost of N parallel tasks is therefore `N × 4 000` pack tokens rather than `4 000` shared; SC-1's ≥30 % reduction target is framed against this per-task cost in runs where `implementer.parallel_tasks > 1`.

- [ ] **Step 6: Commit**

```bash
git add docs/superpowers/specs/2026-04-19-10-repo-map-pagerank-design.md
git commit -m "docs(phase10): fix 3 minor spec issues (cache key, baseline, bypass, parallel)"
```

---

## Task 14: Phase 01 eval scenario `10-repo-map-ab` + CI matrix gate

**Files:**
- Create: `tests/evals/pipeline/scenarios/10-repo-map-ab/scenario.yaml`
- Create: `tests/evals/pipeline/scenarios/10-repo-map-ab/README.md`
- Modify: `.github/workflows/evals.yml`
- Create: `tests/contract/evals_matrix_compaction.bats`

- [ ] **Step 1: Write the failing contract test**

```bash
# tests/contract/evals_matrix_compaction.bats
#!/usr/bin/env bats

@test "10-repo-map-ab scenario file exists" {
  [ -f "${BATS_TEST_DIRNAME}/../../tests/evals/pipeline/scenarios/10-repo-map-ab/scenario.yaml" ]
}

@test "evals.yml has compaction matrix axis" {
  grep -q "compaction:" \
    "${BATS_TEST_DIRNAME}/../../.github/workflows/evals.yml"
  grep -q "\\[ *off *, *on *\\]" \
    "${BATS_TEST_DIRNAME}/../../.github/workflows/evals.yml"
}

@test "evals.yml gates composite delta at 2.0" {
  grep -qE "(composite.*2\.0|2\.0.*composite|COMPACTION_COMPOSITE_MAX_DELTA)" \
    "${BATS_TEST_DIRNAME}/../../.github/workflows/evals.yml"
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./tests/lib/bats-core/bin/bats tests/contract/evals_matrix_compaction.bats`
Expected: 3 failures (scenario + workflow changes absent).

- [ ] **Step 3: Create the eval scenario**

Write `tests/evals/pipeline/scenarios/10-repo-map-ab/scenario.yaml`:

```yaml
id: 10-repo-map-ab
name: Repo-map compaction A/B
description: |
  Runs the same frozen pipeline request twice — once with prompt_compaction
  disabled, once enabled — and records composite score, orchestrator/planner
  token totals, and elapsed time for delta comparison.

fixture_repo: tests/evals/pipeline/fixtures/medium-kotlin
requirement: "Add a `/health` endpoint to the PlanController that returns 200 OK."

variants:
  - name: compaction_off
    config_overrides:
      code_graph.prompt_compaction.enabled: false
  - name: compaction_on
    config_overrides:
      code_graph.prompt_compaction.enabled: true

assertions:
  # SC-1 — ≥30 % token reduction on orchestrator + planner combined
  - metric: tokens_orchestrator_planner_delta_ratio
    min: 0.30
  # SC-2 — composite drop ≤ 2.0 points
  - metric: composite_score_delta
    min: -2.0
  # SC-3 — elapsed delta ≤ +5 %
  - metric: elapsed_delta_ratio
    max: 0.05
  # SC-4 — zero failure-class bypass events
  - metric: repomap_bypass_failure_count
    max: 0

timeout_seconds: 1200
```

- [ ] **Step 4: Write scenario README**

`tests/evals/pipeline/scenarios/10-repo-map-ab/README.md`:

```markdown
# Scenario: 10-repo-map-ab

Phase 10 A/B evaluation of repo-map PageRank prompt compaction.

Runs each frozen scenario twice on the same commit (via the `compaction:[off,on]`
CI matrix) and records the deltas used by the SC-1..SC-4 success criteria.

This scenario is the CI graduation gate for Phase 10 rollout stage 3 → 4:
20 aggregated passes on `master` flip `plugin.json` default to `enabled: true`.
```

- [ ] **Step 5: Modify `.github/workflows/evals.yml`**

Add to the matrix section of the eval job:

```yaml
strategy:
  fail-fast: false
  matrix:
    os: [ubuntu-latest, macos-latest, windows-latest]
    compaction: [off, on]

env:
  COMPACTION_COMPOSITE_MAX_DELTA: "2.0"
  FORGE_COMPACTION: ${{ matrix.compaction }}

steps:
  - uses: actions/checkout@v4
  - name: Install Python deps (Phase 02)
    run: |
      python3 -m pip install -r hooks/_py/requirements.txt
  - name: Run evals with compaction ${{ matrix.compaction }}
    run: |
      export CODE_GRAPH_PROMPT_COMPACTION_ENABLED=${{ matrix.compaction == 'on' && 'true' || 'false' }}
      python3 tests/evals/pipeline/run_evals.py --scenario 10-repo-map-ab \
        --out .forge/eval-results-${{ matrix.compaction }}.json
  - name: Compare A/B results (gate composite delta ≤ 2.0)
    if: matrix.compaction == 'on'
    run: |
      python3 tests/evals/pipeline/gate_composite_delta.py \
        --off .forge/eval-results-off.json \
        --on  .forge/eval-results-on.json \
        --max-delta "$COMPACTION_COMPOSITE_MAX_DELTA"
```

Note for the executing engineer: `run_evals.py` and `gate_composite_delta.py` are Phase 01 harness scripts; if they do not yet exist in your branch, create stubs that read scenario YAML, invoke `/forge-run --from=preflight`, capture `state.json`, diff composite+tokens between OFF/ON, and exit non-zero on delta > `--max-delta`. Full harness implementation is Phase 01's scope; this plan only adds the compaction-specific matrix entries.

- [ ] **Step 6: Run contract tests to verify they pass**

Run: `./tests/lib/bats-core/bin/bats tests/contract/evals_matrix_compaction.bats`
Expected: 3 passed.

- [ ] **Step 7: Commit**

```bash
git add tests/evals/pipeline/scenarios/10-repo-map-ab/ \
        .github/workflows/evals.yml \
        tests/contract/evals_matrix_compaction.bats
git commit -m "feat(phase10): add 10-repo-map-ab eval scenario + CI matrix gate"
```

---

## Task 15: CLAUDE.md entry + rollout graduation logic (20-run gate)

**Files:**
- Modify: `CLAUDE.md`
- Create: `tests/contract/claudemd_phase10_entry.bats`
- Create: `shared/rollout/repomap-graduation.md`

- [ ] **Step 1: Write the failing contract test**

```bash
# tests/contract/claudemd_phase10_entry.bats
#!/usr/bin/env bats

@test "CLAUDE.md v2.0 features table includes Repo-map PageRank row" {
  grep -qE "Repo-map PageRank|Prompt compaction|prompt_compaction" \
    "${BATS_TEST_DIRNAME}/../../CLAUDE.md"
}

@test "CLAUDE.md supporting-systems list includes repomap.py" {
  grep -q "repomap" "${BATS_TEST_DIRNAME}/../../CLAUDE.md"
}

@test "rollout graduation doc documents 20-run gate" {
  local f="${BATS_TEST_DIRNAME}/../../shared/rollout/repomap-graduation.md"
  [ -f "$f" ]
  grep -q "20" "$f"
  grep -q "composite" "$f"
  grep -q "30 %" "$f" || grep -q "30%" "$f"
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./tests/lib/bats-core/bin/bats tests/contract/claudemd_phase10_entry.bats`
Expected: 3 failures.

- [ ] **Step 3: Add row to `CLAUDE.md` v2.0 features table**

Find the v2.0 features table in `CLAUDE.md` (around the "Supporting systems" paragraph) and insert:

```markdown
| Repo-map PageRank (F32) | `code_graph.prompt_compaction.*` | `hooks/_py/repomap.py` — biased PageRank + token-budgeted pack assembly. Replaces full-directory listings in `fg-100`, `fg-200`, `fg-300` prompts. Opt-in default OFF. Categories: `REPOMAP-BYPASS-*` |
```

Under "Supporting systems" prose, add one line:

> Repo-map PageRank (Phase 10): `hooks/_py/repomap.py` ranks files in the code graph by structural centrality × recency × keyword overlap; the orchestrator, planner, and implementer substitute a `{{REPO_MAP_PACK}}` placeholder for full directory listings, saving 30–50 % tokens per stage. Cache: `.forge/ranked-files-cache.json` (survives `/forge-recover reset`). Reference: `shared/graph/pagerank-sql.md`.

- [ ] **Step 4: Write graduation doc**

Write `shared/rollout/repomap-graduation.md`:

```markdown
# Phase 10 Graduation Gate — Repo-map PageRank

Governs the rollout-stage-3 → stage-4 transition (flipping
`code_graph.prompt_compaction.enabled` default from `false` to `true` in
`plugin.json`).

## Gate criteria (all must hold across 20 consecutive passing `master` eval runs)

| # | Metric | Threshold | Source |
|---|---|---|---|
| G1 | Mean composite score delta (ON − OFF) | ≥ −2.0 points | `state.json.final_score`, scenario `10-repo-map-ab` |
| G2 | Mean orchestrator+planner prompt-token reduction | ≥ 30 % | `state.json.prompt_compaction.stages.*.pack_tokens` vs `baseline_tokens_estimate` |
| G3 | Mean elapsed delta | ≤ +5 % | `state.json.elapsed_ms` |
| G4 | `repomap.bypass.failure` aggregate count (sum over 20 runs) | = 0 | `state.json.prompt_compaction.bypass_events` (excludes `sparse_graph`) |
| G5 | Median `overall_ratio` | ≥ 0.25 | `state.json.prompt_compaction.overall_ratio` |

## Revert rule

A **single** master eval run with composite delta < −2.0 resets the consecutive counter to 0 and files a P1 issue before the next flip attempt. The code stays shipped; only the default flag reverts.

## Reviewer action at 20 runs

1. Run `python3 tests/evals/pipeline/summarize_runs.py --scenario 10-repo-map-ab --last 20` and confirm G1–G5.
2. Flip `code_graph.prompt_compaction.enabled` to `true` in the framework `forge-config-template.md` files (not `plugin.json` — the per-framework template is the resolved default).
3. Bump CLAUDE.md row to mark Phase 10 as "on by default."
4. Open a PR titled `chore(phase10): graduate prompt_compaction to default ON`.
```

- [ ] **Step 5: Run contract tests to verify they pass**

Run: `./tests/lib/bats-core/bin/bats tests/contract/claudemd_phase10_entry.bats`
Expected: 3 passed.

- [ ] **Step 6: Commit**

```bash
git add CLAUDE.md shared/rollout/repomap-graduation.md \
        tests/contract/claudemd_phase10_entry.bats
git commit -m "docs(phase10): CLAUDE.md entry + 20-run graduation gate definition"
```

---

## Task 16: Final structural validation + full-suite smoke

**Files:**
- None (verification-only)

- [ ] **Step 1: Run structural validation**

Run: `./tests/validate-plugin.sh`
Expected: 73+ structural checks pass, including the new agent-frontmatter / schema-version checks.

- [ ] **Step 2: Run unit + contract tests**

Run: `./tests/run-all.sh unit contract`
Expected: all new tests green; no regressions in pre-existing suite.

- [ ] **Step 3: Smoke-test CLI on the repo's own graph**

Run (assumes `.forge/code-graph.db` exists from a prior `/forge-init`):

```bash
python3 -m hooks._py.repomap build-pack \
  --db .forge/code-graph.db \
  --cache /tmp/ranked-files-cache.json \
  --keywords-file /dev/null \
  --budget 8000 --top-k 25
```

Expected: a pack with header `## Repo-map (top N of M files, budget X/8000 tokens)` followed by up to 25 lines. No `repomap.bypass.*` on stderr unless the DB is sparse.

- [ ] **Step 4: Final commit (no-op marker)**

If all three steps pass, no further commits are needed — Phase 10 is ready for rollout stage 1 (land dark). Tag:

```bash
git tag -a phase10-land-dark -m "Phase 10 repo-map PageRank: shipped dark, default OFF"
```

---

## Spec-coverage map (self-review)

| Spec section | Requirement | Task(s) |
|---|---|---|
| §3 In scope | PageRank over nodes/edges | Task 3 |
| §3 In scope | `score = pagerank × recency × (1 + overlap)` | Task 4 |
| §3 In scope | Top-K selector with partial slices + 8 000 budget | Task 5 |
| §3 In scope | Write-through cache 4-tuple key | Task 6 (algo), Task 13 (spec fix) |
| §3 In scope | Python helper `hooks/_py/repomap.py` | Tasks 2–7 |
| §3 In scope | Eval integration (2-pt guard) | Task 14 |
| §3 In scope | `forge-config.md` section | Task 9 |
| §3 In scope | `state.json.prompt_compaction.stages[*].ratio` | Task 11 |
| §3 In scope | `shared/graph/pagerank-sql.md` | Task 12 |
| §4.1 Damping 0.85 + convergence 1e-6 / 100 iters | Algorithm | Task 3 |
| §4.1 Edge weights table | Weights constant + config surface | Tasks 3, 9 |
| §4.2 Recency multiplier [1.0, 1.5] | Computation + bounds test | Task 4 |
| §4.2 Keyword overlap with cap | Computation + cap test | Tasks 1, 4 |
| §4.3 Whole → partial → skip ladder | Assembly | Task 5 |
| §4.3 `top_k` hard cap | Assembly + test | Task 5 |
| §4.4 Integration call sites | Placeholder in 3 agents | Task 10 |
| §4.4 JSON cache schema | Cache module + contract schema | Tasks 6, 8 |
| §5.1–5.2 File list | All new/modified files | Tasks 1–15 |
| §6.1 Config defaults | Config block + defaults table | Task 9 |
| §6.2 Baseline bootstrap (Issue #2) | Analytical `sum(bytes)/3.5` | Tasks 7, 11, 13 |
| §6.3 Artifacts (cache survives reset) | Cache module; noted in CLAUDE.md | Tasks 6, 15 |
| §7 Opt-in, no backcompat | Default `enabled: false` | Task 9 |
| §8.1 Unit tests (10 named) | All covered | Tasks 1–7 (20+ tests) |
| §8.2 Contract tests | Schema, placeholder, config, docs, state, evals | Tasks 8–15 |
| §8.3 Eval harness integration | Scenario + CI matrix | Task 14 |
| §9 Four rollout stages | Land dark → dogfood → opt-in → default ON | Tasks 15, 16 |
| §10 Risks (sparse, keyword, slice, cache, BLAS) | All mitigated in code + docs | Tasks 3, 7, 12 |
| §11 SC-1..SC-6 | Eval gates in scenario + graduation doc | Tasks 14, 15 |

**Placeholder scan:** no `TBD`, `TODO`, `<...>`, "implement later", or unreferenced types. Every code step shows the code. Every method referenced in a later task (`assemble_pack`, `score_files`, `run_pagerank`, `compute_graph_sha`, `compute_keywords_hash`, `PackCache`, `extract_keywords`) is defined in the task that introduces it.

**Type consistency:** `FileScore`, `PackConfig`, `PackEntry`, `Pack`, `CachedPack`, `RecencyConfig`, `DEFAULT_EDGE_WEIGHTS` are introduced in one place and reused consistently across tasks. CLI flag names (`--budget`, `--top-k`, `--keywords-file`, `--cache`, `--db`, `--min-nodes-for-rank`) are stable from Task 7 through Tasks 10 and 14. Bypass event names (`repomap.bypass.{sparse_graph,missing_graph,solve_diverged,corrupt_cache}`) are identical in code, spec edits, docs, and state schema.
