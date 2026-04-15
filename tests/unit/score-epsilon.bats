#!/usr/bin/env bats
load '../helpers/test-helpers'

setup() {
  TEST_TEMP="$(mktemp -d "${TMPDIR:-${TMP:-${TEMP:-/tmp}}}/bats-forge.XXXXXX")"
  MOCK_BIN="${TEST_TEMP}/mock-bin"
  mkdir -p "${MOCK_BIN}"
  export PATH="${MOCK_BIN}:${PATH}"
  PYTHON="${FORGE_PYTHON:-python3}"
}

teardown() {
  [[ -n "${TEST_TEMP:-}" && -d "${TEST_TEMP}" ]] && rm -rf "${TEST_TEMP}"
}

@test "score_gt treats 0.0001 as not greater than 0" {
  run "$PYTHON" -c "
import sys
sys.path.insert(0, '${PLUGIN_ROOT}/shared/python')
from state_transitions import score_gt
assert score_gt(0.0001, 0) == False, 'Should be within epsilon'
"
  assert_success
}

@test "score_gt treats 0.01 as greater than 0" {
  run "$PYTHON" -c "
import sys
sys.path.insert(0, '${PLUGIN_ROOT}/shared/python')
from state_transitions import score_gt
assert score_gt(0.01, 0) == True, 'Should be above epsilon'
"
  assert_success
}

@test "score_eq treats 5.0 and 5.0001 as equal" {
  run "$PYTHON" -c "
import sys
sys.path.insert(0, '${PLUGIN_ROOT}/shared/python')
from state_transitions import score_eq
assert score_eq(5.0, 5.0001) == True
"
  assert_success
}

@test "score_le treats -5.01 as less than 0" {
  run "$PYTHON" -c "
import sys
sys.path.insert(0, '${PLUGIN_ROOT}/shared/python')
from state_transitions import score_le
assert score_le(-5.01, 0) == True
"
  assert_success
}
