# Plan 01: Evaluation Harness — Code Review

**Plan:** `docs/superpowers/plans/2026-04-19-01-evaluation-harness-plan.md`
**Reviewer:** superpowers:code-reviewer
**Date:** 2026-04-19

## Verdict: CONCERNS

## Strengths
- Comprehensive architectural coverage: 20 tasks across 2815 lines covering schema, executor, judge, reporter, CLI, CI, and 10 scenarios.
- Addresses all three blockers from the spec review (wall-clock timing semantics, canonical field naming, baseline snapshot strategy).
- Strong TDD discipline in the early tasks (2/3, 4/5, 7/8 split red-phase test commits from green-phase implementation commits).
- Explicit acceptance criteria per task with measurable verification steps.
- Scenario taxonomy is well-scoped: each scenario has prompt + expected-yaml contract, enabling deterministic judging.

## Critical
- None.

## Important
1. **Task 18 Step 3 placeholder violation** — Scenarios 05 (Go), 06 (Rust), and 10 (PHP) provide only `expected.yaml` and `prompt.md` bodies. Fixture contents are deferred with "follow the same recipe" prose instead of `cat > ...` heredocs with concrete file bodies. This violates the no-placeholder rule from the writing-plans skill. Remediation: either expand Task 18 inline with full heredocs for all three scenarios, or split into Task 18a/18b/18c per language so each has its own self-contained step.
2. **TDD ordering gap for executor/report/CLI** — The plan's self-review admits the executor, report generator, and CLI tasks lack preceding failing tests; the justification is "validated by CI." This substitutes end-to-end CI validation for the red-green-refactor discipline required by the writing-plans skill. Remediation: add explicit test-first sub-tasks (write failing test → commit red → implement → commit green) for each of the three components, matching the pattern established by Tasks 2/3, 4/5, and 7/8.
3. **Task 6 collapses red + green into one commit** — Tests and implementation land together in a single commit, breaking the red/green separation used consistently elsewhere in the plan. Remediation: split Task 6 into Task 6a (write failing tests, commit) and Task 6b (implement until green, commit).

## Minor
- Consider cross-referencing the spec review resolutions (wall-clock/field-name/baseline) explicitly in the plan preamble so future maintainers can trace the decisions.
- Scenarios 05/06/10 lacking concrete fixtures also means their acceptance criteria cannot be verified at plan-read time — reviewer had to infer intent. Inline bodies fix this as a side effect.

## Overall assessment
CONCERNS: The plan is comprehensive on architecture (20 tasks, 2815 lines) and resolves the spec-review's three blockers (wall-clock, field-name, baseline). However, the fixture-deferral and TDD-compression issues must be resolved before execution — either by expanding Task 18 inline or by splitting it per-scenario, and by splitting Task 6 into red + green commits. Implementers should read this review before starting and patch the plan as their first action.
