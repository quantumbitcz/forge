#!/usr/bin/env bats
load '../../helpers/test-helpers'

AGENT_FILE="${PLUGIN_ROOT}/agents/fg-103-cross-repo-coordinator.md"

@test "fg-103-cross-repo-coordinator.md exists" {
  assert [ -f "$AGENT_FILE" ]
}

@test "fg-103 frontmatter name matches filename" {
  local name
  name=$(get_frontmatter "$AGENT_FILE" | grep '^name:' | sed 's/^name:[[:space:]]*//')
  assert_equal "$name" "fg-103-cross-repo-coordinator"
}

@test "fg-103 has description in frontmatter" {
  local desc
  desc=$(get_frontmatter "$AGENT_FILE" | grep '^description:' | sed 's/^description:[[:space:]]*//')
  assert [ -n "$desc" ]
}

@test "fg-103 has tools in frontmatter" {
  run get_frontmatter "$AGENT_FILE"
  assert_output --partial "tools:"
}

@test "fg-103 contains expected behavioral keywords" {
  run grep -ci 'cross-repo\|lock.*order\|alphabetical\|timeout' "$AGENT_FILE"
  assert_success
  assert [ "$output" -ge 1 ]
}
