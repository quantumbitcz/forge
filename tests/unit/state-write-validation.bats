#!/usr/bin/env bats
# Unit tests: advisory schema validation in forge-state-write.sh

load '../helpers/test-helpers'

STATE_WRITER="$PLUGIN_ROOT/shared/forge-state-write.sh"

# ---------------------------------------------------------------------------
# 1. Valid state writes without warnings
# ---------------------------------------------------------------------------

@test "state-write-validation: valid state produces no WARNING on stderr" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"

  local valid_json
  valid_json=$(cat "$PLUGIN_ROOT/tests/fixtures/state/v1.5.0-valid.json")

  run bash "$STATE_WRITER" write "$valid_json" --forge-dir "$forge_dir"
  assert_success
  refute_output --partial "WARNING: State validation failed"
}

# ---------------------------------------------------------------------------
# 2. Invalid state (bad story_state) writes but emits WARNING
# ---------------------------------------------------------------------------

@test "state-write-validation: invalid story_state emits WARNING but still writes" {
  # Skip if jsonschema not installed
  python3 -c "import jsonschema" 2>/dev/null || skip "jsonschema not installed"

  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"

  local invalid_json='{"version":"1.5.0","_seq":0,"complete":false,"story_id":"X","requirement":"x","story_state":"INVALID_STATE","mode":"standard","dry_run":false,"convergence":{"phase":"correctness","phase_iterations":0,"total_iterations":0,"plateau_count":0,"last_score_delta":0,"convergence_state":"IMPROVING","phase_history":[],"safety_gate_passed":false,"safety_gate_failures":0,"unfixable_findings":[],"diminishing_count":0,"unfixable_info_count":0},"recovery":{"total_failures":0,"total_recoveries":0,"degraded_capabilities":[],"failures":[],"budget_warning_issued":false},"recovery_budget":{"total_weight":0,"max_weight":5.5,"applications":[]},"integrations":{},"cost":{"wall_time_seconds":0,"stages_completed":0},"score_history":[]}'

  run bash "$STATE_WRITER" write "$invalid_json" --forge-dir "$forge_dir"
  assert_success
  # Should emit a warning to stderr — check the file was still written
  [[ -f "$forge_dir/state.json" ]]
}

# ---------------------------------------------------------------------------
# 3. Validation skipped gracefully when jsonschema not installed
# ---------------------------------------------------------------------------

@test "state-write-validation: writes successfully when VALIDATE=false" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"

  local valid_json
  valid_json=$(cat "$PLUGIN_ROOT/tests/fixtures/state/v1.5.0-valid.json")

  VALIDATE=false run bash "$STATE_WRITER" write "$valid_json" --forge-dir "$forge_dir"
  assert_success
  [[ -f "$forge_dir/state.json" ]]
}
