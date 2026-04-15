#!/usr/bin/env bats
load '../helpers/test-helpers'

setup() {
  TEST_TEMP="$(mktemp -d "${TMPDIR:-${TMP:-${TEMP:-/tmp}}}/bats-forge.XXXXXX")"
  MOCK_BIN="${TEST_TEMP}/mock-bin"
  mkdir -p "${MOCK_BIN}"
  export PATH="${MOCK_BIN}:${PATH}"
  PYTHON="${FORGE_PYTHON:-python3}"
  SCRIPT="${PLUGIN_ROOT}/shared/python/state_migrate.py"
  INIT_SCRIPT="${PLUGIN_ROOT}/shared/python/state_init.py"
}

teardown() {
  [[ -n "${TEST_TEMP:-}" && -d "${TEST_TEMP}" ]] && rm -rf "${TEST_TEMP}"
}

@test "v1.5.0 state migrates to v1.6.0 with new fields" {
  # Create a minimal v1.5.0 state (NOT via state_init.py which creates v1.6.0)
  local state='{"version":"1.5.0","_seq":0,"story_state":"PREFLIGHT","recovery":{},"convergence":{}}'
  local migrated
  migrated=$(echo "$state" | "$PYTHON" "$SCRIPT")
  assert [ $? -eq 0 ]
  echo "$migrated" | "$PYTHON" -c "
import json, sys
s = json.load(sys.stdin)
assert s['version'] == '1.6.0', f'version: {s[\"version\"]}'
assert 'circuit_breakers' in s.get('recovery', {}), 'missing circuit_breakers'
assert 'critic_revisions' in s, 'missing critic_revisions'
assert s['critic_revisions'] == 0
assert 'schema_version_history' in s
assert len(s['schema_version_history']) == 1
assert s['schema_version_history'][0]['from'] == '1.5.0'
"
}

@test "already v1.6.0 state passes through unchanged" {
  local state
  state=$("$PYTHON" "$INIT_SCRIPT" "FG-001" "Test" "standard" "false")
  # Already v1.6.0, migration is no-op
  local migrated
  migrated=$(echo "$state" | "$PYTHON" "$SCRIPT")
  assert [ $? -eq 0 ]
  echo "$migrated" | "$PYTHON" -c "
import json, sys
s = json.load(sys.stdin)
assert s['version'] == '1.6.0'
# schema_version_history should be empty (no migration happened)
assert len(s.get('schema_version_history', [])) == 0
"
}

@test "unknown version exits with code 2" {
  run bash -c "echo '{\"version\": \"0.9.0\"}' | '$PYTHON' '$SCRIPT'"
  assert_failure
  [ "$status" -eq 2 ]
}
