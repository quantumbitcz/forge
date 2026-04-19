# Phase 01 Evaluation Harness — Spec Review

**Spec under review:** `/Users/denissajnar/IdeaProjects/forge/docs/superpowers/specs/2026-04-19-01-evaluation-harness-design.md`
**Reviewer role:** Senior Code Reviewer (spec gate for P0 foundational phase)
**Date:** 2026-04-19

---

## Verdict

**CONCERNS** — Spec is substantively complete and clearly written; all 12 sections present with real content, two architecture alternatives properly rejected, URLs in place, and breaking changes acknowledged. However, there is a material internal numeric inconsistency on the single most load-bearing number (suite wall-clock budget), a citation whose URL is almost certainly a typo, and a schema-vs-YAML field-name mismatch that will bite the first scenario author. These are fix-before-merge items, not rewrite-the-spec items. Approve after revisions.

---

## Strengths

1. **Section coverage is thorough.** All 12 required sections are present and substantively filled — no skeletons, no "TBD", and Motivation properly grounds the work in an internal audit finding (W1) plus four external references. Rare for a P0 spec to nail this on the first pass.

2. **Architecture alternatives have real rejection rationale.** §4 rejects both the bash-extension path (language mismatch, wrong test-speed envelope) and the "just extend agent evals" path (different question being answered) with specific, defensible reasoning — not strawman rejections.

3. **Composite scoring math is defined, not hand-waved.** §6 gives exact formulas with `clamp01` semantics, over/under-budget behavior, and explicitly isolates overlap as reporting-only. PREFLIGHT constraints (`composite_weights` sum to 1.0, tolerance bounded to [0, 20]) are codified — future config drift will be caught.

4. **Rollout ordering is thoughtful.** §9's 5-commit plan keeps the point-of-no-return (CI gate flip) isolated to commit 5 so commits 1-3 ship the harness without risk and commit 4 is a clean revert unit. R4's `FORGE_EVAL=1` env guard is a good defense-in-depth move.

5. **Scope boundaries are crisp.** §3 "out of scope" list correctly defers cross-plugin benchmarking, user-supplied scenarios, and Docker isolation — each of those is a spec-sized item on its own. §5 ends with "Deletes: None" which makes the additive-only claim concrete.

6. **Success criteria are mostly numeric.** SC1 (p90 of 10 runs), SC2 (composite ≥70 across 5 consecutive runs), SC5 (<5s collect) are falsifiable. SC6 (zero touches to `tests/evals/agents/`) is a clean diff check.

7. **Self-awareness on LLM non-determinism.** R1 acknowledges the 3-point tolerance is a judgment call and ties it to a measurement plan (run 5× against `master` in dispatch-only mode before enforcement). This is the right engineering posture for a gating threshold.

---

## Critical issues

### C1. Wall-clock budget is inconsistent across three sections.

Three different numbers for the same thing:

- `§6` config: `total_budget_seconds: 2700` (= 45 min)
- `§8` Testing Strategy: "Full suite (slow, ~30 min wall-clock budget with parallel execution)"
- `§10` R3: "parallelism of 3 yields ~35 real minutes"
- `§11` SC1: "Full harness completes in ≤15 minutes wall-clock … p90 of 10 consecutive `master` runs"

The SC1 target (15 min p90) is tighter than the §6 config ceiling (45 min), the §8 narrative (~30 min), and the §10 risk estimate (~35 min). If SC1 is the acceptance bar, then the config cap and risk estimate violate it. If the 30-45 min numbers are the real picture, SC1 is unreachable and the success criterion is a lie.

**Fix:** Pick one number, reconcile all four sites. Most likely SC1 should become "≤30 minutes wall-clock p90" (matching §8) with `total_budget_seconds: 2700` as the hard ceiling with 50% headroom — but the author should decide, not the reviewer.

### C2. `expected.yaml` and `state-schema.md` use different field names for the same data.

`§6` `expected.yaml` schema declares:

```yaml
touched_files:
  - src/server.ts
```

`§6` `state-schema.md` declares:

```json
"touched_files_expected": ["src/server.ts", ...]
```

Same concept, two names. Scenario authors will copy from the YAML example; runner code will key on `touched_files_expected`. First PR that adds a scenario will have a silent "oh the overlap metric is always 0" bug that takes 30 minutes to track down.

**Fix:** Rename both to the same key. `touched_files_expected` is clearer in both locations; the YAML isn't load-bearing for brevity.

### C3. SWE-CI arxiv URL is implausible.

Reference: `https://arxiv.org/html/2603.03823v1` — the arxiv id `2603.03823` decodes to "March 2026" (`YYMM.NNNNN`), which is consistent with today's date (2026-04-19), so the id itself is not impossible. But the URL was not verified in this review, and if it's a typo for a real paper (e.g. `2503.*` or `2403.*`) the broken citation weakens Motivation. The other three external links (perevillega, openhands.dev, github.com/princeton-pli) look well-formed.

**Fix:** Verify the arxiv URL resolves. If the paper was real-at-writing but not-yet-indexed, add an access date ("retrieved 2026-04-19"). If it's a typo, correct it or drop the citation.

---

## Important issues

### I1. "STUB" scenarios are a latent placeholder.

§10 Q3 openly says scenarios 07 (ML-ops) and 09 (Swift concurrency) will ship as stubs marked `notes: "STUB — replace before Phase 03"`. This is the spec admitting it won't fully meet its own §1 goal ("10 frozen scenarios covering standard/bugfix/migration/bootstrap") on day one — the 10 scenarios will exist as files, but two will be placeholders whose production replacement is deferred to a follow-up PR.

This is not a blocker (the stubs exercise the harness plumbing, which is the actual P0 deliverable), but the Goal statement in §1 overclaims. Either §1 should say "10 scenario slots, 8 production + 2 stub" or Q3 should be upgraded to a Phase 01 deliverable. Pick one.

### I2. `--eval-mode` safety flag interaction is under-specified.

R4 says orchestrator refuses `--eval-mode` unless `FORGE_EVAL=1` env var is set. Good. But `§5` modifies `agents/fg-100-orchestrator.md` to "recognize `--eval-mode <id>` flag; disable Linear/Slack/AskUserQuestion when set; force `autonomous: true`" — with no mention of the env-var guard. The guard lives only in R4 risk-mitigation prose, not in the Components contract.

**Fix:** Move the `FORGE_EVAL=1` requirement from R4 into §5 Components as part of the orchestrator modification contract, so implementers don't silently drop it.

### I3. Baseline-storage "open question" (Q1) is a runtime dependency, not optional.

Q1 asks where the `master` baseline artifact lives and recommends Actions artifacts with 90-day retention. The "regression gate" in §4 *requires* this baseline to function — if the baseline is missing, CI has nothing to compare against and either fails-open (silent regression) or fails-closed (every PR fails). The spec does not specify behavior when the baseline is unavailable (first master run, retention expiry, artifact fetch failure).

**Fix:** Either promote Q1 out of "open questions" and commit to Actions artifacts (with an explicit fallback: "on baseline-missing, emit `EVAL-BASELINE-UNAVAILABLE` as WARNING and skip regression gate") or defer enforcement (commit 5) until Q1 is answered.

### I4. Flag-collision risk with `/forge-run --eval-mode` and existing `--dry-run`.

§4 and §5 introduce `/forge-run --eval-mode <id>`. §8 testing step 2 runs scenario 01 "with `--dry-run`". These flags presumably compose (dry-run + eval-mode = runner plumbing smoke without pipeline execution), but the composition contract is not stated. If they don't compose, step 2 of testing is under-specified.

**Fix:** One sentence in §5 defining `--eval-mode + --dry-run` semantics (exit after PREFLIGHT, emit `.forge/eval-results.jsonl` stub with `status: dry_run`, etc.).

---

## Minor issues

### M1. SC3 is the only non-numeric success criterion.

SC3: "A deliberately regression-inducing PR … fails CI with a **clear** `EVAL-REGRESSION` finding. Validated manually before merge." The word "clear" is subjective. Tighten to "fails CI with exit code 1 and the `EVAL-REGRESSION` finding present in `.forge/eval-results.jsonl`". The other five SCs are already measurable; don't let this one drag the set down.

### M2. `leaderboard.md` commit strategy could fight-commit with developers.

§1 scope says "CI bot commits on `master` pushes only". If a developer edits `tests/evals/pipeline/leaderboard.md` in the same PR that the CI bot tries to overwrite on merge, there's a merge conflict. Low-likelihood (the file says "auto-generated, do not edit") but worth one sentence telling contributors "do not hand-edit; regenerate via runner".

### M3. `requirements.txt` with `pydantic>=2, pyyaml, requests` has no version pins for the last two.

§5 creates `tests/evals/pipeline/runner/requirements.txt` with `pydantic>=2`, `pyyaml`, `requests`. Only pydantic has a version floor. CI reproducibility argues for pinning all three or using a lockfile. Minor — CI pip-installs are pretty stable — but worth a pin pass before commit 2.

### M4. Scenario count mismatch in the ASCII tree.

§4 tree shows `02-python-bugfix/` then `...` then `10-php-security-fix/`. Harmless, but the full list appears in §5 anyway. If someone reads only §4, they might think scenarios 03-09 are undefined. One-line fix: replace `...` with "(scenarios 03-09 — see §5 for full list)".

### M5. Category severity assignment for `EVAL-VERDICT-MISMATCH` feels light.

§6 table marks `EVAL-VERDICT-MISMATCH` as WARNING. Rationale: if a scenario requires PASS and the pipeline returns CONCERNS, that's a quality signal worth CRITICAL-ing, not a WARNING. This is arguable — the composite score will already drop, and CRITICAL might cause noise — but worth one line of justification in the table.

### M6. No rollback plan for commit 5.

§9 says commit 5 is "the point of no return for CI gating" and "if the baseline turns out to be unstable, it is reverted in isolation". Good. But what is the rollback signal? After N consecutive false-positive `EVAL-REGRESSION` blocks on `master`-PRs that shouldn't regress, revert? Define the trip-wire.

---

## Overall assessment

This spec is above-average for a P0 foundational phase. The author thought about the *shape* of the problem (architecture alternatives, composite scoring math, CI integration strategy), the *edges* (non-determinism tolerance, fixture drift, env-var safety guard), and the *exit conditions* (5 numerically-grounded success criteria, dispatch-only variance measurement before enforcement). The deferred "stub" scenarios are honest rather than hidden.

The three critical issues are all local fixes, not structural: (C1) pick one wall-clock number and propagate it, (C2) rename one YAML key, (C3) verify one URL. The four important issues are hardening the contracts so Phase 02+ authors don't trip over under-specified surfaces (env-var guard, flag composition, baseline-missing behavior, stub-vs-goal scope framing).

Recommend a revision pass addressing C1-C3 and I1-I4, after which this is ready to merge. Minor issues are polish and can land in the scaffolding commit itself.

**Verdict:** CONCERNS — approve after C1, C2, C3 are fixed; I1-I4 strongly recommended in the same pass.
