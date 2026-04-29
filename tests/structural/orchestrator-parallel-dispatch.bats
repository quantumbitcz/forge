#!/usr/bin/env bats
# AC-POLISH-003, AC-POLISH-004: parallel single-block + per-3-task checkpoint.
load '../helpers/test-helpers'

F100="$PLUGIN_ROOT/agents/fg-100-orchestrator.md"

@test "fg-100 references dispatching-parallel-agents pattern" {
  run grep -F 'dispatching-parallel-agents' "$F100"
  assert_success
}

@test "fg-100 references executing-plans pattern" {
  run grep -F 'executing-plans' "$F100"
  assert_success
}

@test "fg-100 instructs single tool-use parallel block" {
  run grep -E 'single tool-use block|single message.*multiple Task' "$F100"
  assert_success
}

@test "fg-100 emits checkpoint after every 3 tasks" {
  run grep -E 'every 3 tasks|after.*3.*tasks|per.*3.*task' "$F100"
  assert_success
}

@test "fg-100 documents parallel-group dispatch" {
  run grep -F 'parallel groups' "$F100"
  assert_success
}
