#!/usr/bin/env bats
load '../helpers/test-helpers'

setup() {
  TEST_TEMP="$(mktemp -d "${TMPDIR:-${TMP:-${TEMP:-/tmp}}}/bats-forge.XXXXXX")"
  MOCK_BIN="${TEST_TEMP}/mock-bin"
  mkdir -p "${MOCK_BIN}"
  export PATH="${MOCK_BIN}:${PATH}"
  PYTHON="${FORGE_PYTHON:-python3}"
  SCRIPT="${PLUGIN_ROOT}/shared/python/state_init.py"
}

teardown() {
  [[ -n "${TEST_TEMP:-}" && -d "${TEST_TEMP}" ]] && rm -rf "${TEST_TEMP}"
}

@test "state_init.py produces valid JSON with required fields" {
  run "$PYTHON" "$SCRIPT" "FG-001" "Test requirement" "standard" "false"
  assert_success
  echo "$output" | "$PYTHON" -c "
import json, sys
state = json.load(sys.stdin)
assert state['version'] == '1.6.0', f'version: {state[\"version\"]}'
assert state['story_id'] == 'FG-001'
assert state['requirement'] == 'Test requirement'
assert state['mode'] == 'standard'
assert state['dry_run'] == False
assert state['story_state'] == 'PREFLIGHT'
assert '_seq' in state
assert 'convergence' in state
assert 'recovery' in state
assert 'integrations' in state
"
}

@test "state_init.py dry_run=true sets dry_run field" {
  run "$PYTHON" "$SCRIPT" "FG-002" "Dry run req" "standard" "true"
  assert_success
  echo "$output" | "$PYTHON" -c "
import json, sys
state = json.load(sys.stdin)
assert state['dry_run'] == True
"
}

@test "state_init.py fails with missing args" {
  run "$PYTHON" "$SCRIPT"
  assert_failure
}

@test "state_init.py accepts all valid modes" {
  for mode in standard bugfix migration bootstrap testing refactor performance; do
    run "$PYTHON" "$SCRIPT" "FG-003" "Req" "$mode" "false"
    assert_success
  done
}
