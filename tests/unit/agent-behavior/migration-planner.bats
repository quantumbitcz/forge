#!/usr/bin/env bats
load '../../helpers/test-helpers'

AGENT_FILE="${PLUGIN_ROOT}/agents/fg-160-migration-planner.md"

@test "fg-160-migration-planner.md exists" {
  assert [ -f "$AGENT_FILE" ]
}

@test "fg-160 frontmatter name matches filename" {
  local name
  name=$(get_frontmatter "$AGENT_FILE" | grep '^name:' | sed 's/^name:[[:space:]]*//')
  assert_equal "$name" "fg-160-migration-planner"
}

@test "fg-160 has description in frontmatter" {
  local desc
  desc=$(get_frontmatter "$AGENT_FILE" | grep '^description:' | sed 's/^description:[[:space:]]*//')
  assert [ -n "$desc" ]
}

@test "fg-160 has tools in frontmatter" {
  run get_frontmatter "$AGENT_FILE"
  assert_output --partial "tools:"
}

@test "fg-160 contains expected behavioral keywords" {
  run grep -ci 'migration\|rollback\|breaking.*change' "$AGENT_FILE"
  assert_success
  assert [ "$output" -ge 1 ]
}
