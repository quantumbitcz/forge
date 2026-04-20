# Review — Phase 11 Self-Consistency Voting Design Spec

**Spec:** `/Users/denissajnar/IdeaProjects/forge/docs/superpowers/specs/2026-04-19-11-self-consistency-voting-design.md`
**Reviewer:** Senior Code Reviewer
**Date:** 2026-04-19
**Verdict:** APPROVE WITH MINOR REVISIONS

---

## 1. Criterion Check Matrix

| # | Criterion | Status | Notes |
|---|---|---|---|
| 1 | All 12 sections present | PASS | Goal, Motivation, Scope, Architecture, Components, Data/State/Config, Compatibility, Testing, Rollout, Risks, Success Criteria, References. |
| 2 | No placeholders | PASS | No `TBD`, `TODO`, `XXX`, `FIXME`, or `???` anywhere. Open questions are explicitly deferred with rationale, not placeholders. |
| 3 | 3 decision points named and bounded | PASS | §3 In-Scope item 2 and §4.4 integration table name agent file + call site + label space + fallback. Explicit exclusions: per-perspective findings (§3 Out-of-scope 3), shaping dialogue (§3.2a parenthetical), deterministic verdict rules (§5.4 sub-step 1). |
| 4 | Aggregation algorithm specified | PASS | §4.2 four-step cascade: majority → confidence-weighted sum → highest single confidence → low_consensus flag. Pseudocode-level precision. |
| 5 | Tie-break confidence source specified | PASS | §4.2 step 2 uses `sum(confidence_i)` per group; step 3 uses single highest individual confidence. §5.2 forces `confidence` via JSON schema, enum `labels`, float [0,1]. |
| 6 | Cost/latency analysis (N=3 → 3x samples) | PARTIAL | §7.1 gives a per-seam budget (+800ms-2s × 3) and a worst-case +6s. §7.2 asserts cost is "below noise floor" without a number. See Issue I1. |
| 7 | Fast-tier bias mitigation | PASS | §10 R1 names the risk explicitly and defers the mitigation to the eval harness (accuracy-based, not agreement-based), with per-decision tier override as escape hatch. |
| 8 | Cache key formation + invalidation including `state.mode` | PARTIAL | §4.3 names the key components (decision_point, prompt, n_samples, model_tier). §10 R2 flags `state.mode` as an open question and leans yes but does NOT commit. See Issue I2 (top issue). |
| 9 | 2 alternatives rejected with rationale | PASS | §4.5 Alt 1 (single-sample + confidence threshold, rejected via Kadavath 2022 bimodal confidence). Alt 2 (CoT ensemble + judge, rejected via arXiv 2203.11171 §4.2 cost/noise argument). Both cite primary sources. |
| 10 | `low_consensus` fallback per-decision defined | PASS | §4.2 step 4 + §4.4 table: shaper → AskUserQuestion; validator → force REVISE; post-run → force `design`. All three are deterministic. |

**Summary:** 8 PASS, 2 PARTIAL, 0 FAIL. No criterion is missed entirely.

---

## 2. Strengths

1. **Bounded decision surface.** §3 is explicit about what is NOT voted (per-perspective findings, deterministic verdict rules, shaping dialogue, code generation). This scope discipline prevents "vote everything" scope creep that would 3x the pipeline token budget for marginal lift.
2. **Soft self-consistency is actually soft.** §4.2 correctly implements the Wang 2024 soft variant (confidence-weighted sum in the tie-break), not a misnamed hard-vote-with-tiebreaker. The cascade (majority → weighted → highest) is the correct generalization.
3. **Fallback path preserves the "safer rewind" property.** §4.4 validator `low_consensus` → REVISE (re-plan), post-run `low_consensus` → `design` (rewind further). Both bias toward deeper rollback, which matches the motivation (wrong GO is 10-50x more expensive than wrong REVISE).
4. **Cache invariant is defended.** §10 R2 reasons about which prompts carry codebase state (validator plan text does, shaper `$ARGUMENTS` does not, post-run PR feedback does) instead of hand-waving "hash is enough."
5. **Evidence-based acceptance.** §8 ties the ≥5pp accuracy lift and <30% latency targets directly to the CI eval harness (Phase 01 dep). No "ship and see" — §11 success criteria are all mechanically measurable.
6. **Correct schema bump.** §6.3 bumps `_seq` version 1.6.0 → 1.7.0 per `state-schema.md` discipline, with in-place upgrade semantics.
7. **Respects `shared/` contract discipline.** §5.1 (`shared/consistency/voting.md`) follows the pattern: agents reference the contract, they don't inline the protocol. This keeps agent `.md` token cost flat when the dispatch semantics evolve.
8. **No backwards-compat shims.** §3 Out-of-scope 4 and §7.3 hold the line per the phase preamble — single `consistency.enabled` kill switch, no per-decision bypass. This matches the repo convention of clean breaks over backwards-compat shims.

---

## 3. Issues

### I1 — Cost analysis is qualitative, not numeric (IMPORTANT)

**Location:** §7.2 Compatibility → Cost.

**Problem:** The criterion explicitly calls for "Cost/latency analysis (N=3 → 3x samples)." §7.1 gives real latency numbers (+800ms-2s per seam). §7.2 says cost is "additive but below the noise floor of the overall pipeline cost" — but does not quantify:

- Fast-tier price per decision (ballpark: $0.0001-0.0005 per sample for a short classification).
- Additive cost at N=3: `2 × fast_tier_price × 3_decisions × runs_per_day`.
- The ratio to the baseline premium-tier call that is NOT being removed (sample 1 remains at caller's tier).

**Recommendation:** Add a table to §7.2:

```
| Seam | Baseline (1 sample) | With voting (N=3) | Delta |
|---|---|---|---|
| shaper_intent | 1× caller-tier | 1× caller-tier + 2× fast | +2× fast |
| validator_verdict | 1× caller-tier | 1× caller-tier + 2× fast | +2× fast |
| pr_rejection | 1× caller-tier | 1× caller-tier + 2× fast | +2× fast |
Total per run: +6× fast-tier short-classification calls (~$0.001-0.003).
```

This matches the precision given for latency and makes §11 success criterion 4 ("zero cost regression on unused decisions") verifiable against a baseline.

**Severity:** Important (does not block the spec, but the phase preamble said "no placeholders" and this is the closest thing to a placeholder in the document).

---

### I2 — `state.mode` cache key inclusion left as open question (IMPORTANT)

**Location:** §4.3 Caching (key derivation) and §10 R2 (open question).

**Problem:** The review criteria explicitly ask for "Cache key formation + invalidation (**including state.mode**)." §4.3 defines the key as `sha256(decision_point || '\0' || prompt || '\0' || n_samples || '\0' || model_tier)` — `state.mode` is NOT in the key. §10 R2 flags this as an open question and says "leaning yes — added to the cache key as belt-and-suspenders" but this is not reflected in §4.3 or §5.2.

This matters concretely: a shaper intent vote cached during `state.mode = "standard"` could be reused during a `state.mode = "bugfix"` re-run (e.g. after `/forge-recover reset` with the same `$ARGUMENTS`). The prompt is identical but the classification context is not — a vague bugfix-shaped argument in `bugfix` mode should not reuse a `standard`-mode vote.

**Recommendation:** Commit the decision. Update §4.3 to:

```
Key: sha256(decision_point || '\0' || state.mode || '\0' || prompt || '\0' || n_samples || '\0' || model_tier)
```

And remove the open-question half of §10 R2 (keep the "codebase state is captured in the prompt body" half as the justification). This is a one-line spec change that closes the most important gap in the review criteria.

**Severity:** Important (the spec is internally inconsistent — R2 says "leaning yes" but the normative §4.3 and §5.2 do not include the field).

---

### I3 — N-sample schema-violation semantics underspecified for N=3 edge case (SUGGESTION)

**Location:** §5.2 internals bullet 3 — "If fewer than `ceil(N/2)` samples survive, raise `ConsistencyError` — caller falls back to single-sample behavior."

**Problem:** `ceil(3/2) = 2`. So at N=3 the fallback triggers when only 1 sample survives. But §4.2 aggregation assumes an odd N; with 2 surviving samples from a 3-sample run, you can hit a perfect tie that only the §4.2 cascade steps 3 (highest single confidence) can resolve. The §5.2 "caller falls back to single-sample behavior" path is also undefined — which sample? The caller's own pre-voting call? A new one? This matters for the validator, where "single-sample behavior" means reverting to the deterministic rule-based verdict, not re-dispatching the LLM.

**Recommendation:** Add one clarifying sentence to §5.2:

> On `ConsistencyError`, the caller treats the decision as `low_consensus: true` and applies the §4.4 fallback for that decision point (REVISE / AskUserQuestion / `design`). The caller does NOT re-invoke the dispatch.

This makes the degraded-path behavior deterministic and reuses the same fallback machinery the happy path already defines, rather than inventing a separate single-sample path.

**Severity:** Suggestion.

---

### I4 — Validator verdict voting boundary is subtly ambiguous (SUGGESTION)

**Location:** §5.4 — "the summarization step that decides GO vs REVISE when findings are borderline."

**Problem:** The spec says the deterministic rules (SEC → NO-GO, HARD ARCH → NO-GO, 3+ EDGE/TEST → REVISE) still run single-sample, AND the voting synthesis runs over the structured findings. It is not clear whether voting is called ALWAYS (and its output overridden by a hard-rule NO-GO) or ONLY when the rules are inconclusive. The first is wasteful; the second needs a "borderline" predicate.

**Recommendation:** Spell out the gating predicate in §5.4:

> Voting is invoked only if the deterministic rule pass returns `INCONCLUSIVE` (no SEC/HARD-ARCH trigger, no 3+ EDGE/TEST trigger, but at least one WARNING-level finding present). If the rules return a hard verdict, voting is skipped and `consistency_votes.validator_verdict.invocations` is not incremented.

This also makes the cost analysis tighter — most real runs will NOT hit the voting path at the validator.

**Severity:** Suggestion.

---

### I5 — `/forge-insights` "flipped-verdict count" definition is thin (SUGGESTION)

**Location:** §6.5 — "flipped-verdict count (votes where the majority label differs from the first sample's label)."

**Problem:** "First sample" is not defined. In §4.1, N parallel Task() calls are dispatched concurrently — there is no canonical "first." If the intent is "the sample the agent would have produced without voting," that is a counterfactual, not a measurable. If the intent is "the first sample returned in dispatch order," that is implementation-dependent (asyncio.gather order is deterministic by index, so this is fine, but it should be pinned down).

**Recommendation:** Pin it: "sample at index 0 in the dispatch order." Or, better, reframe the metric: "disagreement rate = fraction of votes where at least one sample disagreed with the majority." That is a cleaner measure of voting's value-add and doesn't depend on an arbitrary "first."

**Severity:** Suggestion.

---

## 4. Alignment With Project Conventions

- **Matches `shared/` contract pattern:** §5.1 adds `shared/consistency/voting.md`, agents reference it. Correct per CLAUDE.md "Core contracts" discipline.
- **Matches state schema versioning:** §6.3 bumps `_seq` 1.6.0 → 1.7.0 with in-place upgrade. Correct per `shared/state-schema.md` convention.
- **Matches "survives reset" discipline:** §6.4 + §9.7 add `.forge/consistency-cache.jsonl` to the list alongside `explore-cache.json`, `plan-cache/`, etc. Correct per CLAUDE.md gotchas.
- **Matches PREFLIGHT constraints pattern:** §6.2 adds constraints to `shared/preflight-constraints.md` rather than inlining validation in the dispatch helper. Correct per CLAUDE.md "PREFLIGHT constraints" guidance.
- **Matches Phase 02 dependency:** §5.2 correctly uses `hooks/_py/state_write.py` for atomic appends rather than re-implementing. Correct per the phase dependency graph.
- **Matches model-routing discipline:** §4.1 + §5.2 route through `shared/model-routing.md` tiers rather than hardcoding model names. Correct per CLAUDE.md version-resolution gotcha ("NEVER use training data versions").
- **Matches insights surfacing pattern:** §6.5 adds a section to `/forge-insights` rather than a new skill. Correct per the skill-selection guide.

No deviations from established patterns.

---

## 5. Plan Deviation Assessment

The phase preamble required: 12 sections, no placeholders, no backcompat, CI eval validation with labeled dataset, ≥5% accuracy lift + <30% latency bound.

- **12 sections:** Delivered.
- **No placeholders:** Delivered (open questions are explicitly deferred with rationale, which is the correct spec discipline — not the same as placeholders).
- **No backcompat:** Delivered (§3.4, §7.3). Single `consistency.enabled` kill switch, no per-decision bypass.
- **CI eval + labeled dataset:** Delivered (§8.1 three datasets, §8.2 five assertions).
- **≥5% accuracy + <30% latency targets:** Delivered in §11 success criteria, both mechanically verifiable in CI.

No deviations from the plan. The spec hits every required element.

---

## 6. Verdict

**APPROVE WITH MINOR REVISIONS.**

The spec is well-reasoned, evidence-backed (three primary-source citations), scope-disciplined, and internally consistent with one exception (I2 — the `state.mode` cache key open question contradicts the criterion). Fix I1 (add cost table) and I2 (commit `state.mode` in the cache key and delete the R2 open-question half) before merge. I3-I5 are nice-to-haves that can go into a follow-up pass.

The spec is READY for the implementation plan (`/forge-run` Stage 2 → `fg-200-planner`) once I1 and I2 are addressed.

---

## 7. Artifacts Touched

- **Reviewed:** `/Users/denissajnar/IdeaProjects/forge/docs/superpowers/specs/2026-04-19-11-self-consistency-voting-design.md`
- **Referenced for convention check:**
  - `/Users/denissajnar/IdeaProjects/forge/CLAUDE.md`
  - `/Users/denissajnar/IdeaProjects/forge/shared/intent-classification.md` (via spec §4.4)
  - `/Users/denissajnar/IdeaProjects/forge/shared/model-routing.md` (via spec §4.1)
  - `/Users/denissajnar/IdeaProjects/forge/shared/preflight-constraints.md` (via spec §6.2)
  - `/Users/denissajnar/IdeaProjects/forge/shared/state-schema.md` (via spec §6.3)
- **Review written to:** `/Users/denissajnar/IdeaProjects/forge/docs/superpowers/reviews/2026-04-19-11-self-consistency-voting-spec-review.md`
