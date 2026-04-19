# Review: Phase 12 — Speculative Parallel Plan Branches Spec

**Spec:** `/Users/denissajnar/IdeaProjects/forge/docs/superpowers/specs/2026-04-19-12-speculative-plan-branches-design.md`
**Reviewer:** Senior Code Reviewer
**Date:** 2026-04-19
**Verdict:** APPROVE WITH MINOR REVISIONS

---

## Summary

Phase 12 spec is thorough, internally consistent, and correctly aligned with the A+ roadmap slot for speculative parallel plan branches at PLAN stage. All 12 required sections are present, no placeholders, no backcompat shims, and the design cleanly reuses `fg-210-validator` unchanged. Scope boundaries are well-drawn (single-pass only; no implementation speculation; no cross-run reuse in v1). CI eval harness defines the three quality/cost/precision floors required by the criteria. Minor gaps listed below — none are blockers.

---

## Criterion-by-Criterion Evaluation

### 1. All 12 sections present — PASS

Goal, Motivation, Scope, Architecture, Components, Data/State/Config, Compatibility, Testing Strategy, Rollout, Risks/Open Questions, Success Criteria, References — all present, numbered, and substantive. Section 4 (Architecture) is fully decomposed into 4.1-4.6; Section 5 covers all 6 touch-points.

### 2. No placeholders — PASS

No TBD/TODO/FIXME markers. All config defaults are concrete (N=3, delta=5, token_ceiling=2.5x, eviction=20 runs). All URLs are real. JSON examples are fully populated.

### 3. Ambiguity trigger deterministic — PASS (minor)

Trigger decision is expressed as an if/elif cascade in §4.1 with four explicit ambiguity signal sources. Matches criterion exactly (shaper signal + confidence band + keyword regex + plan-cache marginal band). `hooks/_py/speculation.py#detect_ambiguity` isolates the logic.

**Minor:** signal #2 (keyword regex) and signal #3 (multi-domain detection) can both fire on the same requirement, but the spec does not describe OR-combination semantics for the three `ambiguity_signal_hit` sources versus shaper alternatives. Implicit OR is inferred from "any one triggers," but be explicit in `shared/speculation.md` so the contract test can assert it.

### 4. Token cost cap enforced — PASS

`token_ceiling_multiplier: 2.5` in config (§6.1), pre-dispatch estimation described in §5.3 and §10 risk 1, CI eval asserts ≤ 2.5x as hard ceiling (§8.5 metric 2). Abort path (fall back to single-plan with WARNING) is defined.

**Minor:** the estimation formula ("baseline + recent planner token averages × N") is described in prose only. Include the exact formula in `shared/speculation.md §Cost guardrails` so the abort trigger is reproducible in tests.

### 5. Selection formula explicit — PASS

§4.4 shows the formula exactly as the criterion requires:

```
selection_score = validator_score + verdict_bonus + 0.1 × token_efficiency_bonus
```

Verdict bonuses (+0 GO, -15 REVISE, NO-GO eliminated) and token efficiency bonus (`(max - cand) / max × 100`) are fully specified. The 0.1 multiplier correctly keeps efficiency sub-dominant (≤10 pts influence).

### 6. Interactive vs autonomous differentiated — PASS

§4.4 selection-rules table distinguishes the tie case explicitly: interactive fires `AskUserQuestion`; autonomous auto-picks top-1 and logs `[AUTO]` + runner-up hash. §3 (Out) confirms no auto-retry on NO-GO tie. Consistent with the project's autonomous-mode contract (`autonomous: true` never blocks on user).

### 7. Diversity check mechanism — PASS (minor)

§10 risk 2 defines plan-hash / content-overlap check (≥85% overlap → degraded mode). §5.4 persistence schema includes `plan_hash` field. §5.3 lists diversity enforcement via exploration_seed + emphasis_axis hints.

**Minor:** the 85% content-overlap threshold is stated once in a risk bullet but should be promoted to `shared/speculation.md §Dispatch protocol` as a first-class parameter (e.g., `speculation.min_diversity_score: 0.15`) and have a dedicated unit test. Otherwise the degraded-mode trigger is not testable from the contract.

### 8. Alternatives rejected with rationale — PASS

§4.6 rejects both Tournament (Alt A: doubles validator cost, muddies attribution) and Beam Search (Alt B: exponential cost, wrong problem shape since PLAN has one fitness signal, hard to cost-cap). Rationales are technical and specific — not hand-waved.

### 9. Candidate persistence schema — PASS

§5.4 specifies `.forge/plans/candidates/{run_id}/cand-{N}.json` with full JSON schema (schema_version, run_id, candidate_id, emphasis_axis, exploration_seed, plan_hash, plan_content, validator_verdict, validator_score, selection_score, selected, tokens{planner,validator}, created_at). Index file + FIFO eviction (keep last 20 runs) defined. Survives `/forge-recover reset` per §4.5.

### 10. Selection-precision floor in CI — PASS

§8.5 metric 3: "Selection precision ≥ 60% against human-labeled best approach (target 75%)". CI-enforced. Eval corpus size (12 curated requirements across 5 domains) is stated, and A/B baseline methodology (speculation off on identical seeds) is defined.

---

## Top 3 Issues (minor, non-blocking)

1. **Diversity threshold is under-specified.** The 85% content-overlap / `speculation.degraded = "low_diversity"` trigger lives only in a risk bullet. Promote to `shared/speculation.md` as a named config parameter (`min_diversity_score` or equivalent) with a concrete definition of "content overlap" (plan_hash exact match? normalized diff ratio? embedding cosine?). Add a unit test in `tests/unit/speculation-diversity.bats`.

2. **Token estimation formula is prose-only.** §5.3 and §10 describe the pre-dispatch cost estimate as "baseline + recent planner token averages × N" but don't define the window (last N runs? rolling 10?) or fallback when no history exists (first-run cold-start). Make it a deterministic function in `hooks/_py/speculation.py#estimate_cost` so the 2.5x ceiling abort is reproducible and testable.

3. **Ambiguity-signal OR semantics unstated.** §4.1 lists four signal sources and says "any one triggers when confidence is MEDIUM," but the shaper-alternatives signal is treated separately in the pseudocode (`shaper_output.alternatives_count >= 2 OR ambiguity_signal_hit`). This implies shaper is special (elevated) while signals 1-4 inside `ambiguity_signal_hit` are OR'd — make this explicit in the contract doc and cover with fixtures in `speculation-ambiguity-detector.bats`.

---

## Strengths (worth preserving)

- Clean separation of "what belongs in v1" vs "future work" — scope §3 is disciplined.
- Reusing `fg-210-validator` unchanged is the right call; no new agent, no new review dimensions.
- Selection formula mathematically sound: efficiency as tiebreaker only, correctness dominant.
- Eval harness metrics cover all three axes (quality lift, cost cap, selection precision) with both target and hard-floor values.
- Cache integration explicitly skips speculation when cache similarity ≥ 0.60 — avoids redundant work.
- Retrospective filter (only analyze losers with validator_score ≥ 60) prevents PREEMPT pollution from bad plans.
- Version bump rationale (3.0.0 → 3.1.0, not major) is correctly justified: plan cache is internal state, not user-facing API.

---

## Recommended Next Steps

1. Address the three minor gaps above by promoting prose-level details into `shared/speculation.md` as first-class contract items with matching unit/contract tests.
2. Proceed to implementation PR per §9 rollout plan.
3. After first 20 real speculation runs, review `speculation_quality_lift` and `speculation_trigger_rate` DX metrics against targets; tune `auto_pick_threshold_delta` if user-confirmation rate exceeds 20%.

**Final verdict:** APPROVE WITH MINOR REVISIONS. Spec meets all 10 review criteria. Three gaps are documentation/testability nits, not design flaws — safe to resolve during implementation.
