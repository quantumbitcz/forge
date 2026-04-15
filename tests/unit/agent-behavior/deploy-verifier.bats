#!/usr/bin/env bats
load '../../helpers/test-helpers'

AGENT_FILE="${PLUGIN_ROOT}/agents/fg-620-deploy-verifier.md"

@test "fg-620-deploy-verifier.md exists" {
  assert [ -f "$AGENT_FILE" ]
}

@test "fg-620 frontmatter name matches filename" {
  local name
  name=$(get_frontmatter "$AGENT_FILE" | grep '^name:' | sed 's/^name:[[:space:]]*//')
  assert_equal "$name" "fg-620-deploy-verifier"
}

@test "fg-620 has description in frontmatter" {
  local desc
  desc=$(get_frontmatter "$AGENT_FILE" | grep '^description:' | sed 's/^description:[[:space:]]*//')
  assert [ -n "$desc" ]
}

@test "fg-620 has tools in frontmatter" {
  run get_frontmatter "$AGENT_FILE"
  assert_output --partial "tools:"
}

@test "fg-620 contains expected behavioral keywords" {
  run grep -ci 'canary\|blue-green\|rolling\|health.*check\|deploy' "$AGENT_FILE"
  assert_success
  assert [ "$output" -ge 1 ]
}
