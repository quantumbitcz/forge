#!/usr/bin/env bats
# Contract tests: shared/stage-contract.md — validates the stage contract document.

load '../helpers/test-helpers'

STAGE_CONTRACT="$PLUGIN_ROOT/shared/stage-contract.md"

# ---------------------------------------------------------------------------
# 1. Document exists
# ---------------------------------------------------------------------------
@test "stage-contract: document exists" {
  [[ -f "$STAGE_CONTRACT" ]]
}

# ---------------------------------------------------------------------------
# 2. All 10 stages documented (Stage 0 through Stage 9)
# ---------------------------------------------------------------------------
@test "stage-contract: all 10 stages (0-9) are documented" {
  for n in 0 1 2 3 4 5 6 7 8 9; do
    grep -q "Stage ${n}" "$STAGE_CONTRACT" \
      || fail "Stage $n not found in stage-contract.md"
  done
}

# ---------------------------------------------------------------------------
# 3. Stage names match the canonical list
# ---------------------------------------------------------------------------
@test "stage-contract: stage names PREFLIGHT EXPLORE PLAN VALIDATE IMPLEMENT VERIFY REVIEW DOCS SHIP LEARN" {
  local names=(PREFLIGHT EXPLORE PLAN VALIDATE IMPLEMENT VERIFY REVIEW DOCS SHIP LEARN)
  for name in "${names[@]}"; do
    grep -q "$name" "$STAGE_CONTRACT" \
      || fail "Stage name $name not found in stage-contract.md"
  done
}

# ---------------------------------------------------------------------------
# 4. story_state values documented
# ---------------------------------------------------------------------------
@test "stage-contract: story_state values documented for all pipeline stages" {
  local states=(PREFLIGHT EXPLORING PLANNING VALIDATING IMPLEMENTING VERIFYING REVIEWING DOCUMENTING SHIPPING LEARNING)
  for state in "${states[@]}"; do
    grep -q "\`${state}\`\|\"${state}\"" "$STAGE_CONTRACT" \
      || fail "story_state value $state not found in stage-contract.md"
  done
}

# ---------------------------------------------------------------------------
# 5. Migration-specific states documented (in state-schema.md, referenced in CLAUDE.md)
# ---------------------------------------------------------------------------
@test "stage-contract: migration-specific states documented in state-schema or CLAUDE.md" {
  local STATE_SCHEMA="$PLUGIN_ROOT/shared/state-schema.md"
  local migration_states=(MIGRATING MIGRATION_PAUSED MIGRATION_CLEANUP MIGRATION_VERIFY)
  for state in "${migration_states[@]}"; do
    grep -q "$state" "$STATE_SCHEMA" \
      || fail "Migration state $state not found in state-schema.md"
  done
}

# ---------------------------------------------------------------------------
# 6. Each stage has "Entry condition" section
# ---------------------------------------------------------------------------
@test "stage-contract: every stage section has an Entry condition" {
  local count
  count=$(grep -c "Entry condition" "$STAGE_CONTRACT" || true)
  # 10 stages × 1 entry condition each — plus possibly the table header
  [[ "$count" -ge 10 ]] \
    || fail "Expected at least 10 Entry condition sections, found $count"
}

# ---------------------------------------------------------------------------
# 7. Each stage has "Exit condition" section
# ---------------------------------------------------------------------------
@test "stage-contract: every stage section has an Exit condition" {
  local count
  count=$(grep -c "Exit condition" "$STAGE_CONTRACT" || true)
  [[ "$count" -ge 10 ]] \
    || fail "Expected at least 10 Exit condition sections, found $count"
}

# ---------------------------------------------------------------------------
# 8. Retry loops documented (VALIDATE→PLAN, VERIFY→IMPLEMENT, REVIEW→IMPLEMENT)
# ---------------------------------------------------------------------------
@test "stage-contract: retry loops documented for VALIDATE-PLAN, VERIFY-IMPLEMENT, REVIEW-IMPLEMENT" {
  grep -q "VALIDATE.*PLAN\|Plan revision" "$STAGE_CONTRACT" \
    || fail "VALIDATE→PLAN retry loop not documented"
  grep -q "VERIFY.*IMPLEMENT\|Test fix" "$STAGE_CONTRACT" \
    || fail "VERIFY→IMPLEMENT retry loop not documented"
  grep -q "REVIEW.*IMPLEMENT\|Quality fix" "$STAGE_CONTRACT" \
    || fail "REVIEW→IMPLEMENT retry loop not documented"
}

# ---------------------------------------------------------------------------
# 9. --dry-run behavior documented (stops after VALIDATE, stages 4-9 skipped)
# ---------------------------------------------------------------------------
@test "stage-contract: --dry-run behavior documented and stops after VALIDATE" {
  grep -q "dry-run\|dry_run" "$STAGE_CONTRACT" \
    || fail "--dry-run not mentioned in stage-contract.md"
  grep -q "Stages 4-9\|stages 4-9\|4-9.*skipped\|stop.*VALIDATE\|stops.*after VALIDATE" "$STAGE_CONTRACT" \
    || fail "--dry-run stop-after-VALIDATE behavior not documented"
}

# ---------------------------------------------------------------------------
# 10. Escalation paths documented
# ---------------------------------------------------------------------------
@test "stage-contract: escalation paths documented" {
  grep -q "Escalation\|escalat" "$STAGE_CONTRACT" \
    || fail "Escalation paths not documented in stage-contract.md"
  # Verify multiple conditions are listed in the escalation table
  local count
  count=$(grep -ci "escalat" "$STAGE_CONTRACT" || true)
  [[ "$count" -ge 3 ]] \
    || fail "Expected at least 3 escalation mentions, found $count"
}

# ---------------------------------------------------------------------------
# 11. Bootstrap mode stage definitions
# ---------------------------------------------------------------------------
@test "stage-contract: bootstrap mode defined with stage-by-stage behavior" {
  grep -q "Bootstrap mode" "$STAGE_CONTRACT" \
    || fail "Bootstrap mode not documented in stage-contract.md"
  grep -q "Stage 4.*IMPLEMENT.*Skip\|Skip.*entirely\|skipped" "$STAGE_CONTRACT" \
    || fail "Bootstrap mode does not document Stage 4 skip"
  grep -qi "reduced reviewer\|architecture-reviewer.*security-reviewer" "$STAGE_CONTRACT" \
    || fail "Bootstrap mode does not document reduced reviewer set at Stage 6"
}

# ---------------------------------------------------------------------------
# 12. Migration mode stage definitions
# ---------------------------------------------------------------------------
@test "stage-contract: migration mode defined with per-stage behavior" {
  grep -q "Migration mode" "$STAGE_CONTRACT" \
    || fail "Migration mode not documented in stage-contract.md"
  grep -q "MIGRATING" "$STAGE_CONTRACT" \
    || fail "MIGRATING state not documented in migration mode"
  grep -q "fg-160-migration-planner" "$STAGE_CONTRACT" \
    || fail "fg-160-migration-planner not referenced in migration mode"
}

# ---------------------------------------------------------------------------
# 13. Feedback loop detection documented
# ---------------------------------------------------------------------------
@test "stage-contract: feedback loop detection with escalation options" {
  grep -q "feedback_loop_count" "$STAGE_CONTRACT" \
    || fail "feedback_loop_count not documented in stage-contract.md"
  grep -q "Guide.*Start fresh.*Override" "$STAGE_CONTRACT" \
    || fail "Feedback loop escalation options not documented"
}
