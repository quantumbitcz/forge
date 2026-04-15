#!/usr/bin/env bats
load '../helpers/test-helpers'

setup() {
  TEST_TEMP="$(mktemp -d "${TMPDIR:-${TMP:-${TEMP:-/tmp}}}/bats-forge.XXXXXX")"
  MOCK_BIN="${TEST_TEMP}/mock-bin"
  mkdir -p "${MOCK_BIN}"
  export PATH="${MOCK_BIN}:${PATH}"
  PYTHON="${FORGE_PYTHON:-python3}"
  SCRIPT="${PLUGIN_ROOT}/shared/python/guard_parser.py"
}

teardown() {
  [[ -n "${TEST_TEMP:-}" && -d "${TEST_TEMP}" ]] && rm -rf "${TEST_TEMP}"
}

@test "guard_parser coerces booleans" {
  run "$PYTHON" "$SCRIPT" "dry_run=true" "valid=false"
  assert_success
  echo "$output" | "$PYTHON" -c "
import json, sys
d = json.load(sys.stdin)
assert d['dry_run'] is True
assert d['valid'] is False
"
}

@test "guard_parser coerces integers" {
  run "$PYTHON" "$SCRIPT" "count=5" "max=10"
  assert_success
  echo "$output" | "$PYTHON" -c "
import json, sys
d = json.load(sys.stdin)
assert d['count'] == 5
assert d['max'] == 10
"
}

@test "guard_parser coerces floats" {
  run "$PYTHON" "$SCRIPT" "weight=3.14"
  assert_success
  echo "$output" | "$PYTHON" -c "
import json, sys
d = json.load(sys.stdin)
assert abs(d['weight'] - 3.14) < 0.001
"
}

@test "guard_parser keeps strings" {
  run "$PYTHON" "$SCRIPT" "name=hello" "classification=implementation"
  assert_success
  echo "$output" | "$PYTHON" -c "
import json, sys
d = json.load(sys.stdin)
assert d['name'] == 'hello'
assert d['classification'] == 'implementation'
"
}

@test "guard_parser with no args outputs empty object" {
  run "$PYTHON" "$SCRIPT"
  assert_success
  assert_output '{}'
}
