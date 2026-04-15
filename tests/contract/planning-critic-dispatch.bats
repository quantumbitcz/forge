#!/usr/bin/env bats
load '../helpers/test-helpers'

@test "orchestrator references fg-205-planning-critic" {
  run grep -c 'fg-205\|planning-critic' "${PLUGIN_ROOT}/agents/fg-100-orchestrator.md"
  assert_success
  assert [ "$output" -ge 1 ]
}

@test "critic dispatched between PLANNING and VALIDATING" {
  run grep -ci 'critic.*before.*validat\|after.*planner.*critic\|plan.*critic.*review' "${PLUGIN_ROOT}/agents/fg-100-orchestrator.md"
  assert_success
  assert [ "$output" -ge 1 ]
}

@test "critic verdicts are PROCEED/REVISE/RESHAPE" {
  run grep -c 'PROCEED\|REVISE\|RESHAPE' "${PLUGIN_ROOT}/agents/fg-205-planning-critic.md"
  assert_success
  assert [ "$output" -ge 3 ]
}
