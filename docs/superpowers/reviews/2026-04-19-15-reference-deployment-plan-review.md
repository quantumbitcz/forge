# Review: Phase 15 Reference Deployment Implementation Plan

**Plan:** `/Users/denissajnar/IdeaProjects/forge/docs/superpowers/plans/2026-04-19-15-reference-deployment-plan.md`
**Spec:** `/Users/denissajnar/IdeaProjects/forge/docs/superpowers/specs/2026-04-19-15-reference-deployment-design.md`
**Spec review:** `/Users/denissajnar/IdeaProjects/forge/docs/superpowers/reviews/2026-04-19-15-reference-deployment-spec-review.md`
**Reviewer role:** Senior Code Reviewer
**Date:** 2026-04-19
**Verdict:** APPROVE WITH MINOR REVISIONS

---

## Summary

The plan is 16 tasks over 1534 lines with explicit commits per task, structured templates, shell verifications, and a thorough self-review checklist mapping every spec §§ and every review issue (I1/I2/I3, S1-S5, nits) to concrete tasks. The Phase 01-14 dependency gate is called out in the header `Dependencies:` line and again in the self-review checklist. Spec coverage is complete: shortlist (T1), license review + a.1/a.2 split (T3-T4), fork + rewrite (T5-T6), evidence (T7-T9), case study (T11), plugin.json badge (T14), marketplace PR (T12/T14), quarterly cron (T13), secret scrub (T6 Step 5 + T9 Step 2), selection bias disclaimer (T2, T11).

Issues below are refinements, not blockers.

---

## Criteria checklist

| # | Criterion | Status | Notes |
|---|---|---|---|
| 1 | writing-plans format | PASS | Goal / Files / numbered Steps / `- [ ]` checkboxes / commit command per task. Matches superpowers:writing-plans convention. |
| 2 | No placeholders | PASS-WITH-CAVEAT | No `TODO`/`TBD`. Templated variables (`<lib-name>`, `<upstream-tag>`, `<SHA>`) are execution-time fills and are explicitly declared as such in §Self-Review #3. However, Task 1 intentionally ships a document with `<fill>` markers for the human research step (resolved in Task 1 Step 3 via grep assertion). Acceptable given the research-gated workflow, but see I1 below. |
| 3 | Type consistency | PASS | `evidence.json.verdict`/`.score`, `state.json.components`/`.plan.challenge_brief`/`.score_history` match spec and state-schema v1.6.0. Branch/tag names consistent across Tasks 5-10. `forge-590-pre-ship-verifier` contract respected. |
| 4 | Each task commits | PASS | Every task has a commit step; Task 4 is a wait-gate that commits the checkbox flip; Tasks 5-9 commit in both fork and forge repos where appropriate; post-merge updates (T14 Step 7) commit together. |
| 5 | Spec coverage: shortlist, license, fork+rewrite, evidence, case study, badge, marketplace, cron | PASS | T1 (shortlist), T3 (license), T5-T6 (fork+rewrite), T7-T9 (evidence), T11 (case study), T14 (badge + plugin.json bump), T12+T14 (marketplace), T13 (cron). |
| 6 | Review feedback: 3 named candidates, a.1/a.2 split, SC#3 relaxed | PARTIAL | I1 addressed in *structure* (Task 1 names slots for three concrete repos) but does NOT name them — the template still has `<fill>` placeholders for repo URLs. I2 addressed: T1 = freeze, T3 = pick-one. I3 addressed: T14 Step 5 + T15 resubmission loop + T16 SC#3 language. See I1 below. |
| 7 | Selection bias mitigation | PASS | T2 (index disclaimer), T11 (case study "What this does not prove"), ADR 1 Consequences (T8). Phase 15.1/15.2 fallback named. |
| 8 | Phase 01-14 dependency gate | PASS | Header `Dependencies:` line is explicit: "Phases 01-14 must be shipped before Phase 15 rollout step (c). Rollout step (a.1) and (a.2) can begin earlier but nothing ships publicly until 01-14 are live." Self-review #1 reaffirms. |
| 9 | Quarterly cron workflow | PASS | T13 ships canonical YAML to forge repo + copies into fork. Cron matches spec §8.2 (`0 0 1 */3 *`). Workflow has permissions, secret injection, scrub step, TRAJECTORY.md append, PR open with regression label. T13 Step 4 runs workflow_dispatch once to satisfy SC#4. |
| 10 | Secret scrub task | PASS | T6 Step 5 scrubs pre-commit; T9 Step 2 scrubs the tarball; T13 scrubs in the quarterly workflow. Patterns cover `sk-ant-`, `ANTHROPIC_API_KEY`, `ghp_`/`gho_`/`ghs_`, `AKIA`, `/Users/` (per review S3). Self-referential lib-scan optional in T6 Step 5. |

---

## Issues

### Important (should fix before Task 1 executes)

**I1. Task 1 template ships `<fill>` placeholders that contradict spec-review I1's "name three concrete repos" requirement.**
Spec-review I1 said: "before the spec leaves Draft, resolve #2 and #3 to concrete repo URLs". The plan's Task 1 defers that to a "human research step" (Task 1 Step 2) with the `<fill>` pattern. This is reasonable given the research workload, but the plan itself is the handoff artifact — a downstream agent executing this plan has no way to know *which* three repos to research without doing open-ended GitHub search. **Fix:** either (a) pre-populate the three candidate URLs in the plan now with tentative picks (marked "verify at execution"), or (b) add explicit `gh search` queries whose top-3 results *are* the shortlist (not just "suggested search approach"). Current wording ("Suggested search approach") is a hint, not a deterministic input.

**I2. Task 6 `/forge-run` invocation assumes Claude Code can drive a pipeline inside a GitHub Actions runner or local shell — but the instruction "Open Claude Code and run: /forge-run ..." is for a human sitting at a terminal.**
Task 13's quarterly refresh workflow calls `./.claude/plugins/forge/shared/forge-sim.sh "quarterly refresh ..."` — a simulation harness, not a real pipeline run. If the goal is "zero hand-patching", the initial rewrite in T6 *must* be a real pipeline run. The plan does not address how a real `/forge-run` executes headlessly in CI, nor how the quarterly refresh reconciles `forge-sim.sh` output with real `evidence.json`. **Fix:** either (a) declare T6 as human-interactive only, explicitly (current wording is ambiguous), and (b) document in T13 that `forge-sim.sh` is a placeholder whose real implementation depends on a future Claude Code CLI headless mode — or replace with a manual-trigger-only workflow.

**I3. Task 14 Step 4 `--body-file /path/to/forge/docs/marketing/submission-checklist.md#pr-body-template` uses a URL fragment syntax that `gh pr create --body-file` does not support.**
`gh` reads the whole file; anchors are ignored. The PR body will include the entire submission checklist, not just the PR body template section. **Fix:** extract the PR body template to a standalone file (e.g. `docs/marketing/submission-pr-body.md`) during T12, or inline the body via `--body "$(sed -n '/^## PR body template/,/^## /p' ...)"`.

### Suggestions (nice to have)

**S1. Task 5 Step 2 `gh repo fork ... --org forge-reference-deployments` requires the destination org to exist.**
Task 5 Step 1 creates the org via web UI (blocking instruction). Fine, but the plan should note that `gh` alone cannot do this — it is already hinted ("`gh` CLI does not create orgs") but the flow ordering deserves explicit emphasis: the web UI step is a strict prerequisite and no retry logic handles a "org not found" failure from Step 2.

**S2. Task 7 Step 4 "Disable issues and PRs" comment correctly notes PRs cannot be fully disabled, but the follow-up branch-protection rule is described loosely ("document in README").**
For R8 mitigation to be real, the protection rule should be a concrete `gh api` call or a `settings.yml` file. Current wording lets this mitigation decay.

**S3. Task 9 Step 1's sqlite export query assumes `.forge/run-history.db` has a `runs` table with `run_id/score/tokens/elapsed/created_at` columns.**
Verify against `shared/run-history/` schema before Task 9 executes. If column names differ, the `sqlite3` invocation will silently produce `null` values in the bundle.

**S4. Task 13's branch-name computation uses `date +%Y-Q$(( ( $(date +%-m) - 1 ) / 3 + 1 ))`.**
This works on GNU date but `%-m` is not POSIX. GitHub Actions ubuntu-latest ships GNU date so fine, but if the workflow ever runs on a Mac or BSD runner, this silently breaks. Cheap fix: replace with `date +%Y-Q%q` (quarter specifier, supported by GNU coreutils ≥9) or pre-compute in bash with a portable expression.

**S5. Task 15's "ship at 75%" is asserted but not unit-tested.**
If SC#3 is relaxed to "PR opened + feedback responded", the pass/fail logic in T16 Step 3 needs a concrete check: "at least one commit on submission branch after the first reviewer comment" or similar. Without it, "responded to" is subjective.

### Nits

- T10 Step 6 shields.io badge: `reference-<lib--name>-blue`. Correct per review nit, but `<lib--name>` will be confusing to a plan reader who has not seen the nit — add an inline comment referencing spec-review nit.
- T14 Step 6 post-merge plugin.json bump is 3.0.0 → 3.0.1. CLAUDE.md currently references v3.0.0 (master). Make sure the plan notes it should *also* update any `version:` reference in CLAUDE.md that tracks the plugin version explicitly.
- T8 Step 1 "Read the fork's `.forge/state.json`" — the fork is a separate checkout on the operator's machine; the plan never clarifies whether ADR.md is authored while both checkouts are side-by-side or via round-trip commits. Suggest a single "working directory map" block at the top of the plan (forge checkout at X, fork checkout at Y).
- Self-review checklist §4 claims `forge-590-pre-ship-verifier` but the agent is `fg-590-pre-ship-verifier`. Typo.

---

## What was done well

- **Review-driven adjustments section at the top.** Every review issue (I1, I2, I3) maps to a specific task — makes traceability automatic.
- **Commit cadence per task is disciplined.** Each task ends with a commit; Task 4 (wait-gate) even commits the checkbox flip so the 14-day clock is auditable in git log.
- **Explicit "forge repo vs fork repo" separation.** Tasks 5-7/9/13 are dual-repo; the plan is careful to say which `git add` targets which working directory. Path annotations like `git -C /Users/.../forge` in Task 5 Step 5 prevent the common error of committing fork-only files to forge.
- **Gating rule for publishing headline numbers (S4).** T9 Step 3 + T10 Step 1 enforce "verdict=SHIP AND score≥80 else pending". This prevents the "we shipped a 62 CONCERNS run and called it a reference deployment" failure mode.
- **Resubmission branch (T15).** Phase 15.0.1 with resubmission-log.md + explicit "ship at 75%" fallback — prevents the phase from hard-failing on an Anthropic rejection.
- **Self-review checklist is load-bearing, not decorative.** It concretely maps every spec section and every review issue to tasks. This should be standard for future plans.

---

## Recommendation

**APPROVE** to advance to Task 1 execution after addressing **I1** (pre-populate candidate URLs or provide deterministic `gh search` commands) and **I3** (fix the `gh pr create --body-file` anchor syntax). **I2** (headless `/forge-run` feasibility) can be deferred until Task 6 is reached but should be flagged on Task 6's execution checklist. S1-S5 and nits are cleanup that can land during execution without blocking.

Phase 15 is ready to start rollout step (a.1).
