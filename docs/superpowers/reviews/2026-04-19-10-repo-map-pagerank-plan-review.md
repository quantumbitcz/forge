# Phase 10 — Repo-Map PageRank Implementation Plan Review

**Plan:** `/Users/denissajnar/IdeaProjects/forge/docs/superpowers/plans/2026-04-19-10-repo-map-pagerank-plan.md`
**Spec:** `/Users/denissajnar/IdeaProjects/forge/docs/superpowers/specs/2026-04-19-10-repo-map-pagerank-design.md`
**Spec review:** `/Users/denissajnar/IdeaProjects/forge/docs/superpowers/reviews/2026-04-19-10-repo-map-pagerank-spec-review.md`
**Reviewer:** Senior Code Reviewer
**Date:** 2026-04-19
**Verdict:** **APPROVE with minor revisions**

---

## 1. Criteria Checklist

| # | Criterion | Status | Evidence |
|---|---|---|---|
| 1 | writing-plans format (frontmatter, task checklists, TDD Red/Green/Commit, review gates) | PASS | Frontmatter block with Goal/Architecture/Tech Stack/Review-issue resolutions. Each of the 16 tasks uses the canonical 5-step sequence: write failing test → run (expect fail) → implement → run (expect pass) → commit. Checkbox `- [ ]` syntax throughout. Sub-skill line at top invokes `superpowers:subagent-driven-development` / `superpowers:executing-plans`. |
| 2 | No placeholders (TBD / TODO / `<...>`) | PASS | Scan of the 2 312-line plan shows no `TBD`, `TODO`, `FIXME`, `<placeholder>`, or "implement later" markers. Every referenced symbol (`assemble_pack`, `score_files`, `run_pagerank`, `compute_graph_sha`, `compute_keywords_hash`, `PackCache`, `extract_keywords`, `FileScore`, `PackConfig`, `RecencyConfig`, `CachedPack`) is defined in the task that introduces it. Self-audit at the bottom of the plan confirms. |
| 3 | Cache-key 4-tuple used consistently throughout | PASS | 4-tuple `(graph_sha, keywords_hash, budget, top_k)` is used identically in: Task 2 (`compute_graph_sha`, `compute_keywords_hash` helpers), Task 6 (`PackCache._key`, `CachedPack` dataclass), Task 8 (SQL `PRIMARY KEY (graph_sha, keywords_hash, budget, top_k)`), Task 13 (spec-text fix to §3). Test `test_cache_miss_on_any_tuple_component_change` explicitly mutates each of the four components. |
| 4 | Each task commits | PASS | Tasks 1–15 each terminate with a `git add ... && git commit -m "..."` step. Task 16 is verification-only (documented as such) and ends with an optional annotated tag `phase10-land-dark`. Commit messages follow `feat(phase10):` / `docs(phase10):` Conventional Commits, consistent with the project's `shared/git-conventions.md`. |
| 5 | Spec coverage (PageRank, pack assembly, cache, bypass thresholds, integration hooks) | PASS | Explicit spec-coverage map at the bottom of the plan (lines 2277–2309) maps every spec subsection (§3, §4.1, §4.2, §4.3, §4.4, §5.1–5.2, §6.1, §6.2, §6.3, §7, §8.1, §8.2, §8.3, §9, §10, §11) to the implementing task(s). All 12 spec sections are accounted for. Integration hooks: Task 10 wires `fg-100-orchestrator` (8 000 budget), `fg-200-planner` (10 000), `fg-300-implementer` (4 000 per task). |
| 6 | Review feedback addressed (Issues #1, #2, #3) | PASS | Review-issue resolution block (plan lines 11–17) explicitly maps each spec-review issue to the implementing task: Issue #1 (4-tuple cache key) → Task 13 spec edit + consistent use in Tasks 2, 6, 8. Issue #2 (baseline bootstrap) → analytical `sum(size_bytes)/3.5` in Task 7, state field `baseline_source` in Task 11, spec edit in Task 13 §6.2. Issue #3 (content-derived graph hash, not file SHA) → Task 2 `compute_graph_sha` over `id\|updated_at` projection, test `test_graph_sha_is_content_derived_stable_under_noop_touch` in Task 2, spec edit §10 Risk #4 in Task 13. Bonus: Issues #4 (bypass event taxonomy) and #5 (per-task packs for parallel implementer) are also resolved in Tasks 7, 10, 13. |
| 7 | NumPy dep via Phase 02 explicit | PASS | Plan frontmatter Tech Stack line: "NumPy (Phase 02 dep)". Task 3 Step 3 imports `numpy as np`. Task 14 CI step installs via `python3 -m pip install -r hooks/_py/requirements.txt` — i.e., Phase 02's already-declared runtime dependency file, not a new one. No new runtime deps introduced in this phase. |
| 8 | Bypass event taxonomy (sparse / missing / diverged / corrupt) defined | PASS | Four named events defined identically across five locations: (a) Task 2 module docstring in `hooks/_py/repomap.py`; (b) Task 7 CLI fallbacks (`_log_bypass("repomap.bypass.missing_graph")`, etc.); (c) Task 11 state-schema `bypass_events` object; (d) Task 12 reference doc table; (e) Task 13 spec edit §5.3. SC-4 aggregate rule (`repomap.bypass.failure = {missing_graph, solve_diverged, corrupt_cache}`, excluding `sparse_graph`) is repeated consistently. Tests cover sparse (Task 7 `test_sparse_graph_bypass`), missing (`test_missing_graph_degrades`), diverged (Task 3 raises `RuntimeError("repomap.bypass.solve_diverged")`), corrupt (Task 6 `test_cache_corrupt_returns_empty_and_logs`). |
| 9 | 20-run CI graduation gate | PASS | Task 15 creates `shared/rollout/repomap-graduation.md` with explicit 5-metric gate table (G1 composite ≥ −2.0, G2 token reduction ≥ 30 %, G3 elapsed ≤ +5 %, G4 `repomap.bypass.failure` = 0, G5 median `overall_ratio` ≥ 0.25), all "across 20 consecutive passing master eval runs." Single-regression revert rule stated. Reviewer action checklist documented. Contract test `tests/contract/claudemd_phase10_entry.bats` asserts "20" and "composite" and "30 %" tokens appear. |
| 10 | Integration hooks for orchestrator / planner / implementer | PASS | Task 10 edits all three agents with explicit per-agent budgets: orchestrator `{{REPO_MAP_PACK:BUDGET=8000:TOPK=25}}`, planner `BUDGET=10000`, implementer `BUDGET=4000` (per-task). Each agent section names `prompt_compaction.enabled` as the gate and describes graceful fallback to prior full listing on bypass. Contract test `tests/contract/repomap_placeholder.bats` enforces the three budget constants. |

All 10 criteria pass. The plan is APPROVE-worthy; the issues below are polish, not blockers.

---

## 2. Strengths

- **Self-contained review-issue resolution block at the top of the plan.** The first 20 lines map every spec-review issue (including #4 and #5 which were "Suggestions") to the implementing task, with the chosen design option named. A reader who has not read the spec review still knows what changed and why.
- **Executable code is shown inline, not promised.** Every task's Step 3 is concrete Python / SQL / YAML. No handwaving about "then implement the scoring function" — the scoring function *is* in the plan, 75 lines of it with type hints and docstrings. This matches the project's "plan = enough detail that a fresh agent can execute" standard.
- **TDD cadence is disciplined.** Every task's Step 1 is the failing test, Step 2 runs it and names the expected error (`ImportError`, `ModuleNotFoundError`), Step 3 implements, Step 4 re-runs and names the expected pass count. No "implement and then write a test" inversions. Determinism, bounds, and cap behaviors all have tests before the code.
- **Task sizing is right.** Tasks 1–7 are the algorithm+cache core (each testable in isolation); Tasks 8–12 are schema/doc/state wiring (contract tests); Tasks 13–15 are documentation and rollout; Task 16 is verification. No task ships more than one concept; no task is so small it should have merged with a neighbor.
- **The 4-tuple cache key is defended, not just stated.** The Task 13 spec edit explicitly writes *why* the 2-tuple would have caused collisions ("orchestrator 8 000 vs implementer 4 000 produce different packs"). This level of care with minor review issues is how compounding mistakes are prevented.
- **Bypass events are plumbed end-to-end.** Sparse / missing / diverged / corrupt appear as string constants in the module docstring, as `_log_bypass` calls in the CLI, as `state.json.prompt_compaction.bypass_events` counters, as a troubleshooting table in `pagerank-sql.md`, and as rollout gate G4. There is exactly one definition and five consistent consumers.
- **Graduation gate is falsifiable.** G1–G5 are all quantitative with explicit field sources in `state.json`. The revert rule ("single regression resets the counter, P1 issue filed, code stays shipped") separates code reverts from flag reverts — mature rollout design.
- **Self-review section at the bottom.** Lines 2277–2313 include a spec-coverage map, a placeholder scan, and a type-consistency audit. The reviewer has already done half of the reviewer's job; the plan author has raised the floor on the review process itself.

---

## 3. Issues

### Issue #1 (Important) — `_estimate_tokens` uses a broken integer-division expression

**Location:** Task 5, Step 3, line 885 of the plan:

```python
def _estimate_tokens(size_bytes: int) -> int:
    return max(1, int(-(-size_bytes // 1) / _BYTES_PER_TOKEN))
```

**Why it matters:** The `-(-x // 1)` idiom is the "ceiling-divide" trick, but here the divisor is `1` (a no-op), not `_BYTES_PER_TOKEN`. The expression reduces to `int(size_bytes / 3.5)`, which is floor, not ceiling, and the negation pair is dead code. The spec §4.3 specifies `ceil(size_bytes / 3.5)`; the test `test_budget_honored_whole_files` uses 1 000-byte files which hit `int(1000/3.5) = 285` not `286`, so the test happens to pass, but on edge sizes (e.g. 7 bytes → `int(7/3.5) = 2`, ceiling would give `2` too; 8 bytes → floor `2`, ceiling `3`) the budget accounting is off-by-one downward, which under-counts pack tokens and can let the assembler exceed the budget by ≤ N tokens for N included files.

**Recommendation:** Replace with the correct ceiling-divide:

```python
def _estimate_tokens(size_bytes: int) -> int:
    # ceil(size_bytes / 3.5) = ceil((size_bytes * 10) / 35)
    return max(1, (size_bytes * 10 + 34) // 35)
```

Or, more readably:

```python
import math
def _estimate_tokens(size_bytes: int) -> int:
    return max(1, math.ceil(size_bytes / _BYTES_PER_TOKEN))
```

Either is one-line. Add a test asserting `_estimate_tokens(8) == 3` (floor gives 2) to lock in the ceiling semantics.

### Issue #2 (Important) — `schema_metadata` table is assumed to exist but not declared in the plan's SQL

**Location:** Task 8, Step 3, lines 1478–1480:

```sql
INSERT OR REPLACE INTO schema_metadata(key, value)
VALUES ('schema_version', '1.1.0');
```

**Why it matters:** The plan appends this INSERT but never declares `schema_metadata` in the Phase 10 delta. If `schared/graph/code-graph-schema.sql` does not already define it, the schema load fails with `no such table: schema_metadata`. The contract test `schema applies cleanly in a fresh sqlite DB` (Task 8 line 1442) runs the full schema file into a fresh DB and would catch this in CI — but only if the existing file defines `schema_metadata`. Worth either (a) verifying the pre-existing file before landing, or (b) adding `CREATE TABLE IF NOT EXISTS schema_metadata(key TEXT PRIMARY KEY, value TEXT)` to the Phase 10 delta defensively. The latter is one line and removes a dependency on assumed pre-state.

**Recommendation:** Prepend to the Task 8 SQL block:

```sql
CREATE TABLE IF NOT EXISTS schema_metadata (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
);
```

Note it explicitly as "defensive; idempotent if already present."

### Issue #3 (Suggestion) — Task 9 touches only one framework template, not all 21

**Location:** Task 9, Step 4 edits `modules/frameworks/spring/forge-config-template.md` only. The contract test `at least one framework template declares the new block` (line 1517) accepts this.

**Why it matters:** The plan ships the config block to one of 21 frameworks. Users on `modules/frameworks/react`, `axum`, `fastapi`, etc. who run `/forge-init` will get their framework's default `forge-config.md` without the `prompt_compaction` block, which means they cannot opt in without hand-editing. This is *functionally* fine — the code defaults to `enabled: false` when the key is missing — but the rollout stage 3 guidance ("users flip the flag") becomes "find and edit the block that does not exist yet." In a multi-framework codebase this is a real friction point during dogfood.

**Recommendation:** Either (a) add a Task 9.5 that fans out the block to all 21 `forge-config-template.md` files using a sed/awk loop shown inline (10-min mechanical change), or (b) document explicitly in the plan that framework templates will be updated in a follow-up PR before rollout stage 3, and add a contract test asserting the block appears in all 21 once that PR lands. Option (a) is cleaner because it keeps Phase 10 self-contained.

### Issue #4 (Suggestion) — Windows determinism is asserted but not platform-gated in tests

**Location:** Task 14 eval matrix includes `windows-latest`. Task 3 PageRank test asserts `ranks[1] > ranks[2]` and `sum(ranks) ≈ 1.0`.

**Why it matters:** The plan notes BLAS variance between macOS Accelerate and Linux OpenBLAS, mitigates via rank-*order* assertions (not absolute values), and adds a `1e-6` tolerance. Windows NumPy uses yet another BLAS (typically Intel MKL via pip wheels). The plan does not explicitly test or document Windows behavior. Rank *order* should still hold — that's the whole point of the mitigation — but the small 3-node fixture in `test_pagerank_hub_ranks_highest` has PR values close enough that MKL's slightly different rounding could, in principle, flip a near-tie. Unlikely at 3 nodes with the given edge asymmetry, but worth one defensive test.

**Recommendation:** Add one test to Task 3: `test_pagerank_cross_platform_margin` — on a 5-node graph with `CALLS` edges designed to produce rank gaps ≥ 0.05, assert the top-3 ordering survives under `_TOLERANCE = 1e-8` (tighter). This catches any platform where BLAS noise exceeds 1e-6 before a real pipeline sees it. Cost: 10 lines of fixture + assertion.

### Issue #5 (Suggestion) — `run_evals.py` and `gate_composite_delta.py` are acknowledged as Phase 01 deps with a fallback-stub clause

**Location:** Task 14, note after Step 5 (line 2124): "if they do not yet exist in your branch, create stubs…"

**Why it matters:** The plan correctly identifies the Phase 01 dependency and offers a stub escape hatch, but does not specify the stub's contract rigorously enough for a fresh agent to implement consistently with Phase 01's eventual harness. If Phase 01 lands on a different stub shape, the matrix CI silently starts measuring different things. The existing `state.json.final_score` field reference (line 2206) is concrete; the scenario YAML assertion keys (`tokens_orchestrator_planner_delta_ratio`, `composite_score_delta`, `elapsed_delta_ratio`, `repomap_bypass_failure_count`) are conventional-but-novel and would need a stable definition in one of the two harness scripts.

**Recommendation:** Either (a) reference `docs/superpowers/specs/2026-04-19-01-evaluation-harness-design.md` explicitly at Task 14 Step 5 (with the section that defines these metric keys), or (b) in Task 14 append a brief "metric contract" block listing the 4 assertion keys, each's source field in `state.json`, and the arithmetic (e.g., `elapsed_delta_ratio = (on.elapsed_ms - off.elapsed_ms) / off.elapsed_ms`). Option (b) makes the scenario YAML self-contained even if Phase 01 shifts. ~15 lines.

---

## 4. Plan-Deviation Analysis

No deviations from the spec or the spec review. Every named item from WHAT_WAS_IMPLEMENTED is present:

- **PageRank over nodes/edges:** Task 3, damping 0.85, tolerance 1e-6, cap 100 iters — matches spec §4.1 exactly.
- **Token-budget pack assembly:** Task 5, whole → slice → skip ladder, top-k hard cap 25, `min_slice_tokens` floor — matches spec §4.3.
- **4-tuple cache:** Tasks 2, 6, 8, 13 — matches the spec review's Issue #1 resolution.
- **Content-derived hash:** Task 2 `compute_graph_sha` projection — matches spec review Issue #3 resolution.
- **Bypass thresholds:** `min_nodes_for_rank` default 50 (Task 7), configurable — matches spec §10 Risk #1.
- **16 tasks:** Tasks 1–16 present; Task 16 is verification-only (correctly labeled).

Bonus items (not in WHAT_WAS_IMPLEMENTED but delivered):

- Parallel-implementer per-task pack decision (spec review Issue #5) addressed in Task 10 Step 5 and Task 13 Step 5.
- Rollout graduation doc as a first-class artifact at `shared/rollout/repomap-graduation.md`.
- CLAUDE.md entry assigned category index `F32` (consistent with F29–F31 progression).

---

## 5. Final Verdict

**APPROVE with 2 minor revisions (Issues #1 and #2) before implementation lands.**

Issue #1 is a real off-by-one in budget accounting; fix before Task 5 commits. Issue #2 is a defensive schema DDL one-liner; fix before Task 8 commits. Issues #3–#5 are polish that can be tracked as follow-up tasks in the Phase 10 rollout PR or deferred to a Phase 10.1 cleanup PR.

The plan is rigorous, complete, and executable. The review-issue resolution table at the top, the inline code samples at every step, the TDD cadence, and the self-review audit at the bottom are all hallmarks of a plan written by someone who expects it to be executed by a fresh agent without re-reading the spec. That is the standard.

Combined with the already-APPROVED spec (with the 3 minor revisions now folded into Task 13), Phase 10 is ready to build after the two fixes above.

---

## 6. Files Referenced

- Plan under review: `/Users/denissajnar/IdeaProjects/forge/docs/superpowers/plans/2026-04-19-10-repo-map-pagerank-plan.md`
- Spec: `/Users/denissajnar/IdeaProjects/forge/docs/superpowers/specs/2026-04-19-10-repo-map-pagerank-design.md`
- Spec review: `/Users/denissajnar/IdeaProjects/forge/docs/superpowers/reviews/2026-04-19-10-repo-map-pagerank-spec-review.md`
- Target modules (new): `/Users/denissajnar/IdeaProjects/forge/hooks/_py/repomap.py`, `/Users/denissajnar/IdeaProjects/forge/hooks/_py/keyword_extract.py`, `/Users/denissajnar/IdeaProjects/forge/shared/graph/pagerank-sql.md`, `/Users/denissajnar/IdeaProjects/forge/shared/rollout/repomap-graduation.md`
- Target modules (modified): `/Users/denissajnar/IdeaProjects/forge/shared/graph/code-graph-schema.sql`, `/Users/denissajnar/IdeaProjects/forge/agents/fg-100-orchestrator.md`, `/Users/denissajnar/IdeaProjects/forge/agents/fg-200-planner.md`, `/Users/denissajnar/IdeaProjects/forge/agents/fg-300-implementer.md`, `/Users/denissajnar/IdeaProjects/forge/shared/state-schema.md`, `/Users/denissajnar/IdeaProjects/forge/shared/preflight-constraints.md`, `/Users/denissajnar/IdeaProjects/forge/CLAUDE.md`, `/Users/denissajnar/IdeaProjects/forge/.github/workflows/evals.yml`
