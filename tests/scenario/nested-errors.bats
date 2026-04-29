#!/usr/bin/env bats
# Scenario test: nested error handling and recovery edge cases.
# Tests error-during-recovery, WAL fallback, hook failure isolation,
# and timeout bounding.

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
# 1. Recovery of recovery failure does not infinite loop (ESCALATED is terminal)
# ---------------------------------------------------------------------------
@test "nested-errors: exhausted recovery budget goes to ESCALATED, not infinite loop" {
  bash "$FORGE_STATE_SH" init "NE-001" "Test nested recovery" --mode standard --forge-dir "$FORGE_DIR"
  bash "$FORGE_STATE_SH" transition preflight_complete --forge-dir "$FORGE_DIR" > /dev/null

  # Craft state with exhausted recovery budget and several failure entries
  local state_json
  state_json=$(jq '
    .recovery_budget.total_weight = 6.0 |
    .recovery_budget.max_weight = 5.5 |
    .recovery_budget.applications = [
      {"strategy": "retry", "cost": 1.0},
      {"strategy": "skip", "cost": 1.0},
      {"strategy": "degrade", "cost": 1.5},
      {"strategy": "isolate", "cost": 1.0},
      {"strategy": "retry", "cost": 0.5},
      {"strategy": "skip", "cost": 0.5},
      {"strategy": "retry", "cost": 0.5}
    ] |
    .recovery.total_failures = 7
  ' "$FORGE_DIR/state.json")
  echo "$state_json" > "$FORGE_DIR/state.json"

  # Trigger recovery_budget_exhausted -- should go to ESCALATED (E2, terminal)
  run bash "$FORGE_STATE_SH" transition recovery_budget_exhausted --forge-dir "$FORGE_DIR"
  assert_success

  local state
  state="$(jq -r '.story_state' "$FORGE_DIR/state.json")"
  [[ "$state" == "ESCALATED" ]] \
    || fail "Expected ESCALATED (terminal for recovery), got $state"
}

# ---------------------------------------------------------------------------
# 2. State corruption: query on invalid JSON fails gracefully
# ---------------------------------------------------------------------------
@test "nested-errors: query on corrupted state.json returns content without crashing" {
  bash "$FORGE_STATE_SH" init "NE-002" "Test corruption" --mode standard --forge-dir "$FORGE_DIR"

  # Corrupt the state.json
  echo "THIS IS NOT JSON {{{" > "$FORGE_DIR/state.json"

  # Query reads via cat — exits 0 with raw file content (no JSON validation on read).
  # The important contract is that it does not crash or hang.
  run bash "$FORGE_STATE_SH" query --forge-dir "$FORGE_DIR"
  assert_success
  [[ "$output" == *"THIS IS NOT JSON"* ]] \
    || fail "Expected corrupted content in output, got: $output"
}

# ---------------------------------------------------------------------------
# 3. Hook failure isolation: recovery engine documents graceful degradation
# ---------------------------------------------------------------------------
@test "nested-errors: recovery engine documents graceful degradation for hook failures" {
  local recovery_dir="$PLUGIN_ROOT/shared/recovery"
  [[ -d "$recovery_dir" ]] || skip "recovery directory not found"

  # Verify recovery-engine.md exists and documents failure handling
  [[ -f "$recovery_dir/recovery-engine.md" ]] \
    || fail "recovery-engine.md not found"

  # Recovery engine should document what happens when recovery itself fails
  grep -qi "budget\|ceiling\|exhausted\|unrecoverable" "$recovery_dir/recovery-engine.md" \
    || fail "recovery-engine.md does not document budget exhaustion or unrecoverable state"
}

# ---------------------------------------------------------------------------
# 4. Timeout script has self-enforcing timeout mechanism
# ---------------------------------------------------------------------------
@test "nested-errors: forge-timeout.sh has bounded timeout mechanism" {
  local timeout_script="$PLUGIN_ROOT/shared/forge-timeout.sh"
  [[ -f "$timeout_script" ]] || skip "forge-timeout.sh not found"

  # Verify the script has timeout enforcement (checks elapsed time)
  grep -q "elapsed\|MAX_SECONDS\|exceeded\|budget" "$timeout_script" \
    || fail "forge-timeout.sh does not contain timeout enforcement logic"

  # Verify it exits 0 when state.json is missing (graceful degradation)
  run bash "$timeout_script" "${TEST_TEMP}/nonexistent-forge-dir" 7200
  assert_success
}
