# State Machine Transition Table

Formal, deterministic transition table for all orchestrator control flow decisions. This is the **single source of truth** for state transitions — prose descriptions in agents and other documents describe *why*, this table specifies *what happens*.

## Design Principle

**Deterministic scaffolding, LLM judgment where it matters.**

Control flow (which state comes next, when to retry, when to escalate) is fully determined by this table. The LLM provides judgment for code review, implementation quality, architecture decisions, and plan design — never for state transitions. Given the same `(current_state, event, guard)` tuple, two different LLM runs MUST produce the same `next_state`.

---

## Pipeline State Transitions (Normal Flow)

Every row is a unique `(current_state, event, guard)` triple. The orchestrator looks up the matching row and executes the action.

| # | current_state | event | guard | next_state | action |
|---|---------------|-------|-------|------------|--------|
| 1 | `PREFLIGHT` | `preflight_complete` | `dry_run == false` | `EXPLORING` | Initialize state, create worktree, resolve convention stacks |
| 2 | `PREFLIGHT` | `preflight_complete` | `dry_run == true` | `EXPLORING` | Initialize state (no worktree, no lock, no checkpoints) |
| 3 | `PREFLIGHT` | `interrupted_run_detected` | `checkpoint_valid AND no_git_drift` | Resume from first incomplete stage | Load checkpoint, resume pipeline |
| 4 | `PREFLIGHT` | `interrupted_run_detected` | `git_drift_detected` | `PREFLIGHT` | Warn user, ask whether to incorporate or discard changes |
| 5 | `EXPLORING` | `explore_complete` | `scope < decomposition_threshold` | `PLANNING` | Write stage_1_notes, pass exploration context to planner |
| 6 | `EXPLORING` | `explore_complete` | `scope >= decomposition_threshold` | `DECOMPOSED` | Dispatch fg-015-scope-decomposer, then fg-090-sprint-orchestrator |
| 7 | `EXPLORING` | `explore_timeout` | — | `PLANNING` | Log WARNING, set exploration_degraded = true, proceed with reduced context |
| 8 | `EXPLORING` | `explore_failure` | — | `PLANNING` | Log WARNING, set exploration_degraded = true, proceed with reduced context |
| 9 | `PLANNING` | `plan_complete` | — | `VALIDATING` | Write stage_2_notes, dispatch fg-210-validator |
| 10 | `VALIDATING` | `verdict_GO` | `risk <= auto_proceed_risk` | `IMPLEMENTING` | Proceed automatically, announce briefly |
| 11 | `VALIDATING` | `verdict_GO` | `risk > auto_proceed_risk` | `VALIDATING` (user gate) | Show plan via AskUserQuestion, await approval |
| 12 | `VALIDATING` | `user_approve_plan` | — | `IMPLEMENTING` | Proceed to Stage 4 |
| 13 | `VALIDATING` | `user_revise_plan` | — | `PLANNING` | Re-enter planner with user feedback |
| 14 | `VALIDATING` | `verdict_REVISE` | `validation_retries < max_validation_retries` | `PLANNING` | Increment validation_retries, re-plan with validator findings |
| 15 | `VALIDATING` | `verdict_REVISE` | `validation_retries >= max_validation_retries` | ESCALATED | Escalate as NO-GO |
| 16 | `VALIDATING` | `verdict_NOGO` | — | ESCALATED | Escalate to user: Reshape spec / Try replanning / Abort |
| 17 | `VALIDATING` | `contract_breaking` | `consumer_tasks_in_plan` | `IMPLEMENTING` | Add contract findings as WARNING, proceed |
| 18 | `VALIDATING` | `contract_breaking` | `no_consumer_tasks` | `PLANNING` | Amend plan for breaking changes, increment validation_retries |
| 19 | `IMPLEMENTING` | `implement_complete` | `at_least_one_task_passed` | `VERIFYING` | Git checkpoint, dispatch Phase A (build+lint) |
| 21 | `IMPLEMENTING` | `implement_complete` | `all_tasks_failed` | ESCALATED | AskUserQuestion: Re-plan / Retry / Abort |
| 22 | `VERIFYING` | `phase_a_failure` | `verify_fix_count < max_fix_loops AND total_iterations < max_iterations` | `IMPLEMENTING` | Increment verify_fix_count + total_iterations + total_retries, dispatch implementer with build/lint errors |
| 23 | `VERIFYING` | `phase_a_failure` | `verify_fix_count >= max_fix_loops OR total_iterations >= max_iterations` | ESCALATED | AskUserQuestion: Fix manually / Re-plan / Abort |
| 24 | `VERIFYING` | `tests_fail` | `phase_iterations < max_test_cycles AND total_iterations < max_iterations` | `IMPLEMENTING` | Increment phase_iterations + total_iterations + total_retries, dispatch implementer with test failures |
| 25 | `VERIFYING` | `tests_fail` | `phase_iterations >= max_test_cycles OR total_iterations >= max_iterations` | ESCALATED | AskUserQuestion: Fix manually / Re-plan / Abort |
| 26 | `VERIFYING` | `verify_pass` | `convergence.phase == "correctness"` | `REVIEWING` | Transition convergence to "perfection", reset phase_iterations = 0 |
| 27 | `VERIFYING` | `verify_pass` | `convergence.phase == "safety_gate"` | `DOCUMENTING` | Set safety_gate_passed = true, proceed to DOCS |
| 28 | `VERIFYING` | `safety_gate_fail` | `safety_gate_failures < 2` | `IMPLEMENTING` | Transition convergence to "correctness", reset phase_iterations/plateau_count/last_score_delta/convergence_state, increment safety_gate_failures + total_iterations |
| 29 | `VERIFYING` | `safety_gate_fail` | `safety_gate_failures >= 2` | ESCALATED | Cross-phase oscillation detected, escalate to user |
| 30 | `REVIEWING` | `score_target_reached` | — | `VERIFYING` | Transition convergence to "safety_gate", dispatch final VERIFY |
| 31 | `REVIEWING` | `score_improving` | `total_iterations < max_iterations` | `IMPLEMENTING` | Reset plateau_count, increment phase_iterations + total_iterations + quality_cycles + total_retries, dispatch implementer with findings |
| 32 | `REVIEWING` | `score_improving` | `total_iterations >= max_iterations` | ESCALATED | Global iteration cap reached |
| 33 | `REVIEWING` | `score_plateau` | `plateau_count >= plateau_patience AND score >= pass_threshold` | `VERIFYING` | Transition to "safety_gate", document unfixable findings |
| 34 | `REVIEWING` | `score_plateau` | `plateau_count >= plateau_patience AND score >= concerns_threshold AND score < pass_threshold` | ESCALATED | AskUserQuestion: Keep trying / Fix manually / Abort |
| 35 | `REVIEWING` | `score_plateau` | `plateau_count >= plateau_patience AND score < concerns_threshold` | ESCALATED | Recommend abort, AskUserQuestion: Keep trying / Fix manually / Abort |
| 36 | `REVIEWING` | `score_plateau` | `plateau_count < plateau_patience AND total_iterations < max_iterations` | `IMPLEMENTING` | Increment plateau_count + phase_iterations + total_iterations + total_retries, dispatch implementer with findings |
| 37 | `REVIEWING` | `score_regressing` | `abs(delta) > oscillation_tolerance` | ESCALATED | Set convergence_state = REGRESSING, escalate immediately |
| 38 | `DOCUMENTING` | `docs_complete` | — | `SHIPPING` | Dispatch fg-590-pre-ship-verifier |
| 39 | `DOCUMENTING` | `docs_failure` | — | `SHIPPING` | Log WARNING, set documentation.generation_error = true, proceed to pre-ship |
| 40 | `SHIPPING` | `evidence_SHIP` | `evidence fresh (< evidence_max_age_minutes)` | `SHIPPING` (PR creation) | Dispatch fg-600-pr-builder |
| 41 | `SHIPPING` | `evidence_SHIP` | `evidence stale` | `SHIPPING` (re-verify) | Re-dispatch fg-590-pre-ship-verifier |
| 42 | `SHIPPING` | `evidence_BLOCK` | `block_reason in (build, lint, tests)` | `IMPLEMENTING` | Transition convergence to Phase 1 (correctness), re-enter IMPLEMENT -> VERIFY |
| 43 | `SHIPPING` | `evidence_BLOCK` | `block_reason in (review, score)` | `IMPLEMENTING` | Transition convergence to Phase 2 (perfection), re-enter IMPLEMENT -> REVIEW |
| 44 | `SHIPPING` | `pr_created` | — | `SHIPPING` (user gate) | Present PR to user, await approval |
| 45 | `SHIPPING` | `user_approve_pr` | — | `LEARNING` | Move kanban ticket to done, proceed to Stage 9 |
| 46 | `SHIPPING` | `pr_rejected` | `feedback_classification == "implementation"` | `IMPLEMENTING` | Reset quality_cycles + test_cycles = 0, increment total_retries, re-enter Stage 4 with feedback |
| 47 | `SHIPPING` | `pr_rejected` | `feedback_classification == "design"` | `PLANNING` | Reset quality_cycles + test_cycles + verify_fix_count + validation_retries = 0, increment total_retries, re-enter Stage 2 |
| 48 | `SHIPPING` | `feedback_loop_detected` | `feedback_loop_count >= 2` | ESCALATED | AskUserQuestion: Guide / Start fresh / Override |
| 49 | `LEARNING` | `retrospective_complete` | — | `COMPLETE` | Write run report, auto-tune config, archive tracking ticket |

---

## Error Transitions (from ANY pipeline state)

These transitions can fire from any current_state. They take priority over normal flow transitions.

| # | current_state | event | guard | next_state | action |
|---|---------------|-------|-------|------------|--------|
| E1 | ANY | `budget_exhausted` | `total_retries >= total_retries_max` | ESCALATED | Hard stop: escalate to user with retry budget summary |
| E2 | ANY | `recovery_budget_exhausted` | `recovery_budget.total_weight >= max_weight` | ESCALATED | Recovery engine raises BUDGET_EXHAUSTED, escalate to user |
| E3 | ANY | `circuit_breaker_open` | `3 consecutive transient failures in 60s` | ESCALATED | Non-recoverable per error-taxonomy.md, escalate |
| E4 | ANY | `unrecoverable_error` | `error.recoverable == false` | ESCALATED | Log error with full context, escalate to user |
| E5 | ANY (ESCALATED) | `user_continue` | — | Previous state | Resume from escalation point with user guidance |
| E6 | ANY (ESCALATED) | `user_abort` | — | `ABORTED` | Write abort-report.md, clean up worktree, release lock |
| E7 | ANY (ESCALATED) | `user_reshape` | — | `PLANNING` | Re-run forge-shape with current context, then re-enter PLAN |

---

## Dry-Run Flow

Dry-run mode executes only stages 0-3 with no side effects (no worktree, no lock, no checkpoints, no Linear). Dry-run transitions are part of the Normal Flow table above (guarded by `dry_run == true`): rows 2 (PREFLIGHT), and the row below (VALIDATING exit). During dry-run, EXPLORING and PLANNING use the same normal-flow transitions (rows 5/9) — the `dry_run` guard only affects PREFLIGHT initialization and the VALIDATING exit.

| # | current_state | event | guard | next_state | action |
|---|---------------|-------|-------|------------|--------|
| D1 | `VALIDATING` | `validate_complete` | `dry_run == true` | `COMPLETE` | Output dry-run report: plan + validation verdict + risk assessment |

---

## Convergence Phase Transitions

Sub-state machine governing the IMPLEMENTING <-> VERIFYING <-> REVIEWING iteration loop. These transitions operate within the convergence engine and are referenced by the main pipeline transitions above.

| # | current_phase | event | guard | next_phase | action |
|---|---------------|-------|-------|------------|--------|
| C1 | `correctness` | `phase_a_failure` | `verify_fix_count < max_fix_loops AND total_iterations < max_iterations` | `correctness` | Increment verify_fix_count + total_iterations, dispatch IMPLEMENT with build/lint errors then VERIFY |
| C2 | `correctness` | `phase_a_failure` | `verify_fix_count >= max_fix_loops OR total_iterations >= max_iterations` | ESCALATED | Cap exhausted, escalate |
| C3 | `correctness` | `tests_fail` | `phase_iterations < max_test_cycles AND total_iterations < max_iterations` | `correctness` | Increment phase_iterations + total_iterations, dispatch IMPLEMENT with test failures then VERIFY |
| C4 | `correctness` | `tests_fail` | `phase_iterations >= max_test_cycles OR total_iterations >= max_iterations` | ESCALATED | Cap exhausted, escalate |
| C5 | `correctness` | `verify_pass` | `tests_pass AND analysis_pass` | `perfection` | Reset phase_iterations = 0, transition to Phase 2 |
| C6 | `perfection` | `score_target_reached` | `score >= target_score` | `safety_gate` | Transition to safety gate, dispatch final VERIFY |
| C7 | `perfection` | `score_improving` | `delta > plateau_threshold AND total_iterations < max_iterations` | `perfection` | Reset plateau_count = 0, increment phase_iterations + total_iterations, dispatch IMPLEMENT then REVIEW |
| C8 | `perfection` | `score_plateau` | `plateau_count >= plateau_patience` | `safety_gate` or ESCALATED | Apply score escalation ladder (see scoring.md) |
| C9 | `perfection` | `score_regressing` | `abs(delta) > oscillation_tolerance` | ESCALATED | Set convergence_state = REGRESSING, escalate |
| C10 | `perfection` | `score_plateau` | `plateau_count < plateau_patience AND total_iterations < max_iterations` | `perfection` | Increment plateau_count + phase_iterations + total_iterations, dispatch IMPLEMENT then REVIEW |
| C11 | `safety_gate` | `verify_pass` | `tests_pass` | CONVERGED | Set safety_gate_passed = true, proceed to DOCS |
| C12 | `safety_gate` | `safety_gate_fail` | `safety_gate_failures < 2` | `correctness` | Increment safety_gate_failures + total_iterations, reset phase_iterations + plateau_count + last_score_delta + convergence_state to IMPROVING |
| C13 | `safety_gate` | `safety_gate_fail` | `safety_gate_failures >= 2` | ESCALATED | Cross-phase oscillation detected, escalate |

---

## Lookup Protocol

The orchestrator follows this 6-step protocol for EVERY state transition:

1. **Read** `current_state` from `state.json.story_state` (pipeline) or `state.json.convergence.phase` (convergence).
2. **Classify** the event that just occurred (e.g., `verify_pass`, `score_improving`, `evidence_BLOCK`).
3. **Evaluate** guards by reading the relevant state fields (counters, config values, verdicts).
4. **Look up** the unique matching `(current_state, event, guard)` row in this table.
5. **Execute** the action specified in the row. Update `state.json` accordingly.
6. **Transition** to `next_state`. If the row is not found, log `ERROR: No transition for (state={current_state}, event={event}, guard={guard_values})` and escalate to user.

The orchestrator MUST NOT infer transitions from prose descriptions. If a `(state, event)` pair is not in this table, it is a bug in the table (not a decision for the LLM to make).

---

## Invariants

These properties hold for the entire state machine:

1. **Deterministic:** Every `(current_state, event, guard)` tuple maps to exactly one `(next_state, action)`. No ambiguity. No LLM interpretation of "which state comes next."

2. **Complete:** Every reachable `(state, event)` pair has at least one row (with guards covering all cases). The error transitions (ANY state) serve as the completeness backstop.

3. **No dead states:** Every state is either terminal (`COMPLETE`, `ABORTED`) or has at least one outgoing transition. `ESCALATED` is a pseudo-state that resolves via user response (`user_continue`, `user_abort`, `user_reshape`).

4. **Budget-bounded:** Every iteration loop is bounded by at least one of: `max_fix_loops`, `max_test_cycles`, `max_iterations`, `total_retries_max`, `recovery_budget.max_weight`. The pipeline cannot iterate indefinitely.

5. **User sovereignty:** The user can always abort (`user_abort`). The pipeline never auto-ships below `shipping.min_score`. Escalations always offer user choice. Autonomous mode auto-selects "keep trying" but still respects hard caps.
