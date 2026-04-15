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
  MIGRATE_SCRIPT="${PLUGIN_ROOT}/shared/python/state_migrate.py"
}

teardown() {
  [[ -n "${TEST_TEMP:-}" && -d "${TEST_TEMP}" ]] && rm -rf "${TEST_TEMP}"
}

@test "score_history capped at 50 after transition" {
  local state
  state=$("$PYTHON" "$INIT_SCRIPT" "FG-001" "Test" "standard" "false")
  state=$(echo "$state" | "$PYTHON" "$MIGRATE_SCRIPT")
  state=$(echo "$state" | "$PYTHON" -c "
import json, sys
s = json.load(sys.stdin)
s['score_history'] = list(range(100))
print(json.dumps(s))
")
  local result
  result=$(echo "$state" | "$PYTHON" "$SCRIPT" "preflight_complete" '{}' ".forge")
  echo "$result" | "$PYTHON" -c "
import json, sys
r = json.load(sys.stdin)
s = r['updated_state']
assert len(s['score_history']) <= 50, f'got {len(s[\"score_history\"])}'
"
}

@test "small score_history unchanged after transition" {
  local state
  state=$("$PYTHON" "$INIT_SCRIPT" "FG-001" "Test" "standard" "false")
  state=$(echo "$state" | "$PYTHON" "$MIGRATE_SCRIPT")
  state=$(echo "$state" | "$PYTHON" -c "
import json, sys
s = json.load(sys.stdin)
s['score_history'] = [80, 85, 90]
print(json.dumps(s))
")
  local result
  result=$(echo "$state" | "$PYTHON" "$SCRIPT" "preflight_complete" '{}' ".forge")
  echo "$result" | "$PYTHON" -c "
import json, sys
r = json.load(sys.stdin)
s = r['updated_state']
assert len(s['score_history']) == 3
"
}
