#!/usr/bin/env bash

setup() {
  load '../../helpers/test-helpers'
  AGENTS_DIR="$BATS_TEST_DIRNAME/../../../agents"
}

@test "fg-020: documents reproduction attempts" {
  run grep -qi 'reproduc\|failing test\|repro' "$AGENTS_DIR/fg-020-bug-investigator.md"
  assert_success
}

@test "fg-020: frontmatter name matches" {
  run sed -n 's/^name: *//p' "$AGENTS_DIR/fg-020-bug-investigator.md"
  assert_output "fg-020-bug-investigator"
}

@test "fg-050: frontmatter name matches" {
  run sed -n 's/^name: *//p' "$AGENTS_DIR/fg-050-project-bootstrapper.md"
  assert_output "fg-050-project-bootstrapper"
}
