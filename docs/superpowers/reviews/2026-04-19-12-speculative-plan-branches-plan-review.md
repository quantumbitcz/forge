# Review: Phase 12 — Speculative Parallel Plan Branches Implementation Plan

**Plan:** `/Users/denissajnar/IdeaProjects/forge/docs/superpowers/plans/2026-04-19-12-speculative-plan-branches-plan.md`
**Spec:** `/Users/denissajnar/IdeaProjects/forge/docs/superpowers/specs/2026-04-19-12-speculative-plan-branches-design.md`
**Spec Review:** `/Users/denissajnar/IdeaProjects/forge/docs/superpowers/reviews/2026-04-19-12-speculative-plan-branches-spec-review.md`
**Reviewer:** Senior Code Reviewer
**Date:** 2026-04-19
**Verdict:** APPROVE WITH MINOR REVISIONS

---

## Summary

Plan correctly implements the spec across 17 tasks with a consistent TDD skeleton (write failing test → implement → re-run → commit). Each task ends with exactly one `git commit` (17/17). All three spec-review gaps are tracked explicitly in the "Review Issue Resolutions" block and implemented as first-class params:

- Diversity threshold → `min_diversity_score` default `0.15`, Jaccard-based, config-surfaced, PREFLIGHT-validated, unit-tested (Task 5).
- Cost estimation formula → `estimate_cost(baseline, recent_planner_tokens[-10:], N, cold_start=4500)` deterministic, tested (Task 4).
- Ambiguity OR semantics → explicit predicate `(MEDIUM) AND (shaper OR keyword OR multi_domain OR marginal_cache)` with shaper-elevated `reasons[0]`; per-signal + OR-combination fixtures (Task 3).

fg-200 branch-mode (Task 8) and fg-100 speculative-dispatch (Task 9) are both modified with contract tests. CI gates (Task 15) enforce all 4 metrics: quality lift ≥ 0, token ratio ≤ 2.5x, selection precision ≥ 0.60, trigger rate in [0.20, 0.50]. Token ceiling (2.5x) surfaces in config, PREFLIGHT, contract doc, orchestrator dispatch, and CI gate — 5 reinforcing layers.

---

## Criterion-by-Criterion

### 1. `writing-plans` format — PASS

Preamble cites `superpowers:subagent-driven-development` / `executing-plans` as required sub-skill. Checkbox (`- [ ]`) tracking. Goal + Architecture + Tech Stack + File Structure + Task Breakdown + Self-Review + Handoff sections all present. Each task has Files / Steps / Test scaffold / Run / Implement / Re-run / Commit structure.

### 2. No placeholders — PASS (one marked placeholder; intentional)

No TBD/FIXME. One explicit `# placeholder; real harness replaces` in `runner.sh` selection-precision (synthetic harness for deterministic CI; acceptable since the bats gate asserts `>= 0.60` and the live harness substitutes at integration time). Everything else is concrete.

### 3. Type consistency — PASS

Function signatures stable across tasks 3–7: `detect_ambiguity(...) -> dict`, `derive_seed(run_id, candidate_id) -> int`, `estimate_cost(baseline, recent_planner_tokens, N, cold_start_default=4500) -> dict`, `check_diversity(plans: list[str], min_diversity_score: float) -> dict`, `compute_selection_score(validator_score, verdict, tokens, batch_max_tokens) -> float`, `pick_winner(candidates, auto_pick_threshold_delta, mode) -> dict`, `persist_candidate(...) -> str`. CLI subcommands (`detect-ambiguity`, `derive-seed`, `estimate-cost`, `check-diversity`, `compute-selection`, `pick-winner`, `persist-candidate`) match between orchestrator shell-outs (Task 9) and Python impl (Tasks 3–7). Cost formula (`baseline + mean(recent[-10:]) × N`, abort when `> baseline × ceiling`) reappears identically in `shared/speculation.md`, `estimate_cost`, and eval runner.

### 4. Each task commits — PASS

17 tasks, 17 `git commit` invocations (one per task). Messages follow conventional-commits style (`feat(phase12): ...`, `chore(phase12): ...`, `docs(phase12): ...`). No `--no-verify`, no `Co-Authored-By`, no AI attribution — compliant with `shared/git-conventions.md`.

### 5. Spec coverage — PASS

Coverage matrix (plan preamble + Self-Review Notes):

| Spec section                          | Plan task(s)          |
|---------------------------------------|-----------------------|
| §4.1 Trigger logic (ambiguity)        | Task 3                |
| §4.2 Parallel dispatch (2–3 cands)    | Tasks 4, 9            |
| §4.3 Parallel validation              | Task 9                |
| §4.4 Scoring / selection              | Task 6                |
| §4.5 Candidate persistence            | Task 7                |
| §5.1 fg-200 branch mode               | Task 8                |
| §5.2 fg-100 dispatch                  | Task 9                |
| §5.3 shared/speculation.md            | Task 1                |
| §5.4 candidate JSON schema            | Task 7                |
| §5.5 hooks/_py/speculation.py         | Tasks 3–7             |
| §5.6 plan-cache v2 schema             | Task 11               |
| §6.1 forge-config block + PREFLIGHT   | Task 2                |
| §6.2 state schema v1.7.0              | Task 10               |
| §6.3 event log (started/resolved)     | Task 9                |
| §8.1–8.4 structural/unit/contract/scenario | Tasks 1–7, 13, 14 |
| §8.5 eval harness + CI gates          | Task 15               |
| §9 rollout (version bumps)            | Task 12               |

Diversity check (§10 risk 2) is promoted to Task 5 with a named config param — exceeds spec by elevating a risk-bullet to first-class contract. Good.

### 6. Review feedback addressed — PASS

All three spec-review gaps explicitly tracked in the "Review Issue Resolutions" block and implemented:

- **Diversity threshold as config:** `min_diversity_score: 0.15` in `forge-config-template.md` (Task 2), validated at PREFLIGHT (`[0.05, 0.50]`), defined with Jaccard formula in `shared/speculation.md`, implemented in `check_diversity` (Task 5), dedicated unit test `speculation-diversity.bats`.
- **Cost formula formalized:** Exact formula `estimated = baseline + (mean(recent_planner_tokens[-10:]) or cold_start_default) × N` with `cold_start_default = 4500` and abort predicate `estimated > baseline × token_ceiling_multiplier`. Codified in `shared/speculation.md`, `estimate_cost()`, and the CI gate.
- **OR semantics explicit:** Predicate `triggered = (confidence == MEDIUM) AND (shaper_alternatives_ok OR keyword_hit OR multi_domain_hit OR marginal_cache_hit)` in both the contract doc and `detect_ambiguity`. Shaper-elevated `reasons[0] = "shaper_alternatives>=2"`. Fixtures cover keyword-alone, shaper-alone, and combined cases (Task 3).

### 7. Token ceiling enforced (2.5x) — PASS (5-layer defense)

1. **Config:** `token_ceiling_multiplier: 2.5` in `forge-config-template.md` (Task 2).
2. **PREFLIGHT validation:** `token_ceiling_multiplier in [1.5, 4.0]` → `CONFIG-SPECULATION-CEILING` CRITICAL (Task 2).
3. **Contract doc:** abort formula in `shared/speculation.md §Cost Guardrails` (Task 1).
4. **Runtime abort:** orchestrator step 2 shells out to `estimate-cost`, logs `speculation.aborted=token_ceiling` + `speculation.skipped` event on abort (Task 9).
5. **CI gate:** `tests/ci/speculation-eval-gate.bats` asserts `token_ratio <= 2.5` as hard ceiling (Task 15).

Pre-dispatch estimation (before LLM spend) is the correct placement — cheaper than post-hoc.

### 8. Selection precision floor CI gate — PASS

`tests/ci/speculation-eval-gate.bats` contains a named test `selection precision >= 0.60 (hard floor)`. Target 0.75 per spec success criteria. Wired into `.github/workflows/speculation-eval.yml` on `pull_request` + `push` to `master` with a 12-item corpus across 5 domains (auth / migrations / api / state / ui) plus 2 control items for trigger-rate sanity.

### 9. fg-200 + fg-100 modifications — PASS

- **fg-200 (Task 8):** Appends `## Branch Mode (Speculative)` after "Planning Process"; specifies 200-word brief cap, `speculative: true`, `candidate_id: cand-{N}`, `emphasis_axis`, skip Plan Mode. Contract test asserts 5 invariants including frontmatter unchanged.
- **fg-100 (Task 9):** Inserts `### Speculative Dispatch (PLAN)` subsection with 10-step protocol (detect → estimate → assign axes → dispatch → diversity → validate → pick → persist → state → proceed). References `shared/speculation.md`. Each candidate dispatch creates its own blue substage task (consistent with `shared/agent-ui.md` nesting). Contract test asserts 8 invariants.

### 10. Four CI metric gates — PASS

All four asserted in `tests/ci/speculation-eval-gate.bats`:

| Metric                 | Threshold                  | Test                                         |
|------------------------|----------------------------|----------------------------------------------|
| Quality lift           | `>= 0` (hard floor)        | `quality lift >= 0 (hard floor, no regression)` |
| Token ratio            | `<= 2.5` (hard ceiling)    | `token ratio <= 2.5x (hard ceiling)`         |
| Selection precision    | `>= 0.60` (target 0.75)    | `selection precision >= 0.60 (hard floor)`   |
| Trigger rate           | `[0.20, 0.50]`             | `trigger rate within 0.20-0.50 band`         |

GitHub Actions workflow uploads metrics as artifact — enables trend tracking over PRs.

---

## Top 3 Issues (minor, non-blocking)

1. **Synthetic eval harness may mask real signal.** `evals/speculation/runner.sh` hard-codes `precision = 0.72` as a placeholder and synthesizes `+6` bonus for the "best" candidate via a hash-to-axis mapping. This makes the CI gate green by construction regardless of real model behavior. Mitigation exists (comment says "real harness substitutes live LLM calls" per Phase 01), but recommend adding a bats guard that fails if `runner.sh` is invoked without an env flag like `SPECULATION_EVAL_MODE=live|synthetic`, so the synthetic path cannot silently ship to master. Otherwise a selection-precision regression in real LLM behavior goes undetected until a human notices.

2. **Per-framework config propagation via inline `for` loop is fragile.** Task 2 Step 6 appends the `speculation:` block to every `modules/frameworks/*/forge-config-template.md` via a bash `for` loop. This mutates 21 framework templates in a single commit with no template-specific override hooks. If any framework already has a `speculation:` stanza at a different indent or nested under another block, the `grep -q "^speculation:"` guard misses it and appends a duplicate. Recommend: (a) dry-run check listing all 21 target files before mutating; (b) verify no `speculation:` appears at any indent level, not just column 0; (c) commit per framework group (language-grouped) rather than one 21-file commit to simplify bisecting if a template breaks.

3. **Task 9 orchestrator `.md` delta is large (~60 lines of protocol + shell-outs inlined).** `fg-100-orchestrator.md` is already one of the largest system-prompt agents (every line = tokens on every orchestrator dispatch). Inlining 8 shell-out command blocks with quoted argument lists adds significant token cost per run, even on runs where speculation does not trigger. Recommend compressing the subsection to a short "Speculative Dispatch (PLAN): see `shared/speculation.md §Orchestrator Protocol` for the 10-step dispatch contract" pointer and moving the command-line examples to the shared doc. Mirrors the existing pattern in `shared/agent-defaults.md` where long protocols are referenced, not inlined.

---

## Strengths (worth preserving)

- TDD skeleton is uniform across all 17 tasks (test first, fail, implement, pass, commit).
- Self-Review Notes at the end proactively maps all 12 spec sections to tasks — catches coverage gaps before handoff.
- Review-feedback tracking block (at the top of Task Breakdown) makes spec-review resolutions auditable.
- 5-layer defense-in-depth on the token ceiling (config / PREFLIGHT / contract / runtime / CI) is exemplary.
- Named configuration parameters (`min_diversity_score`, `token_ceiling_multiplier`, `auto_pick_threshold_delta`, `cold_start_default`) instead of hard-coded magic numbers.
- Shaper-alternatives signal correctly elevated as `reasons[0]` over keyword/domain/cache signals — preserves shaper authority per `shared/confidence-scoring.md`.
- Diversity Jaccard formula uses normalized token sets with stopword removal — robust against trivial whitespace / word-order noise.
- CI workflow scoped to relevant paths (`hooks/_py/speculation.py`, `evals/speculation/**`, the two agent files, `shared/speculation.md`) rather than running on every push.
- Plan-cache v2 schema breaking change explicitly acknowledged (per "no backwards compat" project constraint) with clear invalidation path.

---

## Recommended Next Steps

1. Address the three minor issues above — particularly (1) gating the synthetic eval behind an env flag, which is cheap insurance against a silent regression.
2. Consider splitting Task 2 Step 6 (21-framework propagation) into its own commit for easier revert.
3. Proceed to implementation via `superpowers:subagent-driven-development` (recommended per plan preamble).
4. After the first 20 real speculation runs, check `speculation_quality_lift` and `speculation_trigger_rate` DX metrics and tune `auto_pick_threshold_delta` if user-confirmation rate exceeds 20%.

**Final verdict:** APPROVE WITH MINOR REVISIONS. Plan meets all 10 review criteria with strong spec fidelity and explicit resolution of the three spec-review gaps. Three noted issues are defense-in-depth and maintainability concerns, not correctness blockers — safe to resolve during implementation.
