#!/usr/bin/env bats
# Scenario test: pipeline mode transitions (bugfix, bootstrap, dry-run, standard).
# Validates mode-specific behavior using forge-state.sh.

# Covers:

load '../helpers/test-helpers'

FORGE_STATE_SH="$PLUGIN_ROOT/shared/forge-state.sh"

setup() {
  TEST_TEMP="$(mktemp -d "${TMPDIR:-${TMP:-${TEMP:-/tmp}}}/bats-forge.XXXXXX")"
  MOCK_BIN="${TEST_TEMP}/mock-bin"
  mkdir -p "${MOCK_BIN}"
  export PATH="${MOCK_BIN}:${PATH}"

  FORGE_DIR="${TEST_TEMP}/.forge"
  mkdir -p "$FORGE_DIR"
}

teardown() {
  [[ -n "${TEST_TEMP:-}" && -d "${TEST_TEMP}" ]] && rm -rf "${TEST_TEMP}"
}

# ---------------------------------------------------------------------------
# 1. Bugfix mode sets mode field correctly
# ---------------------------------------------------------------------------
@test "mode-transitions: bugfix mode sets mode=bugfix in state" {
  bash "$FORGE_STATE_SH" init "MT-001" "Fix login bug" --mode bugfix --forge-dir "$FORGE_DIR"

  local mode
  mode="$(jq -r '.mode' "$FORGE_DIR/state.json")"
  [[ "$mode" == "bugfix" ]] \
    || fail "Expected mode=bugfix, got $mode"
}

# ---------------------------------------------------------------------------
# 2. Bootstrap mode still transitions through VALIDATING (reduced, not skipped)
# ---------------------------------------------------------------------------
@test "mode-transitions: bootstrap mode transitions through VALIDATING" {
  bash "$FORGE_STATE_SH" init "MT-002" "Bootstrap new service" --mode bootstrap --forge-dir "$FORGE_DIR"
  bash "$FORGE_STATE_SH" transition preflight_complete --forge-dir "$FORGE_DIR" > /dev/null
  bash "$FORGE_STATE_SH" transition explore_complete --guard "scope=1" --guard "decomposition_threshold=3" --forge-dir "$FORGE_DIR" > /dev/null
  bash "$FORGE_STATE_SH" transition plan_complete --forge-dir "$FORGE_DIR" > /dev/null

  # Now at VALIDATING -- bootstrap does NOT skip this state
  local state
  state="$(jq -r '.story_state' "$FORGE_DIR/state.json")"
  [[ "$state" == "VALIDATING" ]] \
    || fail "Expected VALIDATING (not skipped for bootstrap), got $state"

  # Can proceed through VALIDATING normally
  run bash "$FORGE_STATE_SH" transition verdict_GO --guard "risk=LOW" --guard "auto_proceed_risk=MEDIUM" --forge-dir "$FORGE_DIR"
  assert_success

  state="$(jq -r '.story_state' "$FORGE_DIR/state.json")"
  [[ "$state" == "IMPLEMENTING" ]] \
    || fail "Expected IMPLEMENTING after bootstrap validation, got $state"
}

# ---------------------------------------------------------------------------
# 3. Dry-run mode stops at VALIDATING then COMPLETE (D1)
# ---------------------------------------------------------------------------
@test "mode-transitions: dry-run mode completes at VALIDATING" {
  bash "$FORGE_STATE_SH" init "MT-003" "Dry run test" --mode standard --dry-run --forge-dir "$FORGE_DIR"
  bash "$FORGE_STATE_SH" transition preflight_complete --forge-dir "$FORGE_DIR" > /dev/null
  bash "$FORGE_STATE_SH" transition explore_complete --guard "scope=1" --guard "decomposition_threshold=3" --forge-dir "$FORGE_DIR" > /dev/null
  bash "$FORGE_STATE_SH" transition plan_complete --forge-dir "$FORGE_DIR" > /dev/null
  run bash "$FORGE_STATE_SH" transition validate_complete --forge-dir "$FORGE_DIR"
  assert_success

  local state mode dry_run
  state="$(jq -r '.story_state' "$FORGE_DIR/state.json")"
  mode="$(jq -r '.mode' "$FORGE_DIR/state.json")"
  dry_run="$(jq -r '.dry_run' "$FORGE_DIR/state.json")"

  [[ "$state" == "COMPLETE" ]] \
    || fail "Expected COMPLETE for dry-run, got $state"
  [[ "$mode" == "standard" ]] \
    || fail "Expected mode=standard, got $mode"
  [[ "$dry_run" == "true" ]] \
    || fail "Expected dry_run=true, got $dry_run"
}

# ---------------------------------------------------------------------------
# 4. Standard mode transitions to IMPLEMENTING (not COMPLETE) after validation
# ---------------------------------------------------------------------------
@test "mode-transitions: standard mode goes to IMPLEMENTING after validation" {
  bash "$FORGE_STATE_SH" init "MT-004" "Standard feature" --mode standard --forge-dir "$FORGE_DIR"
  bash "$FORGE_STATE_SH" transition preflight_complete --forge-dir "$FORGE_DIR" > /dev/null
  bash "$FORGE_STATE_SH" transition explore_complete --guard "scope=1" --guard "decomposition_threshold=3" --forge-dir "$FORGE_DIR" > /dev/null
  bash "$FORGE_STATE_SH" transition plan_complete --forge-dir "$FORGE_DIR" > /dev/null
  run bash "$FORGE_STATE_SH" transition verdict_GO --guard "risk=LOW" --guard "auto_proceed_risk=MEDIUM" --forge-dir "$FORGE_DIR"
  assert_success

  local state
  state="$(jq -r '.story_state' "$FORGE_DIR/state.json")"
  [[ "$state" == "IMPLEMENTING" ]] \
    || fail "Expected IMPLEMENTING for standard mode, got $state"
}

# ---------------------------------------------------------------------------
# 5. Mode field persists across transitions
# ---------------------------------------------------------------------------
@test "mode-transitions: mode field persists across multiple transitions" {
  bash "$FORGE_STATE_SH" init "MT-005" "Bugfix persistence" --mode bugfix --forge-dir "$FORGE_DIR"

  # Transition through several states
  bash "$FORGE_STATE_SH" transition preflight_complete --forge-dir "$FORGE_DIR" > /dev/null
  local mode1
  mode1="$(jq -r '.mode' "$FORGE_DIR/state.json")"
  [[ "$mode1" == "bugfix" ]] || fail "Mode lost after preflight_complete: $mode1"

  bash "$FORGE_STATE_SH" transition explore_complete --guard "scope=1" --guard "decomposition_threshold=3" --forge-dir "$FORGE_DIR" > /dev/null
  local mode2
  mode2="$(jq -r '.mode' "$FORGE_DIR/state.json")"
  [[ "$mode2" == "bugfix" ]] || fail "Mode lost after explore_complete: $mode2"

  bash "$FORGE_STATE_SH" transition plan_complete --forge-dir "$FORGE_DIR" > /dev/null
  local mode3
  mode3="$(jq -r '.mode' "$FORGE_DIR/state.json")"
  [[ "$mode3" == "bugfix" ]] || fail "Mode lost after plan_complete: $mode3"
}
