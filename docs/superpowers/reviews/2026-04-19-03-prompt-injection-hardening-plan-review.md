# Review — Phase 03 Prompt Injection Hardening Implementation Plan

**Plan:** `/Users/denissajnar/IdeaProjects/forge/docs/superpowers/plans/2026-04-19-03-prompt-injection-hardening-plan.md`
**Spec:** `/Users/denissajnar/IdeaProjects/forge/docs/superpowers/specs/2026-04-19-03-prompt-injection-hardening-design.md`
**Spec review:** `/Users/denissajnar/IdeaProjects/forge/docs/superpowers/reviews/2026-04-19-03-prompt-injection-hardening-spec-review.md`
**Reviewer:** Senior Code Reviewer (Claude)
**Date:** 2026-04-19
**Verdict:** APPROVE WITH MINOR FIXES

---

## Criteria checklist

| # | Criterion | Status | Evidence |
|---|-----------|--------|----------|
| 1 | writing-plans format (checkbox steps, file list, TDD) | PASS | Every task uses `- [ ]` steps with Files / Step 1 test / Step 2 fail / Step 3 impl / Step N commit pattern. Uses the required sub-skill hint at top. |
| 2 | No placeholders | FAIL (minor) | `INJA-OVERRIDE-004` (line 184) is a deliberate typo with a note ("replace with `INJ-OVERRIDE-004` when writing"). Real content, but a foot-gun — see Issue #1. Task 21 benchmark script has a duplicate trailing `OUT` heredoc marker (line 2220–2221) — stray token. |
| 3 | Type consistency | PASS | `FilterResult`, `Finding`, `MAX_ENVELOPE_BYTES`, `MAX_AGGREGATE_BYTES`, `TIER_TABLE`, `CONSUMER_SOURCES`, `CATEGORY_TO_REGISTRY`, `EVENTS_PATH` consistent across Task 3 module, Task 4 Bats, all scenarios, and the tier-mapping-complete structural test. |
| 4 | TDD ordering | PASS | Tasks 1, 2, 3, 5, 6, 13, 19 explicitly Write-failing-test → Run-to-fail → Implement → Run-to-pass. Eval scenarios (14–16) follow the same cadence. |
| 5 | Each task commits | PASS | All 23 tasks end with a `git commit` step except Task 23 (final verification sweep, acceptable — no changes to commit). |
| 6 | Spec coverage — envelope, trust tiers, 42 agents, MCP filter, detection patterns, adversarial evals | PASS | Envelope → Task 2. Trust tiers → Tasks 2, 3 (TIER_TABLE). 42 agents → Tasks 6+7. Filter → Task 3. Patterns → Task 1. Adversarial evals → Tasks 14, 15, 16 (10 scenarios). |
| 7 | Spec review feedback addressed | PASS | §"Review feedback incorporated" at top of plan addresses all three Important items: plan-cache tier (Task 2), SEC-INJECTION-HISTORICAL registration (Task 5), byte-unit standardization (Tasks 2, 3, 18). Suggestions #4–#7 also addressed. |
| 8 | Bulk-update of 42 agent headers is one task or coherent set | PASS | Tasks 6 (SHA256 verifier + structural test, TDD-first) and 7 (idempotent `apply-untrusted-header.sh` + bulk apply + commit) form a coherent pair. Test lands before the mutation, exactly as it should. |
| 9 | Adversarial eval scenarios task present (depends on Phase 01) | PASS WITH NOTE | Tasks 14 (scenario 01), 15 (scenarios 02–05), 16 (scenarios 06–10) ship all 10 adversarial scenarios the spec §8.3 requires. Each scenario has fixture, bats, README. **Note:** the spec §8.3 preamble says "shares the Phase 01 eval harness," but the plan implements the scenarios as direct Bats + pytest-style tests under `tests/evals/scenarios/` without integrating with a Phase 01 harness. See Issue #3. |
| 10 | Standard agent header text verbatim in plan | PASS | The canonical block appears verbatim in Task 6 step 1 (verifier heredoc, line 1036–1038) and Task 7 step 1 (apply heredoc, line 1136–1138). Byte-for-byte identical. Spec §4.3 text matches both. SHA256 structural enforcement guarantees drift resistance. |

---

## What was done well

- **Review-feedback table at the top of the plan** explicitly binds each Important spec-review issue to a task number. This makes review-trace auditable without scanning all 23 tasks.
- **TDD cadence is unusually clean.** Task 3 writes ten pytest cases for the filter before any source; Task 6 writes the SHA256 verifier before any agent is modified; Task 19 writes three Bats cases for the gate before the script exists.
- **SHA256-anchored header text.** Rather than relying on a prose spec for the 120-word block, the plan makes the verifier script the source-of-truth (`tools/verify-untrusted-header.sh`), then the apply script uses the same heredoc. Drift is impossible as long as both heredocs stay in sync — and they are byte-identical in the plan.
- **Scenario 10 ordering pragmatism.** Task 16 step 5 correctly recognizes that Scenario 10 depends on Task 20's `preflight-injection-check.sh`, explicitly says "mark XFAIL or reorder," and Task 20 step 3 un-skips it. Honest about cross-task ordering.
- **Task 7 step 4 "spot-check one agent file"** with exact expected line numbers is the kind of grounded verification many plans skip.
- **Every code block is complete, runnable content.** Tests, modules, and scripts are shown in full, not sketched.

---

## Issues

### Important (fix before execution)

1. **Deliberate typo `INJA-OVERRIDE-004` in Task 1 Step 4 seed JSON (line 184).** Plan leaves the bad ID in the shown payload with a note to fix it on write. An executing agent following the plan literally may copy-paste the bad ID, then the schema's `^INJ-[A-Z_]+-\d{3}$` regex will reject the file and the test will fail for the wrong reason. Replace the payload with the correct ID (`INJ-OVERRIDE-004`) and move the "IDs are authoritative" note to a comment — don't smuggle a trap into copy-pasted content.

2. **Task 21 benchmark script has a duplicated trailing heredoc marker.** Lines 2220–2221:

       typical per-run (18 dispatched avg): ~$per_run_tokens tokens
       OUT
       OUT

   The second `OUT` is outside the heredoc and will be interpreted as a command, causing `command not found: OUT` at runtime. The test on line 2235 will fail. Delete the stray second `OUT`.

3. **Scenario 10 bats uses `$ROOT` but `$ROOT` is not defined in the snippet shown (line 1795).** Task 16 Step 5 shows a bats assertion `run bash "$ROOT/shared/preflight-injection-check.sh" ...` without a `setup()` block that assigns `ROOT`. Scenarios 01–09 all set `ROOT` in `setup()`. Scenario 10 must as well, or the run will fail with an unresolved variable.

### Suggestions (nice to have)

4. **Phase 01 harness integration gap.** Spec §8.3 preamble: "The Phase 01 eval harness is extended with an `injection-redteam` suite." The plan instead ships standalone Bats scenarios under `tests/evals/scenarios/injection-redteam/`. Functionally equivalent, but if Phase 01 introduces a harness with aggregate reporting, convergence metrics, or CI glue, the standalone approach will need to be retrofitted. Add a brief note in Task 14 that the scenarios follow the Phase 01 harness's directory convention and can be enumerated by a future aggregator.

5. **Task 13's orchestrator wiring is prose-only.** The test asserts `grep -q "hooks/_py/mcp_response_filter.py"` — which is satisfied by the markdown edits. There's no test that the orchestrator actually calls the filter at runtime. That's acceptable for a doc-only plugin, but worth calling out so no one mistakes markdown references for runtime wiring. Task 17's e2e test exercises the filter directly, not through the orchestrator.

6. **Task 18 (forge-config templates) lacks a test.** Every other modification task has a structural test; Task 18 only has a `grep -l ... | wc -l` shell check in Step 3. A `tests/structural/config-templates-have-injection-block.bats` would fit the pattern and prevent regression if a new framework is added.

7. **Task 20's YAML parsing is fragile.** `preflight-injection-check.sh` uses `grep -Eq '^\s+enabled:\s*false\s*$'` near a heading it located separately. A `security: { untrusted_envelope: { enabled: true }, injection_detection: { enabled: false } }` config could be misclassified because the script doesn't track YAML scope. A minimal Python one-liner using `yaml.safe_load` would be robust; the project already requires Python 3.10+.

8. **Task 22 Step 1 says "single occurrence" for `marketplace.json`.** If `marketplace.json` has the version in multiple fields (e.g. top-level + per-plugin entry), this will silently miss one. Recommend `grep -c '"version"' marketplace.json` as a verification step before the edit.

---

## Verdict

**APPROVE WITH MINOR FIXES.**

All 10 review criteria pass substantively. The three Important issues (typo trap, stray heredoc marker, undefined `$ROOT` in scenario 10) are mechanical fixes — each is a single-line edit. None requires re-planning. Plan is executable after those three corrections. Suggestions 4–8 are worth addressing opportunistically during execution but do not block.

Recommend proceeding to execution after Important issues addressed.
