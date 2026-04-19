#!/usr/bin/env bats

ROOT="${BATS_TEST_DIRNAME}/../.."

@test "fg-301: agent file exists" {
  [ -f "${ROOT}/agents/fg-301-implementer-critic.md" ]
}

@test "fg-301: frontmatter name matches filename" {
  run grep -m1 '^name:' "${ROOT}/agents/fg-301-implementer-critic.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *"fg-301-implementer-critic"* ]]
}

@test "fg-301: model tier is fast" {
  run grep -m1 '^model:' "${ROOT}/agents/fg-301-implementer-critic.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *"fast"* ]]
}

@test "fg-301: color is lime" {
  run grep -m1 '^color:' "${ROOT}/agents/fg-301-implementer-critic.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *"lime"* ]]
}

@test "fg-301: tools is Read-only" {
  run grep -m1 '^tools:' "${ROOT}/agents/fg-301-implementer-critic.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Read"* ]]
  [[ "$output" != *"Edit"* ]]
  [[ "$output" != *"Write"* ]]
  [[ "$output" != *"Bash"* ]]
}

@test "fg-301: ui frontmatter declares Tier-4 (all false)" {
  run grep -A3 '^ui:' "${ROOT}/agents/fg-301-implementer-critic.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *"tasks: false"* ]]
  [[ "$output" == *"ask: false"* ]]
  [[ "$output" == *"plan_mode: false"* ]]
}
