# Phase 10 — Repo-Map PageRank Dynamic Prompt Context

> **Phase:** 10 (of the forge A+ roadmap)
> **Priority:** P2 — quality-of-life optimization on top of the existing code graph
> **Status:** Draft (requirements pre-approved by maintainer; no Q&A loop)
> **Audience:** forge maintainers, agent authors, Phase 02 hook-migration owners
> **Depends on:** Phase 02 (`hooks/_py/` Python runtime), existing SQLite code graph
> **Breaking changes:** none — opt-in behind `code_graph.prompt_compaction.enabled: false`

---

## 1. Goal

Use the existing SQLite code graph plus PageRank centrality — weighted by recent-touch and task-keyword overlap — to select a top-K set of files (and partial-file slices) for injection into `fg-100-orchestrator`, `fg-200-planner`, and `fg-300-implementer` prompts, replacing full-directory listings and shrinking stage prompts by 30–50 % without a measurable score regression.

---

## 2. Motivation

Audit finding **W11 — forge exposes the SQLite code graph to query surfaces (`/forge-ask`, `/forge-graph-query`) but has never fed it back into the agent prompts themselves.** Convention stacks (soft-capped at 12 files per component), PREFLIGHT docs index fragments, and explore-cache `file_index` payloads are all shipped wholesale into stage dispatch prompts. On a 1 K-file project the orchestrator alone pays 6–10 K tokens per stage for context it largely does not need, and those tokens compound across the 10-stage pipeline and across every retry.

The reference design is **Aider's repo-map** — a tree-sitter-backed directed graph over symbol definitions/references, scored with a biased PageRank that picks the top-K "most relevant" files for the current chat within a fixed token budget:
<https://aider.chat/docs/repomap.html>. Aider reports that a ~1 K-token repo-map outperforms naive listings even when the naive listing is several times larger, because rank orders what the model sees.

Forge already has every input Aider needs (tree-sitter, SQLite graph, file hashes, bug-fix history); W11 is simply "wire it in." Phase 10 closes that gap.

---

## 3. Scope

### In scope

- PageRank (damping 0.85) computed over the `nodes` / `edges` tables of `.forge/code-graph.db`, biased by recency and task-keyword overlap.
- A deterministic scoring function
  `score = pagerank × recency_multiplier × (1 + keyword_overlap)`.
- A top-K selector honoring a token budget (default 8 000), with partial-file slices (top-ranked symbol windows) for files too large to fit whole.
- Assembly of a compact "context pack" (ranked file list + per-file symbol windows + summary stats) that replaces the current full-listing blocks in stage dispatch prompts.
- Integration via a pre-dispatch Python helper (`hooks/_py/repomap.py`) invoked from the orchestrator when `code_graph.prompt_compaction.enabled: true`.
- Write-through cache `.forge/ranked-files-cache.json` keyed on `(graph_sha, keywords_hash, budget, top_k)` — the 4-tuple matches the durable mirror table in §5.2 and prevents cache collisions across per-agent budgets (orchestrator 8 000 vs implementer 4 000). The PageRank solve runs at most once per pipeline run per query per budget.
- Eval integration: Phase 01 harness runs each scenario twice (compaction OFF vs ON) and asserts the composite score does not drop by more than 2 points.
- New `forge-config.md` section `code_graph.prompt_compaction.*`.
- New `state.json` field `prompt_compaction.stages[*].ratio` for observability.
- Documentation: `shared/graph/pagerank-sql.md` describing the algorithm, schema additions, and query recipes.

### Out of scope (deferred or orthogonal)

- Replacing or rewriting the explore cache (different concern — explore caches *discovery*, repo-map ranks *relevance*; both survive).
- Vector / embedding-based retrieval (PageRank on a code graph is structurally superior for code at this scale; embeddings are the next-phase follow-up if eval shows diminishing returns).
- Cross-repo ranking (related-project graphs are independent; Phase 10 is single-project).
- Prompt compaction for review agents (`fg-41x-*`) — reviewers receive scoped diffs already; Phase 10 targets the three "context-hungry" agents identified in W11.
- Pre-computed rank persisted in the SQLite graph itself (we cache in JSON to keep the graph schema stable).

---

## 4. Architecture

### 4.1 PageRank algorithm

Standard iterative PageRank with damping factor **d = 0.85** (Brin & Page, 1998 — Aider uses the same value; it is the de-facto standard for centrality on code-reference graphs).

    PR(v) = (1 - d) / N  +  d × Σ_{u ∈ in(v)} [ w(u,v) / out_weight(u) ] × PR(u)

Running against the existing SQLite schema:

- **Nodes:** `nodes` rows with `kind IN ('File','Module','Class','Function','Method')`. Functions and classes contribute via their `CONTAINS` edge back to their parent `File`, so the final per-file score is the sum of the ranks of the file node plus every symbol contained in it. This mirrors Aider's file-granular output while preserving symbol-level signal.
- **Edges:** `edges` rows with `edge_type IN ('CALLS','IMPORTS','REFERENCES','INHERITS','IMPLEMENTS','TESTS','CONTAINS')`. `CALLS` and `REFERENCES` get `w = 1.0`; `IMPORTS` `0.7`; `INHERITS`/`IMPLEMENTS` `0.8`; `TESTS` `0.4` (tests are informative but should not dominate); `CONTAINS` `0.3` (structural glue).
- **Solve:** power iteration, convergence when `max(|PR_k - PR_{k-1}|) < 1e-6` or 100 iterations, whichever first. On a 10 K-node graph this completes in < 500 ms with pure Python + `sqlite3` + NumPy (NumPy is already a Phase 02 dep via `hooks/_py/`).
- **Determinism:** sort nodes by `id` before building the transition matrix; seed NumPy with a fixed seed for the personalization vector when keyword bias is applied.

### 4.2 Weighting scheme

Final per-file score for a given query:

    score(f) = pagerank(f)
             × recency_multiplier(f)
             × (1 + keyword_overlap(f, query))

**Recency multiplier** — uses `ProjectFile.last_modified` (mirrored into `nodes.properties` by `build-code-graph.sh`; fallback: `git log -1 --format=%ct -- <path>`):

    age_days = now - last_modified
    if age_days <= recency_window_days:   # default 30
        recency_multiplier = 1.5 - 0.5 × (age_days / recency_window_days)   # 1.5 → 1.0 linear decay
    else:
        recency_multiplier = 1.0

Files touched today get the full 1.5× boost; files untouched in the last 30 days get 1.0; there is no penalty for old files (ranking is relative).

**Keyword overlap** — keywords are extracted from the user's requirement at pipeline start via a deterministic, dependency-free function (`hooks/_py/keyword_extract.py`):

1. Lowercase, strip punctuation, tokenize on whitespace.
2. Drop English stopwords (hard-coded 180-word list embedded in the module; no NLTK dep).
3. Drop tokens of length < 3 and pure numerics.
4. Keep top-20 by frequency; ties broken by first occurrence.

Per-file overlap is computed as the count of query keywords appearing in the file's `path`, `package`, top-level symbol names, or docstring summaries (the latter pulled from `nodes.properties` when present). Overlap is capped at 5 to prevent a single keyword-heavy file from monopolizing the top-K.

### 4.3 Top-K assembly and token budget

Given a ranked list and a token budget `B` (default 8 000):

1. Estimate each file's "full" token cost via `ceil(size_bytes / 3.5)` (cheap heuristic; good enough for budget allocation, exact counts happen at prompt build time).
2. Walk the ranked list in order; for each file:
   - If `remaining_budget ≥ full_cost`, include the whole file. Deduct.
   - Else if `remaining_budget ≥ min_slice_cost` (default 400 tokens): include a **partial-file slice** — the top-ranked `(start_line, end_line)` windows belonging to the highest-ranked symbols inside that file, stitched with `# ... elided N lines ...` markers. Deduct actual slice cost.
   - Else skip.
3. Stop when budget is exhausted or the ranked list is exhausted.
4. Cap at `top_k` (default 25) files regardless of remaining budget — we want the model to see *few, relevant* things, not a soup.

The result is a **context pack** emitted as a compact YAML-ish block:

    ## Repo-map (top 25 of 1 247 files, budget 7 832/8 000 tokens)
    src/domain/Plan.kt              [full]   rank=0.042 recent=yes
    src/domain/PlanRepository.kt    [full]   rank=0.038 recent=yes
    src/api/PlanController.kt       [slice]  rank=0.031 lines=1-14,87-112
    ...

The pack is injected in place of the current "full directory listing" / "convention stack file dump" blocks in each affected agent's dispatch prompt.

### 4.4 Integration points

Three call sites, each invoking `hooks/_py/repomap.py build-pack` with stage-specific knobs:

| Agent | When | What it replaces | Budget override |
|---|---|---|---|
| `fg-100-orchestrator` | Once at PREFLIGHT, re-used across stages | `components/` directory walks, PREFLIGHT docs-index dump | 8 000 |
| `fg-200-planner` | EXPLORE phase entry | Full `file_index` from explore-cache | 10 000 (planner needs broader view) |
| `fg-300-implementer` | Each task dispatch | Convention stack (12 files/component) + touched-files list | 4 000 per task |

**Parallel implementer dispatch:** Each implementer task receives its **own** pack (per-task, not shared across parallel tasks at the same IMPLEMENT stage). Per-task packs are chosen because a shared pack must serve disjoint task contexts — its ranking relevance collapses in the common case where parallel tasks touch unrelated subsystems. The total-token cost of N parallel tasks is therefore `N × 4 000` pack tokens rather than `4 000` shared; SC-1's ≥30 % reduction target is framed against this per-task cost in runs where `implementer.parallel_tasks > 1`.

Each call resolves through the write-through cache `.forge/ranked-files-cache.json`:

    {
      "schema_version": "1.0.0",
      "entries": [
        {
          "graph_sha": "sha256:...",            // hash of code-graph.db file
          "keywords_hash": "sha256:...",        // hash of sorted query keywords
          "budget": 8000,
          "top_k": 25,
          "computed_at": "2026-04-19T10:00:00Z",
          "ranked": [{ "file": "...", "score": 0.042, "slice": null }, ...]
        }
      ]
    }

Cache entries are LRU-evicted past 16 rows; the cache survives `/forge-recover reset` (same policy as `code-graph.db`).

### 4.5 Alternatives considered

**A. BM25 / SQLite FTS5 full-text search.** Trivially available — `run-history.db` already uses FTS5 — and fast. *Rejected as primary mechanism* because BM25 ranks on textual keyword match alone; it has no notion of *structural* centrality. A file containing the query word 20 times but never imported by anything is not more relevant than a central utility module that the query-relevant files all call. BM25 remains useful as a **tie-breaker** inside `keyword_overlap` (we may fold it in during rollout if the plain-count overlap proves too coarse), but not as the trunk algorithm.

**B. Vector embeddings (ada-002 / local sentence-transformers).** Highest recall on natural-language queries. *Rejected for Phase 10* because (1) it adds a new runtime dep (either a network call or a 200 MB model file), contradicting the Phase 02 stdlib-first posture; (2) it requires an embedding refresh pipeline tied to file changes; (3) PageRank on the already-built graph is free structural signal that embeddings do not capture (call/import topology). Embeddings are the natural Phase 11+ follow-up if eval data show PageRank alone plateaus.

**PageRank-first rationale:** leverages data we already compute, is deterministic, has zero new runtime deps (NumPy is Phase 02), is well-understood (Aider production-validated), and composes cleanly with keyword overlap to recover most of the BM25/embedding upside.

---

## 5. Components

### 5.1 New files

| Path (absolute) | Purpose |
|---|---|
| `/Users/denissajnar/IdeaProjects/forge/hooks/_py/repomap.py` | Core module. CLI + library. Subcommands: `pagerank`, `build-pack`, `cache-clear`, `explain`. Python 3.10+, stdlib + NumPy only. |
| `/Users/denissajnar/IdeaProjects/forge/hooks/_py/keyword_extract.py` | Deterministic keyword extraction from requirement text. Embedded stopwords list. No NLTK / spaCy. |
| `/Users/denissajnar/IdeaProjects/forge/shared/graph/pagerank-sql.md` | Algorithm reference, weighting table, example Cypher-equivalent SQL, troubleshooting. |
| `/Users/denissajnar/IdeaProjects/forge/tests/unit/repomap.py` | Unit tests for ranking determinism, budget honoring, partial-slice assembly, cache hits. |
| `/Users/denissajnar/IdeaProjects/forge/tests/evals/pipeline/scenarios/10-repo-map-ab/` | Phase 01 eval scenario: A/B the same task with compaction OFF / ON. |

### 5.2 Modified files

| Path (absolute) | Change |
|---|---|
| `/Users/denissajnar/IdeaProjects/forge/shared/graph/code-graph-schema.sql` | Add table `ranked_files_cache(graph_sha TEXT, keywords_hash TEXT, budget INT, top_k INT, ranked_json TEXT, computed_at TEXT, PRIMARY KEY(graph_sha, keywords_hash, budget, top_k))` — optional durable mirror of the JSON cache; the JSON file remains primary. Add index `idx_nodes_last_modified` on `nodes(json_extract(properties, '$.last_modified'))`. Bump schema to 1.1.0. |
| `/Users/denissajnar/IdeaProjects/forge/agents/fg-100-orchestrator.md` | Replace "full directory listing" dispatch blocks with a `{{REPO_MAP_PACK}}` placeholder resolved by the pre-dispatch hook. Budget 8 000. |
| `/Users/denissajnar/IdeaProjects/forge/agents/fg-200-planner.md` | Replace explore-cache `file_index` dump with `{{REPO_MAP_PACK}}`. Budget 10 000. |
| `/Users/denissajnar/IdeaProjects/forge/agents/fg-300-implementer.md` | Replace convention-stack file listing and touched-files list with `{{REPO_MAP_PACK}}`. Budget 4 000 per task. |
| `/Users/denissajnar/IdeaProjects/forge/shared/state-schema.md` | Document new `prompt_compaction` field. Bump to 1.7.0. |
| `/Users/denissajnar/IdeaProjects/forge/shared/preflight-constraints.md` | Add validation: if `code_graph.prompt_compaction.enabled: true` but `code_graph.enabled: false`, PREFLIGHT fails with a clear error. |
| `/Users/denissajnar/IdeaProjects/forge/CLAUDE.md` | One-line entry under "Supporting systems" and new row in the v2.0 features table. |

### 5.3 Dispatch flow

1. Orchestrator resolves a dispatch template containing `{{REPO_MAP_PACK:BUDGET=8000:TOPK=25}}`.
2. The pre-dispatch step invokes `python3 ${CLAUDE_PLUGIN_ROOT}/hooks/_py/repomap.py build-pack --budget 8000 --top-k 25 --keywords-file .forge/current-keywords.txt`.
3. `repomap.py` hits the cache; on miss, runs PageRank on `.forge/code-graph.db`, writes cache, returns the pack on stdout.
4. Orchestrator substitutes the pack into the template, logs `prompt_compaction.stages[<stage>] = { budget, pack_tokens, files, ratio }` into `state.json`.
5. Pack is passed to the subagent as part of its system prompt.

On any failure, the pre-dispatch hook logs INFO to stderr using one of the following named bypass events, emits a degraded pack (empty entries; upstream caller supplies the prior full listing), and the pipeline proceeds:

- `repomap.bypass.missing_graph` — `code-graph.db` absent, unreadable, or malformed.
- `repomap.bypass.solve_diverged` — power iteration did not converge in 100 iters.
- `repomap.bypass.corrupt_cache` — `.forge/ranked-files-cache.json` invalid.
- `repomap.bypass.sparse_graph` — `node_count < min_nodes_for_rank` (expected; tracked separately).

SC-4's `repomap.bypass.failure` aggregates `{missing_graph, solve_diverged, corrupt_cache}`. `sparse_graph` is excluded (it is a legitimate pre-populated-graph state, not a fault).

---

## 6. Data / State / Config

### 6.1 `forge-config.md`

    code_graph:
      enabled: true
      backend: auto
      prompt_compaction:
        enabled: false              # opt-in; flips to true in rollout stage 3
        top_k: 25                   # hard cap on files in a pack
        token_budget: 8000          # orchestrator default; per-agent overrides live in mode_config
        recency_window_days: 30     # recency multiplier linearly decays 1.5× → 1.0× over this window
        min_slice_tokens: 400       # minimum budget to allocate a partial-file slice
        recency_boost_max: 1.5      # cap for recency multiplier (safety net)
        keyword_overlap_cap: 5      # max count of keyword hits counted per file
        cache_max_entries: 16       # LRU cap on .forge/ranked-files-cache.json
        edge_weights:               # expert tuning only; defaults from §4.1
          CALLS: 1.0
          REFERENCES: 1.0
          IMPORTS: 0.7
          INHERITS: 0.8
          IMPLEMENTS: 0.8
          TESTS: 0.4
          CONTAINS: 0.3

### 6.2 State schema additions

`state.json.prompt_compaction`:

    {
      "enabled": true,
      "stages": {
        "orchestrator_preflight": { "budget": 8000, "pack_tokens": 6420, "files": 25, "ratio": 0.38 },
        "planner_explore":        { "budget": 10000, "pack_tokens": 8930, "files": 25, "ratio": 0.42 },
        "implementer_task_3":     { "budget": 4000, "pack_tokens": 3210, "files": 12, "ratio": 0.51 }
      },
      "baseline_tokens_estimate": 22500,
      "compacted_tokens_total":   18560,
      "overall_ratio":            0.18
    }

`ratio` is defined as `(baseline_tokens − pack_tokens) / baseline_tokens` for that stage. `baseline_tokens_estimate` is computed **analytically** as `sum(size_bytes for every File node) / 3.5` each time the pack is rendered. This is deterministic, requires no extra pipeline run, and makes `ratio` defined from the first compacted run. State-level field `baseline_source` records the origin:

- `"estimated"` — analytical formula above (the default, always available).
- `"measured"` — averaged from `.forge/run-history.db` once `run_count ≥ 5` for the project.

The earlier "dry pass" option is removed.

### 6.3 `.forge/` artifacts

| Artifact | Survives `/forge-recover reset`? | Note |
|---|---|---|
| `.forge/ranked-files-cache.json` | **yes** | Same policy as `code-graph.db`, `explore-cache.json`, `wiki/` |
| `.forge/current-keywords.txt` | no | Per-run scratch |

---

## 7. Compatibility

- **Opt-in by config.** Default `enabled: false`. Existing projects see zero behavior change until they flip the flag or until rollout graduates the default (§9).
- **No agent API break.** Dispatch templates add a new `{{REPO_MAP_PACK}}` placeholder; templates that do not include it behave unchanged. Only `fg-100`, `fg-200`, `fg-300` adopt the placeholder in Phase 10.
- **No graph schema break.** The new `ranked_files_cache` table and `idx_nodes_last_modified` index are additive; schema 1.0.0 consumers still work. Schema bumps to 1.1.0.
- **Graceful degradation.** If `code-graph.db` is missing, corrupt, or Python / NumPy is unavailable (Phase 02 guarantees they are), the pre-dispatch hook returns a truncated full listing and the pipeline proceeds.
- **No backwards-compat shim.** Per the project-wide policy there is no "legacy path" fallback once the flag is on.

---

## 8. Testing Strategy

No local test execution — all verification runs in CI after push (per project policy).

### 8.1 Unit tests (`tests/unit/repomap.py`, Python stdlib + pytest)

- `test_pagerank_determinism` — same DB + same keywords → byte-identical ranked list across runs.
- `test_pagerank_convergence_bounded` — fabricated 500-node graph converges in ≤ 100 iters.
- `test_recency_multiplier_bounds` — multiplier stays in `[1.0, 1.5]` for any `age_days ≥ 0`.
- `test_keyword_overlap_cap` — a file containing a keyword 100× scores the same as one containing it `keyword_overlap_cap` times.
- `test_budget_honored_whole_files` — sum of included file token estimates ≤ budget.
- `test_budget_honored_with_slices` — partial-slice mode emits valid line ranges and stays ≤ budget.
- `test_topk_hard_cap` — pack never contains > `top_k` files even with budget to spare.
- `test_cache_hit_roundtrip` — second call with same `(graph_sha, keywords_hash, budget, top_k)` returns cached pack without running the solver (assert via instrumentation counter).
- `test_cache_invalidation_on_graph_change` — mutating `code-graph.db` content bumps `graph_sha` and evicts stale entries.
- `test_missing_graph_degrades_gracefully` — DB absent → returns degraded pack, no exception.

### 8.2 Contract tests

- `tests/contract/repomap_schema.bats` — asserts `ranked_files_cache.json` round-trips through jsonschema.
- `tests/contract/state_schema.bats` — `state.json.prompt_compaction` validates against the schema bumped to 1.7.0.

### 8.3 Eval harness integration (Phase 01)

- New scenario `10-repo-map-ab` runs each of the 10 frozen scenarios **twice** — once with `prompt_compaction.enabled: false`, once with `true` — and diffs:
  - pipeline composite score (must not drop > 2.0 points, eval gate)
  - total prompt tokens (must drop ≥ 30 % on orchestrator + planner combined)
  - total elapsed (expected flat; measurement for regression only)
- GitHub Actions `.github/workflows/evals.yml` gets a matrix axis `compaction: [off, on]`.
- CI gate: `evals.yml` fails the PR when the `on` run's composite is more than 2 points below the `off` run's composite on the same commit.

### 8.4 Manual verification checklist (post-merge, on a real project)

Run `/forge-run <req>` on `wellplanned-be` with compaction on; compare `state.json.prompt_compaction.overall_ratio` ≥ 0.30 and pipeline final score to the last five baseline runs in `.forge/run-history.db`.

---

## 9. Rollout

Four stages, each gated by the Phase 01 eval harness on `master`.

| Stage | Duration | Config default | Gate to advance |
|---|---|---|---|
| 1. Land dark | 1 week | `enabled: false`, code shipped | Unit + contract tests green on `windows-latest` / `ubuntu-latest` / `macos-latest`. |
| 2. Dogfood | 2 weeks | `enabled: false`, maintainers flip locally | 5 maintainer runs on real projects, no regressions in `/forge-insights` score trend. |
| 3. Opt-in highlighted | 4 weeks | `enabled: false`, `/forge-tour` mentions the flag, `/forge-config` surfaces it | 20 aggregated eval runs on `master` show mean composite ≥ baseline − 2.0 and mean orchestrator-token reduction ≥ 30 %. |
| 4. Default on | — | `enabled: true` in `plugin.json` ship config | n/a — terminal state. |

At any stage, a single eval regression > 2 points on `master` reverts the default to `false` and files a P1 issue before the next attempt.

---

## 10. Risks and Open Questions

### Risks

1. **PageRank on sparse graphs degenerates to uniform.** A fresh or tiny project (< 50 nodes) has little edge structure, making the rank nearly uniform and the pack a random top-K. *Mitigation:* when `node_count < 50`, bypass PageRank and emit the current full listing (logged as `repomap.bypass.sparse_graph`). The cutoff is a config knob (`min_nodes_for_rank`, default 50, undocumented expert tuning).
2. **Keyword extraction too coarse for code-heavy requirements.** Queries like "fix null-pointer in `PlanService.validate`" already carry exact symbol names; the stopwords/frequency approach keeps them. Queries like "make it faster" strip to nothing useful. *Mitigation:* when `len(keywords) < 2`, skip the keyword factor (`keyword_overlap = 0`) and rely on PageRank × recency alone. Emit INFO note in `stage_0_notes`.
3. **Partial-slice assembly produces stitched code the model miscounts.** If the elided-lines marker is taken literally the model may hallucinate line numbers. *Mitigation:* use a marker that is valid in all 15 supported languages' comment syntaxes (`# ... elided N lines ...` for script-style, `/* ... elided N lines ... */` for C-family); include absolute line numbers for each retained window (`lines=87-112`) in the header so the model has grounding.
4. **Cache staleness between incremental graph updates and compaction call.** Phase 02's incremental graph updater races the compaction call. *Mitigation:* `graph_sha` is **not** `sha256(file(code-graph.db))` (which would change on every SQLite write even for no-op updates). Instead, it is a content-derived SHA-256 over `id || '|' || updated_at` for all rows in `nodes` followed by all rows in `edges`, ordered by `id`. This is stable under no-op or metadata-only writes and invalidates the cache only when row contents actually change. Incremental graph updates that touch a single file re-SHA that file's rows but leave the other 999 files' contributions unchanged — so cross-cache-entry invalidation is eliminated except where the user's dispatch keywords intersect the updated rows.
5. **Determinism across platforms.** NumPy BLAS differs between macOS Accelerate and Linux OpenBLAS. *Mitigation:* unit tests assert ranked *order* (not absolute values), and the power-iteration tolerance (`1e-6`) is well above BLAS noise. Tie-breaking falls back to `node.id` ascending.

### Open questions

- Q1: Should we eventually rank at the **symbol** level and present symbol-granular packs instead of file-granular? Aider is file-granular and works; punt to Phase 11.
- Q2: Should reviewer agents (`fg-41x-*`) also consume the pack? Current intuition: no, they get scoped diffs. Revisit after 20 eval runs if reviewer-stage tokens dominate.
- Q3: How should the pack interact with the explore cache's `file_index` patterns? Initial answer: pack *replaces* the file_index dump in the prompt; the cache itself is still written and consulted. Validate in eval.
- Q4: What's the right default budget for monorepos with 10 K+ files? Current 8 000 may underfit; consider tiering via `monorepo.affected` set.

---

## 11. Success Criteria

All must hold after 20 eval runs on `master` (rollout stage 3 → 4 gate):

- **SC-1.** Mean prompt-token delta across orchestrator + planner: **≥ 30 % reduction**, targeting 30–50 %.
- **SC-2.** Mean pipeline composite score delta: **≥ −2.0 points** (i.e., score does not drop by more than 2 points vs baseline).
- **SC-3.** Mean pipeline elapsed delta: **≤ +5 %** (compaction adds PageRank solve but removes listing tokens; net expected flat or faster).
- **SC-4.** Zero `repomap.bypass.failure` events on `master` CI across the 20 runs. Sparse-graph bypass (`repomap.bypass.sparse_graph`) is allowed and counted separately.
- **SC-5.** `state.json.prompt_compaction.overall_ratio` reported for every run; median ≥ 0.25 across the 20 runs.
- **SC-6.** A Phase 10-labeled entry on `tests/evals/pipeline/leaderboard.md` shows both A and B bars for each scenario.

---

## 12. References

- Aider repo-map — https://aider.chat/docs/repomap.html
- Brin, S. & Page, L. (1998). *The Anatomy of a Large-Scale Hypertextual Web Search Engine* — https://research.google/pubs/pub334/
- Aider source (graph.py, PageRank implementation) — https://github.com/Aider-AI/aider/blob/main/aider/repomap.py
- tree-sitter repo-map technique discussion — https://aider.chat/2023/10/22/repomap.html
- Forge audit W11 (internal, referenced in the Phase 10 roadmap entry)
- Phase 01 eval harness spec — `docs/superpowers/specs/2026-04-19-01-evaluation-harness-design.md`
- Phase 02 Python hook runtime spec — `docs/superpowers/specs/2026-04-19-02-cross-platform-python-hooks-design.md`
- Forge code-graph schema — `shared/graph/code-graph-schema.sql`
- Forge explore-cache contract — `shared/explore-cache.md`
- Forge state schema — `shared/state-schema.md`
