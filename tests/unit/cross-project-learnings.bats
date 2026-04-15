#!/usr/bin/env bats
load '../helpers/test-helpers'

@test "cross-project-learnings.md exists" {
  assert [ -f "${PLUGIN_ROOT}/shared/cross-project-learnings.md" ]
}

@test "cross-project learnings stored in ~/.claude/forge-learnings/" {
  run grep -c 'forge-learnings' "${PLUGIN_ROOT}/shared/cross-project-learnings.md"
  assert_success
  assert [ "$output" -ge 2 ]
}

@test "cross-project items start at MEDIUM confidence" {
  run grep -c 'MEDIUM' "${PLUGIN_ROOT}/shared/cross-project-learnings.md"
  assert_success
  assert [ "$output" -ge 1 ]
}

@test "cross-project learnings has opt-out config" {
  run grep -c 'cross_project_learnings.enabled' "${PLUGIN_ROOT}/shared/cross-project-learnings.md"
  assert_success
  assert [ "$output" -ge 1 ]
}
