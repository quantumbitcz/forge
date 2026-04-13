#!/usr/bin/env bash

setup() {
  load '../../helpers/test-helpers'
  AGENTS_DIR="$BATS_TEST_DIRNAME/../../../agents"
}

@test "fg-010: documents spec file output" {
  run grep -qi 'spec\|requirement\|epic\|story\|acceptance' "$AGENTS_DIR/fg-010-shaper.md"
  assert_success
}

@test "fg-010: frontmatter name matches" {
  run sed -n 's/^name: *//p' "$AGENTS_DIR/fg-010-shaper.md"
  assert_output "fg-010-shaper"
}

@test "fg-015: frontmatter name matches" {
  run sed -n 's/^name: *//p' "$AGENTS_DIR/fg-015-scope-decomposer.md"
  assert_output "fg-015-scope-decomposer"
}
