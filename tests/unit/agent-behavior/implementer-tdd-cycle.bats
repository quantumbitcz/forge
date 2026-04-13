#!/usr/bin/env bash

setup() {
  load '../../helpers/test-helpers'
  AGENTS_DIR="$BATS_TEST_DIRNAME/../../../agents"
}

@test "fg-300: documents TDD RED phase" {
  run grep -qi 'RED\|failing test\|test first' "$AGENTS_DIR/fg-300-implementer.md"
  assert_success
}

@test "fg-300: documents TDD GREEN phase" {
  run grep -qi 'GREEN\|pass\|implement' "$AGENTS_DIR/fg-300-implementer.md"
  assert_success
}

@test "fg-300: documents REFACTOR phase" {
  run grep -qi 'REFACTOR' "$AGENTS_DIR/fg-300-implementer.md"
  assert_success
}

@test "fg-300: documents inner-loop fix cycles" {
  run grep -qi 'inner.loop\|fix.cycle\|implementer_fix_cycles' "$AGENTS_DIR/fg-300-implementer.md"
  assert_success
}

@test "fg-300: frontmatter name matches filename" {
  run sed -n 's/^name: *//p' "$AGENTS_DIR/fg-300-implementer.md"
  assert_output "fg-300-implementer"
}

@test "fg-310: frontmatter name matches filename" {
  run sed -n 's/^name: *//p' "$AGENTS_DIR/fg-310-scaffolder.md"
  assert_output "fg-310-scaffolder"
}

@test "fg-320: frontmatter name matches filename" {
  run sed -n 's/^name: *//p' "$AGENTS_DIR/fg-320-frontend-polisher.md"
  assert_output "fg-320-frontend-polisher"
}
