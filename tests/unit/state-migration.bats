#!/usr/bin/env bats
load '../helpers/test-helpers'

setup() {
  TEST_TEMP="$(mktemp -d "${TMPDIR:-${TMP:-${TEMP:-/tmp}}}/bats-forge.XXXXXX")"
  PYTHON="${FORGE_PYTHON:-python3}"
  SCRIPT="${PLUGIN_ROOT}/shared/python/state_migrate.py"
}

teardown() {
  [[ -n "${TEST_TEMP:-}" && -d "${TEST_TEMP}" ]] && rm -rf "${TEST_TEMP}"
}

@test "state migrations disabled under no-backcompat policy" {
  run "$PYTHON" -c "
import sys
sys.path.insert(0, '${PLUGIN_ROOT}/shared/python')
from state_migrate import migrate_disallowed
migrate_disallowed()
"
  [ "$status" -ne 0 ]
}

@test "state_migrate.py CLI exits non-zero" {
  run bash -c "echo '{\"version\": \"1.5.0\"}' | '$PYTHON' '$SCRIPT'"
  [ "$status" -ne 0 ]
}
