#!/usr/bin/env bats
# Scenario tests: state integrity validation integration with the pipeline.
# Verifies the orchestrator references the validator at PREFLIGHT, and that
# the validator produces correct exit codes on valid/invalid state.

load '../helpers/test-helpers'

SCRIPT="$PLUGIN_ROOT/shared/state-integrity.sh"
ORCHESTRATOR="$PLUGIN_ROOT/agents/fg-100-orchestrator.md"

# ---------------------------------------------------------------------------
# 1. Orchestrator references state-integrity at PREFLIGHT
# ---------------------------------------------------------------------------
@test "state-integrity-scenario: orchestrator runs validator at PREFLIGHT" {
  run grep -i 'state-integrity\|integrity check\|integrity valid' "$ORCHESTRATOR"

  assert_success
  # The orchestrator should mention the state integrity validator
  assert_output --partial "state-integrity"
}

# ---------------------------------------------------------------------------
# 2. Validator exits 0 on valid state
# ---------------------------------------------------------------------------
@test "state-integrity-scenario: validator exits 0 on valid state" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  cat > "$forge_dir/state.json" << 'EOF'
{
  "version": "1.5.0",
  "complete": false,
  "story_id": "feat-plan-comments",
  "story_state": "IMPLEMENTING",
  "domain_area": "plan",
  "risk_level": "MEDIUM",
  "total_retries": 3,
  "total_retries_max": 10,
  "total_iterations": 2,
  "quality_cycles": 1,
  "test_cycles": 1,
  "verify_fix_count": 0
}
EOF
  # Also create a matching checkpoint file
  echo '{"tasks_completed": []}' > "$forge_dir/checkpoint-feat-plan-comments.json"

  run bash "$SCRIPT" "$forge_dir"

  assert_success
  assert_output --partial "OK: state integrity validated"
}

# ---------------------------------------------------------------------------
# 3. Validator exits 1 on invalid state
# ---------------------------------------------------------------------------
@test "state-integrity-scenario: validator exits 1 on invalid state" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  # Missing required fields + counter violation
  cat > "$forge_dir/state.json" << 'EOF'
{
  "version": "1.5.0",
  "complete": false,
  "story_id": "test-broken",
  "story_state": "INVALID_STATE",
  "domain_area": "Test With Spaces",
  "total_retries": 20,
  "total_retries_max": 10
}
EOF
  # Create orphaned checkpoint for a different story
  echo '{}' > "$forge_dir/checkpoint-old-story.json"

  run bash "$SCRIPT" "$forge_dir"

  assert_failure
  # Should report the counter violation
  assert_output --partial "exceeds"
  # Should report the invalid state
  assert_output --partial "invalid story_state"
}
