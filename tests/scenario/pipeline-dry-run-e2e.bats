#!/usr/bin/env bats
# Scenario test: dry-run pipeline state machine progression.
# Validates PREFLIGHT -> EXPLORING -> PLANNING -> VALIDATING -> COMPLETE
# using forge-state.sh transition events.

# Covers: T-01, T-02, T-09, D-01

load '../helpers/test-helpers'

FORGE_STATE_SH="$PLUGIN_ROOT/shared/forge-state.sh"

setup() {
  # Standard setup from helpers
  TEST_TEMP="$(mktemp -d "${TMPDIR:-${TMP:-${TEMP:-/tmp}}}/bats-forge.XXXXXX")"
  MOCK_BIN="${TEST_TEMP}/mock-bin"
  mkdir -p "${MOCK_BIN}"
  export PATH="${MOCK_BIN}:${PATH}"

  FORGE_DIR="${TEST_TEMP}/.forge"
  mkdir -p "$FORGE_DIR"

  # Initialize state via the init command (dry-run mode)
  bash "$FORGE_STATE_SH" init "feat-dry-run-test" "Test dry run pipeline" --mode standard --dry-run --forge-dir "$FORGE_DIR"
}

teardown() {
  [[ -n "${TEST_TEMP:-}" && -d "${TEST_TEMP}" ]] && rm -rf "${TEST_TEMP}"
}

@test "dry-run: initial state is PREFLIGHT" {
  local state
  state="$(jq -r '.story_state' "$FORGE_DIR/state.json")"
  [[ "$state" == "PREFLIGHT" ]]
}

@test "dry-run: preflight_complete transitions to EXPLORING" {
  run bash "$FORGE_STATE_SH" transition preflight_complete --forge-dir "$FORGE_DIR"
  assert_success
  local state
  state="$(jq -r '.story_state' "$FORGE_DIR/state.json")"
  [[ "$state" == "EXPLORING" ]]
}

@test "dry-run: explore_complete transitions to PLANNING" {
  # First get to EXPLORING
  bash "$FORGE_STATE_SH" transition preflight_complete --forge-dir "$FORGE_DIR" > /dev/null
  # Then transition to PLANNING (scope < threshold)
  run bash "$FORGE_STATE_SH" transition explore_complete --guard "scope=1" --guard "decomposition_threshold=3" --forge-dir "$FORGE_DIR"
  assert_success
  local state
  state="$(jq -r '.story_state' "$FORGE_DIR/state.json")"
  [[ "$state" == "PLANNING" ]]
}

@test "dry-run: plan_complete transitions to VALIDATING" {
  bash "$FORGE_STATE_SH" transition preflight_complete --forge-dir "$FORGE_DIR" > /dev/null
  bash "$FORGE_STATE_SH" transition explore_complete --guard "scope=1" --guard "decomposition_threshold=3" --forge-dir "$FORGE_DIR" > /dev/null
  run bash "$FORGE_STATE_SH" transition plan_complete --forge-dir "$FORGE_DIR"
  assert_success
  local state
  state="$(jq -r '.story_state' "$FORGE_DIR/state.json")"
  [[ "$state" == "VALIDATING" ]]
}

@test "dry-run: validate_complete with dry_run=true completes pipeline" {
  bash "$FORGE_STATE_SH" transition preflight_complete --forge-dir "$FORGE_DIR" > /dev/null
  bash "$FORGE_STATE_SH" transition explore_complete --guard "scope=1" --guard "decomposition_threshold=3" --forge-dir "$FORGE_DIR" > /dev/null
  bash "$FORGE_STATE_SH" transition plan_complete --forge-dir "$FORGE_DIR" > /dev/null
  run bash "$FORGE_STATE_SH" transition validate_complete --forge-dir "$FORGE_DIR"
  assert_success
  local state
  state="$(jq -r '.story_state' "$FORGE_DIR/state.json")"
  # dry_run=true triggers Row D1: VALIDATING + validate_complete -> COMPLETE
  [[ "$state" == "COMPLETE" ]]
}

@test "dry-run: state file well-formed after transitions" {
  bash "$FORGE_STATE_SH" transition preflight_complete --forge-dir "$FORGE_DIR" > /dev/null
  bash "$FORGE_STATE_SH" transition explore_complete --guard "scope=1" --guard "decomposition_threshold=3" --forge-dir "$FORGE_DIR" > /dev/null

  # Validate required fields exist
  local version state mode seq
  version="$(jq -r '.version' "$FORGE_DIR/state.json")"
  state="$(jq -r '.story_state' "$FORGE_DIR/state.json")"
  mode="$(jq -r '.mode' "$FORGE_DIR/state.json")"
  seq="$(jq -r '._seq' "$FORGE_DIR/state.json")"

  [[ "$version" == "1.6.0" ]]
  [[ -n "$state" && "$state" != "null" ]]
  [[ "$mode" == "standard" ]]
  (( seq > 0 ))
}

@test "dry-run: _seq increments on each transition" {
  local seq_before seq_after
  seq_before="$(jq -r '._seq' "$FORGE_DIR/state.json")"
  bash "$FORGE_STATE_SH" transition preflight_complete --forge-dir "$FORGE_DIR" > /dev/null
  seq_after="$(jq -r '._seq' "$FORGE_DIR/state.json")"
  (( seq_after > seq_before ))
}

@test "dry-run: invalid event from wrong state is rejected" {
  # From PREFLIGHT, send explore_complete (wrong -- should be preflight_complete)
  run bash "$FORGE_STATE_SH" transition explore_complete --guard "scope=1" --guard "decomposition_threshold=3" --forge-dir "$FORGE_DIR"
  assert_failure
}
