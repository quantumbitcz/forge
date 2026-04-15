#!/usr/bin/env bats
load '../helpers/test-helpers'

@test "agent-communication.md does not cap dedup hints at 20" {
  local count
  count=$(grep -c 'top 20 findings' "${PLUGIN_ROOT}/shared/agent-communication.md" || true)
  assert [ "$count" -eq 0 ]
}

@test "agent-communication.md includes all findings with domain affinity" {
  run grep -c 'Include.*all.*previous batch findings' "${PLUGIN_ROOT}/shared/agent-communication.md"
  assert_success
  assert [ "$output" -ge 1 ]
}

@test "agent-communication.md specifies compressed format for >50 findings" {
  run grep -c 'exceed 50.*compress' "${PLUGIN_ROOT}/shared/agent-communication.md"
  assert_success
  assert [ "$output" -ge 1 ]
}
