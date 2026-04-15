#!/usr/bin/env bats
load '../helpers/test-helpers'

@test "convergence-engine.md documents context-aware PREEMPT decay" {
  run grep -c 'applicable_context' "${PLUGIN_ROOT}/shared/convergence-engine.md"
  assert_success
  assert [ "$output" -ge 2 ]
}

@test "context matching uses components section from forge-config" {
  run grep -ci 'components.*forge' "${PLUGIN_ROOT}/shared/convergence-engine.md"
  assert_success
  assert [ "$output" -ge 1 ]
}

@test "legacy items without applicable_context decay normally" {
  run grep -ci 'without.*applicable_context\|legacy behavior' "${PLUGIN_ROOT}/shared/convergence-engine.md"
  assert_success
  assert [ "$output" -ge 1 ]
}
