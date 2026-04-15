#!/usr/bin/env bats
load '../../helpers/test-helpers'

AGENT_FILE="${PLUGIN_ROOT}/agents/fg-101-worktree-manager.md"

@test "fg-101-worktree-manager.md exists" {
  assert [ -f "$AGENT_FILE" ]
}

@test "fg-101 frontmatter name matches filename" {
  local name
  name=$(get_frontmatter "$AGENT_FILE" | grep '^name:' | sed 's/^name:[[:space:]]*//')
  assert_equal "$name" "fg-101-worktree-manager"
}

@test "fg-101 has description in frontmatter" {
  local desc
  desc=$(get_frontmatter "$AGENT_FILE" | grep '^description:' | sed 's/^description:[[:space:]]*//')
  assert [ -n "$desc" ]
}

@test "fg-101 has tools in frontmatter" {
  run get_frontmatter "$AGENT_FILE"
  assert_output --partial "tools:"
}

@test "fg-101 contains expected behavioral keywords" {
  run grep -ci 'worktree\|branch\|\.forge/worktree' "$AGENT_FILE"
  assert_success
  assert [ "$output" -ge 1 ]
}
