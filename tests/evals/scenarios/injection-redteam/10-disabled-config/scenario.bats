#!/usr/bin/env bats
# Injection red-team scenario 10: PREFLIGHT must halt when forge-config tries to disable
# the envelope mechanism. Depends on shared/preflight-injection-check.sh.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../../../../.." && pwd)"
  CHECK="$ROOT/shared/preflight-injection-check.sh"
}

@test "scenario 10: disabled-config — PREFLIGHT emits SEC-INJECTION-DISABLED and halts" {
  [ -f "$CHECK" ]
  TMP="$(mktemp -d)"
  run bash "$CHECK" "$BATS_TEST_DIRNAME/fixture-forge-config.md" "$TMP/.forge"
  rm -rf "$TMP"
  [ "$status" -ne 0 ]
  [[ "$output" == *"SEC-INJECTION-DISABLED"* ]] || [[ "$stderr" == *"SEC-INJECTION-DISABLED"* ]]
}
