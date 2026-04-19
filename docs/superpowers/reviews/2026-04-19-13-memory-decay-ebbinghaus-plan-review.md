# Review — Phase 13 Memory Decay (Ebbinghaus) Implementation Plan

**Plan:** `docs/superpowers/plans/2026-04-19-13-memory-decay-ebbinghaus-plan.md`
**Spec:** `docs/superpowers/specs/2026-04-19-13-memory-decay-ebbinghaus-design.md`
**Spec review:** `docs/superpowers/reviews/2026-04-19-13-memory-decay-ebbinghaus-spec-review.md`
**Reviewer date:** 2026-04-19
**Verdict:** **APPROVE — ready to execute (3 minor issues, all non-blocking).**

---

## 1. Criterion-by-criterion check

| # | Criterion | Evidence | Pass? |
|--:|-----------|----------|------:|
| 1 | `writing-plans` format (checkbox tasks, TDD steps, commits per task) | 18 numbered tasks; each uses `- [ ]` checkbox steps; TDD pattern (failing test → run → impl → run → commit) in every code task. Intro references `superpowers:subagent-driven-development` / `superpowers:executing-plans`. | PASS |
| 2 | No placeholders | No `TBD`/`TODO`/`FIXME`/`<…>` anywhere. Every constant, path, test, and commit message is concrete. Only "approx L273/L302" line-number hints (Task 13), which are explicitly framed as locators. | PASS |
| 3 | Type consistency (`auto-discovered 14d / cross-project 30d / canonical 90d`) | Matches across: §Goal (L5), `HALF_LIFE_DAYS` const (L130-134), `decay.md` table (L309-312), Task 7 regression test (L720-743), Task 12 docs rewrite (L1080-1083), Task 13 `CLAUDE.md` edit (L1187), Task 15 fixture grid (L1349-1357), Task 17 config defaults (L1475-1478), Appendix (L1560-1562). All 43 numeric references align. | PASS |
| 4 | Each task commits | Tasks 1–17 all end in a `git commit -m "..."` step. Task 18 is a verification-only pass with a conditional final commit. Conventional Commits style (`feat(phase13)`, `docs(phase13)`, `test(phase13)`, `chore(phase13)`, `ci(phase13)`). | PASS |
| 5 | Spec coverage (formula / half-lives / FP penalty / success boost / migrator / clock-skew clamp) | Formula: Task 1 impl + tests 1-3. Half-lives: Task 1 const + Task 7 regression. FP penalty (×0.80 + clock reset): Task 5. Success boost (+0.05): Task 4. Migrator (warm start + legacy-tier mapping + idempotency + legacy-field deletion): Task 6. Clock-skew clamp (`[0, 365]`): Task 2 with two tests covering both ends. | PASS |
| 6 | Spec-review feedback addressed (0.95 cap / `last_fp` reader / tuning warning) | Issue 1 (0.95 ceiling): `MAX_BASE_CONFIDENCE = 0.95` in Task 1 consts; Task 4 `test_apply_success_caps_at_0_95` + Task 5 `test_apply_false_positive_on_maxed_item_drops_to_0_76`; Task 6 migrator maps legacy HIGH → 0.95. Issue 2 (`last_false_positive_at` reader): Task 9 `count_recent_false_positives()` + two tests; Task 10 wires it into `fg-700` summary line. Issue 3 (tuning warning): Task 3 `decay.md` §7 + Task 17 `forge-config.md` comment. Plan header explicitly calls out the mapping at L40-44. | PASS |
| 7 | Migrator warm-start task explicit | Task 6 — dedicated task. Tests cover: legacy HIGH → 0.95 (not 1.0), MEDIUM/LOW/ARCHIVED tier mapping, idempotency, already-migrated pass-through, type inference via the migrator. Implementation comment cites §7 of the spec. Orchestrator (Task 11) calls migrator on first PREFLIGHT. | PASS |
| 8 | Unit tests for 0.95 cap + FP compound | 0.95 cap: `test_apply_success_caps_at_0_95` (Task 4) verifies both single-hit cap and "second success does not push past 0.95". FP compound behaviour: `test_apply_false_positive_on_maxed_item_drops_to_0_76` (Task 5) asserts `0.95 * 0.80 = 0.76` — demonstrates the penalty remains meaningful after cap. `test_apply_false_positive_drops_and_resets` covers generic case (0.80 → 0.64). | PASS |
| 9 | `shared/learnings/` docs updated | Task 12 rewrites `README.md` §PREEMPT Lifecycle, `memory-discovery.md` §Promotion and Decay, `rule-promotion.md` §Decay Rules — each pointing at `decay.md`. Task 13 updates `knowledge-base.md`, `agent-communication.md` (two call-sites), `domain-detection.md`. Task 14 hand-stamps frontmatter on every shipped `shared/learnings/*.md`. Task 18 Step 5 globs for `decay.md` references everywhere they should be. | PASS |
| 10 | `fg-700` integration | Task 10 — dedicated task. Edits LEARN-stage pseudocode to call `apply_success`/`apply_false_positive`, compute `effective_confidence` + `tier`, archive demoted items, emit summary line with `count_recent_false_positives`. Removes `runs_since_last_hit`/`decay_multiplier` language. Post-edit Grep asserts zero stale refs. | PASS |

**All 10 criteria pass.** The plan is execution-ready and each task ends in a reviewable commit.

---

## 2. What the plan does well

1. **TDD per task, strictly.** Every code-producing task opens with a failing test, runs it to confirm the failure mode (with expected error quoted verbatim), then implements the minimum to pass. This is the superpowers TDD contract executed cleanly — not performative.
2. **Single source of numeric truth.** The Appendix (L1554-1571) declares the Python constants as the authoritative source, and the plan says changing any of them without updating `decay.md` + `forge-config.md` "is a bug". This is the same discipline `shared/scoring.md` uses and prevents numeric drift across docs.
3. **Review feedback mapped task-by-task.** Section "Review-feedback integration" (L40-44) explicitly pins each of the three spec-review issues to the task that implements it. No silent "oh, we'll get to that" — every suggestion is an explicit test + implementation step.
4. **Legacy sweep is enumerated, not hand-waved.** Tasks 12-14 enumerate every file that still uses "10 unused / 5 unused / 3 unused" language, including non-obvious ones (`shared/agent-communication.md` L273/L302, `benchmarks/prompts.json` L15-16, `DEPRECATIONS.md` L91). Task 18 Step 4 does a final global grep to catch strays. `CLAUDE.md` gets the pointer update at L352 (matches our source-of-truth convention).
5. **Eval harness encodes the math.** Task 15 builds a type × age grid fixture (9 cells + 2 extras) and a shell harness that asserts expected tier per cell. The `fp_victim` cell (base 0.60, 2 days old, auto-discovered) is computed inline (`0.60 × 2^(-2/14) ≈ 0.5434 → MEDIUM`) — reviewers can re-verify the arithmetic. Task 16 wires it into CI.

---

## 3. Issues / recommendations (top 3, all non-blocking)

### Issue 1 — Misleading comment in eval harness (minor, cosmetic)

**Where:** Task 15, `tests/evals/memory_decay_eval.sh` (plan L1390).

**Observation:** The comment reads:
> `# Fresh (Δt=0) → full base (0.75) → MEDIUM (per thresholds, 0.75 is exactly HIGH boundary).`

The next three lines correctly assert HIGH. The `decay.md` table (Task 3 L322-325) uses half-open intervals: `c ≥ 0.75` is HIGH. The comment saying "→ MEDIUM" is wrong and contradicts the next three assertions. Low-risk (the asserts will catch any real regression) but a future reader could mistake it for ambiguity in the threshold convention.

**Recommendation:** rewrite the comment to `# Fresh (Δt=0) → base 0.75 → HIGH (0.75 is the HIGH boundary; c ≥ 0.75 = HIGH).`

### Issue 2 — Fixture extra (`fp_victim`) has no `type` key until migrator runs (minor)

**Where:** Task 15, plan L1361 (`fp_victim.json` description).

**Observation:** The fixture is described as "auto-discovered, `last_false_positive_at` 2 days ago" and has `base_confidence: 0.60`, but the shown JSON template for `auto_fresh.json` (L1312-1320) includes an explicit `"type": "auto-discovered"` field. The prose description for `fp_victim` doesn't list the exact JSON, so it's ambiguous whether the fixture author writes `type: auto-discovered` explicitly or relies on `_resolve_type` inference. For inference to return `auto-discovered`, the fixture would need a `source: auto-discovered` field (per `_resolve_type`). If the fixture author writes neither `type` nor `source`, the fallback is `cross-project` (HL=30), which changes the expected `c = 0.60 × 2^(-2/30) ≈ 0.573 → MEDIUM`. The harness still passes in this case (MEDIUM is the asserted tier) but for the wrong reason.

**Recommendation:** add one line to Task 15 Step 1 explicitly specifying the `fp_victim.json` contents in full, including `"type": "auto-discovered"` so the assertion tests what it claims to test (HL=14 path, not HL=30 path). Example:

```json
{
  "id": "fp_victim",
  "type": "auto-discovered",
  "base_confidence": 0.60,
  "last_success_at": "2026-04-17T12:00:00Z",
  "last_false_positive_at": "2026-04-17T12:00:00Z"
}
```

### Issue 3 — Task 14 frontmatter stamp uses `last_success_at: "2026-04-19T00:00:00Z"` but other examples use `T12:00:00Z` (nit)

**Where:** Task 14, plan L1269, L1277.

**Observation:** Task 14 hand-stamps shipped `shared/learnings/*.md` frontmatter with `last_success_at: "2026-04-19T00:00:00Z"` (midnight). Every other example and test fixture in the plan uses `2026-04-19T12:00:00Z` (noon) as the reference `now`. Two consequences:

1. If CI runs the eval harness with `NOW=2026-04-19T12:00:00Z` against a repo where shipped items were stamped at `T00:00:00Z`, there is a 12-hour offset in `Δt` — within floating-point tolerance for the decay formula and tier boundaries (`2^(-0.5/14) ≈ 0.9756` of base), but a real drift that could bite edge-case fixtures.
2. More importantly, the migration date is a convention; picking a consistent instant avoids confusion in subsequent grep/diff reviews of frontmatter.

**Recommendation:** standardize on one migration instant in Task 14 — either align it to the spec's reference `now` (`T12:00:00Z`) or pick an unambiguous convention (e.g. the merge commit timestamp). Not a correctness issue; a consistency one.

---

## 4. Verdict

**APPROVE — ready to execute.**

All 10 review criteria pass. The plan:

- Maps each spec section and review issue to a concrete task with tests.
- Follows TDD per task (fail → run → impl → run → commit).
- Uses Conventional Commits with `phase13` scope.
- Pins a single numeric source of truth (Python consts) and sweeps every doc that duplicates values.
- Ends with a verification-only pass (Task 18) that globs for legacy wording and for `decay.md` references everywhere they should exist.

The three issues above are cosmetic or consistency nits. Issue 2 (explicit `fp_victim.json` contents) is the most useful to fix before execution because it makes the test verify what it claims — a five-line addition to Task 15. Issues 1 and 3 can land inline during execution or in a post-merge sweep.

**Ready for `superpowers:executing-plans` / `superpowers:subagent-driven-development`.**

---

## 5. Relevant files

- Plan under review: `/Users/denissajnar/IdeaProjects/forge/docs/superpowers/plans/2026-04-19-13-memory-decay-ebbinghaus-plan.md`
- Spec: `/Users/denissajnar/IdeaProjects/forge/docs/superpowers/specs/2026-04-19-13-memory-decay-ebbinghaus-design.md`
- Spec review: `/Users/denissajnar/IdeaProjects/forge/docs/superpowers/reviews/2026-04-19-13-memory-decay-ebbinghaus-spec-review.md`
- New artifacts to be created:
  - `/Users/denissajnar/IdeaProjects/forge/hooks/_py/memory_decay.py`
  - `/Users/denissajnar/IdeaProjects/forge/shared/learnings/decay.md`
  - `/Users/denissajnar/IdeaProjects/forge/tests/unit/memory_decay_test.py`
  - `/Users/denissajnar/IdeaProjects/forge/tests/evals/memory_decay_eval.sh`
  - `/Users/denissajnar/IdeaProjects/forge/tests/evals/fixtures/memory_decay/` (11 JSON fixtures)
- Files to be modified:
  - `/Users/denissajnar/IdeaProjects/forge/agents/fg-700-retrospective.md`
  - `/Users/denissajnar/IdeaProjects/forge/agents/fg-100-orchestrator.md`
  - `/Users/denissajnar/IdeaProjects/forge/shared/learnings/README.md`
  - `/Users/denissajnar/IdeaProjects/forge/shared/learnings/memory-discovery.md`
  - `/Users/denissajnar/IdeaProjects/forge/shared/learnings/rule-promotion.md`
  - `/Users/denissajnar/IdeaProjects/forge/shared/knowledge-base.md`
  - `/Users/denissajnar/IdeaProjects/forge/shared/agent-communication.md`
  - `/Users/denissajnar/IdeaProjects/forge/shared/domain-detection.md`
  - `/Users/denissajnar/IdeaProjects/forge/CLAUDE.md`
  - `/Users/denissajnar/IdeaProjects/forge/DEPRECATIONS.md`
  - `/Users/denissajnar/IdeaProjects/forge/benchmarks/prompts.json`
  - `/Users/denissajnar/IdeaProjects/forge/forge-config.md`
  - every `/Users/denissajnar/IdeaProjects/forge/shared/learnings/*.md` with PREEMPT frontmatter
