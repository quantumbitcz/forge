# State Machine Transition Table

Formal, deterministic transition table for all orchestrator control flow decisions. This is the **single source of truth** for state transitions — prose descriptions in agents and other documents describe *why*, this table specifies *what happens*.

## Design Principle

**Deterministic scaffolding, LLM judgment where it matters.**

Control flow (which state comes next, when to retry, when to escalate) is fully determined by this table. The LLM provides judgment for code review, implementation quality, architecture decisions, and plan design — never for state transitions. Given the same `(current_state, event, guard)` tuple, two different LLM runs MUST produce the same `next_state`.

---

## Pipeline States

The canonical pipeline state values `story_state` can take are enumerated in `shared/state-schema.md`: `PREFLIGHT`, `EXPLORING`, `PLANNING`, `VALIDATING`, `IMPLEMENTING`, `VERIFYING`, `REVIEWING`, `DOCUMENTING`, `SHIPPING`, `LEARNING`, `COMPLETE`, `ABORTED`, plus the `ESCALATED` pseudo-state that resolves via user response.

- **REWINDING** *(pseudo-state, non-persistent, added in state-schema v1.9.0)* — in effect only during the atomic rewind transaction. `state.story_state` is NOT written as `REWINDING`; this name appears only in `events.jsonl` `StateTransitionEvent` pairs that bracket the rewind op.

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
| 50 | `REVIEWING` | `score_diminishing` | `diminishing_count >= 2 AND score >= pass_threshold` | `VERIFYING` | Transition to "safety_gate", document diminishing gains as unfixable |
| 51 | `REVIEWING` | `score_plateau` | `plateau_count < plateau_patience AND total_iterations >= max_iterations` | ESCALATED | Global iteration cap reached despite patience remaining |
| 52 | `SHIPPING` | `evidence_SHIP` | `evidence_stale AND evidence_refresh_count >= 3` | ESCALATED | Evidence refresh loop cap reached, escalate to user |

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
| E8 | ANY | `token_budget_exhausted` | `tokens.estimated_total >= budget_ceiling AND budget_ceiling > 0` | ESCALATED | Token budget exceeded, escalate to user. **Note:** The orchestrator's `cost-alerting.sh` system warns the user at configurable thresholds (default 50%/75%/90%) BEFORE E8 fires. E8 serves as an absolute safety net at the hard ceiling (default 2,000,000 tokens). The orchestrator calls `cost-alerting.sh check` before each agent dispatch; if exit 3 (CRITICAL) or 4 (EXCEEDED), it surfaces options to the user before E8's hard ESCALATED transition fires. |
| E9 | ANY (not COMPLETE, not ABORTED) | `user_abort_direct` | — | `ABORTED` | Direct abort from /forge-abort skill. Set abort_reason, release lock, preserve worktree. |
| R1 | ANY | `recovery_op_rewind` | `/forge-recover rewind --to=<id>` dispatched by orchestrator | `REWINDING` | Entered transiently at the start of rewind. `StateTransitionEvent { from: <current>, to: "REWINDING" }` logged. `state.story_state` is NOT written. |
| R2 | `REWINDING` | `rewind_commit_success` | CAS atomic restore succeeded (python3 -m hooks._py.time_travel exit 0) | `<checkpoint.story_state>` | Whichever story_state the target checkpoint captured. `state.story_state` set to the target's captured story_state; `StateTransitionEvent { from: "REWINDING", to: <target> }` logged. |
| R3 | `REWINDING` | `rewind_abort` | CAS restore failed (exit 5 dirty / 6 unknown / 7 tx-collision) | `<prior story_state>` | Zero side effects; pipeline returns to state before rewind. `StateTransitionEvent { from: "REWINDING", to: <prior> }` logged. Abort code surfaced via `AskUserQuestion`. |

---

## Dry-Run Flow

Dry-run mode executes only stages 0-3 with no side effects (no worktree, no lock, no checkpoints, no Linear). Dry-run transitions are part of the Normal Flow table above (guarded by `dry_run == true`): rows 2 (PREFLIGHT), and the row below (VALIDATING exit). During dry-run, EXPLORING and PLANNING use the same normal-flow transitions (rows 5/9) — the `dry_run` guard only affects PREFLIGHT initialization and the VALIDATING exit.

| # | current_state | event | guard | next_state | action |
|---|---------------|-------|-------|------------|--------|
| D1 | `VALIDATING` | `validate_complete` | `dry_run == true` | `COMPLETE` | Output dry-run report: plan + validation verdict + risk assessment |

---

## § Rewind transitions

Rewind is the only transition type that can originate from ANY pipeline state. It is also the only one with a pseudo-state (`REWINDING`) that never persists to `state.story_state`. The sequence is:

1. Orchestrator receives `recovery_op: rewind` with `--to=<id>` (see `agents/fg-100-orchestrator.md` §Recovery op dispatch).
2. `StateTransitionEvent { from: <current>, to: "REWINDING" }` appended to `events.jsonl` (row R1 above).
3. `python3 -m hooks._py.time_travel rewind` runs (atomic 5-step protocol, see `shared/recovery/time-travel.md`).
4a. On success (exit 0): `StateTransitionEvent { from: "REWINDING", to: <checkpoint.story_state> }` logged; `state.story_state` is set to the target's story_state (row R2).
4b. On abort (exit 5/6/7): `StateTransitionEvent { from: "REWINDING", to: <prior story_state> }` logged; `state.story_state` reverts (row R3). Abort code surfaced via `AskUserQuestion`.

Subsequent forward progress is normal. The next `/forge-recover resume` continues from the rewound head.

---

## Convergence Phase Transitions

Sub-state machine governing the IMPLEMENTING <-> VERIFYING <-> REVIEWING iteration loop. These transitions operate within the convergence engine and are referenced by the main pipeline transitions above.

| # | current_phase | event | guard | next_phase | action |
|---|---------------|-------|-------|------------|--------|
| C1 | `correctness` | `phase_a_failure` | `verify_fix_count < max_fix_loops AND total_iterations < max_iterations` | `correctness` | Increment verify_fix_count + total_iterations, dispatch IMPLEMENT with build/lint errors then VERIFY. Note: Phase A failures always skip Phase B. verify_fix_count tracks inner-loop retries (separate from phase_iterations which tracks Phase B cycles). See convergence-engine.md §Phase A. |
| C2 | `correctness` | `phase_a_failure` | `verify_fix_count >= max_fix_loops OR total_iterations >= max_iterations` | ESCALATED | Cap exhausted, escalate |
| C3 | `correctness` | `tests_fail` | `phase_iterations < max_test_cycles AND total_iterations < max_iterations` | `correctness` | Increment phase_iterations + total_iterations, dispatch IMPLEMENT with test failures then VERIFY |
| C4 | `correctness` | `tests_fail` | `phase_iterations >= max_test_cycles OR total_iterations >= max_iterations` | ESCALATED | Cap exhausted, escalate |
| C5 | `correctness` | `verify_pass` | `tests_pass AND analysis_pass` | `perfection` | Reset phase_iterations = 0, transition to Phase 2 |
| C6 | `perfection` | `score_target_reached` | `score >= target_score` | `safety_gate` | Transition to safety gate, dispatch final VERIFY |
| C7 | `perfection` | `score_improving` | `delta > plateau_threshold AND total_iterations < max_iterations` | `perfection` | Reset plateau_count = 0, increment phase_iterations + total_iterations, dispatch IMPLEMENT then REVIEW |
| C8 | `perfection` | `score_plateau` | `phase_iterations >= 2 AND plateau_count >= plateau_patience` | `safety_gate` or ESCALATED | Apply score escalation ladder (see scoring.md) (Note: Plateau detection guarded by phase_iterations >= 2 per convergence-engine.md §Plateau Detection. First 2 cycles always classified as IMPROVING regardless of delta.) |
| C9 | `perfection` | `score_regressing` | `abs(delta) > oscillation_tolerance` | ESCALATED | Set convergence_state = REGRESSING, escalate |
| C10 | `perfection` | `score_plateau` | `phase_iterations >= 2 AND plateau_count < plateau_patience AND total_iterations < max_iterations` | `perfection` | Increment plateau_count + phase_iterations + total_iterations, dispatch IMPLEMENT then REVIEW |
| C10a | `perfection` | `score_plateau` | `phase_iterations < 2` | `perfection` | First 2 cycles exempt from plateau counting (establishing baseline). Increment phase_iterations + total_iterations + total_retries, treat as IMPROVING. |
| C11 | `safety_gate` | `verify_pass` | `tests_pass` | CONVERGED | Set safety_gate_passed = true, proceed to DOCS |
| C12 | `safety_gate` | `safety_gate_fail` | `safety_gate_failures < 2` | `correctness` | Increment safety_gate_failures + total_iterations, reset phase_iterations + plateau_count + last_score_delta + convergence_state to IMPROVING |
| C13 | `safety_gate` | `safety_gate_fail` | `safety_gate_failures >= 2` | ESCALATED | Cross-phase oscillation detected, escalate |

---

## Mode Overlay Effects on Transitions

Mode overlays (defined in `shared/modes/*.md`) modify the effective values used in guard evaluation:

| Mode | Affected Guard | Override |
|------|---------------|----------|
| standard | — | No overrides (uses forge-config.md defaults) |
| bugfix | `target_score` in C6, C8 | Uses `pass_threshold` instead of `target_score` |
| bugfix | `max_iterations` in C1-C10 | 10 (default 15) |
| bugfix | `plateau_patience` in C8/C10 | 2 (default 3) |
| bugfix | `max_quality_cycles` | 2 (default 3) |
| bootstrap | `target_score` in C6, C8 | Uses `pass_threshold` instead of `target_score` |
| bootstrap | `max_iterations` in C1-C10 | 5 |
| bootstrap | `plateau_patience` in C8/C10 | 1 |
| bootstrap | `max_quality_cycles` | 1 |
| migration | `max_iterations` in C1-C10 | 15 |
| testing | `target_score` in C6, C8 | Uses `pass_threshold` instead of `target_score` |
| testing | `max_iterations` in C1-C10 | 10 |
| testing | `plateau_patience` in C8/C10 | 2 |
| testing | `max_quality_cycles` | 2 |
| refactor | `plateau_threshold` in C7/C8 | 2 (default 3) |
| refactor | `max_iterations` in C1-C10 | 12 |
| performance | `max_iterations` in C1-C10 | 12 |
| performance | `max_quality_cycles` | 4 |

**Resolution:** At PREFLIGHT, the orchestrator resolves the effective values based on the active mode's overrides and stores them in `state.json.convergence`. All transition guards reference these resolved values.

---

## Oscillation Detection Interaction

Two complementary oscillation detection mechanisms operate concurrently during the convergence loop:

| Mechanism | Scope | Operates on | Authority |
|-----------|-------|-------------|-----------|
| Convergence engine REGRESSING | Cross-iteration | `convergence.score_history[]` across IMPLEMENT->REVIEW cycles | **Authoritative** (triggers state transition C9) |
| Quality gate Consecutive Dip Rule | Within-iteration | `score_history[]` within a single convergence iteration's quality gate cycles | **Advisory** (logs WARNING, escalates within iteration) |

### Interaction Rules

1. **Convergence engine is authoritative for state transitions.** When the convergence engine detects REGRESSING (score delta exceeds `oscillation_tolerance` across iterations), it triggers transition C9 -> ESCALATED. The quality gate's inner dip detection cannot override or delay this.

2. **Quality gate is authoritative within its iteration.** When the quality gate detects two consecutive dips within its review cycles (the Consecutive Dip Rule in `scoring.md`), it escalates within the current convergence iteration. This causes the convergence engine to receive a `score_regressing` event for C9 evaluation.

3. **No double escalation.** If the quality gate's Consecutive Dip Rule triggers an escalation AND the convergence engine independently detects REGRESSING on the same score delta, only one ESCALATED transition fires. The convergence engine checks `story_state == ESCALATED` before transitioning.

4. **Precedence on simultaneous detection.** If both mechanisms detect regression on the same review cycle completion:
   - The quality gate emits its Consecutive Dip escalation first (it runs synchronously within the review stage)
   - The convergence engine, receiving the review result, detects REGRESSING
   - The orchestrator sees `story_state` is already ESCALATED and does not re-escalate
   - The decision log records both detections with `source: quality_gate_dip_rule` and `source: convergence_engine_regressing`

5. **Advisory dips that do not trigger convergence REGRESSING.** A single dip within tolerance (scoring.md rule 4) is logged by the quality gate as WARNING but does not trigger convergence engine REGRESSING. The convergence engine only evaluates score deltas between iterations, not within quality gate cycles.

### State Field Mapping

| Field | Written by | Read by |
|-------|-----------|---------|
| `score_history[]` (state.json) | Quality gate (append after each cycle) | Convergence engine (cross-iteration delta), quality gate (within-iteration dip detection) |
| `convergence.state` | Convergence engine | Orchestrator (transition lookup) |
| `convergence.last_score_delta` | Convergence engine | Orchestrator (oscillation tolerance check) |

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
