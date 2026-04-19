# Phase 10 — Repo-Map PageRank Design Spec Review

**Spec:** `/Users/denissajnar/IdeaProjects/forge/docs/superpowers/specs/2026-04-19-10-repo-map-pagerank-design.md`
**Reviewer:** Senior Code Reviewer
**Date:** 2026-04-19
**Verdict:** **APPROVE with minor revisions**

---

## 1. Criteria Checklist

| # | Criterion | Status | Evidence |
|---|---|---|---|
| 1 | All 12 sections present | PASS | Goal, Motivation, Scope, Architecture, Components, Data/State/Config, Compatibility, Testing, Rollout, Risks, Success Criteria, References — all twelve present and numbered. |
| 2 | No placeholders (no TBD/TODO/`<...>`) | PASS | No `TBD`, `TODO`, `FIXME`, or unresolved `<placeholder>` tokens found. All values are concrete. |
| 3 | PageRank algorithm parameters specified (d=0.85, edge weights per edge type) | PASS | §4.1: damping `d = 0.85`, convergence `1e-6`, 100 iter cap. §4.1 edge-weight table covers all 7 edge types (CALLS 1.0, REFERENCES 1.0, IMPORTS 0.7, INHERITS 0.8, IMPLEMENTS 0.8, TESTS 0.4, CONTAINS 0.3), mirrored in `forge-config.md` §6.1. |
| 4 | Pack assembly algorithm described (whole → partial slices when budget low) | PASS | §4.3 step-by-step: whole file if `remaining ≥ full_cost`, partial slice if `remaining ≥ min_slice_cost` (400), skip otherwise; caps at `top_k=25`; example output block shown. |
| 5 | Token budgets per agent quantified | PASS | §4.4 table: orchestrator 8 000, planner 10 000, implementer 4 000 per task, with rationale for each. |
| 6 | Cache key includes graph SHA + keywords hash + budget + top_k | PASS (with minor copy inconsistency) | §4.4 JSON schema includes all four fields; §8.1 `test_cache_hit_roundtrip` asserts the 4-tuple. However §3 in-scope bullet says the cache is keyed on `(graph_sha, keywords_hash)` only — see Issue #1. |
| 7 | Rollout gated by eval metrics (30–50 % token reduction, ≤2-pt score drop) | PASS | §9 stage-3 gate: "20 aggregated eval runs … mean composite ≥ baseline − 2.0 and mean orchestrator-token reduction ≥ 30 %." §8.3 CI gate enforces the ≤2-pt threshold per commit. §11 SC-1/SC-2 restate the thresholds. |
| 8 | Sparse-graph fallback addressed | PASS | §10 Risk #1: `node_count < 50` bypasses PageRank and emits full listing, logged as `repomap.bypass.sparse_graph`. Config knob `min_nodes_for_rank` documented (default 50). |
| 9 | Two alternatives (BM25, embeddings) rejected with rationale | PASS | §4.5: (A) BM25 — rejected because no structural centrality signal, kept as optional tie-breaker. (B) Embeddings — rejected for new-dep cost, refresh pipeline, Phase-02 stdlib-first posture; framed as Phase-11+ follow-up. |
| 10 | Dependency on Phase 02 (NumPy) explicit | PASS | Frontmatter `Depends on:` line names Phase 02 Python runtime; §4.1 notes "NumPy is already a Phase 02 dep via `hooks/_py/`"; §4.5 repeats "NumPy is Phase 02"; §12 references the Phase 02 spec by path. |

All ten criteria pass; the spec is APPROVE-worthy. Issues below are polish, not blockers.

---

## 2. Strengths

- **Algorithm is fully specified, not gestured at.** §4.1 gives the closed-form PageRank recurrence, exact convergence tolerance, iteration cap, determinism guarantees (node-id sort, fixed NumPy seed), and BLAS-noise mitigation strategy (rank-order tests, not absolute values). A Phase-02 implementer has everything they need.
- **Weighting scheme is principled.** Edge weights are motivated (TESTS 0.4 because "tests are informative but should not dominate"), the recency multiplier caps at 1.5 with no old-file penalty, and `keyword_overlap_cap=5` prevents single-file monopolization. All three factors are bounded and deterministic.
- **Pack assembly handles the hard case.** The whole-file → partial-slice → skip ladder with a `min_slice_tokens` floor avoids the trap of packing 100 one-line slices; the top-k hard cap (25) enforces "few, relevant" over "soup." Multi-language comment-marker strategy in §10 Risk #3 shows attention to the 15-language matrix.
- **Rollout is measurable.** Four stages gated on concrete eval metrics with a single-regression revert rule. SC-1..SC-6 are all quantitative; no "looks good" judgments.
- **Graceful degradation is first-class, not an afterthought.** Missing graph, corrupt cache, NumPy solve divergence, sparse graph, empty keyword set — each has a named fallback and logging convention (`repomap.bypass.*`).
- **Alternatives are honest.** BM25 is not dismissed — it's retained as a potential tie-breaker. Embeddings are deferred with a clear upgrade path, not ruled out forever. This is mature engineering.
- **Compatibility is airtight.** Opt-in default off, additive schema change (1.0.0 → 1.1.0), placeholder-based template change (`{{REPO_MAP_PACK}}`) means non-adopting agents are unaffected. Per-project policy on "no backcompat shim" is explicitly invoked.

---

## 3. Issues

### Issue #1 (Important) — Cache-key copy is inconsistent between §3 and §4.4

**Location:** §3 in-scope bullet (line 39 of the spec) says:

> "Write-through cache `.forge/ranked-files-cache.json` keyed on `(graph_sha, keywords_hash)` so the PageRank solve runs at most once per pipeline run per query."

But §4.4 JSON schema, §6.3 config, and §8.1 `test_cache_hit_roundtrip` all use the 4-tuple `(graph_sha, keywords_hash, budget, top_k)`. The schema addition in §5.2 confirms the 4-tuple as the PRIMARY KEY on the durable mirror table.

**Why it matters:** The 4-tuple is the correct key — two agents at the same pipeline stage with different budgets (orchestrator 8 000 vs implementer 4 000) will hit the same `graph_sha`/`keywords_hash` but produce different packs. The §3 copy would suggest a cache collision that the real implementation does not have. A reader skimming scope gets the wrong mental model.

**Recommendation:** Update §3 to say "keyed on `(graph_sha, keywords_hash, budget, top_k)`". One-word fix.

### Issue #2 (Important) — `baseline_tokens_estimate` bootstrap mechanism is hand-wavy

**Location:** §6.2 says:

> "`baseline_tokens_estimate` is computed on the *first* run by temporarily disabling compaction for a dry pass — or, after rollout, pulled from `.forge/run-history.db` averages."

**Why it matters:** "A dry pass" is not defined as a pipeline mode anywhere in the codebase. `/forge-run --dry-run` stops at VALIDATE (per `CLAUDE.md` "Pipeline modes") and does not exercise implementer dispatch, so it cannot produce a baseline for the `implementer_task_*` stages. Without a concrete bootstrap strategy, `ratio` is undefined for the first N runs — which means the `/forge-insights` and SC-5 median-ratio check are both ungrounded until `run-history.db` warms up.

**Recommendation:** Pick one:
- (a) Compute `baseline_tokens_estimate` analytically as `sum(size_bytes / 3.5)` over the files that *would* have been in the full listing (cheap, deterministic, no extra run needed), and mark `baseline_source: "estimated"` in state; or
- (b) Require two consecutive runs (one OFF, one ON) on first adoption, documented as a one-time cost, and gate SC-5 until `run_count ≥ 2`.

Either is fine; the spec needs to pick one and remove the "dry pass" wording.

### Issue #3 (Suggestion) — Graph-SHA approach may thrash the cache under incremental updates

**Location:** §10 Risk #4 notes Phase-02's incremental updater writes to `code-graph.db`, which changes the file SHA; "Eventual consistency is acceptable (one stale dispatch per update)."

**Why it matters:** This is actually the *opposite* concern — the SHA changes on *every* write, which means an incremental single-file update invalidates every cache entry across all `(budget, top_k)` combinations, even though ranks for the other 999 files are unchanged. Under active development with frequent graph rebuilds, the cache hit rate could collapse toward zero, which is the scenario the cache exists to prevent.

**Recommendation:** Consider replacing the file-SHA with a content-derived SHA (e.g., `SELECT sha256(group_concat(id || '|' || updated_at ORDER BY id) FROM nodes)` plus edges), or a monotonic `graph_version` counter bumped by the builder. This is a Phase-10.1 refinement, not a blocker for initial landing — document as a follow-up in Q5 of the open-questions list, or inline in Risk #4 with "revisit if cache hit-rate telemetry drops below X %."

### Issue #4 (Suggestion) — No `repomap.bypass.failure` definition

**Location:** §11 SC-4 references `repomap.bypass.failure` events as the failure metric (target: zero). §5.3 says "on any failure … log INFO, emit a degraded pack … never block the pipeline." But the event name `repomap.bypass.failure` is not otherwise defined — only `repomap.bypass.sparse_graph` is explicitly named.

**Why it matters:** The CI gate in §11 SC-4 hinges on counting this event, but a reader cannot tell whether it means "graph missing," "NumPy divergence," "corrupt cache," or all of the above. Auditing success against SC-4 requires the event taxonomy.

**Recommendation:** In §5.3 (dispatch flow, failure branch), enumerate the three failure sub-events: `repomap.bypass.missing_graph`, `repomap.bypass.solve_diverged`, `repomap.bypass.corrupt_cache`, and state that SC-4's `repomap.bypass.failure` aggregates the three. One paragraph.

### Issue #5 (Suggestion) — Implementer budget 4 000 per task may compound badly on parallel task dispatch

**Location:** §4.4 table: implementer budget "4 000 per task."

**Why it matters:** Forge supports parallel implementer dispatch (per `CLAUDE.md` "Parallel task conflict detection"). With N parallel implementer agents each pulling a 4 000-token pack, a 5-task parallel fan-out costs 20 000 pack tokens where the current full-convention-stack listing is shared. There is no discussion of pack sharing vs per-task recomputation in parallel dispatch.

**Recommendation:** Add one paragraph to §4.4 clarifying whether parallel implementer tasks (a) share a single pack computed once at IMPLEMENT entry or (b) each get a per-task pack. If (a), note the trade-off (shared context, potentially less task-relevant ranking); if (b), acknowledge the total-token cost in §11 SC-1 so the ≥30 % target is correctly framed against parallel runs.

### Issue #6 (Nit) — `edge_weights` in §6.1 does not include `CALLS: 1.0` bullet comment

No actual issue — just confirming the config block's edge-weight table is byte-consistent with §4.1. It is. Skip.

---

## 4. Plan-Deviation Analysis

No plan deviations identified. The spec matches all WHAT_WAS_IMPLEMENTED claims:

- 12 required sections: delivered.
- No placeholders: verified by ripgrep-equivalent scan for TBD/TODO/`<...>` markers.
- No backcompat: §7 "No backwards-compat shim" explicit; §9 rollout opt-in default OFF with 20-run promotion gate, matching the "promote to ON after 20 eval runs" requirement.
- CI with eval harness: §8.3 integrates with Phase-01 harness (`.github/workflows/evals.yml` matrix axis `compaction: [off, on]`).
- NumPy via Phase 02: explicit in frontmatter, §4.1, §4.5, and §12 references the Phase-02 spec by path.

The Aider reference is genuine — the spec cites the repomap documentation, the 2023 blog post, and the graph.py source — and the PageRank parameters (d=0.85) and file-granular output mirror Aider's production setup.

---

## 5. Final Verdict

**APPROVE with 2 minor revisions (Issues #1 and #2) before implementation.**

Issues #3–#5 are Phase-10.1 polish and can be tracked as follow-up items in the open-questions list; none should block the start of implementation.

The design is rigorous, measurable, and honest about trade-offs. It is the strongest spec in the Phase 10 batch I have reviewed. Fix the cache-key copy and pin down the baseline bootstrap, and this is ready to build.

---

## 6. Files Referenced

- Spec under review: `/Users/denissajnar/IdeaProjects/forge/docs/superpowers/specs/2026-04-19-10-repo-map-pagerank-design.md`
- Phase 01 harness (dependency): `/Users/denissajnar/IdeaProjects/forge/docs/superpowers/specs/2026-04-19-01-evaluation-harness-design.md`
- Phase 02 Python runtime (dependency): `/Users/denissajnar/IdeaProjects/forge/docs/superpowers/specs/2026-04-19-02-cross-platform-python-hooks-design.md`
- Code graph schema (to be modified): `/Users/denissajnar/IdeaProjects/forge/shared/graph/code-graph-schema.sql`
- State schema (to be modified): `/Users/denissajnar/IdeaProjects/forge/shared/state-schema.md`
- PREFLIGHT constraints (to be modified): `/Users/denissajnar/IdeaProjects/forge/shared/preflight-constraints.md`
