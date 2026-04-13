#!/usr/bin/env bash

setup() {
  load '../../helpers/test-helpers'
  AGENTS_DIR="$BATS_TEST_DIRNAME/../../../agents"
}

@test "fg-200: documents plan output structure" {
  run grep -qi 'plan\|story\|task\|decompos' "$AGENTS_DIR/fg-200-planner.md"
  assert_success
}

@test "fg-200: documents risk assessment" {
  run grep -qi 'risk' "$AGENTS_DIR/fg-200-planner.md"
  assert_success
}

@test "fg-200: has Agent in tools for sub-dispatching" {
  run grep -q 'Agent' "$AGENTS_DIR/fg-200-planner.md"
  assert_success
}

@test "fg-210: documents validation verdict (GO/REVISE/NO-GO)" {
  local agent="$AGENTS_DIR/fg-210-validator.md"
  run grep -q 'GO' "$agent"
  assert_success
  run grep -q 'REVISE\|NO.GO' "$agent"
  assert_success
}

@test "fg-210: frontmatter name matches filename" {
  run sed -n 's/^name: *//p' "$AGENTS_DIR/fg-210-validator.md"
  assert_output "fg-210-validator"
}
