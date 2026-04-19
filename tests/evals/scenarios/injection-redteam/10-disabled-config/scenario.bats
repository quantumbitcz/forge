#!/usr/bin/env bats
# Phase 03 scenario 10: PREFLIGHT must halt when forge-config tries to disable
# the envelope mechanism. Depends on shared/preflight-injection-check.sh which
# is added in Task 20 — skipped until then.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../../../../.." && pwd)"
  CHECK="$ROOT/shared/preflight-injection-check.sh"
}

@test "scenario 10: disabled-config — PREFLIGHT emits SEC-INJECTION-DISABLED and halts" {
  if [ ! -f "$CHECK" ]; then
    skip "requires shared/preflight-injection-check.sh from Task 20"
  fi
  run bash "$CHECK" "$BATS_TEST_DIRNAME/fixture-forge-config.md"
  [ "$status" -ne 0 ]
  [[ "$output" == *"SEC-INJECTION-DISABLED"* ]]
}
