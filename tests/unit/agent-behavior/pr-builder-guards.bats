#!/usr/bin/env bash

setup() {
  load '../../helpers/test-helpers'
  AGENTS_DIR="$BATS_TEST_DIRNAME/../../../agents"
}

@test "fg-600: requires evidence before PR creation" {
  run grep -qi 'evidence\|verdict.*SHIP' "$AGENTS_DIR/fg-600-pr-builder.md"
  assert_success
}

@test "fg-600: documents PR URL output" {
  run grep -qi 'pr.*url\|pull.*request' "$AGENTS_DIR/fg-600-pr-builder.md"
  assert_success
}

@test "fg-600: documents branch naming" {
  run grep -qi 'branch' "$AGENTS_DIR/fg-600-pr-builder.md"
  assert_success
}

@test "fg-600: frontmatter name matches" {
  run sed -n 's/^name: *//p' "$AGENTS_DIR/fg-600-pr-builder.md"
  assert_output "fg-600-pr-builder"
}
