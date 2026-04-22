#!/usr/bin/env bats
load '../helpers/test-helpers'

@test "flapping detection: 3 OPEN-HALF_OPEN-OPEN cycles locks circuit" {
  run grep -c 'flapping_count >= 3' "${PLUGIN_ROOT}/shared/recovery/recovery-engine.md"
  assert_success
  assert [ "$output" -ge 1 ]
}

@test "flapping detection: locked circuit skips HALF_OPEN probe" {
  run grep -c 'circuit_breaker_locked' "${PLUGIN_ROOT}/shared/recovery/recovery-engine.md"
  assert_success
  assert [ "$output" -ge 1 ]
}

@test "flapping detection: successful probe resets flapping_count" {
  run grep -c 'flapping_count = 0' "${PLUGIN_ROOT}/shared/recovery/recovery-engine.md"
  assert_success
  assert [ "$output" -ge 1 ]
}

@test "circuit breaker schema includes flapping_count and locked fields" {
  run grep -c 'flapping_count' "${PLUGIN_ROOT}/shared/state-schema-fields.md"
  assert_success
  assert [ "$output" -ge 1 ]
  run grep -c '"locked"' "${PLUGIN_ROOT}/shared/state-schema-fields.md"
  assert_success
}
