#!/usr/bin/env bats
# AC-DEBUG-002: parallel dispatch in single tool-use block.
load '../helpers/test-helpers'

F020="$PLUGIN_ROOT/agents/fg-020-bug-investigator.md"

@test "fg-020 references dispatching-parallel-agents pattern" {
  run grep -F 'dispatching-parallel-agents' "$F020"
  assert_success
}

@test "fg-020 instructs single tool-use block dispatch" {
  run grep -E 'single tool-use block' "$F020"
  assert_success
}

@test "fg-020 caps parallel sub-investigators at 3" {
  run grep -E 'up to 3|maximum 3|max 3' "$F020"
  assert_success
}

@test "fg-020 honours bug.hypothesis_branching.enabled: false fallback" {
  run grep -F 'bug.hypothesis_branching.enabled' "$F020"
  assert_success
  run grep -F 'single-hypothesis serial' "$F020"
  assert_success
}
