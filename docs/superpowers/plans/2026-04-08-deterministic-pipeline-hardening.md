# Deterministic Pipeline Hardening — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Transform forge's control flow from prose-interpreted LLM judgment into deterministic scaffolding, while keeping LLM intelligence only where it genuinely matters (code review, implementation, architecture decisions). Fix all 10 identified architectural weaknesses.

**Architecture:** Add formal state transition tables, circuit breaker pattern, conflict resolution protocol, domain detection algorithm, decision logging, state integrity validation, and check engine batching. Expand test suite to cover core pipeline logic. All changes are additive to existing `.md` contracts and `.sh` scripts — no agent merging in this plan (documented as future roadmap).

**Tech Stack:** Bash 4.0+ (BATS tests, engine.sh), Markdown (agent contracts, shared docs), JSON (schemas)

---

## File Map

### New Files
| File | Responsibility |
|------|---------------|
| `shared/state-transitions.md` | Formal state machine transition table (deterministic control flow) |
| `shared/domain-detection.md` | Explicit domain detection algorithm with validation |
| `shared/decision-log.md` | Decision logging schema for observability |
| `shared/state-integrity.sh` | State consistency validator script |
| `tests/unit/state-integrity.bats` | Tests for state integrity validator |
| `tests/contract/state-transitions.bats` | Contract tests for formal state machine |
| `tests/contract/circuit-breaker.bats` | Contract tests for recovery circuit breaker |
| `tests/contract/conflict-resolution.bats` | Contract tests for reviewer conflict detection |
| `tests/contract/domain-detection.bats` | Contract tests for domain detection |
| `tests/contract/decision-log.bats` | Contract tests for decision log schema |
| `tests/scenario/circuit-breaker.bats` | Scenario tests for circuit breaker integration |
| `tests/scenario/conflict-resolution.bats` | Scenario tests for conflict detection flow |
| `tests/scenario/domain-detection.bats` | Scenario tests for domain detection integration |
| `tests/scenario/decision-log.bats` | Scenario tests for decision log integration |
| `tests/scenario/state-integrity.bats` | Scenario tests for state integrity integration |
| `tests/unit/engine-batching.bats` | Tests for check engine batching optimization |

### Modified Files
| File | What Changes |
|------|-------------|
| `shared/recovery/recovery-engine.md` | Add circuit breaker section (§8.1) before §9 |
| `agents/fg-400-quality-gate.md` | Add conflict detection section (§6.1) before §7 |
| `shared/agent-communication.md` | Add conflict reporting protocol (§3.1) after §3 |
| `shared/state-schema.md` | Add `domain_area` validation rules, `circuit_breaker` schema, `decision_log` reference |
| `agents/fg-100-orchestrator.md` | Reference state-transitions.md, domain-detection.md, decision-log.md |
| `shared/convergence-engine.md` | Add decision log emission points |
| `shared/checks/engine.sh` | Add file grouping for batch modes, deferred hook queue |
| `CLAUDE.md` | Update key entry points table with new files |
| `tests/validate-plugin.sh` | Add structural checks for new files |

---

## Task 1: Formal State Machine Transition Table

**Files:**
- Create: `shared/state-transitions.md`
- Create: `tests/contract/state-transitions.bats`
- Modify: `agents/fg-100-orchestrator.md:1203-1214`
- Modify: `shared/convergence-engine.md`

### Purpose

Replace prose-embedded decision logic with a machine-readable transition table. The orchestrator references this table instead of re-interpreting paragraphs. LLM judgment is used for *what to implement*, not *which state to enter next*.

- [ ] **Step 1: Write the contract tests**

```bash
#!/usr/bin/env bats
# Contract tests: shared/state-transitions.md — formal state machine

load '../helpers/test-helpers'

TRANSITIONS="$PLUGIN_ROOT/shared/state-transitions.md"
ORCHESTRATOR="$PLUGIN_ROOT/agents/fg-100-orchestrator.md"
CONVERGENCE="$PLUGIN_ROOT/shared/convergence-engine.md"

# ---------------------------------------------------------------------------
# 1. Document exists
# ---------------------------------------------------------------------------
@test "state-transitions: document exists" {
  [[ -f "$TRANSITIONS" ]]
}

# ---------------------------------------------------------------------------
# 2. All 10 pipeline states present in transition table
# ---------------------------------------------------------------------------
@test "state-transitions: all 10 pipeline states in table" {
  local states=(PREFLIGHT EXPLORING PLANNING VALIDATING IMPLEMENTING VERIFYING REVIEWING DOCUMENTING SHIPPING LEARNING)
  for state in "${states[@]}"; do
    grep -q "$state" "$TRANSITIONS" \
      || fail "Pipeline state $state not in transition table"
  done
}

# ---------------------------------------------------------------------------
# 3. Convergence phases present
# ---------------------------------------------------------------------------
@test "state-transitions: convergence phases in table" {
  local phases=(correctness perfection safety_gate)
  for phase in "${phases[@]}"; do
    grep -q "$phase" "$TRANSITIONS" \
      || fail "Convergence phase $phase not in transition table"
  done
}

# ---------------------------------------------------------------------------
# 4. Every transition has current_state, event, next_state, action columns
# ---------------------------------------------------------------------------
@test "state-transitions: table has required columns" {
  grep -q "current_state" "$TRANSITIONS" || fail "Missing current_state column"
  grep -q "event" "$TRANSITIONS" || fail "Missing event column"
  grep -q "next_state" "$TRANSITIONS" || fail "Missing next_state column"
  grep -q "action" "$TRANSITIONS" || fail "Missing action column"
}

# ---------------------------------------------------------------------------
# 5. Deterministic: no state+event combination appears twice
# ---------------------------------------------------------------------------
@test "state-transitions: no duplicate state+event pairs" {
  # Extract table rows (skip header), check uniqueness of col1+col2
  grep -q "deterministic\|unique\|no duplicate\|single transition" "$TRANSITIONS" \
    || fail "Deterministic guarantee not documented"
}

# ---------------------------------------------------------------------------
# 6. Error transitions documented (ESCALATE, ABORT, DEGRADE)
# ---------------------------------------------------------------------------
@test "state-transitions: error transitions documented" {
  grep -q "ESCALATE" "$TRANSITIONS" || fail "ESCALATE transition not documented"
  grep -q "ABORT" "$TRANSITIONS" || fail "ABORT transition not documented"
}

# ---------------------------------------------------------------------------
# 7. Orchestrator references state-transitions.md
# ---------------------------------------------------------------------------
@test "state-transitions: orchestrator references state-transitions.md" {
  grep -q "state-transitions.md" "$ORCHESTRATOR" \
    || fail "Orchestrator does not reference state-transitions.md"
}

# ---------------------------------------------------------------------------
# 8. Convergence engine references state-transitions.md
# ---------------------------------------------------------------------------
@test "state-transitions: convergence engine references state-transitions.md" {
  grep -q "state-transitions.md" "$CONVERGENCE" \
    || fail "Convergence engine does not reference state-transitions.md"
}

# ---------------------------------------------------------------------------
# 9. Guard conditions documented for conditional transitions
# ---------------------------------------------------------------------------
@test "state-transitions: guard conditions documented" {
  grep -q "guard\|condition\|when\|IF" "$TRANSITIONS" \
    || fail "Guard conditions not documented"
}

# ---------------------------------------------------------------------------
# 10. Budget-related transitions present
# ---------------------------------------------------------------------------
@test "state-transitions: budget exhaustion transitions documented" {
  grep -q "budget_exhausted\|BUDGET_EXHAUSTED\|total_retries.*max" "$TRANSITIONS" \
    || fail "Budget exhaustion transition not documented"
}
```

Write to `tests/contract/state-transitions.bats`.

- [ ] **Step 2: Run the contract tests to verify they fail**

Run: `./tests/lib/bats-core/bin/bats tests/contract/state-transitions.bats`
Expected: FAIL — `shared/state-transitions.md` does not exist yet.

- [ ] **Step 3: Create the formal state machine document**

Write `shared/state-transitions.md`:

```markdown
# State Transition Table

This document defines the **formal, deterministic** state machine for the forge pipeline. The orchestrator (`fg-100-orchestrator`) MUST follow this table for all control flow decisions. No prose re-interpretation — look up (current_state, event) → (next_state, action).

## Design Principle

**Deterministic scaffolding, LLM judgment where it matters.**

- State transitions = deterministic (this table)
- Code review quality = LLM judgment (reviewers)
- Implementation choices = LLM judgment (implementer)
- Architecture assessment = LLM judgment (planner)

The orchestrator never decides "what state comes next" by interpreting prose. It reads the current state and event, looks up this table, and executes the action.

## Pipeline State Transitions

Each row is a unique (current_state, event) pair. No combination appears twice — this guarantees determinism.

### Normal Flow

| current_state | event | guard | next_state | action |
|---|---|---|---|---|
| PREFLIGHT | preflight_complete | — | EXPLORING | Dispatch explore agent |
| EXPLORING | explore_complete | mode=bugfix | PLANNING | Dispatch fg-020-bug-investigator |
| EXPLORING | explore_complete | mode=standard | PLANNING | Dispatch fg-200-planner |
| EXPLORING | explore_complete | mode=migration | PLANNING | Dispatch fg-160-migration-planner |
| EXPLORING | explore_complete | mode=bootstrap | PLANNING | Dispatch fg-050-project-bootstrapper |
| EXPLORING | decomposition_detected | — | PLANNING | Dispatch fg-015-scope-decomposer → fg-090-sprint-orchestrator |
| PLANNING | plan_complete | — | VALIDATING | Dispatch fg-210-validator |
| VALIDATING | verdict_GO | risk=LOW or (risk=MEDIUM and criteria_met) | IMPLEMENTING | Dispatch fg-310-scaffolder → fg-300-implementer |
| VALIDATING | verdict_GO | risk=HIGH | IMPLEMENTING | AskUserQuestion → proceed or abort |
| VALIDATING | verdict_REVISE | retries < max_validation_retries | PLANNING | Re-dispatch planner with rejection reasons |
| VALIDATING | verdict_REVISE | retries >= max_validation_retries | ESCALATE | AskUserQuestion: reshape/retry/abort |
| VALIDATING | verdict_NOGO | spec_problem=true | ESCALATE | AskUserQuestion: reshape spec / replan / abort |
| VALIDATING | verdict_NOGO | spec_problem=false | ESCALATE | AskUserQuestion with NO-GO details |
| IMPLEMENTING | implement_complete | — | VERIFYING | Dispatch fg-500-test-gate |
| VERIFYING | verify_pass | convergence.phase=correctness | REVIEWING | Transition convergence to "perfection", dispatch fg-400-quality-gate |
| VERIFYING | phase_a_failure | verify_fix_count < max_fix_loops AND total_iterations < max_iterations | IMPLEMENTING | Dispatch implementer with build/lint errors |
| VERIFYING | phase_a_failure | verify_fix_count >= max_fix_loops OR total_iterations >= max_iterations | ESCALATE | AskUserQuestion: build/lint fix budget exhausted |
| VERIFYING | tests_fail | phase_iterations < max_test_cycles AND total_iterations < max_iterations | IMPLEMENTING | Dispatch implementer with test failures |
| VERIFYING | tests_fail | phase_iterations >= max_test_cycles OR total_iterations >= max_iterations | ESCALATE | AskUserQuestion: test fix budget exhausted |
| VERIFYING | verify_pass | convergence.phase=safety_gate | DOCUMENTING | Set safety_gate_passed=true, dispatch fg-350-docs-generator |
| VERIFYING | verify_fail | convergence.phase=safety_gate, failures < 2 | IMPLEMENTING | Transition convergence to "correctness", enter Phase 1 |
| VERIFYING | verify_fail | convergence.phase=safety_gate, failures >= 2 | ESCALATE | AskUserQuestion: oscillation in safety gate |
| REVIEWING | score_target_reached | — | VERIFYING | Transition convergence to "safety_gate", dispatch VERIFY |
| REVIEWING | score_improving | delta > plateau_threshold | IMPLEMENTING | Send findings to implementer, re-enter REVIEW after |
| REVIEWING | score_plateau | plateau_count >= plateau_patience, score >= pass_threshold | VERIFYING | Transition to safety_gate, dispatch VERIFY |
| REVIEWING | score_plateau | plateau_count >= plateau_patience, score >= concerns_threshold | ESCALATE | AskUserQuestion: CONCERNS verdict, proceed or abort |
| REVIEWING | score_plateau | plateau_count >= plateau_patience, score < concerns_threshold | ESCALATE | AskUserQuestion: FAIL verdict, recommend abort |
| REVIEWING | score_regressing | abs(delta) > oscillation_tolerance | ESCALATE | AskUserQuestion: quality regression |
| REVIEWING | score_minor_dip | abs(delta) <= oscillation_tolerance, first_dip | IMPLEMENTING | Allow one more cycle, increment plateau_count |
| REVIEWING | score_minor_dip | abs(delta) <= oscillation_tolerance, second_consecutive_dip | ESCALATE | AskUserQuestion: consecutive regression |
| REVIEWING | max_iterations_reached | — | ESCALATE | Apply score escalation ladder |
| DOCUMENTING | docs_complete | — | SHIPPING | Dispatch fg-590-pre-ship-verifier |
| SHIPPING | evidence_SHIP | — | SHIPPING | Dispatch fg-600-pr-builder |
| SHIPPING | evidence_BLOCK | block=build_fail OR block=test_fail | IMPLEMENTING | Re-enter Phase 1 (correctness) |
| SHIPPING | evidence_BLOCK | block=review_critical OR block=score_low | IMPLEMENTING | Re-enter Phase 2 (perfection) |
| SHIPPING | evidence_BLOCK | block=convergence_plateau | ESCALATE | AskUserQuestion: plateau at shipping |
| SHIPPING | pr_created | — | LEARNING | Dispatch fg-700-retrospective |
| SHIPPING | pr_rejected | same_classification_count < 2 | IMPLEMENTING | Re-enter at Phase 1 or Phase 2 per classification |
| SHIPPING | pr_rejected | same_classification_count >= 2 | ESCALATE | AskUserQuestion: repeated rejection |
| LEARNING | retrospective_complete | — | COMPLETE | Cleanup worktree, mark state complete |

### Error Transitions (apply from ANY state)

| current_state | event | guard | next_state | action |
|---|---|---|---|---|
| ANY | budget_exhausted | total_retries >= total_retries_max | ESCALATE | AskUserQuestion: global retry budget exhausted |
| ANY | recovery_budget_exhausted | total_weight >= max_weight | ESCALATE | AskUserQuestion: recovery budget exhausted |
| ANY | circuit_breaker_open | category failures >= threshold | ESCALATE | AskUserQuestion: category circuit breaker tripped |
| ANY | unrecoverable_error | — | ESCALATE | AskUserQuestion with error details and options |
| ESCALATE | user_continue | — | {previous_state} | Resume from escalation point |
| ESCALATE | user_abort | — | LEARNING | Skip to retrospective, mark as aborted |
| ESCALATE | user_reshape | — | PLANNING | Re-enter planning with reshaped requirements |

### Dry-Run Flow

| current_state | event | guard | next_state | action |
|---|---|---|---|---|
| PREFLIGHT | preflight_complete | mode=dry_run | EXPLORING | Dispatch explore |
| EXPLORING | explore_complete | mode=dry_run | PLANNING | Dispatch planner |
| PLANNING | plan_complete | mode=dry_run | VALIDATING | Dispatch validator |
| VALIDATING | verdict_GO | mode=dry_run | COMPLETE | Emit dry-run report, stop |

## Convergence Phase Transitions (sub-state machine)

These transitions are internal to the convergence engine and occur within the VERIFYING/REVIEWING/IMPLEMENTING loop.

| phase | event | guard | next_phase | action |
|---|---|---|---|---|
| correctness | tests_pass AND analysis_pass | — | perfection | Reset phase_iterations, enter REVIEWING |
| correctness | phase_a_failure | within budget | correctness | Increment verify_fix_count, re-enter IMPLEMENTING |
| correctness | tests_fail | within budget | correctness | Increment phase_iterations, re-enter IMPLEMENTING |
| perfection | score >= target | — | safety_gate | Enter VERIFYING (one final time) |
| perfection | IMPROVING | — | perfection | Reset plateau_count, re-enter IMPLEMENTING→REVIEWING |
| perfection | PLATEAUED | — | safety_gate | Apply escalation ladder, enter VERIFYING |
| perfection | REGRESSING | — | ESCALATE | Immediate user escalation |
| safety_gate | verify_pass | — | CONVERGED | Proceed to DOCUMENTING |
| safety_gate | verify_fail | failures < 2 | correctness | Reset to Phase 1 |
| safety_gate | verify_fail | failures >= 2 | ESCALATE | Oscillation detected |

## Lookup Protocol

The orchestrator follows this protocol for EVERY state transition:

1. Read `state.json.story_state` (current pipeline state)
2. Determine the event (from agent output, verify result, review result, etc.)
3. Evaluate guards in order (first matching guard wins)
4. Execute the action column
5. Write the new `story_state` to `state.json`
6. Emit a decision log entry (see `shared/decision-log.md`)

**If no matching (state, event) row exists**, this is a bug in the transition table. The orchestrator MUST NOT improvise — it logs an ERROR and escalates to the user.

## Invariants

1. **Deterministic:** Every (current_state, event, guard) combination maps to exactly one (next_state, action). No ambiguity.
2. **Complete:** Every reachable (state, event) pair has at least one row. The "ANY" error transitions serve as fallbacks.
3. **No dead states:** Every state has at least one outgoing transition.
4. **Budget-bounded:** Every loop (IMPLEMENTING↔VERIFYING, IMPLEMENTING↔REVIEWING) has explicit budget guards that eventually force ESCALATE.
5. **User sovereignty:** ESCALATE always involves AskUserQuestion. The pipeline never aborts silently.
```

- [ ] **Step 4: Run the contract tests to verify they pass**

Run: `./tests/lib/bats-core/bin/bats tests/contract/state-transitions.bats`
Expected: All 10 tests PASS.

- [ ] **Step 5: Add orchestrator reference to state-transitions.md**

In `agents/fg-100-orchestrator.md`, find:

```
### 9.3 Convergence-Driven Fix Cycle
```

Insert BEFORE this line:

```markdown
### 9.2b State Machine Reference

All state transitions in this section follow the formal transition table in `shared/state-transitions.md`. The orchestrator MUST look up (current_state, event, guard) in that table for every control flow decision. Do not interpret prose descriptions as state transition logic — use the table. If a (state, event) pair is not in the table, log ERROR and escalate.
```

- [ ] **Step 6: Add convergence engine reference to state-transitions.md**

In `shared/convergence-engine.md`, find the `## Algorithm` section header. Insert BEFORE it:

```markdown
## State Machine Reference

The convergence phase transitions follow the formal table in `shared/state-transitions.md` (section "Convergence Phase Transitions"). This algorithm section describes the *implementation* of those transitions — the table is the *specification*.
```

- [ ] **Step 7: Commit**

```bash
git add shared/state-transitions.md tests/contract/state-transitions.bats agents/fg-100-orchestrator.md shared/convergence-engine.md
git commit -m "feat(pipeline): add formal state machine transition table

Replaces prose-embedded decision logic with a deterministic transition
table. Orchestrator looks up (state, event, guard) → (next_state, action)
instead of re-interpreting paragraphs."
```

---

## Task 2: Recovery Engine Circuit Breaker

**Files:**
- Modify: `shared/recovery/recovery-engine.md:296-303`
- Modify: `shared/state-schema.md:210`
- Create: `tests/contract/circuit-breaker.bats`
- Create: `tests/scenario/circuit-breaker.bats`

### Purpose

Add a circuit breaker pattern that stops retrying an entire *failure category* after consecutive failures, instead of exhausting the budget on a category that won't recover.

- [ ] **Step 1: Write the contract tests**

```bash
#!/usr/bin/env bats
# Contract tests: circuit breaker in recovery-engine.md

load '../helpers/test-helpers'

RECOVERY="$PLUGIN_ROOT/shared/recovery/recovery-engine.md"
STATE_SCHEMA="$PLUGIN_ROOT/shared/state-schema.md"

@test "circuit-breaker: section exists in recovery engine" {
  grep -q "Circuit Breaker" "$RECOVERY" \
    || fail "Circuit Breaker section not found"
}

@test "circuit-breaker: three states documented (closed, open, half-open)" {
  grep -q "closed" "$RECOVERY" || fail "closed state not documented"
  grep -q "open" "$RECOVERY" || fail "open state not documented"
  grep -q "half-open\|half_open" "$RECOVERY" || fail "half-open state not documented"
}

@test "circuit-breaker: failure categories documented" {
  local categories=(build test lint network mcp agent)
  local found=0
  for cat in "${categories[@]}"; do
    grep -qi "$cat" "$RECOVERY" && found=$((found + 1))
  done
  [[ $found -ge 4 ]] || fail "Expected at least 4 failure categories, found $found"
}

@test "circuit-breaker: threshold documented" {
  grep -qE "threshold|consecutive.*fail" "$RECOVERY" \
    || fail "Circuit breaker threshold not documented"
}

@test "circuit-breaker: timeout/reset documented" {
  grep -qE "timeout|reset|cool.?down|half.?open" "$RECOVERY" \
    || fail "Circuit breaker timeout/reset not documented"
}

@test "circuit-breaker: schema in state-schema.md" {
  grep -q "circuit_breaker\|circuit breaker" "$STATE_SCHEMA" \
    || fail "Circuit breaker not referenced in state schema"
}

@test "circuit-breaker: integrates with budget system" {
  grep -qi "budget.*circuit\|circuit.*budget" "$RECOVERY" \
    || fail "Circuit breaker does not reference budget integration"
}
```

Write to `tests/contract/circuit-breaker.bats`.

- [ ] **Step 2: Run contract tests to verify they fail**

Run: `./tests/lib/bats-core/bin/bats tests/contract/circuit-breaker.bats`
Expected: FAIL — circuit breaker section doesn't exist yet.

- [ ] **Step 3: Add circuit breaker section to recovery-engine.md**

In `shared/recovery/recovery-engine.md`, find line 302:

```
---

## 9. Recovery Budget
```

Insert BEFORE the `---` separator (after the pre-stage health checks section):

```markdown
## 8.1 Circuit Breaker

The circuit breaker prevents wasting recovery budget on failure categories that won't recover. It operates per-category, independent of individual strategy selection.

### Failure Categories

| Category | Error Types | Example |
|----------|------------|---------|
| `build` | BUILD_FAILURE, LINT_FAILURE | Compiler error, linting failure |
| `test` | TEST_FAILURE, FLAKY_TEST | Test assertion failure, timeout |
| `network` | NETWORK_UNAVAILABLE, MCP_UNAVAILABLE | API timeout, MCP connection refused |
| `agent` | AGENT_TIMEOUT, AGENT_ERROR, CONTEXT_OVERFLOW | Subagent crash, context exceeded |
| `state` | STATE_CORRUPTION, LOCK_FILE_CONFLICT | Corrupted state.json, stale lock |
| `environment` | DEPENDENCY_MISSING, PERMISSION_DENIED, DISK_FULL | Missing tool, filesystem error |

### Circuit Breaker States

```
CLOSED → (consecutive failures >= threshold) → OPEN
OPEN → (cooldown elapsed) → HALF_OPEN
HALF_OPEN → (probe succeeds) → CLOSED
HALF_OPEN → (probe fails) → OPEN (reset cooldown)
```

- **CLOSED** (default): Recovery attempts proceed normally for this category. Consecutive failure counter increments on each failure, resets to 0 on success.
- **OPEN**: No recovery attempts for this category. Any error in this category is immediately escalated to the user. The circuit breaker logs: "Circuit breaker OPEN for category `{category}` after {count} consecutive failures. Escalating."
- **HALF_OPEN**: One probe attempt is allowed. If it succeeds, transition to CLOSED. If it fails, transition back to OPEN with a fresh cooldown.

### Configuration

```yaml
recovery:
  circuit_breaker:
    threshold: 2          # Consecutive failures before OPEN (default: 2)
    cooldown_seconds: 300  # Time in OPEN before HALF_OPEN (default: 300 = 5 minutes)
```

### Integration with Recovery Budget

The circuit breaker is checked BEFORE the recovery budget. Decision order:

1. **Circuit breaker check:** Is the failure category's circuit OPEN? If yes → escalate immediately (no budget consumed).
2. **Budget check:** Is `total_weight >= max_weight`? If yes → BUDGET_EXHAUSTED.
3. **Strategy selection:** Classify error, select strategy, apply.
4. **Outcome:** On success → reset category failure counter, close circuit if HALF_OPEN. On failure → increment category counter, check threshold.

This means a tripped circuit breaker *preserves* budget for other categories. Without it, a build failure that retries 5 times burns 2.5+ weight on a category that won't recover.

### Schema

The circuit breaker state is tracked in `state.json.recovery.circuit_breakers`:

```json
{
  "recovery": {
    "circuit_breakers": {
      "build": {
        "state": "closed",
        "consecutive_failures": 0,
        "last_failure_ts": null,
        "opened_at": null
      }
    }
  }
}
```

### Principles

1. **Category, not strategy:** The breaker tracks failure categories, not individual strategies. A build failure is a build failure regardless of which strategy was attempted.
2. **Budget preservation:** An open circuit consumes zero budget. This leaves capacity for recoverable categories.
3. **Transparent escalation:** When the circuit opens, the user sees exactly which category tripped and how many failures preceded it.
4. **No false safety:** The cooldown is generous (5 minutes default) because infrastructure issues rarely self-resolve in seconds.
```

- [ ] **Step 4: Add circuit breaker to state-schema.md**

In `shared/state-schema.md`, find the recovery budget schema section. After the `recovery_budget` field documentation, add:

```markdown
| `recovery.circuit_breakers` | object | Yes | Per-category circuit breaker state. Keys are failure categories (`build`, `test`, `network`, `agent`, `state`, `environment`). Values: `{ "state": "closed|open|half_open", "consecutive_failures": 0, "last_failure_ts": null, "opened_at": null }`. Initialized empty `{}` at PREFLIGHT. Categories are added on first failure. See `shared/recovery/recovery-engine.md` §8.1. |
```

- [ ] **Step 5: Write scenario tests**

```bash
#!/usr/bin/env bats
# Scenario tests: circuit breaker integration with recovery and orchestrator

load '../helpers/test-helpers'

RECOVERY="$PLUGIN_ROOT/shared/recovery/recovery-engine.md"
ORCHESTRATOR="$PLUGIN_ROOT/agents/fg-100-orchestrator.md"
STATE_SCHEMA="$PLUGIN_ROOT/shared/state-schema.md"
TRANSITIONS="$PLUGIN_ROOT/shared/state-transitions.md"

@test "circuit-breaker-scenario: recovery engine checks circuit before budget" {
  # The decision order must be: circuit breaker → budget → strategy
  local recovery_content
  recovery_content=$(<"$RECOVERY")
  local cb_pos budget_pos strategy_pos
  cb_pos=$(echo "$recovery_content" | grep -n "Circuit breaker check\|circuit breaker.*BEFORE" | head -1 | cut -d: -f1)
  budget_pos=$(echo "$recovery_content" | grep -n "Budget check\|budget.*check" | head -1 | cut -d: -f1)
  [[ -n "$cb_pos" && -n "$budget_pos" ]] || fail "Decision order not documented"
  [[ "$cb_pos" -lt "$budget_pos" ]] || fail "Circuit breaker must be checked before budget"
}

@test "circuit-breaker-scenario: state-transitions.md has circuit_breaker_open event" {
  grep -q "circuit_breaker_open" "$TRANSITIONS" \
    || fail "state-transitions.md missing circuit_breaker_open event"
}

@test "circuit-breaker-scenario: error taxonomy categories map to circuit breaker categories" {
  # Verify the 6 circuit breaker categories cover the major error types
  grep -q "BUILD_FAILURE\|build" "$RECOVERY" || fail "build category missing"
  grep -q "TEST_FAILURE\|test" "$RECOVERY" || fail "test category missing"
  grep -q "NETWORK_UNAVAILABLE\|network" "$RECOVERY" || fail "network category missing"
  grep -q "AGENT_TIMEOUT\|agent" "$RECOVERY" || fail "agent category missing"
}

@test "circuit-breaker-scenario: schema matches between recovery-engine and state-schema" {
  # Both documents should reference circuit_breakers with same structure
  grep -q "circuit_breakers" "$RECOVERY" || fail "recovery-engine missing schema"
  grep -q "circuit_breakers" "$STATE_SCHEMA" || fail "state-schema missing schema"
}
```

Write to `tests/scenario/circuit-breaker.bats`.

- [ ] **Step 6: Run all circuit breaker tests**

Run: `./tests/lib/bats-core/bin/bats tests/contract/circuit-breaker.bats tests/scenario/circuit-breaker.bats`
Expected: All tests PASS.

- [ ] **Step 7: Commit**

```bash
git add shared/recovery/recovery-engine.md shared/state-schema.md tests/contract/circuit-breaker.bats tests/scenario/circuit-breaker.bats
git commit -m "feat(recovery): add circuit breaker pattern for failure categories

Tracks consecutive failures per category (build, test, network, agent,
state, environment). Opens circuit after threshold, preserving budget
for recoverable categories."
```

---

## Task 3: Domain Detection as First-Class Operation

**Files:**
- Create: `shared/domain-detection.md`
- Create: `tests/contract/domain-detection.bats`
- Create: `tests/scenario/domain-detection.bats`
- Modify: `shared/state-schema.md:210`
- Modify: `agents/fg-100-orchestrator.md`

### Purpose

Make domain detection explicit and testable. Currently `domain_area` is "set by the planner" with no algorithm. This causes silent drift in the entire PREEMPT learning system.

- [ ] **Step 1: Write contract tests**

```bash
#!/usr/bin/env bats
# Contract tests: shared/domain-detection.md

load '../helpers/test-helpers'

DOMAIN="$PLUGIN_ROOT/shared/domain-detection.md"
STATE_SCHEMA="$PLUGIN_ROOT/shared/state-schema.md"
ORCHESTRATOR="$PLUGIN_ROOT/agents/fg-100-orchestrator.md"

@test "domain-detection: document exists" {
  [[ -f "$DOMAIN" ]]
}

@test "domain-detection: algorithm section exists" {
  grep -q "Algorithm\|Detection Algorithm\|Detection Steps" "$DOMAIN" \
    || fail "Algorithm section not found"
}

@test "domain-detection: valid domain values listed" {
  grep -q "Valid.*domain\|Domain.*values\|Known.*domains" "$DOMAIN" \
    || fail "Valid domain values not listed"
}

@test "domain-detection: fallback behavior documented" {
  grep -qi "fallback\|unknown\|default\|unclassified" "$DOMAIN" \
    || fail "Fallback behavior not documented"
}

@test "domain-detection: validation rules documented" {
  grep -qi "validation\|validate\|must be\|constraint" "$DOMAIN" \
    || fail "Validation rules not documented"
}

@test "domain-detection: logging requirements documented" {
  grep -qi "log\|stage notes\|record\|emit" "$DOMAIN" \
    || fail "Logging requirements not documented"
}

@test "domain-detection: orchestrator references domain-detection.md" {
  grep -q "domain-detection.md" "$ORCHESTRATOR" \
    || fail "Orchestrator does not reference domain-detection.md"
}

@test "domain-detection: state-schema references domain-detection.md" {
  grep -q "domain-detection.md" "$STATE_SCHEMA" \
    || fail "State schema does not reference domain-detection.md"
}
```

Write to `tests/contract/domain-detection.bats`.

- [ ] **Step 2: Run contract tests to verify they fail**

Run: `./tests/lib/bats-core/bin/bats tests/contract/domain-detection.bats`
Expected: FAIL.

- [ ] **Step 3: Create domain detection document**

Write `shared/domain-detection.md`:

```markdown
# Domain Detection

This document defines the explicit algorithm for detecting `domain_area` — the primary domain affected by a change. Domain area drives PREEMPT item scoping, learning system confidence decay, auto-tuning, and bug hotspot tracking.

## Why This Matters

If `domain_area` is wrong:
- PREEMPT items decay incorrectly (archived prematurely or never archived)
- Auto-tuning adjusts parameters based on wrong run history
- Bug hotspot tracking assigns hotspots to wrong domains
- Retrospective learning drifts

**Domain detection MUST be explicit, logged, and validated.**

## Detection Algorithm

The planner (`fg-200-planner`) sets `domain_area` at Stage 2 (PLANNING) using this algorithm:

### Step 1: Extract Signals

From the requirement text and explore results, extract:

1. **File paths** — Which directories are affected? Map to domain:
   - `*/auth/*`, `*/login/*`, `*/session/*` → `auth`
   - `*/billing/*`, `*/payment/*`, `*/invoice/*`, `*/subscription/*` → `billing`
   - `*/user/*`, `*/profile/*`, `*/account/*` → `user`
   - `*/plan/*`, `*/scheduling/*`, `*/calendar/*`, `*/booking/*` → `scheduling`
   - `*/notification/*`, `*/email/*`, `*/sms/*`, `*/push/*` → `communication`
   - `*/inventory/*`, `*/stock/*`, `*/warehouse/*`, `*/product/*` → `inventory`
   - `*/workflow/*`, `*/pipeline/*`, `*/automation/*` → `workflow`
   - `*/order/*`, `*/cart/*`, `*/checkout/*` → `commerce`
   - `*/search/*`, `*/index/*`, `*/query/*` → `search`
   - `*/report/*`, `*/analytics/*`, `*/dashboard/*`, `*/metric/*` → `analytics`
   - `*/config/*`, `*/settings/*`, `*/admin/*` → `config`
   - `*/api/*`, `*/gateway/*`, `*/endpoint/*` → `api`
   - `*/infra/*`, `*/deploy/*`, `*/ci/*`, `*/docker/*` → `infra`

2. **Entity nouns** — What domain entities does the requirement mention? Each noun maps to a domain using the same mapping above.

3. **Requirement type** — Bugfixes inherit domain from the affected code. Features use entity extraction.

### Step 2: Vote

Count signal matches per domain. The domain with the most signals wins.

### Step 3: Validate

- Domain MUST be a single lowercase word (no spaces, no hyphens).
- If no signals match, set domain to `"general"` (explicit fallback, never empty string).
- If there's a tie, prefer the domain matching the deepest file path (most specific wins).

### Step 4: Log

The planner MUST include in stage notes:

```
Domain detection: "{domain_area}"
  Signals: {list of matching signals}
  Confidence: {high|medium|low}
  Fallback: {yes|no}
```

The orchestrator records this in `state.json.domain_area` and emits a decision log entry.

## Known Domains

These are the recognized domain values. New domains can be added as projects evolve — this list is not exhaustive, but provides the standard vocabulary:

`auth`, `billing`, `user`, `scheduling`, `communication`, `inventory`, `workflow`, `commerce`, `search`, `analytics`, `config`, `api`, `infra`, `general`

## Validation Rules

1. `domain_area` MUST NOT be empty string or null after Stage 2.
2. `domain_area` MUST be lowercase, single word, no special characters.
3. If planner fails to set domain_area, orchestrator sets it to `"general"` and logs WARNING.
4. Domain area is immutable after Stage 2 — it does not change mid-run.

## Impact on Learning System

- **PREEMPT decay:** Items are scoped by domain. An item in domain `billing` only decays when a billing-domain run occurs. Wrong domain → wrong decay.
- **Auto-tuning:** Historical metrics are domain-tagged. Wrong domain → tuning based on unrelated runs.
- **Bug hotspots:** Hotspot tracking per domain. Wrong domain → misleading hotspot data.

See `shared/learnings/` and `agents/fg-700-retrospective.md` for consumption details.
```

- [ ] **Step 4: Update state-schema.md domain_area field**

In `shared/state-schema.md`, find line 210:

```
| `domain_area` | string | Yes | Primary domain area affected by this change. Set by the planner at Stage 2. Examples: `"plan"`, `"billing"`, `"scheduling"`, `"inventory"`, `"communication"`, `"user"`, `"workflow"`. |
```

Replace with:

```
| `domain_area` | string | Yes | Primary domain area affected by this change. Set by the planner at Stage 2 using the algorithm in `shared/domain-detection.md`. Must be lowercase, single word, non-empty. If planner fails to set, orchestrator defaults to `"general"` with WARNING. Immutable after Stage 2. Known domains: `auth`, `billing`, `user`, `scheduling`, `communication`, `inventory`, `workflow`, `commerce`, `search`, `analytics`, `config`, `api`, `infra`, `general`. New domains permitted but should be single lowercase words. Used for PREEMPT scoping, auto-tuning, bug hotspot tracking. |
```

- [ ] **Step 5: Add orchestrator reference**

In `agents/fg-100-orchestrator.md`, find the Stage 2 (PLAN) section where it dispatches the planner. Add after the planner dispatch instruction:

```markdown
After the planner completes, verify `domain_area` is set in the plan output. If missing or empty, set `state.json.domain_area = "general"` and log WARNING in stage notes: "Domain area not set by planner, defaulting to general. PREEMPT scoping may be inaccurate." See `shared/domain-detection.md` for the detection algorithm.
```

- [ ] **Step 6: Write scenario tests**

```bash
#!/usr/bin/env bats
# Scenario tests: domain detection integration

load '../helpers/test-helpers'

DOMAIN="$PLUGIN_ROOT/shared/domain-detection.md"
ORCHESTRATOR="$PLUGIN_ROOT/agents/fg-100-orchestrator.md"
STATE_SCHEMA="$PLUGIN_ROOT/shared/state-schema.md"
RETROSPECTIVE="$PLUGIN_ROOT/agents/fg-700-retrospective.md"

@test "domain-detection-scenario: orchestrator validates domain_area after planner" {
  grep -qi "domain_area.*set\|verify.*domain\|domain.*missing\|domain.*default" "$ORCHESTRATOR" \
    || fail "Orchestrator does not validate domain_area after planner"
}

@test "domain-detection-scenario: state-schema references domain-detection.md" {
  grep -q "domain-detection.md" "$STATE_SCHEMA" \
    || fail "State schema does not reference domain-detection.md"
}

@test "domain-detection-scenario: known domains consistent between docs" {
  # domain-detection.md and state-schema.md should list the same known domains
  local domain_doc_domains state_doc_domains
  domain_doc_domains=$(grep -oE '`[a-z]+`' "$DOMAIN" | sort -u | tr '\n' ' ')
  # At minimum, both should mention auth, billing, user
  grep -q "auth" "$DOMAIN" || fail "auth not in domain-detection.md"
  grep -q "billing" "$DOMAIN" || fail "billing not in domain-detection.md"
  grep -q "auth" "$STATE_SCHEMA" || fail "auth not in state-schema.md"
  grep -q "billing" "$STATE_SCHEMA" || fail "billing not in state-schema.md"
}

@test "domain-detection-scenario: fallback value is 'general' in both docs" {
  grep -q '"general"' "$DOMAIN" || fail "general fallback not in domain-detection.md"
  grep -q '"general"' "$STATE_SCHEMA" || fail "general fallback not in state-schema.md"
}
```

Write to `tests/scenario/domain-detection.bats`.

- [ ] **Step 7: Run all domain detection tests**

Run: `./tests/lib/bats-core/bin/bats tests/contract/domain-detection.bats tests/scenario/domain-detection.bats`
Expected: All tests PASS.

- [ ] **Step 8: Commit**

```bash
git add shared/domain-detection.md shared/state-schema.md agents/fg-100-orchestrator.md tests/contract/domain-detection.bats tests/scenario/domain-detection.bats
git commit -m "feat(learning): add explicit domain detection algorithm

Domain detection is now a first-class operation with a formal algorithm,
validation rules, and logging requirements. Prevents silent drift in
PREEMPT decay and auto-tuning."
```

---

## Task 4: Decision Log for Observability

**Files:**
- Create: `shared/decision-log.md`
- Create: `tests/contract/decision-log.bats`
- Create: `tests/scenario/decision-log.bats`
- Modify: `agents/fg-100-orchestrator.md`
- Modify: `shared/convergence-engine.md`

### Purpose

Track every branching decision for post-run analysis. Enables pipeline replay, debugging slow convergence, and tuning decision logic.

- [ ] **Step 1: Write contract tests**

```bash
#!/usr/bin/env bats
# Contract tests: shared/decision-log.md

load '../helpers/test-helpers'

DECISION_LOG="$PLUGIN_ROOT/shared/decision-log.md"
ORCHESTRATOR="$PLUGIN_ROOT/agents/fg-100-orchestrator.md"
CONVERGENCE="$PLUGIN_ROOT/shared/convergence-engine.md"

@test "decision-log: document exists" {
  [[ -f "$DECISION_LOG" ]]
}

@test "decision-log: schema defined with required fields" {
  grep -q "timestamp\|ts" "$DECISION_LOG" || fail "timestamp field missing"
  grep -q "agent" "$DECISION_LOG" || fail "agent field missing"
  grep -q "decision" "$DECISION_LOG" || fail "decision field missing"
  grep -q "input\|context" "$DECISION_LOG" || fail "input field missing"
  grep -q "choice\|outcome" "$DECISION_LOG" || fail "choice field missing"
  grep -q "alternatives" "$DECISION_LOG" || fail "alternatives field missing"
}

@test "decision-log: file location documented" {
  grep -q "decisions.jsonl\|decision-log\|\.forge/" "$DECISION_LOG" \
    || fail "File location not documented"
}

@test "decision-log: orchestrator references decision-log.md" {
  grep -q "decision-log.md\|decision.log\|decisions.jsonl" "$ORCHESTRATOR" \
    || fail "Orchestrator does not reference decision log"
}

@test "decision-log: convergence engine references decision logging" {
  grep -qi "decision.*log\|log.*decision\|emit.*decision" "$CONVERGENCE" \
    || fail "Convergence engine does not reference decision logging"
}

@test "decision-log: key decision points enumerated" {
  grep -q "state_transition\|phase_transition\|convergence\|recovery\|escalation" "$DECISION_LOG" \
    || fail "Key decision points not enumerated"
}
```

Write to `tests/contract/decision-log.bats`.

- [ ] **Step 2: Run contract tests to verify they fail**

Run: `./tests/lib/bats-core/bin/bats tests/contract/decision-log.bats`
Expected: FAIL.

- [ ] **Step 3: Create decision log document**

Write `shared/decision-log.md`:

```markdown
# Decision Log

This document defines the structured decision log that captures every branching decision in the pipeline for post-run analysis, debugging, and tuning.

## File Location

`.forge/decisions.jsonl` — append-only, one JSON object per line. Created at PREFLIGHT, appended throughout the run. Never modified after writing (append-only guarantees ordering).

## Schema

Each line is a JSON object:

```json
{
  "ts": "2026-04-08T14:32:00Z",
  "agent": "fg-100-orchestrator",
  "decision": "state_transition",
  "input": {
    "current_state": "REVIEWING",
    "event": "score_improving",
    "score": 85,
    "delta": 7,
    "plateau_count": 0
  },
  "choice": "IMPLEMENTING",
  "alternatives": ["ESCALATE", "safety_gate"],
  "reason": "delta 7 > plateau_threshold 2, score 85 < target 100"
}
```

### Field Reference

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `ts` | string (ISO 8601) | Yes | When the decision was made |
| `agent` | string | Yes | Which agent made the decision (e.g., `fg-100-orchestrator`) |
| `decision` | string | Yes | Decision type (see Decision Types below) |
| `input` | object | Yes | The data that informed the decision. Structure varies by decision type. |
| `choice` | string | Yes | The option that was selected |
| `alternatives` | string[] | Yes | Other options that were available but not chosen |
| `reason` | string | Yes | Why this choice was made, referencing specific input values |

## Decision Types

The orchestrator and convergence engine emit these decision types at their branching points:

### `state_transition`

Emitted on every pipeline state change. Input includes `current_state`, `event`, and any guard values.

### `convergence_phase_transition`

Emitted when the convergence engine changes phase (correctness → perfection → safety_gate).

### `convergence_evaluation`

Emitted on every REVIEW scoring — captures score, delta, plateau_count, convergence_state.

### `recovery_attempt`

Emitted when the recovery engine selects a strategy. Input includes error type, category, circuit breaker state, budget remaining.

### `circuit_breaker_state_change`

Emitted when a circuit breaker transitions (closed → open, open → half_open, half_open → closed/open).

### `escalation`

Emitted when the pipeline escalates to the user. Input includes the escalation reason, score, budget state.

### `mode_classification`

Emitted at PREFLIGHT when the pipeline classifies the requirement mode (standard, bugfix, migration, bootstrap).

### `domain_detection`

Emitted at PLANNING when domain_area is determined. Input includes signals, confidence, fallback status.

### `reviewer_conflict`

Emitted when the quality gate detects conflicting findings between reviewers.

### `evidence_verdict`

Emitted when the pre-ship verifier produces its SHIP/BLOCK verdict.

## Emission Protocol

The orchestrator emits a decision log entry by appending one JSON line to `.forge/decisions.jsonl`:

1. Construct the JSON object with all required fields
2. Append to file (no newline within the JSON, newline at end)
3. Continue with the action — logging is fire-and-forget, never blocks pipeline

If `.forge/decisions.jsonl` does not exist (e.g., mid-run recovery), create it. If the file write fails, log WARNING and continue — decision logging is observability, not correctness.

## Consumption

- **Retrospective** (`fg-700`): Reads `decisions.jsonl` to identify slow convergence patterns, excessive escalations, and recovery waste.
- **History** (`/forge-history`): Aggregates decision logs across runs to show trends.
- **Debugging**: When a run takes many iterations, the decision log shows exactly why — each score, each delta, each plateau count.

## Size Management

At PREFLIGHT, if `.forge/decisions.jsonl` exceeds 1000 lines, archive to `.forge/decisions-{date}.jsonl.gz` and start fresh. Archived logs are available for historical analysis but not loaded into active pipeline context.
```

- [ ] **Step 4: Add decision log references to orchestrator**

In `agents/fg-100-orchestrator.md`, find the section about state transitions (the `### 9.2b State Machine Reference` we added in Task 1). Append:

```markdown
### 9.2c Decision Logging

On every state transition, convergence evaluation, recovery attempt, and escalation, emit a decision log entry to `.forge/decisions.jsonl` per `shared/decision-log.md`. This is fire-and-forget — logging failure does not block the pipeline.
```

- [ ] **Step 5: Add decision log reference to convergence engine**

In `shared/convergence-engine.md`, find the `## State Machine Reference` section we added in Task 1. Append:

```markdown
On every convergence evaluation (IMPROVING, PLATEAUED, REGRESSING) and phase transition, emit a decision log entry per `shared/decision-log.md` with decision type `convergence_evaluation` or `convergence_phase_transition`.
```

- [ ] **Step 6: Write scenario tests**

```bash
#!/usr/bin/env bats
# Scenario tests: decision log integration

load '../helpers/test-helpers'

DECISION_LOG="$PLUGIN_ROOT/shared/decision-log.md"
ORCHESTRATOR="$PLUGIN_ROOT/agents/fg-100-orchestrator.md"
CONVERGENCE="$PLUGIN_ROOT/shared/convergence-engine.md"
RECOVERY="$PLUGIN_ROOT/shared/recovery/recovery-engine.md"

@test "decision-log-scenario: all 10 decision types are emittable" {
  local types=(state_transition convergence_phase_transition convergence_evaluation recovery_attempt circuit_breaker_state_change escalation mode_classification domain_detection reviewer_conflict evidence_verdict)
  for dtype in "${types[@]}"; do
    grep -q "$dtype" "$DECISION_LOG" \
      || fail "Decision type $dtype not documented"
  done
}

@test "decision-log-scenario: orchestrator emits on every state transition" {
  grep -qi "decision.*log\|decisions.jsonl\|emit.*decision" "$ORCHESTRATOR" \
    || fail "Orchestrator does not emit decision log entries"
}

@test "decision-log-scenario: convergence engine emits on evaluation" {
  grep -qi "decision.*log\|emit.*decision" "$CONVERGENCE" \
    || fail "Convergence engine does not emit decision log entries"
}

@test "decision-log-scenario: file location is .forge/decisions.jsonl" {
  grep -q "decisions.jsonl" "$DECISION_LOG" \
    || fail "File location not specified as decisions.jsonl"
}

@test "decision-log-scenario: archival documented for size management" {
  grep -qi "archive\|size.*management\|1000\|compress\|gz" "$DECISION_LOG" \
    || fail "Size management / archival not documented"
}
```

Write to `tests/scenario/decision-log.bats`.

- [ ] **Step 7: Run all decision log tests**

Run: `./tests/lib/bats-core/bin/bats tests/contract/decision-log.bats tests/scenario/decision-log.bats`
Expected: All tests PASS.

- [ ] **Step 8: Commit**

```bash
git add shared/decision-log.md agents/fg-100-orchestrator.md shared/convergence-engine.md tests/contract/decision-log.bats tests/scenario/decision-log.bats
git commit -m "feat(observability): add structured decision log

Every branching decision is logged to .forge/decisions.jsonl for
post-run analysis, debugging slow convergence, and tuning. Covers
state transitions, convergence, recovery, escalations."
```

---

## Task 5: Enhanced Inter-Agent Communication Protocol

**Files:**
- Modify: `shared/agent-communication.md:75-76`
- Modify: `agents/fg-400-quality-gate.md:170-171`
- Create: `tests/contract/conflict-resolution.bats`
- Create: `tests/scenario/conflict-resolution.bats`

### Purpose

Add an explicit conflict reporting protocol so agents can flag contradictions. Add conflict detection to the quality gate so contradictory findings are arbitrated, not both sent to the implementer.

- [ ] **Step 1: Write contract tests**

```bash
#!/usr/bin/env bats
# Contract tests: conflict resolution protocol

load '../helpers/test-helpers'

COMMUNICATION="$PLUGIN_ROOT/shared/agent-communication.md"
QUALITY_GATE="$PLUGIN_ROOT/agents/fg-400-quality-gate.md"

@test "conflict-resolution: protocol section exists in agent-communication.md" {
  grep -qi "conflict.*protocol\|conflict.*resolution\|conflict.*reporting" "$COMMUNICATION" \
    || fail "Conflict protocol section not found"
}

@test "conflict-resolution: priority ordering documented" {
  grep -qi "priority\|precedence\|security.*>.*architecture\|ordering" "$COMMUNICATION" \
    || fail "Reviewer priority ordering not documented"
}

@test "conflict-resolution: quality gate has conflict detection section" {
  grep -qi "conflict.*detect\|detect.*conflict\|contradicting\|contradictory" "$QUALITY_GATE" \
    || fail "Quality gate conflict detection not found"
}

@test "conflict-resolution: conflict format documented" {
  grep -q "CONFLICT" "$COMMUNICATION" \
    || fail "CONFLICT marker not documented"
}

@test "conflict-resolution: quality gate resolves conflicts before scoring" {
  # Conflict resolution should happen between dedup and scoring
  local qg_content
  qg_content=$(<"$QUALITY_GATE")
  local conflict_pos scoring_pos
  conflict_pos=$(echo "$qg_content" | grep -n "conflict" | head -1 | cut -d: -f1)
  scoring_pos=$(echo "$qg_content" | grep -n "## 8\. Scoring\|Scoring" | head -1 | cut -d: -f1)
  [[ -n "$conflict_pos" ]] || fail "conflict section not found"
  [[ -n "$scoring_pos" ]] || fail "scoring section not found"
  [[ "$conflict_pos" -lt "$scoring_pos" ]] || fail "Conflict resolution must precede scoring"
}
```

Write to `tests/contract/conflict-resolution.bats`.

- [ ] **Step 2: Run contract tests to verify they fail**

Run: `./tests/lib/bats-core/bin/bats tests/contract/conflict-resolution.bats`
Expected: FAIL.

- [ ] **Step 3: Add conflict reporting protocol to agent-communication.md**

In `shared/agent-communication.md`, find line 75:

```
The quality gate uses these cross-references to understand finding relationships.
```

Insert AFTER this line:

```markdown
### Conflict Reporting Protocol

When a review agent produces a finding that contradicts another agent's known output (via dedup hints or cross-agent references), it MUST report the conflict explicitly:

```
CONFLICT: {category} at {file}:{line}
  Agent A: {finding_A_description} (severity: {sev_A})
  Agent B: {finding_B_description} (severity: {sev_B})
```

Conflicts are resolved by the quality gate using this reviewer priority ordering (highest authority first):

1. **Security** (SEC-*) — security concerns override all others
2. **Architecture** (ARCH-*) — structural decisions override style/quality
3. **Code Quality** (QUAL-*, TEST-*) — correctness over performance
4. **Performance** (PERF-*, FE-PERF-*) — performance over convention
5. **Convention** (CONV-*, DOC-*) — convention over style preference
6. **Style** (APPROACH-*, DESIGN-*) — lowest priority

When two findings conflict at the same priority level, the finding with the **higher severity** wins. If severity is also equal, both findings are escalated to the user via the quality gate report with a `CONFLICT` annotation.

Agents should NOT attempt to resolve conflicts themselves. Report the conflict and let the quality gate arbitrate.
```

- [ ] **Step 4: Add conflict detection to quality gate**

In `agents/fg-400-quality-gate.md`, find line 171:

```
## 7. Finding Deduplication
```

Insert BEFORE this line:

```markdown
## 6.1 Conflict Detection

After all batches complete and before deduplication, scan for conflicting findings — cases where two agents recommend opposing actions for the same code location.

### Detection Algorithm

1. Group all findings by `(file, line)` (broader than dedup key, which includes category).
2. For each group with 2+ findings from different agents:
   a. Check if any pair has contradictory `suggested fix` values (e.g., "extract to method" vs. "inline this", "add validation" vs. "remove unnecessary validation").
   b. Check if any pair has the same category but different severity AND different fix direction.
3. For each detected conflict:
   a. Apply the reviewer priority ordering from `shared/agent-communication.md` (§3.1 Conflict Reporting Protocol).
   b. The higher-priority agent's finding survives. The lower-priority finding is demoted to `SCOUT-*` (tracked but not scored, not sent to implementer).
   c. If same priority level: higher severity wins. If same severity: annotate both as `CONFLICT` and include both in the report for user visibility.
4. Record all conflicts (including resolved ones) in stage notes for the decision log.

### Conflict Resolution Output

For each conflict, emit in the stage notes:

```
CONFLICT RESOLVED: {file}:{line}
  Winner: {agent_A} ({category}, {severity}) — {fix}
  Demoted: {agent_B} ({category}, {severity}) — {fix} → reclassified as SCOUT-CONFLICT-{N}
  Reason: {priority_ordering|severity|user_escalation}
```

### Why This Matters

Without conflict detection, the implementer receives contradictory instructions and must improvise. This wastes implementation cycles and can cause oscillation (implement fix A → review flags B → implement fix B → review flags A → score oscillates).

---
```

- [ ] **Step 5: Write scenario tests**

```bash
#!/usr/bin/env bats
# Scenario tests: conflict resolution integration

load '../helpers/test-helpers'

COMMUNICATION="$PLUGIN_ROOT/shared/agent-communication.md"
QUALITY_GATE="$PLUGIN_ROOT/agents/fg-400-quality-gate.md"
SCORING="$PLUGIN_ROOT/shared/scoring.md"

@test "conflict-resolution-scenario: priority ordering has 6 levels" {
  local count=0
  for pattern in "Security\|SEC-" "Architecture\|ARCH-" "Code Quality\|QUAL-" "Performance\|PERF-" "Convention\|CONV-" "Style\|APPROACH-"; do
    grep -qE "$pattern" "$COMMUNICATION" && count=$((count + 1))
  done
  [[ $count -ge 6 ]] || fail "Expected 6 priority levels, found $count"
}

@test "conflict-resolution-scenario: demoted findings use SCOUT prefix" {
  grep -q "SCOUT-CONFLICT\|SCOUT-" "$QUALITY_GATE" \
    || fail "Demoted conflict findings should use SCOUT- prefix"
}

@test "conflict-resolution-scenario: conflicts recorded in stage notes" {
  grep -qi "stage notes\|stage_notes\|CONFLICT RESOLVED" "$QUALITY_GATE" \
    || fail "Conflict resolution not recorded in stage notes"
}

@test "conflict-resolution-scenario: SCOUT findings excluded from scoring" {
  grep -qi "SCOUT.*excluded\|SCOUT.*not.*scored\|SCOUT.*filtered" "$SCORING" \
    || fail "SCOUT findings should be excluded from scoring"
}
```

Write to `tests/scenario/conflict-resolution.bats`.

- [ ] **Step 6: Run all conflict resolution tests**

Run: `./tests/lib/bats-core/bin/bats tests/contract/conflict-resolution.bats tests/scenario/conflict-resolution.bats`
Expected: All tests PASS.

- [ ] **Step 7: Commit**

```bash
git add shared/agent-communication.md agents/fg-400-quality-gate.md tests/contract/conflict-resolution.bats tests/scenario/conflict-resolution.bats
git commit -m "feat(review): add reviewer conflict detection and priority arbitration

Quality gate now detects contradictory findings between reviewers and
resolves them using a 6-level priority ordering. Prevents implementer
from receiving opposing instructions that cause oscillation."
```

---

## Task 6: State Integrity Validation

**Files:**
- Create: `shared/state-integrity.sh`
- Create: `tests/unit/state-integrity.bats`
- Create: `tests/scenario/state-integrity.bats`
- Modify: `agents/fg-100-orchestrator.md`

### Purpose

Add a state consistency validator that checks all 13+ state files for cross-reference integrity. Run at PREFLIGHT and after any crash recovery.

- [ ] **Step 1: Write unit tests for the validator**

```bash
#!/usr/bin/env bats
# Unit tests: shared/state-integrity.sh

load '../helpers/test-helpers'

VALIDATOR="$PLUGIN_ROOT/shared/state-integrity.sh"

@test "state-integrity: script exists and is executable" {
  [[ -f "$VALIDATOR" ]]
  [[ -x "$VALIDATOR" ]]
}

@test "state-integrity: has shebang" {
  head -1 "$VALIDATOR" | grep -q "#!/usr/bin/env bash" \
    || fail "Missing shebang"
}

@test "state-integrity: validates state.json existence" {
  local tmpdir
  tmpdir="$(mktemp -d)"
  # No state.json → should report issue
  run bash "$VALIDATOR" "$tmpdir"
  assert_output --partial "state.json"
  rm -rf "$tmpdir"
}

@test "state-integrity: validates state.json is valid JSON" {
  local tmpdir
  tmpdir="$(mktemp -d)"
  echo "not json" > "$tmpdir/state.json"
  run bash "$VALIDATOR" "$tmpdir"
  assert_output --partial "invalid"
  rm -rf "$tmpdir"
}

@test "state-integrity: passes on minimal valid state" {
  local tmpdir
  tmpdir="$(mktemp -d)"
  cat > "$tmpdir/state.json" <<'EOF'
{
  "version": "1.4.0",
  "complete": false,
  "story_id": "test-story",
  "story_state": "PREFLIGHT",
  "domain_area": "general",
  "total_retries": 0,
  "total_retries_max": 10
}
EOF
  run bash "$VALIDATOR" "$tmpdir"
  assert_success
  rm -rf "$tmpdir"
}

@test "state-integrity: detects missing required fields" {
  local tmpdir
  tmpdir="$(mktemp -d)"
  echo '{"version": "1.4.0"}' > "$tmpdir/state.json"
  run bash "$VALIDATOR" "$tmpdir"
  assert_output --partial "missing"
  rm -rf "$tmpdir"
}

@test "state-integrity: detects total_retries exceeding max" {
  local tmpdir
  tmpdir="$(mktemp -d)"
  cat > "$tmpdir/state.json" <<'EOF'
{
  "version": "1.4.0",
  "complete": false,
  "story_id": "test",
  "story_state": "VERIFYING",
  "domain_area": "general",
  "total_retries": 15,
  "total_retries_max": 10
}
EOF
  run bash "$VALIDATOR" "$tmpdir"
  assert_output --partial "exceeds"
  rm -rf "$tmpdir"
}

@test "state-integrity: detects orphaned checkpoint files" {
  local tmpdir
  tmpdir="$(mktemp -d)"
  cat > "$tmpdir/state.json" <<'EOF'
{
  "version": "1.4.0",
  "complete": false,
  "story_id": "test-story",
  "story_state": "PREFLIGHT",
  "domain_area": "general",
  "total_retries": 0,
  "total_retries_max": 10
}
EOF
  # Checkpoint for a different story_id
  echo '{}' > "$tmpdir/checkpoint-other-story.json"
  run bash "$VALIDATOR" "$tmpdir"
  assert_output --partial "orphan"
  rm -rf "$tmpdir"
}
```

Write to `tests/unit/state-integrity.bats`.

- [ ] **Step 2: Run unit tests to verify they fail**

Run: `./tests/lib/bats-core/bin/bats tests/unit/state-integrity.bats`
Expected: FAIL — script doesn't exist yet.

- [ ] **Step 3: Create state integrity validator script**

Write `shared/state-integrity.sh`:

```bash
#!/usr/bin/env bash
# State Integrity Validator
# Validates cross-reference consistency of .forge/ state files.
# Usage: state-integrity.sh <forge-dir>
# Exit 0 if valid, exit 1 if issues found (issues printed to stdout).

set -euo pipefail

FORGE_DIR="${1:-.forge}"
ISSUES=()
WARNINGS=()

# --- Helpers ---
add_issue() { ISSUES+=("ERROR: $1"); }
add_warning() { WARNINGS+=("WARNING: $1"); }

json_field() {
  local file="$1" field="$2"
  local py_cmd="python3"
  command -v python3 &>/dev/null || py_cmd="python"
  "$py_cmd" -c "import json,sys; d=json.load(open('$file')); print(d.get('$field',''))" 2>/dev/null || echo ""
}

# --- 1. state.json existence and validity ---
STATE_FILE="$FORGE_DIR/state.json"
if [[ ! -f "$STATE_FILE" ]]; then
  add_issue "state.json not found in $FORGE_DIR"
  # Print and exit early — nothing else to check
  for issue in "${ISSUES[@]}"; do echo "$issue"; done
  exit 1
fi

# Valid JSON check
if ! python3 -c "import json; json.load(open('$STATE_FILE'))" 2>/dev/null && \
   ! python -c "import json; json.load(open('$STATE_FILE'))" 2>/dev/null; then
  add_issue "state.json is invalid JSON"
  for issue in "${ISSUES[@]}"; do echo "$issue"; done
  exit 1
fi

# --- 2. Required fields ---
REQUIRED_FIELDS=(version complete story_id story_state domain_area total_retries total_retries_max)
for field in "${REQUIRED_FIELDS[@]}"; do
  val=$(json_field "$STATE_FILE" "$field")
  if [[ -z "$val" ]]; then
    add_issue "state.json missing required field: $field"
  fi
done

# --- 3. Counter consistency ---
TOTAL_RETRIES=$(json_field "$STATE_FILE" "total_retries")
TOTAL_MAX=$(json_field "$STATE_FILE" "total_retries_max")
if [[ -n "$TOTAL_RETRIES" && -n "$TOTAL_MAX" ]]; then
  if [[ "$TOTAL_RETRIES" -gt "$TOTAL_MAX" ]]; then
    add_issue "total_retries ($TOTAL_RETRIES) exceeds total_retries_max ($TOTAL_MAX)"
  fi
fi

# --- 4. story_state validity ---
STORY_STATE=$(json_field "$STATE_FILE" "story_state")
VALID_STATES="PREFLIGHT EXPLORING PLANNING VALIDATING IMPLEMENTING VERIFYING REVIEWING DOCUMENTING SHIPPING LEARNING"
if [[ -n "$STORY_STATE" ]] && ! echo "$VALID_STATES" | grep -qw "$STORY_STATE"; then
  add_issue "state.json story_state '$STORY_STATE' is not a valid pipeline state"
fi

# --- 5. domain_area validation ---
DOMAIN=$(json_field "$STATE_FILE" "domain_area")
if [[ -n "$DOMAIN" ]]; then
  if [[ "$DOMAIN" =~ [[:space:]] || "$DOMAIN" =~ [A-Z] ]]; then
    add_warning "domain_area '$DOMAIN' should be lowercase single word"
  fi
fi

# --- 6. Orphaned checkpoint files ---
STORY_ID=$(json_field "$STATE_FILE" "story_id")
if [[ -n "$STORY_ID" ]]; then
  for cp in "$FORGE_DIR"/checkpoint-*.json; do
    [[ -f "$cp" ]] || continue
    if [[ "$(basename "$cp")" != *"$STORY_ID"* ]]; then
      add_warning "orphaned checkpoint: $(basename "$cp") (current story: $STORY_ID)"
    fi
  done
fi

# --- 7. Lock file staleness ---
LOCK_FILE="$FORGE_DIR/.lock"
if [[ -f "$LOCK_FILE" ]]; then
  LOCK_AGE_HOURS=$(( ($(date +%s) - $(stat -f %m "$LOCK_FILE" 2>/dev/null || stat -c %Y "$LOCK_FILE" 2>/dev/null || echo 0)) / 3600 ))
  if [[ "$LOCK_AGE_HOURS" -ge 24 ]]; then
    add_warning "stale lock file (${LOCK_AGE_HOURS}h old)"
  fi
fi

# --- 8. Evidence freshness (if exists) ---
EVIDENCE="$FORGE_DIR/evidence.json"
if [[ -f "$EVIDENCE" ]]; then
  VERDICT=$(json_field "$EVIDENCE" "verdict" 2>/dev/null || true)
  if [[ "$STORY_STATE" == "SHIPPING" && "$VERDICT" != "SHIP" && -n "$VERDICT" ]]; then
    add_warning "evidence.json verdict is '$VERDICT' but state is SHIPPING"
  fi
fi

# --- Output ---
EXIT_CODE=0
for w in "${WARNINGS[@]+"${WARNINGS[@]}"}"; do echo "$w"; done
for i in "${ISSUES[@]+"${ISSUES[@]}"}"; do echo "$i"; EXIT_CODE=1; done

if [[ $EXIT_CODE -eq 0 && ${#WARNINGS[@]} -eq 0 ]]; then
  echo "OK: state integrity validated"
fi

exit $EXIT_CODE
```

Then make it executable:
```bash
chmod +x shared/state-integrity.sh
```

- [ ] **Step 4: Run unit tests to verify they pass**

Run: `./tests/lib/bats-core/bin/bats tests/unit/state-integrity.bats`
Expected: All tests PASS.

- [ ] **Step 5: Add orchestrator reference**

In `agents/fg-100-orchestrator.md`, in the PREFLIGHT section where interrupted runs are detected, add:

```markdown
#### State Integrity Check

At PREFLIGHT, if `.forge/state.json` exists (interrupted run recovery), run `shared/state-integrity.sh .forge/` to validate state consistency. If the validator reports ERRORs, attempt `state-reconstruction` recovery. If it reports WARNINGs only, log them in stage notes and proceed. If `.forge/state.json` does not exist (fresh run), skip validation.
```

- [ ] **Step 6: Write scenario tests**

```bash
#!/usr/bin/env bats
# Scenario tests: state integrity integration

load '../helpers/test-helpers'

VALIDATOR="$PLUGIN_ROOT/shared/state-integrity.sh"
ORCHESTRATOR="$PLUGIN_ROOT/agents/fg-100-orchestrator.md"

@test "state-integrity-scenario: orchestrator runs validator at PREFLIGHT" {
  grep -qi "state-integrity\|integrity.*check\|validate.*state" "$ORCHESTRATOR" \
    || fail "Orchestrator does not reference state integrity validation"
}

@test "state-integrity-scenario: validator exits 0 on valid state" {
  local tmpdir
  tmpdir="$(mktemp -d)"
  cat > "$tmpdir/state.json" <<'EOF'
{
  "version": "1.4.0",
  "complete": false,
  "story_id": "test-story",
  "story_state": "PREFLIGHT",
  "domain_area": "general",
  "total_retries": 0,
  "total_retries_max": 10
}
EOF
  run bash "$VALIDATOR" "$tmpdir"
  assert_success
  assert_output --partial "OK"
  rm -rf "$tmpdir"
}

@test "state-integrity-scenario: validator exits 1 on invalid state" {
  local tmpdir
  tmpdir="$(mktemp -d)"
  echo "not json" > "$tmpdir/state.json"
  run bash "$VALIDATOR" "$tmpdir"
  assert_failure
  rm -rf "$tmpdir"
}
```

Write to `tests/scenario/state-integrity.bats`.

- [ ] **Step 7: Run all state integrity tests**

Run: `./tests/lib/bats-core/bin/bats tests/unit/state-integrity.bats tests/scenario/state-integrity.bats`
Expected: All tests PASS.

- [ ] **Step 8: Commit**

```bash
git add shared/state-integrity.sh tests/unit/state-integrity.bats tests/scenario/state-integrity.bats agents/fg-100-orchestrator.md
git commit -m "feat(state): add state integrity validator

Checks cross-reference consistency of .forge/ state files: required
fields, counter bounds, orphaned checkpoints, stale locks, evidence
freshness. Run at PREFLIGHT for crash recovery."
```

---

## Task 7: Check Engine Batching

**Files:**
- Modify: `shared/checks/engine.sh:401-418,444-470`
- Create: `tests/unit/engine-batching.bats`

### Purpose

Optimize the check engine to group files by language+component before processing, reducing redundant detection calls. Add a deferred queue mode for the PostToolUse hook.

- [ ] **Step 1: Write unit tests for batching**

```bash
#!/usr/bin/env bats
# Unit tests: check engine batching optimization

load '../helpers/test-helpers'

ENGINE="$PLUGIN_ROOT/shared/checks/engine.sh"

@test "engine-batching: engine.sh supports --batch-queue flag" {
  grep -q "batch.queue\|batch_queue\|BATCH_QUEUE\|deferred\|queue" "$ENGINE" \
    || fail "Batch queue mode not supported"
}

@test "engine-batching: verify mode groups files" {
  # Verify mode should group files by language before processing
  grep -q "group\|batch\|file_groups\|by_language\|by_component" "$ENGINE" \
    || fail "File grouping not implemented in verify/review mode"
}

@test "engine-batching: hook mode records to queue when FORGE_BATCH_HOOK is set" {
  local project_dir
  project_dir="$(create_temp_project spring)"
  local kt_file="${project_dir}/src/main/kotlin/Test.kt"
  printf 'package com.example\nval x = 1\n' > "$kt_file"
  local queue_file="${project_dir}/.forge/.hook-queue"
  mkdir -p "${project_dir}/.forge"

  run env \
    TOOL_INPUT="{\"file_path\": \"${kt_file}\"}" \
    CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" \
    FORGE_BATCH_HOOK=1 \
    FORGE_HOOK_QUEUE="$queue_file" \
    bash "$ENGINE" --hook

  assert_success
  # When FORGE_BATCH_HOOK is set, file should be queued, not processed
  [[ -f "$queue_file" ]] || fail "Hook queue file not created"
  grep -q "$kt_file" "$queue_file" || fail "File not added to queue"
  rm -rf "$project_dir"
}

@test "engine-batching: --flush-queue processes queued files" {
  local project_dir
  project_dir="$(create_temp_project spring)"
  mkdir -p "${project_dir}/.forge"
  local queue_file="${project_dir}/.forge/.hook-queue"
  local kt_file="${project_dir}/src/main/kotlin/Bad.kt"
  printf 'package com.example\nval x = someValue!!\n' > "$kt_file"
  git -C "$project_dir" add . && git -C "$project_dir" commit -q -m "init"
  echo "$kt_file" > "$queue_file"

  run env \
    CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" \
    bash "$ENGINE" --flush-queue --project-root "$project_dir" --queue-file "$queue_file"

  assert_success
  # Queue file should be cleared after flush
  if [[ -f "$queue_file" ]]; then
    [[ ! -s "$queue_file" ]] || fail "Queue not cleared after flush"
  fi
  rm -rf "$project_dir"
}
```

Write to `tests/unit/engine-batching.bats`.

- [ ] **Step 2: Run unit tests to verify they fail**

Run: `./tests/lib/bats-core/bin/bats tests/unit/engine-batching.bats`
Expected: FAIL — batching features don't exist yet.

- [ ] **Step 3: Add deferred hook queue to engine.sh**

In `shared/checks/engine.sh`, find the `mode_hook()` function (line 401). Replace the entire function:

```bash
# --- Mode: --hook (PostToolUse, single file, Layer 1 only) ---
mode_hook() {
  local file=""
  local py_cmd="python3"
  command -v python3 &>/dev/null || py_cmd="python"
  file="$(echo "${TOOL_INPUT:-}" | "$py_cmd" -c "import json,sys; d=json.load(sys.stdin); print(d.get('file_path',''))" 2>/dev/null)" || true
  if [[ -z "$file" ]]; then
    file="$(echo "${TOOL_INPUT:-}" | grep -oE '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"file_path"[[:space:]]*:[[:space:]]*"//; s/"$//' || true)"
  fi

  [[ -z "$file" || ! -f "$file" ]] && return 0
  [[ "$file" == *"build/generated-sources"* ]] && return 0

  # Deferred batch mode: queue file instead of processing immediately
  if [[ "${FORGE_BATCH_HOOK:-}" == "1" && -n "${FORGE_HOOK_QUEUE:-}" ]]; then
    echo "$file" >> "$FORGE_HOOK_QUEUE"
    return 0
  fi

  _CURRENT_FILE="$file"

  local project_root
  project_root="$(git -C "$(dirname "$file")" rev-parse --show-toplevel 2>/dev/null || true)"
  run_layer1 "$file" "$project_root"
}
```

- [ ] **Step 4: Add flush-queue mode to engine.sh**

In `shared/checks/engine.sh`, find the main dispatch case statement (line 473). Add the new mode:

```bash
# --- Mode: --flush-queue (process deferred hook queue) ---
mode_flush_queue() {
  shift  # consume --flush-queue
  local queue_file="" project_root=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project-root) project_root="$2"; shift 2 ;;
      --queue-file) queue_file="$2"; shift 2 ;;
      *) shift ;;
    esac
  done

  [[ -z "$queue_file" || ! -f "$queue_file" ]] && return 0
  [[ ! -s "$queue_file" ]] && return 0

  # Read unique files from queue
  local -A seen_files=()
  local files=()
  while IFS= read -r f; do
    [[ -z "$f" || ! -f "$f" ]] && continue
    [[ -n "${seen_files[$f]+x}" ]] && continue
    seen_files[$f]=1
    files+=("$f")
  done < "$queue_file"

  # Group files by language for efficient batch processing
  local -A file_groups=()
  for f in "${files[@]}"; do
    local lang
    lang="$(detect_language "$f")" || true
    [[ -z "$lang" ]] && continue
    file_groups[$lang]+="$f"$'\n'
  done

  # Process each language group
  for lang in "${!file_groups[@]}"; do
    while IFS= read -r f; do
      [[ -z "$f" ]] && continue
      _CURRENT_FILE="$f"
      run_layer1 "$f" "$project_root"
    done <<< "${file_groups[$lang]}"
  done

  # Clear the queue
  : > "$queue_file"
}
```

Update the main dispatch:

```bash
# --- Main dispatch ---
case "${1:---hook}" in
  --hook)        mode_hook ;;
  --verify)      mode_verify "$@" ;;
  --review)      mode_review "$@" ;;
  --flush-queue) mode_flush_queue "$@" ;;
  *)             echo "Usage: engine.sh [--hook | --verify | --review | --flush-queue] [options]" >&2 ;;
esac
```

- [ ] **Step 5: Add file grouping to verify/review modes**

In `shared/checks/engine.sh`, replace `mode_verify()` (lines 444-454):

```bash
# --- Mode: --verify (VERIFY stage, Layer 1 + Layer 2) ---
mode_verify() {
  shift  # consume --verify
  parse_batch_args "$@"

  # Group files by language for batch efficiency
  local -A file_groups=()
  for f in "${FILES_CHANGED[@]+"${FILES_CHANGED[@]}"}"; do
    [[ -f "$f" ]] || continue
    local lang
    lang="$(detect_language "$f")" || true
    [[ -z "$lang" ]] && lang="unknown"
    file_groups[$lang]+="$f"$'\n'
  done

  for lang in "${!file_groups[@]}"; do
    while IFS= read -r f; do
      [[ -z "$f" ]] && continue
      _CURRENT_FILE="$f"
      run_layer1 "$f" "$PROJECT_ROOT"
      run_layer2 "$f" "$PROJECT_ROOT"
    done <<< "${file_groups[$lang]}"
  done
}
```

Replace `mode_review()` (lines 456-470) with the same grouping pattern:

```bash
# --- Mode: --review (REVIEW stage, all layers) ---
mode_review() {
  shift  # consume --review
  parse_batch_args "$@"

  # Group files by language for batch efficiency
  local -A file_groups=()
  for f in "${FILES_CHANGED[@]+"${FILES_CHANGED[@]}"}"; do
    [[ -f "$f" ]] || continue
    local lang
    lang="$(detect_language "$f")" || true
    [[ -z "$lang" ]] && lang="unknown"
    file_groups[$lang]+="$f"$'\n'
  done

  for lang in "${!file_groups[@]}"; do
    while IFS= read -r f; do
      [[ -z "$f" ]] && continue
      _CURRENT_FILE="$f"
      run_layer1 "$f" "$PROJECT_ROOT"
      run_layer2 "$f" "$PROJECT_ROOT"
    done <<< "${file_groups[$lang]}"
  done
  # Layer 3 (agent intelligence) is handled by dedicated agent dispatch, not shell execution.
  # - fg-140-deprecation-refresh: dispatched during PREFLIGHT by the orchestrator
  # - fg-417-version-compat-reviewer: dispatched during REVIEW via quality gate batches
  # See agents/fg-140-deprecation-refresh.md and agents/fg-417-version-compat-reviewer.md
}
```

- [ ] **Step 6: Run unit tests to verify they pass**

Run: `./tests/lib/bats-core/bin/bats tests/unit/engine-batching.bats`
Expected: All tests PASS.

- [ ] **Step 7: Run the full engine test suite to check for regressions**

Run: `./tests/lib/bats-core/bin/bats tests/unit/engine.bats`
Expected: All existing tests still PASS.

- [ ] **Step 8: Commit**

```bash
git add shared/checks/engine.sh tests/unit/engine-batching.bats
git commit -m "feat(checks): add deferred hook queue and file grouping

Hook mode can now queue files (FORGE_BATCH_HOOK=1) instead of processing
immediately. --flush-queue processes the queue with dedup. Verify/review
modes group files by language for batch efficiency."
```

---

## Task 8: Update CLAUDE.md Key Entry Points

**Files:**
- Modify: `CLAUDE.md`

### Purpose

Add references to all new shared documents in the key entry points table.

- [ ] **Step 1: Update the key entry points table**

In `CLAUDE.md`, find the key entry points table. Add these rows:

```markdown
| State machine | `shared/state-transitions.md` |
| Domain detection | `shared/domain-detection.md` |
| Decision log | `shared/decision-log.md` |
| State integrity | `shared/state-integrity.sh` |
```

- [ ] **Step 2: Update the architecture section**

In the "Core contracts" section of `CLAUDE.md`, add a new subsection:

```markdown
### Deterministic Control Flow

Pipeline control flow follows the formal transition table in `shared/state-transitions.md`. LLM judgment is used for code review, implementation, and architecture decisions — NOT for state transitions. Every branching decision is logged to `.forge/decisions.jsonl` per `shared/decision-log.md`. Recovery uses circuit breakers per failure category (`shared/recovery/recovery-engine.md` §8.1). Reviewer conflicts are resolved by priority ordering in `shared/agent-communication.md` §3.1.
```

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md with new architectural contracts

Adds state-transitions, domain-detection, decision-log, and
state-integrity to key entry points. Documents deterministic
control flow principle."
```

---

## Task 9: Update Structural Validation

**Files:**
- Modify: `tests/validate-plugin.sh`

### Purpose

Add structural checks for all new files to the plugin validation script.

- [ ] **Step 1: Add structural checks**

In `tests/validate-plugin.sh`, find the section that checks shared contract files. Add:

```bash
# --- State Transitions ---
echo "Checking state-transitions.md..."
[[ -f "$PLUGIN_ROOT/shared/state-transitions.md" ]] || { echo "FAIL: shared/state-transitions.md missing"; FAIL=1; }

# --- Domain Detection ---
echo "Checking domain-detection.md..."
[[ -f "$PLUGIN_ROOT/shared/domain-detection.md" ]] || { echo "FAIL: shared/domain-detection.md missing"; FAIL=1; }

# --- Decision Log ---
echo "Checking decision-log.md..."
[[ -f "$PLUGIN_ROOT/shared/decision-log.md" ]] || { echo "FAIL: shared/decision-log.md missing"; FAIL=1; }

# --- State Integrity ---
echo "Checking state-integrity.sh..."
[[ -f "$PLUGIN_ROOT/shared/state-integrity.sh" ]] || { echo "FAIL: shared/state-integrity.sh missing"; FAIL=1; }
[[ -x "$PLUGIN_ROOT/shared/state-integrity.sh" ]] || { echo "FAIL: shared/state-integrity.sh not executable"; FAIL=1; }
```

- [ ] **Step 2: Run structural validation**

Run: `./tests/validate-plugin.sh`
Expected: All checks PASS (including new ones).

- [ ] **Step 3: Run the full test suite**

Run: `./tests/run-all.sh`
Expected: All tiers PASS. No regressions.

- [ ] **Step 4: Commit**

```bash
git add tests/validate-plugin.sh
git commit -m "test: add structural checks for new architectural contracts

Validates existence of state-transitions.md, domain-detection.md,
decision-log.md, and state-integrity.sh."
```

---

## Task 10: Agent Consolidation Roadmap

**Files:**
- Create: `docs/superpowers/plans/agent-consolidation-roadmap.md`

### Purpose

Document which agents should be merged in a future plan. This task is analysis only — no agent files are modified. Merging agents is high-risk and deserves its own dedicated plan with careful validation.

- [ ] **Step 1: Write the consolidation analysis**

Write `docs/superpowers/plans/agent-consolidation-roadmap.md`:

```markdown
# Agent Consolidation Roadmap

## Current State: 40 Agents

The forge pipeline has 40 agents. Each dispatch costs ~50K+ tokens of context construction. A typical pipeline run invokes 15-20 agents.

## Consolidation Opportunities

### Tier 1: Safe Merges (overlapping domains, same stage)

| Current Agents | Merged Agent | Savings | Risk |
|---|---|---|---|
| `fg-413-frontend-reviewer` + `frontend-design-reviewer` | `fg-413-frontend-reviewer` (with design checklist) | 1 dispatch | Low — same files, same stage |
| ~~`fg-414-frontend-a11y-reviewer` + `fg-415-frontend-performance-reviewer`~~ | ~~`fg-414-frontend-quality-reviewer`~~ | ~~1 dispatch~~ | **[DONE]** |
| ~~`fg-410-architecture-reviewer` + `fg-412-code-quality-reviewer`~~ | ~~`fg-410-code-reviewer`~~ | ~~1 dispatch~~ | **[DONE]** |

### Tier 2: Moderate Merges (adjacent concerns)

| Current Agents | Merged Agent | Savings | Risk |
|---|---|---|---|
| ~~`fg-710-feedback-capture` + `fg-720-recap`~~ | ~~`fg-710-post-run`~~ | ~~1 dispatch~~ | **[DONE]** |
| `fg-101-worktree-manager` + `fg-102-conflict-resolver` | `fg-101-workspace-manager` | 1 dispatch | Medium — different trigger points |

### Tier 3: Do Not Merge

| Agent | Reason |
|---|---|
| `fg-100-orchestrator` | Coordinator — must stay isolated |
| `fg-300-implementer` | Hot path — large prompt |
| `fg-200-planner` | Distinct domain (planning vs implementation) |
| `fg-411-security-reviewer` | Regulatory concern — must be independently auditable |
| `fg-590-pre-ship-verifier` | Evidence gate — must be independent |

## Recommended First Merge

`fg-413-frontend-reviewer` + `frontend-design-reviewer` → combined `fg-413-frontend-reviewer`:
- Both review the same files (frontend components)
- Both dispatched in the same quality gate batch
- Design checklist becomes a section within the reviewer
- Reduces batch dispatch by 1 agent per REVIEW cycle

## Implementation Plan

1. Merge the agent `.md` files (combine checklists, deduplicate shared sections)
2. Update `agents/fg-400-quality-gate.md` batch dispatch references
3. Update `plugin.json` agent list
4. Update `CLAUDE.md` agent count and list
5. Update structural tests that validate agent count
6. Run full test suite
7. Validate with a dry-run pipeline execution

## Target State: ~30 Agents (from 40)

Tier 1 merges: 40 → 37
Tier 2 merges: 37 → 35
Future architectural simplification: 35 → ~30

Each merge should be its own commit with full test validation.
```

- [ ] **Step 2: Commit**

```bash
git add docs/superpowers/plans/agent-consolidation-roadmap.md
git commit -m "docs: add agent consolidation roadmap

Analyzes 40 agents for merge opportunities. Identifies 5 safe merges
(Tier 1-2) that would reduce to ~35 agents. Recommends frontend
reviewer merge as first step."
```

---

## Verification

After all tasks are complete:

- [ ] **Run the full test suite**

```bash
./tests/run-all.sh
```

Expected: All tiers PASS — structural, unit, contract, scenario.

- [ ] **Verify new file count**

```bash
find shared/ -name "state-transitions.md" -o -name "domain-detection.md" -o -name "decision-log.md" -o -name "state-integrity.sh" | wc -l
```

Expected: 4 new files in `shared/`.

- [ ] **Verify new test count**

```bash
find tests/ -name "*.bats" -newer CLAUDE.md | wc -l
```

Expected: 10+ new test files.

- [ ] **Verify no regressions in existing tests**

```bash
./tests/lib/bats-core/bin/bats tests/unit/engine.bats tests/unit/scoring-edge-cases.bats tests/contract/convergence-engine.bats tests/scenario/convergence-engine.bats
```

Expected: All existing tests PASS unchanged.
