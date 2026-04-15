#!/usr/bin/env bats
load '../helpers/test-helpers'

setup() {
  TEST_TEMP="$(mktemp -d "${TMPDIR:-${TMP:-${TEMP:-/tmp}}}/bats-forge.XXXXXX")"
  MOCK_BIN="${TEST_TEMP}/mock-bin"
  mkdir -p "${MOCK_BIN}"
  export PATH="${MOCK_BIN}:${PATH}"
  PYTHON="${FORGE_PYTHON:-python3}"
  SCRIPT="${PLUGIN_ROOT}/shared/python/state_transitions.py"
  INIT_SCRIPT="${PLUGIN_ROOT}/shared/python/state_init.py"
}

teardown() {
  [[ -n "${TEST_TEMP:-}" && -d "${TEST_TEMP}" ]] && rm -rf "${TEST_TEMP}"
}

@test "transition PREFLIGHT + preflight_complete -> EXPLORING" {
  local state
  state=$("$PYTHON" "$INIT_SCRIPT" "FG-001" "Test" "standard" "false")
  local result
  result=$(echo "$state" | "$PYTHON" "$SCRIPT" "preflight_complete" '{}' "${TEST_TEMP}/.forge")
  assert [ $? -eq 0 ]
  echo "$result" | "$PYTHON" -c "
import json, sys
r = json.load(sys.stdin)
assert r['new_state'] == 'EXPLORING', f'got {r[\"new_state\"]}'
assert r['row_id'] == '1'
"
}

@test "transition returns error JSON for unknown event" {
  local state
  state=$("$PYTHON" "$INIT_SCRIPT" "FG-001" "Test" "standard" "false")
  run bash -c "echo '$state' | '$PYTHON' '$SCRIPT' 'nonexistent_event' '{}' '${TEST_TEMP}/.forge'"
  assert_failure
}

@test "transition VALIDATING + verdict_GO with low risk -> IMPLEMENTING" {
  local state
  state=$("$PYTHON" "$INIT_SCRIPT" "FG-001" "Test" "standard" "false")
  state=$(echo "$state" | "$PYTHON" -c "
import json, sys
s = json.load(sys.stdin)
s['story_state'] = 'VALIDATING'
print(json.dumps(s))
")
  local guards='{"risk": "LOW", "auto_proceed_risk": "MEDIUM"}'
  local result
  result=$(echo "$state" | "$PYTHON" "$SCRIPT" "verdict_GO" "$guards" "${TEST_TEMP}/.forge")
  assert [ $? -eq 0 ]
  echo "$result" | "$PYTHON" -c "
import json, sys
r = json.load(sys.stdin)
assert r['new_state'] == 'IMPLEMENTING', f'got {r[\"new_state\"]}'
assert r['row_id'] == '10'
"
}

@test "transition output contains updated_state with correct story_state" {
  local state
  state=$("$PYTHON" "$INIT_SCRIPT" "FG-001" "Test" "standard" "false")
  local result
  result=$(echo "$state" | "$PYTHON" "$SCRIPT" "preflight_complete" '{}' "${TEST_TEMP}/.forge")
  echo "$result" | "$PYTHON" -c "
import json, sys
r = json.load(sys.stdin)
assert 'updated_state' in r
assert r['updated_state']['story_state'] == 'EXPLORING'
"
}
