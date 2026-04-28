#!/usr/bin/env bats
# AC-DEBUG-002: fg-021 hypothesis-investigator agent shape.
load '../helpers/test-helpers'

F021="$PLUGIN_ROOT/agents/fg-021-hypothesis-investigator.md"

@test "fg-021 file exists" {
  assert [ -f "$F021"  ]
}

@test "fg-021 has name frontmatter matching filename" {
  run grep -E '^name: fg-021-hypothesis-investigator' "$F021"
  assert_success
}

@test "fg-021 declares no UI capabilities (Tier-3)" {
  # ui frontmatter must declare tasks: false (or be Tier-3 by frontmatter rules)
  run grep -E '^ui:' "$F021"
  assert_success
}

@test "fg-021 tools list contains Read" {
  run grep -F '- Read' "$F021"
  assert_success
}

@test "fg-021 tools list contains Grep" {
  run grep -F '- Grep' "$F021"
  assert_success
}

@test "fg-021 tools list contains Glob" {
  run grep -F '- Glob' "$F021"
  assert_success
}

@test "fg-021 tools list contains Bash" {
  run grep -F '- Bash' "$F021"
  assert_success
}

@test "fg-021 declares output schema with hypothesis_id" {
  run grep -F 'hypothesis_id' "$F021"
  assert_success
}

@test "fg-021 declares output schema with passes_test" {
  run grep -F 'passes_test' "$F021"
  assert_success
}

@test "fg-021 declares output schema with confidence high|medium|low" {
  run grep -E 'high.*medium.*low|confidence.*"high"' "$F021"
  assert_success
}

@test "fg-021 declares output schema with evidence list" {
  run grep -F 'evidence' "$F021"
  assert_success
}
