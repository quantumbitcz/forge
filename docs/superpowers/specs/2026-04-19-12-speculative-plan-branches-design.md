# Phase 12: Speculative Parallel Plan Branches — Design Spec

**Status:** Draft
**Date:** 2026-04-19
**Priority:** P2
**Audit:** W13
**Phase:** 12 / A+ roadmap

---

## 1. Goal

At PLAN stage for ambiguous requirements, spawn 2-3 candidate plans in parallel, validate each via `fg-210-validator`, and select the highest-scored plan (with user confirmation when top candidates cluster within threshold), raising pipeline quality on option-rich requirements without re-architecting the planner.

---

## 2. Motivation

**Audit reference:** W13 — single-plan PLAN stage does not explore the option space for ambiguous requirements; validator `REVISE` loop is costly (~5-10 min per iteration) compared to parallel speculation.

**External evidence:**

- **Codex parallel agents (Feb 2026)** — https://docs.kanaries.net/topics/AICoding/parallel-code-agents — reports ~30% speedup from dispatching parallel candidate agents at decision points, choosing best via structured evaluation.
- **Verdent 2026 analysis** — https://www.verdent.ai/guides/codex-app-first-impressions-2026 — confirms parallel speculation improves plan quality and reduces user rework on ambiguous tasks; quality lift dominates wall-clock gain.
- **GPT Pro parallel reasoning** — https://openai.com/index/introducing-gpt-pro/ — established the "best-of-N sampling at decision points" pattern for complex planning tasks.

Forge's PLAN stage is exactly such a decision point: validator `REVISE` implicitly acknowledges that the first plan attempt was suboptimal. Paying ~2.5x plan tokens up-front (once) is cheaper than a REVISE loop (plus downstream rework when a mediocre plan ships).

**Trigger asymmetry:** High-confidence requirements don't need speculation; low-confidence requirements should route to `/forge-shape`. The sweet spot is MEDIUM-confidence requirements with multiple viable approaches — precisely what this phase targets.

---

## 3. Scope

### In

- **Ambiguity detection** at PLAN entry using two signals:
  - Shaper-flagged multi-approach ambiguity (`state.shaper_output.alternatives[]` length ≥ 2 with similar strength).
  - Plan-time confidence = MEDIUM (per `shared/confidence-scoring.md` 4-dimension gate).
- **Speculative dispatch**: N candidate `fg-200-planner` invocations in parallel (N=2-3 default, configurable 2-5), each with a distinct exploration seed.
- **Diversity enforcement**: each candidate receives a different seed and an "emphasis axis" hint (simplicity / robustness / speed-to-ship) to drive genuine divergence rather than minor variations.
- **Parallel validation**: each candidate plan scored by `fg-210-validator` (reused; no new validator agent). Validator dispatches run in parallel.
- **Selection**: deterministic score ranking; tiebreak on token efficiency (lower tokens wins when scores close).
- **User confirmation** (interactive mode) when top-2 candidates score within `auto_pick_threshold_delta` (default 5 validator points).
- **Autonomous mode**: auto-pick top-ranked candidate; log runner-up hashes.
- **Candidate persistence**: losing plans written to `.forge/plans/candidates/` for inspection, retrospective, and future plan-cache seeding.
- **Plan cache integration**: cache entry schema extended to list all candidates (breaking change, acceptable per "no backwards compat").
- **State tracking**: `state.plan_candidates[]` records each candidate's id, score, verdict, tokens, selection status.

### Out

- **Speculative execution beyond PLAN** (implementation forks, multi-branch IMPLEMENT runs): explicitly out of scope. Implementation speculation would multiply pipeline cost and worktree complexity; not justified by audit.
- **Dynamic N selection** (choosing candidate count based on complexity): v1 uses fixed N; future work.
- **Cross-run candidate reuse** (suggesting a losing candidate from run A as primary for run B): future enhancement; v1 persists but does not surface them cross-run.
- **Validator re-ranking** (second-pass deliberation across candidates): v1 uses independent validator scores; future work.
- **Automatic N escalation** on validator tie: v1 returns to user / autonomous tiebreak; no recursive speculation.

---

## 4. Architecture

### 4.1 Trigger Logic

At PLAN stage entry in `fg-100-orchestrator`:

```
if not speculation.enabled:
    proceed single-plan
elif mode in {bugfix, bootstrap}:
    proceed single-plan  # reduced-validation modes skip speculation
elif confidence == HIGH:
    proceed single-plan  # no expected value
elif confidence == LOW:
    route to /forge-shape  # existing behavior; too ambiguous for speculation
elif confidence == MEDIUM:
    if shaper_output.alternatives_count >= 2 OR ambiguity_signal_hit:
        trigger speculation(N=candidates_max)
    else:
        proceed single-plan
else:
    proceed single-plan
```

Ambiguity signal sources (any one triggers when confidence is MEDIUM):

1. `fg-010-shaper` emitted ≥ 2 alternatives with similar strength scores (delta ≤ 10 pts).
2. Requirement contains ambiguity keywords ("either", "or", "could", "maybe", "consider", "multiple approaches") OR a `/` between nouns ("REST/GraphQL", "SQL/NoSQL") — regex classifier in `hooks/_py/speculation.py`.
3. Domain detection returns multiple candidate domains with similar confidence.
4. Plan cache hit similarity is in the 0.40-0.59 band (marginal match — likely multiple ways to go).

### 4.2 Parallel Dispatch

Orchestrator dispatches N parallel `fg-200-planner` subagent instances. Each dispatch includes:

- **Identical requirement + exploration context** — same input baseline.
- **Candidate id**: `cand-{N}` (e.g. `cand-1`, `cand-2`, `cand-3`).
- **Exploration seed**: integer derived from `hash(run_id + candidate_id)` to vary LLM sampling.
- **Emphasis axis** (diversity lever): one of `simplicity`, `robustness`, `velocity` — assigned round-robin. Passed as an extra instruction: "When choosing between approaches of comparable quality, prefer the {axis} option and justify it in the Challenge Brief."
- **`speculative: true` flag**: planner uses shorter Challenge Brief format (still required, but max 200 words; full brief only from the winner).

Planners run in parallel (orchestrator opens N `Agent`-tool dispatches back-to-back; harness runs them concurrently). Each returns its full plan artifact to orchestrator.

### 4.3 Parallel Validation

After all N planners return, orchestrator dispatches N parallel `fg-210-validator` invocations — one per candidate plan. Validator is unchanged; it scores each plan across 7 perspectives and emits GO / REVISE / NO-GO.

**Filtering rule** before scoring:

- Any candidate with NO-GO → eliminated outright.
- Any candidate with REVISE → eligible but penalized (see §4.4).
- All GO → score-only selection.

If **all N candidates are NO-GO** (rare): orchestrator surfaces combined findings to user with escalation options (revise manually, retry speculation with different seeds, abort). This is not auto-retried — 3+ NO-GO signals genuine requirement or domain issue.

### 4.4 Scoring & Selection

Composite selection score per candidate:

```
selection_score =
    validator_score                              (0-100)
  + verdict_bonus                                (+0 GO, -15 REVISE, —— NO-GO eliminated)
  + 0.1 × token_efficiency_bonus                 (see below)
```

**Token efficiency bonus**: `(max_tokens - candidate_tokens) / max_tokens × 100`, where `max_tokens` is the highest-token candidate in this speculation batch. Caps at 100, min 0.

This makes efficiency a tiebreaker (≤ ~10 points influence) — never dominant. Correctness drives selection; efficiency only settles ties.

**Selection rules:**

| Condition | Action |
|---|---|
| Top-1 score ≥ 80 AND delta to #2 > `auto_pick_threshold_delta` | Auto-pick top-1. Log others. |
| Top-1 score ≥ 80 AND delta to #2 ≤ `auto_pick_threshold_delta`, interactive mode | `AskUserQuestion` with top-2 summary, let user choose. |
| Top-1 score ≥ 80 AND delta to #2 ≤ threshold, autonomous mode | Auto-pick top-1. Log `[AUTO]` selection reasoning + runner-up hash. |
| All candidates score < 60 (all FAIL) | Surface finding combination to user; do not auto-proceed. |
| 60 ≤ top-1 < 80 (CONCERNS) | Fall through to existing REVISE path on that candidate — speculation done; normal plan loop resumes. |

### 4.5 Candidate Persistence

Winning plan: consumed by orchestrator as the canonical plan for the run (fed to `fg-300-implementer`).

Losing candidates: written to `.forge/plans/candidates/{run_id}/cand-{N}.json` (schema in §5). Purpose:

- **Retrospective learning**: `fg-700-retrospective` compares winner vs losers to extract patterns ("candidates emphasizing `velocity` consistently score lower on Auth domain → auto-discovered PREEMPT").
- **User inspection**: if final result is poor, user can inspect losers via `/forge-ask "show speculation candidates for last run"`.
- **Future plan-cache seeding**: losers from high-scoring runs may be opportunistically cached (future work, not v1).

Retention: candidates survive `/forge-recover reset`; removed by manual `rm -rf .forge/` or by eviction (keep last 20 runs of candidates; FIFO).

### 4.6 Alternative Architectures Considered

**Alt A: Tournament with elimination rounds.** Start with N=5 candidates, validate all, eliminate bottom 2, have remaining 3 "refine" for a second round, then validate and pick.

- **Rationale for rejection:** Doubles validator cost (10 validator runs vs 3) for marginal quality gain. The "refine" step muddies attribution — is the winner better because it was genuinely better, or because it got a second pass? Single-pass speculation is cleaner and more debuggable. Consider if empirical data shows >15% lift is left on the table.

**Alt B: Beam search.** Generate N candidates, pick top-K (e.g., top-2), expand each into N sub-candidates, validate, repeat until budget exhausted.

- **Rationale for rejection:** Token-cost exponential; unsuitable for the MEDIUM-confidence sweet spot (those requirements don't warrant deep exploration — LOW-confidence ones do, and those route to shaper). Beam search is appropriate when the problem decomposes into stages with clear fitness signals between them; PLAN stage has one fitness signal (validator), used once at the end. Also difficult to cost-cap; a single-pass fixed-N design has a predictable 2.5x ceiling.

**Chosen: Single-pass parallel speculation.** Clean attribution, predictable cost, reuses validator unchanged, easy to A/B with single-plan baseline via eval harness.

---

## 5. Components

### 5.1 Modify `agents/fg-200-planner.md`

Add **Branch Mode** section (after "Planning Process"):

```markdown
## Branch Mode (Speculative)

When orchestrator passes `speculative: true` + `candidate_id: cand-{N}` + `emphasis_axis: {simplicity|robustness|velocity}`:

1. Plan as usual, but bias approach selection toward `emphasis_axis` when ties exist.
2. Challenge Brief length cap: 200 words (vs ~400 normal). Focus on why this approach, not full alternatives.
3. Use exploration seed from orchestrator in any non-deterministic sampling decisions.
4. Skip Plan Mode (no `EnterPlanMode`/`ExitPlanMode`) — orchestrator aggregates and presents to user/validator.
5. Output same format as non-speculative plan — validator does not distinguish.

Winner will be re-asked for a full Challenge Brief if the abbreviated one is insufficient.
```

Frontmatter unchanged.

### 5.2 Modify `agents/fg-100-orchestrator.md`

Add PLAN-stage speculative dispatch logic (new subsection under PLAN):

```markdown
### Speculative Dispatch (PLAN)

If `speculation.enabled == true` AND trigger criteria met (see `shared/speculation.md`):

1. Determine N from `speculation.candidates_max` (default 3).
2. Assign emphasis axes round-robin: `simplicity`, `robustness`, `velocity`.
3. Dispatch N `fg-200-planner` instances in parallel with `speculative: true`, unique `candidate_id`, `emphasis_axis`, and derived `exploration_seed`.
4. Collect all N plans; dispatch N `fg-210-validator` instances in parallel.
5. Apply selection rules from `shared/speculation.md §Selection`.
6. Persist losers to `.forge/plans/candidates/{run_id}/`.
7. Update `state.plan_candidates[]`.
8. Proceed to winner plan for downstream stages.

If trigger criteria not met, single-plan behavior is unchanged.
```

Orchestrator UI: each candidate dispatch creates its own substage task (agent color dot blue, 3 tasks under PLAN).

### 5.3 New `shared/speculation.md`

Authoritative contract document covering:

- Trigger logic (decision table).
- Dispatch protocol (N, seed derivation, emphasis axes).
- Selection formula (including tiebreaker math).
- User-confirmation prompt shape (`AskUserQuestion` payload template for top-2 tie).
- Candidate persistence schema.
- Cost guardrails (abort speculation if estimated token budget exceeds `speculation.token_ceiling`; default 2.5x single-plan baseline).
- Eval methodology (see §8).
- Forbidden actions: no speculation outside PLAN stage; no speculation in bugfix/bootstrap modes; no speculation when `plan_cache` hit ≥ 0.60 (cached plan preferred).

### 5.4 New `.forge/plans/candidates/{run_id}/` directory schema

Each `cand-{N}.json`:

```json
{
  "schema_version": "1.0.0",
  "run_id": "2026-04-19T14-30-00-add-comments",
  "candidate_id": "cand-2",
  "emphasis_axis": "robustness",
  "exploration_seed": 847293,
  "plan_hash": "sha256:...",
  "plan_content": "...full plan markdown...",
  "validator_verdict": "GO",
  "validator_score": 87,
  "selection_score": 87.3,
  "selected": false,
  "tokens": { "planner": 4250, "validator": 2140 },
  "created_at": "2026-04-19T14:30:42Z"
}
```

Index file `.forge/plans/candidates/index.json` lists all run_ids with candidate counts for FIFO eviction.

### 5.5 New `hooks/_py/speculation.py`

Pure-Python dispatch helper (per Phase 2 cross-platform hooks spec). Exposes:

- `detect_ambiguity(requirement_text: str, shaper_output: dict, plan_cache_hit: float) -> dict`: returns `{triggered: bool, reasons: [...], confidence: "MEDIUM"|"HIGH"|"LOW"}`.
- `derive_seed(run_id: str, candidate_id: str) -> int`: deterministic `hash(run_id + candidate_id) % 2**31`.
- `compute_selection_score(validator_score: int, verdict: str, tokens: int, batch_max_tokens: int) -> float`: selection formula from §4.4.
- `pick_winner(candidates: list, auto_pick_threshold_delta: int, mode: str) -> dict`: returns `{winner_id, needs_confirmation, runners_up, reasoning}`.
- `persist_candidate(run_id: str, candidate: dict) -> str`: writes candidate JSON, updates index, runs FIFO eviction (keep last 20 runs).

Orchestrator shells out via `python3 hooks/_py/speculation.py <command> [args]` — mirrors existing Python hook patterns.

### 5.6 Plan cache integration (breaking change)

Current plan cache entry: single `plan_content` field. Phase 12 extends schema to:

```json
{
  "schema_version": "2.0.0",
  "primary_plan": { "content": "...", "hash": "...", "final_score": 94 },
  "candidates": [
    { "candidate_id": "cand-1", "emphasis_axis": "simplicity", "validator_score": 91, "plan_hash": "..." },
    { "candidate_id": "cand-2", "emphasis_axis": "robustness", "validator_score": 87, "plan_hash": "..." }
  ],
  "speculation_used": true,
  "requirement": "...",
  "requirement_keywords": [...],
  "domain_area": "...",
  "created_at": "...",
  "source_sha": "..."
}
```

Non-speculative runs omit `candidates` array; set `speculation_used: false`. Cache readers updated to new schema; `shared/plan-cache.md` doc updated.

---

## 6. Data / State / Config

### 6.1 `forge-config.md` additions

```yaml
speculation:
  enabled: true                       # master switch
  candidates_max: 3                   # N; valid range 2-5
  ambiguity_threshold: MEDIUM         # confidence band that triggers speculation; only MEDIUM supported in v1
  auto_pick_threshold_delta: 5        # if top-2 within this validator-score delta, ask user (interactive) / auto-pick (autonomous)
  save_candidates: true               # persist losers to .forge/plans/candidates/
  token_ceiling_multiplier: 2.5       # abort speculation if estimated cost > this × single-plan baseline
  emphasis_axes: [simplicity, robustness, velocity]   # rotation order; length must be >= candidates_max
  skip_in_modes: [bugfix, bootstrap]  # modes where speculation is disabled regardless of enabled flag
```

PREFLIGHT validates: `candidates_max` in [2,5]; `auto_pick_threshold_delta` in [1,20]; `token_ceiling_multiplier` in [1.5, 4.0]; `emphasis_axes` length ≥ `candidates_max`. Invalid → PREFLIGHT fails with config error.

### 6.2 State schema additions (`shared/state-schema.md` → v1.7.0)

```json
{
  "plan_candidates": [
    {
      "id": "cand-1",
      "emphasis_axis": "simplicity",
      "validator_verdict": "GO",
      "validator_score": 87,
      "selection_score": 87.3,
      "tokens": { "planner": 4120, "validator": 2080 },
      "selected": true
    }
  ],
  "speculation": {
    "triggered": true,
    "reasons": ["shaper_alternatives>=2", "confidence=MEDIUM"],
    "candidates_count": 3,
    "winner_id": "cand-1",
    "user_confirmed": false
  }
}
```

`plan_candidates: []` and `speculation: null` when speculation did not run.

### 6.3 Event log additions

Two new event types in `.forge/events.jsonl`:

- `speculation.started` — `{run_id, candidates_count, reasons, estimated_tokens}`.
- `speculation.resolved` — `{run_id, winner_id, scores: [...], user_confirmed: bool, actual_tokens}`.

### 6.4 DX metrics additions

Two metrics in `.forge/dx-metrics.json`:

- `speculation_trigger_rate`: speculations triggered / PLAN stages entered.
- `speculation_quality_lift`: rolling avg `(winner_score - mean_loser_score)` — signals whether speculation is paying off.

---

## 7. Compatibility

**Breaking changes:**

- **Plan cache schema v1.0.0 → v2.0.0.** Existing cache entries incompatible. Per project constraint ("no backwards compatibility"), cache is invalidated on upgrade. `/forge-init` post-upgrade clears `.forge/plan-cache/` if schema mismatch; user notified.
- **State schema v1.6.0 → v1.7.0.** `plan_candidates` and `speculation` fields added. State files from older runs readable (missing fields default to `[]` / `null`) — forward-compatible, but the bump is recorded.

**Non-breaking:**

- `fg-200-planner` and `fg-210-validator` unchanged in non-speculative path. Branch mode is additive (triggered only by explicit flag).
- Single-plan pipeline behavior identical when `speculation.enabled: false` — default `true`, but opt-out is one config line.
- Retrospective (`fg-700`) can ignore new fields safely; consuming them is incremental work.

**Downstream documentation updates:**

- `CLAUDE.md` — add Phase 12 feature to v2.0 features table.
- `shared/state-schema.md` — bump to v1.7.0, document new fields.
- `shared/plan-cache.md` — document v2.0 schema.
- `shared/confidence-scoring.md` — reference speculation trigger in MEDIUM band.
- `shared/preflight-constraints.md` — document speculation config validation.
- `shared/agent-role-hierarchy.md` — note parallel dispatch at PLAN.
- Test count bumps in `tests/lib/module-lists.bash`.

---

## 8. Testing Strategy

**No local test execution** (per project constraint). All tests run in CI.

### 8.1 Structural tests (`tests/structural/`)

- `speculation-config-schema.bats` — validate config fields, ranges, required arrays.
- `speculation-state-schema.bats` — validate `plan_candidates[]` and `speculation` object against schema.
- `speculation-candidate-dir.bats` — confirm `.forge/plans/candidates/` layout matches spec; check survives-reset behavior (via `/forge-recover reset` simulation fixture).

### 8.2 Unit tests (`tests/unit/`)

- `speculation-ambiguity-detector.bats` — 20+ fixtures covering: clear HIGH-confidence reqs (no trigger), MEDIUM with shaper alternatives (trigger), MEDIUM without signal (no trigger), LOW reqs (route to shaper), bugfix mode (no trigger), ambiguity keywords ("either", "/", "could"), marginal plan-cache hit (0.45 → trigger).
- `speculation-selection.bats` — selection-formula correctness: pure score, verdict penalties, token tiebreaker, all-NO-GO edge case, all-below-60 edge case, exact-tie (auto-pick reproducibility).
- `speculation-seed-derivation.bats` — determinism: same `run_id + candidate_id` → same seed; different candidate_ids → different seeds.
- `speculation-persistence.bats` — candidate JSON write, index update, FIFO eviction after 20+ runs.

### 8.3 Contract tests (`tests/contract/`)

- `fg-200-planner-branch-mode.bats` — planner frontmatter unchanged; branch-mode section present; abbreviated Challenge Brief accepted by validator.
- `fg-100-orchestrator-speculative-dispatch.bats` — orchestrator contains the speculation dispatch subsection; references `shared/speculation.md`.
- `shared-speculation-contract.bats` — `shared/speculation.md` contains all required sections (trigger, dispatch, selection, persistence, cost guardrails, eval).
- `plan-cache-v2-schema.bats` — cache readers/writers use v2 schema; v1 entries rejected with clear error.

### 8.4 Scenario tests (`tests/scenarios/`)

Simulator-based (`shared/forge-sim.sh`) scenarios:

- `speculation-happy-path.bats` — MEDIUM confidence + shaper alternatives → 3 candidates → top-1 wins decisively → state reflects speculation + winner plan used.
- `speculation-tie-interactive.bats` — top-2 within 5 points → `AskUserQuestion` fired → user selects #2 → winner updated.
- `speculation-tie-autonomous.bats` — same tie in autonomous mode → auto-pick top-1, log runner-up.
- `speculation-all-no-go.bats` — all 3 validate NO-GO → orchestrator escalates to user.
- `speculation-disabled.bats` — `enabled: false` → single-plan path, state fields null, no candidates persisted.
- `speculation-skip-bugfix.bats` — bugfix mode → speculation skipped regardless of trigger.
- `speculation-token-ceiling.bats` — estimated cost > 2.5x baseline → speculation aborted, falls back to single-plan, WARNING logged.

### 8.5 Eval harness (per Phase 1)

New eval suite `evals/speculation/` with 12 curated ambiguous requirements spanning domains (auth, migrations, API design, state management, UI architecture). Each has a known "best approach" from human labeling.

**Metrics (CI-enforced):**

1. **Winning-plan quality lift**: `mean(winner_validator_score) - mean(single_plan_baseline_score)`. Target ≥ +5 points. CI asserts ≥ 0 as hard floor (no regression).
2. **Token cost ratio**: `speculation_total_tokens / single_plan_baseline_tokens`. CI asserts ≤ 2.5x (hard ceiling). Speculation aborts if estimate exceeds threshold, so this should never trigger unless estimation drifts.
3. **Selection precision**: fraction of speculation runs where the selected candidate matches the human-labeled best approach. Target ≥ 75%; CI asserts ≥ 60% (hard floor).
4. **Trigger rate sanity**: across a mixed corpus (ambiguous + unambiguous), trigger rate stays in 20-50% band. CI asserts bounds (flagging regressions in either direction).

Baseline run (`speculation.enabled: false`) captured once per CI run; speculation run A/B'd against it on identical seeds.

### 8.6 Documentation tests

- `speculation-doc-consistency.bats` — every config field in `forge-config.md` has a matching entry in `shared/speculation.md` and vice versa.
- `speculation-state-doc-consistency.bats` — every field in `state.plan_candidates` documented in `shared/state-schema.md`.

---

## 9. Rollout

**Single PR.** Per project constraint ("no backwards compatibility"), no staged rollout — ship the complete feature in one merge.

PR scope:

1. New `shared/speculation.md`.
2. New `hooks/_py/speculation.py`.
3. Edits to `agents/fg-200-planner.md` (branch mode section).
4. Edits to `agents/fg-100-orchestrator.md` (speculative dispatch subsection).
5. Edits to `shared/state-schema.md` (v1.7.0 bump, new fields).
6. Edits to `shared/plan-cache.md` (v2.0 schema).
7. Edits to `CLAUDE.md` (feature table entry, version bump to 3.1.0).
8. New tests (structural, unit, contract, scenario, eval).
9. Updates to `tests/lib/module-lists.bash` (MIN_* bumps).
10. Eval fixture set `evals/speculation/`.

**Default:** `speculation.enabled: true`. Users opt out with one config line. Rationale: the feature is gated on MEDIUM confidence + ambiguity signal — it won't fire on straightforward requirements, so the risk of unwanted activation is low and the quality lift accrues immediately.

**Version bump:** forge plugin 3.0.0 → 3.1.0 (new feature, no breaking user-facing API — plan cache is internal).

---

## 10. Risks / Open Questions

### Risks

1. **Token-cost blowout on complex plans.** Mitigation: `token_ceiling_multiplier` config + pre-dispatch estimation (sum of baseline + recent planner token averages × N). If estimate exceeds ceiling, speculation is skipped for that run with a logged WARNING. CI eval asserts ≤ 2.5x hard ceiling.
2. **Non-diverse candidates** (all 3 planners converge on the same approach despite seeds + emphasis axes). Mitigation: post-dispatch diversity check — if all plans hash-match (or ≥ 85% content overlap via plan_hash comparison), fall back to top-1 and skip validator speculation (single validation run instead of 3); log `speculation.degraded = "low_diversity"`. Retrospective flags if this happens >30% of triggered runs.
3. **Validator inconsistency.** Validator scoring variance across parallel runs could pick the wrong winner due to noise rather than plan quality. Mitigation: eval harness specifically measures selection precision against human labels; if <60% we know the signal is noisy and the feature needs re-tuning (or deliberation pass per Alt A).
4. **State file growth.** 20 runs × 3 candidates × ~10 KB = ~600 KB for candidate persistence. Acceptable. FIFO eviction keeps it bounded.
5. **User fatigue from too many confirmations.** If `auto_pick_threshold_delta` is too high, users see `AskUserQuestion` too often. Mitigation: default is 5 points (conservative); DX metric `speculation_trigger_rate` + user feedback after rollout drive tuning.
6. **Interaction with plan cache.** Cache hit at similarity ≥ 0.60 skips speculation (cached plan preferred). But what if the cached plan was itself a speculation winner — do we trust it? v1: yes (cached plan already validated). Future: revalidate cached plans older than N days.
7. **Retrospective pollution.** Losing candidates feeding into retrospective could create noisy PREEMPT items (patterns from bad plans). Mitigation: retrospective only analyzes losers when their validator score ≥ 60 (i.e., they were viable alternatives, not poor plans).

### Open Questions

1. **Should the emphasis_axis be user-configurable per-run?** Future work; v1 uses round-robin.
2. **Should we surface candidate diffs in the `AskUserQuestion` tie prompt?** v1 shows summary + scores; v2 could show structural diff (stories added/removed). Holds for follow-up phase.
3. **Minimum requirement length to trigger?** Very short requirements (<10 words) may not have enough content to diversify. v1: add a requirement-length floor of 15 words for speculation trigger; below that, fall through to single-plan.
4. **Should speculation honor `/forge-run --dry-run`?** v1: yes, speculation runs in dry-run mode (PREFLIGHT → VALIDATE only). Dry-run already caps at Stage 3; speculation simply exercises Stage 2 more.
5. **Parallel dispatch safety.** Does running 3 concurrent `fg-200-planner` subagents hit any rate limit or conflict on shared resources (plan cache reads, Neo4j queries)? v1: Neo4j queries are read-only and concurrency-safe; plan cache is read-once-at-start; no write conflicts. Document assumption in `shared/speculation.md` and add load-test scenario.

---

## 11. Success Criteria

**Quantitative (CI-enforced):**

- **≥ 5% pipeline quality lift on ambiguous scenarios**: `mean(speculation_winner_final_score) - mean(single_plan_baseline_final_score) ≥ 5` on the `evals/speculation/` corpus. Floor: ≥ 0 (no regression).
- **Token cost ≤ 2.5x single-plan baseline** across the eval suite. Hard ceiling enforced in CI.
- **Selection precision ≥ 60%** against human-labeled best approach (target 75%).
- **Trigger rate in 20-50% band** on mixed corpus (neither too eager nor too rare).

**Qualitative:**

- Speculation never fires on HIGH-confidence or LOW-confidence requirements (LOW routes to shaper).
- Users in interactive mode see tie-confirmation prompts fewer than 20% of triggered runs (most have clear winners).
- Retrospective surfaces at least one useful pattern from candidate comparison within the first 20 speculation runs per project (validates learning signal).
- No user-visible breaking changes outside plan cache schema (which is internal state).

**Observable (via `/forge-insights`):**

- `dx_metrics.speculation_trigger_rate` visible in insights dashboard.
- `dx_metrics.speculation_quality_lift` trends non-negative over rolling 10-run window.
- Event log shows `speculation.started` + `speculation.resolved` pairs with matching `run_id`.

---

## 12. References

**External:**

- Codex parallel agents overview — https://docs.kanaries.net/topics/AICoding/parallel-code-agents
- Verdent 2026 Codex App Analysis — https://www.verdent.ai/guides/codex-app-first-impressions-2026
- GPT Pro parallel reasoning — https://openai.com/index/introducing-gpt-pro/
- Best-of-N sampling in LLM decision-making — https://arxiv.org/abs/2407.21787

**Internal:**

- `shared/confidence-scoring.md` — MEDIUM band definition
- `shared/plan-cache.md` — v1 cache (extended to v2 here)
- `shared/state-schema.md` — v1.6.0 → v1.7.0 bump
- `agents/fg-200-planner.md` — branch mode additions
- `agents/fg-210-validator.md` — validator reused unchanged
- `agents/fg-100-orchestrator.md` — speculative dispatch logic
- `shared/agent-philosophy.md` — challenge-assumptions ethos (alternatives are the point)
- Phase 1 (eval harness spec) — infrastructure for the eval suite in §8.5
- Phase 2 (cross-platform Python hooks) — pattern for `hooks/_py/speculation.py`
- Phase 4 (implementer reflection, CoVe) — complementary quality-lift mechanism (IMPLEMENT stage)

---

**End of spec.**
