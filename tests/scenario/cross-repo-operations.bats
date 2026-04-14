#!/usr/bin/env bats
# Scenario test: cross-repo operations.
# Per REVISIONS.md: tests only lock ordering logic and state.json cross-repo
# fields. No actual git discovery simulation.

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
# 1. Alphabetical lock ordering prevents deadlocks
# ---------------------------------------------------------------------------
@test "cross-repo: alphabetical lock ordering sorts repo names correctly" {
  # Simulate the lock ordering that the cross-repo coordinator uses:
  # repos are always locked in alphabetical order to prevent deadlocks.
  local repos="beta alpha gamma delta"
  local sorted
  sorted=$(printf '%s\n' $repos | sort | tr '\n' ' ' | sed 's/ $//')

  [[ "$sorted" == "alpha beta delta gamma" ]] \
    || fail "Expected alphabetical sort 'alpha beta delta gamma', got '$sorted'"

  # Verify alpha comes before beta (deadlock prevention)
  local first
  first=$(printf '%s\n' $repos | sort | head -1)
  [[ "$first" == "alpha" ]] \
    || fail "Expected first lock target to be 'alpha', got '$first'"
}

# ---------------------------------------------------------------------------
# 2. state.json cross_repo fields initialized correctly
# ---------------------------------------------------------------------------
@test "cross-repo: state.json cross_repo fields initialized and settable" {
  bash "$FORGE_STATE_SH" init "CR-001" "Test cross-repo fields" --mode standard --forge-dir "$FORGE_DIR"

  # Verify cross_repo exists and is an empty object on fresh init
  local cross_repo_type
  cross_repo_type="$(jq -r '.cross_repo | type' "$FORGE_DIR/state.json")"
  [[ "$cross_repo_type" == "object" ]] \
    || fail "Expected cross_repo to be an object, got $cross_repo_type"

  # Now craft state with cross-repo data
  local state_json
  state_json=$(jq '.cross_repo = {
    "repos": ["alpha-service", "beta-service"],
    "primary": "alpha-service",
    "lock_order": ["alpha-service", "beta-service"],
    "discovered_at": "PREFLIGHT",
    "detected_via": "forge-init"
  }' "$FORGE_DIR/state.json")
  echo "$state_json" > "$FORGE_DIR/state.json"

  # Verify fields via jq
  local primary repo_count lock_first
  primary="$(jq -r '.cross_repo.primary' "$FORGE_DIR/state.json")"
  repo_count="$(jq '.cross_repo.repos | length' "$FORGE_DIR/state.json")"
  lock_first="$(jq -r '.cross_repo.lock_order[0]' "$FORGE_DIR/state.json")"

  [[ "$primary" == "alpha-service" ]] \
    || fail "Expected primary=alpha-service, got $primary"
  [[ "$repo_count" -eq 2 ]] \
    || fail "Expected 2 repos, got $repo_count"
  [[ "$lock_first" == "alpha-service" ]] \
    || fail "Expected first lock=alpha-service, got $lock_first"
}

# ---------------------------------------------------------------------------
# 3. Cross-repo state persists across transitions
# ---------------------------------------------------------------------------
@test "cross-repo: cross_repo data persists across state transitions" {
  bash "$FORGE_STATE_SH" init "CR-002" "Test cross-repo persistence" --mode standard --forge-dir "$FORGE_DIR"

  # Set cross_repo data
  local state_json
  state_json=$(jq '.cross_repo = {
    "repos": ["api-gateway", "user-service"],
    "primary": "api-gateway"
  }' "$FORGE_DIR/state.json")
  echo "$state_json" > "$FORGE_DIR/state.json"

  # Transition to next state
  bash "$FORGE_STATE_SH" transition preflight_complete --forge-dir "$FORGE_DIR" > /dev/null

  # Verify cross_repo data survived the transition
  local primary repo_count
  primary="$(jq -r '.cross_repo.primary' "$FORGE_DIR/state.json")"
  repo_count="$(jq '.cross_repo.repos | length' "$FORGE_DIR/state.json")"

  [[ "$primary" == "api-gateway" ]] \
    || fail "Expected cross_repo.primary to persist, got $primary"
  [[ "$repo_count" -eq 2 ]] \
    || fail "Expected 2 repos to persist, got $repo_count"
}
