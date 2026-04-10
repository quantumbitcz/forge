#!/usr/bin/env bats
# Contract tests: orchestrator state machine — validates stage progression,
# entry/exit conditions, and retry loop documentation in the orchestrator
# and stage contract.

load '../helpers/test-helpers'

ORCHESTRATOR="$PLUGIN_ROOT/agents/fg-100-orchestrator.md"
ORCHESTRATOR_ALL=("$PLUGIN_ROOT/agents/fg-100-orchestrator.md" "$PLUGIN_ROOT/agents/fg-100-orchestrator.md" "$PLUGIN_ROOT/agents/fg-100-orchestrator.md" "$PLUGIN_ROOT/agents/fg-100-orchestrator.md")
STAGE_CONTRACT="$PLUGIN_ROOT/shared/stage-contract.md"
STATE_SCHEMA="$PLUGIN_ROOT/shared/state-schema.md"

# ---------------------------------------------------------------------------
# 1. All 10 pipeline stages documented in orchestrator
# ---------------------------------------------------------------------------
@test "orchestrator-sm: all 10 story_state values referenced in orchestrator" {
  for state in PREFLIGHT EXPLORING PLANNING VALIDATING IMPLEMENTING VERIFYING REVIEWING DOCUMENTING SHIPPING LEARNING; do
    grep -q "$state" "${ORCHESTRATOR_ALL[@]}" \
      || fail "story_state '$state' not referenced in orchestrator"
  done
}

# ---------------------------------------------------------------------------
# 2. Stage progression order matches stage contract
# ---------------------------------------------------------------------------
@test "orchestrator-sm: stage contract documents all 10 stages (0-9)" {
  grep -qE "Stage 0.*PREFLIGHT|PREFLIGHT.*Stage 0" "$STAGE_CONTRACT" \
    || fail "Stage 0 (PREFLIGHT) not documented"
  grep -qE "Stage 9.*LEARN|LEARN.*Stage 9" "$STAGE_CONTRACT" \
    || fail "Stage 9 (LEARN) not documented"
}

# ---------------------------------------------------------------------------
# 3. Each stage has documented entry and exit conditions
# ---------------------------------------------------------------------------
@test "orchestrator-sm: stage contract documents entry conditions for each stage" {
  local entry_count
  entry_count=$(grep -ci "entry condition\|entry:" "$STAGE_CONTRACT" || echo "0")
  [[ "$entry_count" -ge 10 ]] \
    || fail "Expected >= 10 entry condition mentions, found $entry_count"
}

@test "orchestrator-sm: stage contract documents exit conditions for each stage" {
  local exit_count
  exit_count=$(grep -ci "exit condition\|exit:" "$STAGE_CONTRACT" || echo "0")
  [[ "$exit_count" -ge 10 ]] \
    || fail "Expected >= 10 exit condition mentions, found $exit_count"
}

# ---------------------------------------------------------------------------
# 4. Retry loops documented
# ---------------------------------------------------------------------------
@test "orchestrator-sm: VALIDATE→PLAN retry loop documented" {
  grep -q "VALIDATING.*PLANNING\|VALIDATE.*PLAN\|Stage 3.*Stage 2" "$STAGE_CONTRACT" \
    || grep -q "REVISE" "$STAGE_CONTRACT" \
    || fail "VALIDATE→PLAN retry loop not documented"
}

@test "orchestrator-sm: VERIFY→IMPLEMENT retry loop documented" {
  grep -q "VERIFYING.*IMPLEMENTING\|VERIFY.*IMPLEMENT\|Stage 5.*Stage 4" "$STAGE_CONTRACT" \
    || grep -q "verify_fix_count\|fix.*loop" "$STAGE_CONTRACT" \
    || fail "VERIFY→IMPLEMENT retry loop not documented"
}

@test "orchestrator-sm: REVIEW→IMPLEMENT retry loop documented" {
  grep -q "REVIEWING.*IMPLEMENTING\|REVIEW.*IMPLEMENT\|Stage 6.*Stage 4" "$STAGE_CONTRACT" \
    || grep -q "quality_cycles\|review.*loop" "$STAGE_CONTRACT" \
    || fail "REVIEW→IMPLEMENT retry loop not documented"
}

# ---------------------------------------------------------------------------
# 5. State schema validates story_state enum
# ---------------------------------------------------------------------------
@test "orchestrator-sm: state schema lists all valid story_state values" {
  for state in PREFLIGHT EXPLORING PLANNING VALIDATING IMPLEMENTING VERIFYING REVIEWING DOCUMENTING SHIPPING LEARNING; do
    grep -q "$state" "$STATE_SCHEMA" \
      || fail "story_state '$state' not in state schema"
  done
}

# ---------------------------------------------------------------------------
# 6. Mode-specific stage routing
# ---------------------------------------------------------------------------
@test "orchestrator-sm: bootstrap mode skips Stage 4 (IMPLEMENT)" {
  grep -qi "bootstrap.*skip\|Stage 4.*skip\|skip.*IMPLEMENT.*bootstrap" "$STAGE_CONTRACT" \
    || grep -qi "bootstrap.*reduced\|bootstrap.*Stage 4" "${ORCHESTRATOR_ALL[@]}" \
    || fail "Bootstrap mode stage skipping not documented"
}

@test "orchestrator-sm: bugfix mode has INVESTIGATE and REPRODUCE stages" {
  grep -q "INVESTIGATE" "$STAGE_CONTRACT" || fail "INVESTIGATE not in stage contract"
  grep -q "REPRODUCE" "$STAGE_CONTRACT" || fail "REPRODUCE not in stage contract"
}

@test "orchestrator-sm: migration mode has MIGRATING state" {
  grep -q "MIGRATING" "$STATE_SCHEMA" || fail "MIGRATING state not in state schema"
  grep -q "MIGRATING" "$STAGE_CONTRACT" || fail "MIGRATING not in stage contract"
}

# ---------------------------------------------------------------------------
# 7. Dry-run mode constraints
# ---------------------------------------------------------------------------
@test "orchestrator-sm: dry-run stops at VALIDATE (no IMPLEMENT)" {
  grep -qi "dry.run.*VALIDATE\|dry.run.*Stage 3\|PREFLIGHT.*VALIDATE.*dry" "$STAGE_CONTRACT" \
    || grep -qi "dry.run.*VALIDATE\|dry.run.*no worktree\|dry.run.*read.only" "${ORCHESTRATOR_ALL[@]}" \
    || fail "Dry-run mode VALIDATE-only constraint not documented"
}

# ---------------------------------------------------------------------------
# 8. Iteration counters documented
# ---------------------------------------------------------------------------
@test "orchestrator-sm: 5 iteration counters documented in state schema" {
  grep -q "verify_fix_count" "$STATE_SCHEMA" || fail "verify_fix_count not in state schema"
  grep -q "test_cycles" "$STATE_SCHEMA" || fail "test_cycles not in state schema"
  grep -q "quality_cycles" "$STATE_SCHEMA" || fail "quality_cycles not in state schema"
  grep -q "phase_iterations" "$STATE_SCHEMA" || fail "phase_iterations not in state schema"
  grep -q "total_iterations" "$STATE_SCHEMA" || fail "total_iterations not in state schema"
}

# ---------------------------------------------------------------------------
# 9. Feedback loop escalation
# ---------------------------------------------------------------------------
@test "orchestrator-sm: feedback loop count documented with escalation" {
  grep -q "feedback_loop_count" "$STATE_SCHEMA" || fail "feedback_loop_count not in state schema"
  grep -qi "escalat" "${ORCHESTRATOR_ALL[@]}" || fail "Escalation not mentioned in orchestrator"
}

# ---------------------------------------------------------------------------
# 10. Stage timestamp tracking
# ---------------------------------------------------------------------------
@test "orchestrator-sm: stage timestamps tracked in state" {
  grep -q "stage_timestamps" "$STATE_SCHEMA" || fail "stage_timestamps not in state schema"
}
