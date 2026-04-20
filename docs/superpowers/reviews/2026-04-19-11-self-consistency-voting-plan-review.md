# Review — Phase 11 Self-Consistency Voting Implementation Plan

**Plan:** `/Users/denissajnar/IdeaProjects/forge/docs/superpowers/plans/2026-04-19-11-self-consistency-voting-plan.md`
**Spec:** `/Users/denissajnar/IdeaProjects/forge/docs/superpowers/specs/2026-04-19-11-self-consistency-voting-design.md`
**Spec review:** `/Users/denissajnar/IdeaProjects/forge/docs/superpowers/reviews/2026-04-19-11-self-consistency-voting-spec-review.md`
**Reviewer:** Senior Code Reviewer
**Date:** 2026-04-19
**Verdict:** APPROVE WITH MINOR REVISIONS

---

## 1. Criterion Check Matrix

| # | Criterion | Status | Notes |
|---|---|---|---|
| 1 | `writing-plans` format | PASS | Header with Goal/Architecture/Tech/Deps/Commit style. 14 tasks, each with Files, numbered Steps in checkboxes, explicit commit. Self-Review + Execution Handoff at tail. Matches the writing-plans contract. |
| 2 | No placeholders | PASS | No `TBD`, `TODO`, `FIXME`, `XXX`, `???`. Every code block is syntactically complete. Dataset items are seeded with real examples. |
| 3 | Type consistency (cache key) | PASS | `sha256(decision \0 state.mode \0 prompt \0 n \0 tier)` formula is identical across Task 1 (contract §3), Task 2 (test `_key` helper + `test_cache_key_includes_state_mode`), Task 3 (`cache_key` impl), Task 11 structural bats. `VoteResult` dataclass shape is identical across Task 1/2/3. |
| 4 | Each task commits | PASS | Tasks 1-13 each end with exactly one commit. Task 14 is explicitly validation-only with "No commit" step. Commit messages follow Conventional Commits (`docs(phase11):`, `test(phase11):`, `feat(phase11):`, `ci(phase11):`). |
| 5 | Spec coverage — 3 decision points | PASS | Tasks 6, 7, 8 wrap `fg-010-shaper` / `fg-210-validator` / `fg-710-post-run` with the exact label spaces from spec §4.4. |
| 5b | Spec coverage — aggregation | PASS | Task 2 tests all four cascade branches; Task 3 implements them. `aggregate()` + `aggregate_or_raise()` match spec §4.2 verbatim. |
| 5c | Spec coverage — cache | PASS | Task 1 defines schema, Task 2 tests roundtrip, Task 3 implements `cache_lookup`/`cache_append`. `.forge/consistency-cache.jsonl` survives reset (Task 12). |
| 5d | Spec coverage — fast-tier | PASS | `model_tier: fast` set in config defaults (Task 5). Helper respects `tier` parameter (Task 3). PREFLIGHT validates tier membership in `model_routing.tiers` (Task 5). |
| 5e | Spec coverage — labeled dataset | PASS | Task 9 creates three JSONL datasets with `difficulty` field and minimum per-intent counts. Matches spec §8.1. |
| 6a | Review feedback I1 — cost table | PASS | Task 1 §4 produces a per-seam delta table with latency (ms) and cost (~$ per 1M tokens). Spec I1 is closed. |
| 6b | Review feedback I2 — state.mode in cache key | PASS | Hard-committed in Tasks 1 (§3 formula + §3.1 rationale), 2 (`test_cache_key_includes_state_mode` asserts `k1 != k2`), 3 (`cache_key(..., state_mode, ...)` signature), 11 (structural bats greps for `state\.mode.*\\0`). Spec I2 is closed. |
| 6c | Review feedback I4 — validator INCONCLUSIVE gate | PASS | Task 7 rewrites §5 into 5.1 (deterministic rules, always runs) + 5.2 (voting only on `INCONCLUSIVE`). Structural bats greps for `INCONCLUSIVE` (Task 11). Spec I4 is closed. |
| 7 | Phase 02 + Phase 01 dependencies explicit | PASS | Header `Dependencies:` block names both phases + what each provides. Task 3 uses `hooks/_py/` layout (Phase 02). Task 10 places the runner under `evals/pipeline/` (Phase 01). Task 13 extends `.github/workflows/eval.yml` (Phase 01). |
| 8 | Eval harness labeled dataset task | PASS | Task 9 is a dedicated task. Each dataset has counts, difficulty split, schema, and real seed examples. |
| 9 | CI accuracy + latency gates | PASS | Task 11 `tests/contract/consistency-eval.bats` has 5 gates: unanimity >95%, adversarial low_consensus ≥80%, voted − single ≥5pp, cache correctness, p95 <2500ms. Task 13 wires them into `.github/workflows/eval.yml::consistency-eval`. |
| 10 | Deferred `/forge-insights` display update acknowledged | PASS | Self-Review §"Spec coverage" §6.5 explicitly flags the gap, marks it advisory, and records the deviation "for the reviewer". Counters are still written by the helper so pipeline function is not blocked. |

**Summary:** 14 PASS, 0 PARTIAL, 0 FAIL. All 10 review criteria satisfied.

---

## 2. Strengths

1. **Review-issue traceability is machine-checkable.** The header explicitly lists I1/I2/I4 resolutions AND the Self-Review re-verifies each one against concrete tasks. Task 11 structural bats literally `grep`s for `state\.mode.*\\0` and `INCONCLUSIVE`, so the resolutions can't silently regress.
2. **TDD discipline preserved.** Task 2 writes failing unit tests BEFORE Task 3 implements the helper. Task 4 writes a failing `state-schema.bats` assertion before editing `state-schema.md`. Matches superpowers:test-driven-development.
3. **Cache key evolution is internally consistent.** The five-field formula (`decision \0 mode \0 prompt \0 n \0 tier`) appears verbatim in six places (contract, test helper, test assertion, impl, structural bats grep, acceptance JSONL log) with zero drift. This is the hardest part of a multi-touch plan to get right.
4. **Validator scope fence is over-specified.** Task 7 §5.1 adds an explicit `INCONCLUSIVE` row to the rule table AND says "Voting is SKIPPED. `consistency_votes.validator_verdict.invocations` is NOT incremented." This removes all ambiguity about when voting fires and makes the cost analysis tight (most runs skip voting at the validator).
5. **Offline eval determinism.** Task 10's `offline_sampler` uses `hashlib.sha256(f"{prompt}|{seed}")` as the RNG seed, so CI results are byte-identical across runs. Task 11 bats can assert exact accuracy numbers without flakiness. The `rng.random() < 0.35` adversarial-disagreement threshold is called out as the only tuning knob.
6. **Cache correctness has a real contract test.** Task 11 @test "cache correctness" runs the dispatch twice end-to-end with a random sampler and asserts second-pass `cache_hit=True` AND identical labels. This catches both misses (new sampler rolls) and stale reads (key collision).
7. **Conventional Commits with no AI attribution.** Every commit message is Conventional-Commits-formatted, no `Co-Authored-By`, no `--no-verify`. Matches CLAUDE.md §Git rules and the repo convention of clean, terse commit messages without AI attribution.
8. **Self-Review section is honest about the one gap.** The `/forge-insights` display-update deferral is flagged in Self-Review §"Spec coverage" as "GAP spotted in self-review ... explicit deviation recorded here for the reviewer" rather than buried or omitted. This is exactly the discipline the review criterion asked for.

---

## 3. Issues

### I1 — `/forge-insights` display-update deferral needs a follow-up PR reference or task placeholder (IMPORTANT)

**Location:** Self-Review §"Spec coverage", last bullet.

**Problem:** Spec §6.5 says "`/forge-insights` gains a Consistency Voting section showing cache hit rate, low-consensus rate per decision point, and flipped-verdict count." The plan acknowledges this is deferred, but does not:

- Open a tracking follow-up (no linked ticket / PR number / TODO issue).
- State the target phase or date.
- Add a `@test "TODO /forge-insights consistency section"` stub or pending-skip in the bats file to guarantee the gap is picked up.

Without one of these, the deferral will be forgotten until a user runs `/forge-insights` in production and sees the counters are being written but not surfaced. This matches the project's standing rule that the forge pipeline must match or exceed external reviewers — no `source: builtin` delegation.

**Recommendation:** Add to the Self-Review a single bullet:

```
- [ ] Follow-up: open an issue titled "Phase 11 follow-up — /forge-insights
      Consistency Voting section" referencing spec §6.5 and linking to this plan.
      Blocked on this PR merging; not a merge blocker for Phase 11.
```

Or, equivalently, add Task 15 marked "Deferred — open as a tracking issue after Phase 11 ships." Either makes the deferral observable.

**Severity:** Important (the spec's only scope item not covered by the plan; needs a visible tombstone so it doesn't silently drop).

---

### I2 — `vote()` sync wrapper is called directly by agents but `hooks/_py/consistency.py` lives in a Python-hook tree the agents cannot invoke from markdown (IMPORTANT)

**Location:** Tasks 6, 7, 8 — agent `.md` bodies say things like "Dispatch via `hooks/_py/consistency.py`... Increment `state.consistency_votes.shaper_intent.invocations` by 1."

**Problem:** forge agents are `.md` system prompts loaded by the orchestrator; they do not execute Python. The dispatch has to be invoked either (a) by a hook that fires on the agent's decision emission, (b) by a shell script the agent invokes via `Bash`, or (c) by the orchestrator on the agent's behalf after it reads a specific marker in stage notes.

The plan never names the invocation mechanism. The contract §1 says "The caller does NOT re-invoke dispatch" on `ConsistencyError`, which implies the caller IS the invoker — but the caller is an LLM subagent, and no task wires up a bridge (e.g., a PostToolUse hook that reads a `CONSISTENCY_VOTE_REQUEST:` marker from the agent's output and runs `python3 hooks/_py/consistency.py --decision ... --prompt ...`).

Compare to how `fg-210-validator` today emits findings: the agent produces text, the orchestrator parses it. The same shape is needed here — the agent emits a *request* marker, a hook or the orchestrator dispatches the helper, result is written back into the agent's context.

**Recommendation:** Add a Task 6.5 (between current 6 and 7) titled "Wire the agent-to-helper dispatch bridge":

- Decide: hook vs. orchestrator vs. Bash subcommand. The cheapest is a `Bash` invocation inside the agent: `python3 hooks/_py/consistency_cli.py --decision shaper_intent --prompt-file /tmp/x --labels-file /tmp/y --state-mode "$state_mode"` → JSON on stdout → agent parses.
- Add `hooks/_py/consistency_cli.py` (~40 lines) that argparses the `vote()` kwargs and prints the `VoteResult` as JSON.
- Update Tasks 6/7/8 to call this CLI via the Bash tool with the exact command line.
- Add a structural bats test that each of the three agents references `python3 hooks/_py/consistency_cli.py` in its instructions.

Without this bridge task the plan is technically incomplete — the `.md` agents cannot actually invoke Python. The plan appears to implicitly assume a bridge exists from Phase 02, but Phase 02's spec only provides `state_write.py` (atomic writes), not a dispatch entry point.

**Severity:** Important (implementation gap that blocks end-to-end function; the helper will be dead code without it).

---

### I3 — Eval harness p95 latency gate on `--offline` mode is vacuous (SUGGESTION)

**Location:** Task 11 @test "p95 elapsed time per decision point is under 2500 ms."

**Problem:** The offline sampler is pure Python arithmetic (no network, no LLM call). Its p95 elapsed time will be ~1 ms, well below the 2500 ms gate. The gate cannot fail, so it cannot detect a real latency regression — it only proves the harness ran.

Spec §8.2 assertion 5 says "p95 added latency per decision point is under 2.5 s **on the fast tier**." The "fast tier" qualifier is load-bearing — the gate is meaningful only when the sampler is doing real inference.

**Recommendation:** Either:

1. Remove the p95 gate from the `--offline` bats run and move it to an `--live` CI job (Task 13 already has a `live_sampler` stub — wire the gate there, gated on a `FORGE_EVAL_MODE=live` env var so it doesn't run on PRs that lack API credentials), OR
2. Reword the gate as "p95 elapsed time < 100ms in offline mode" so it at least catches pathological regressions in the helper itself (e.g., an accidental blocking I/O call in `aggregate`).

The current form passes trivially and gives false confidence.

**Severity:** Suggestion (the gate isn't *wrong*, it's just not doing what the spec §8.2.5 success criterion intends).

---

### I4 — Task 5 PREFLIGHT table omits the `cache_enabled` validation row referenced by PREFLIGHT scan (SUGGESTION)

**Location:** Task 5 Step 1 — constraints table in `shared/preflight-constraints.md`.

**Problem:** The table lists `consistency.enabled`, `n_samples`, `decisions`, `model_tier`, `cache_enabled`, `min_consensus_confidence`. That's six rows. But Task 11 structural bats only asserts five (`consistency.enabled`, `n_samples`, `decisions`, `model_tier`, `min_consensus_confidence` — see the `for field in` loop). `cache_enabled` is dropped from the structural check.

This is minor — `cache_enabled` is documented in the table and validated by PREFLIGHT at runtime — but the structural test should match the table to prevent future drift (someone deleting the `cache_enabled` row from the constraints file would not trip the wiring test).

**Recommendation:** Add `'consistency\.cache_enabled'` to the `for field in` list in Task 11's `tests/structural/consistency-wiring.bats` @test "PREFLIGHT constraints cover the five consistency.* fields" (and rename the test to "six fields").

**Severity:** Suggestion (cosmetic; test hygiene, not correctness).

---

### I5 — Task 9 dataset-size math is off by one (SUGGESTION)

**Location:** Task 9 Step 2 — "Minimum per-intent counts (easy / adversarial): bugfix 10/2, migration 8/2, bootstrap 6/2, multi-feature 6/2, vague 6/2, testing 6/2, documentation 6/2, refactor 6/2, performance 6/2, single-feature 16/2 = 100 total (76 easy + 20 adversarial, rounded)."

**Problem:** Summing: easy = 10+8+6+6+6+6+6+6+6+16 = 76. Adversarial = 2×10 = 20. Total = 96, not 100. The spec §8.1 says "~100 prompts." The math is close to right but the plan claims exactly 100 in one place and the per-intent breakdown only reaches 96. The author either meant ~100 (should add "~" to the "100 total" claim) or missed 4 entries.

**Recommendation:** Either (a) bump `single-feature` to `20/2` (yielding exactly 100) for symmetric test coverage on the most common label, or (b) add "~" to the "100 total" summary line. Non-blocking; pick the simpler fix.

Same kind of rounding is present in `validator_verdict` (20 GO + 25 REVISE + 15 NO-GO = 60 ✓) and `pr_rejection` (15 + 15 + 10 = 40 ✓) — those two are clean.

**Severity:** Suggestion.

---

## 4. Alignment With Project Conventions

- **Matches writing-plans contract:** Goal + Architecture + Tech Stack + Dependencies + Commit style header; numbered tasks with Files + Steps + Commit; Self-Review + Execution Handoff tail. 100% shape match.
- **Matches `shared/` discipline:** Task 1 creates `shared/consistency/voting.md` as a contract document, agents reference it in Tasks 6/7/8 rather than inlining. Correct per CLAUDE.md "Core contracts" philosophy.
- **Matches state schema versioning:** Task 4 bumps `_seq` 1.6.0 → 1.7.0, updates in-place upgrade table, writes failing-test-first. Correct per `shared/state-schema.md` convention.
- **Matches PREFLIGHT constraints pattern:** Task 5 appends to `shared/preflight-constraints.md`, agents/callers don't duplicate validation. Correct per CLAUDE.md Gotchas.
- **Matches "survives reset" discipline:** Task 12 adds `.forge/consistency-cache.jsonl` to the CLAUDE.md list alongside `explore-cache.json`, `plan-cache/`, etc.
- **Matches TDD philosophy:** Task 2 writes failing tests, Task 3 makes them pass; Task 4 writes failing bats assertions, then edits schema. Pair of red-green cycles in the first five tasks.
- **Matches the repo's testing discipline:** Task 14 smoke-runs locally but does not gate on a full test suite — the gates are in `.github/workflows/eval.yml` via Task 13. Matches the repo convention of running full test suites in CI, not locally.
- **Matches the repo's implementation workflow:** Code review after each phase, version bump + tag + push + release — the plan's 14-task structure naturally enables this (commit per task → review → next task).
- **Matches Conventional Commits:** Every commit message uses `type(scope):` form, no `Co-Authored-By`, no AI attribution, no `--no-verify`.

No deviations from established patterns.

---

## 5. Plan Deviation Assessment

Spec vs. plan:

- **3 decision points + agent edits:** Delivered (Tasks 6/7/8).
- **Dispatch helper + `VoteResult`:** Delivered (Tasks 2/3).
- **Cache with `state.mode` in key:** Delivered across six locations.
- **INCONCLUSIVE gate for validator:** Delivered (Task 7).
- **Cost delta table:** Delivered (Task 1 §4).
- **Labeled dataset + eval harness + CI gates:** Delivered (Tasks 9/10/11/13).
- **PREFLIGHT + config defaults + state bump + CLAUDE.md:** Delivered (Tasks 4/5/12).

Gaps:

- **`/forge-insights` display update:** Explicitly deferred and flagged in Self-Review. Needs a tracking mechanism (Issue I1).
- **Agent-to-Python dispatch bridge:** Implicit — not a spec gap, but a plan gap (Issue I2). The spec reads as if `consistency.vote(...)` is invocable from an `.md` agent, but in practice agents need a Bash CLI or hook to invoke Python. This is the main thing to fix before execution starts.

Everything else maps 1:1. The scope of the plan matches the spec's in-scope list.

---

## 6. Verdict

**APPROVE WITH MINOR REVISIONS.**

The plan is well-structured, review-feedback-traceable, TDD-disciplined, and internally consistent. It resolves all three spec-review issues (I1 cost table, I2 `state.mode` in cache key, I4 validator INCONCLUSIVE gate) with machine-checkable tests. The 14-task decomposition is sensibly-sized for per-task commit discipline and review loops.

**Before execution starts:**

1. Resolve Issue I2 (agent-to-Python bridge) — add a Task 6.5 wiring step. This is a merge blocker because the helper is dead code without a bridge.
2. Resolve Issue I1 (track the `/forge-insights` deferral) — single bullet or follow-up task.

I3–I5 are non-blocking suggestions for test hygiene.

The plan is READY for execution (`superpowers:subagent-driven-development` or `superpowers:executing-plans`) once I1 and I2 are addressed.

---

## 7. Artifacts Touched

- **Reviewed:** `/Users/denissajnar/IdeaProjects/forge/docs/superpowers/plans/2026-04-19-11-self-consistency-voting-plan.md`
- **Referenced for coverage check:**
  - `/Users/denissajnar/IdeaProjects/forge/docs/superpowers/specs/2026-04-19-11-self-consistency-voting-design.md`
  - `/Users/denissajnar/IdeaProjects/forge/docs/superpowers/reviews/2026-04-19-11-self-consistency-voting-spec-review.md`
- **Review written to:** `/Users/denissajnar/IdeaProjects/forge/docs/superpowers/reviews/2026-04-19-11-self-consistency-voting-plan-review.md`
