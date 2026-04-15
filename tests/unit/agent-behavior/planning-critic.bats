#!/usr/bin/env bats
load '../../helpers/test-helpers'

AGENT_FILE="${PLUGIN_ROOT}/agents/fg-205-planning-critic.md"

@test "fg-205-planning-critic.md exists" {
  assert [ -f "$AGENT_FILE" ]
}

@test "fg-205 frontmatter name matches filename" {
  local name
  name=$(get_frontmatter "$AGENT_FILE" | grep '^name:' | sed 's/^name:[[:space:]]*//')
  assert_equal "$name" "fg-205-planning-critic"
}

@test "fg-205 has description in frontmatter" {
  local desc
  desc=$(get_frontmatter "$AGENT_FILE" | grep '^description:' | sed 's/^description:[[:space:]]*//')
  assert [ -n "$desc" ]
}

@test "fg-205 tools are read-only" {
  run get_frontmatter "$AGENT_FILE"
  assert_output --partial "Read"
  assert_output --partial "Grep"
  assert_output --partial "Glob"
  refute_output --partial "Edit"
  refute_output --partial "Write"
  refute_output --partial "Bash"
}

@test "fg-205 contains verdict format (PROCEED/REVISE/RESHAPE)" {
  run grep -c 'PROCEED\|REVISE\|RESHAPE' "$AGENT_FILE"
  assert_success
  assert [ "$output" -ge 3 ]
}

@test "fg-205 documents feasibility, risk, and scope concerns" {
  run grep -ci 'feasibility\|risk.*blind\|scope.*creep' "$AGENT_FILE"
  assert_success
  assert [ "$output" -ge 2 ]
}
