#!/usr/bin/env bash

setup() {
  load '../../helpers/test-helpers'
  AGENTS_DIR="$BATS_TEST_DIRNAME/../../../agents"
}

@test "fg-500: documents test result parsing" {
  run grep -qi 'test.*result\|pass.*fail\|tests_pass' "$AGENTS_DIR/fg-500-test-gate.md"
  assert_success
}

@test "fg-500: has Agent in tools for sub-dispatch" {
  run grep -q 'Agent' "$AGENTS_DIR/fg-500-test-gate.md"
  assert_success
}

@test "fg-500: frontmatter name matches" {
  run sed -n 's/^name: *//p' "$AGENTS_DIR/fg-500-test-gate.md"
  assert_output "fg-500-test-gate"
}

@test "fg-505: frontmatter name matches" {
  run sed -n 's/^name: *//p' "$AGENTS_DIR/fg-505-build-verifier.md"
  assert_output "fg-505-build-verifier"
}

@test "fg-510: frontmatter name matches" {
  run sed -n 's/^name: *//p' "$AGENTS_DIR/fg-510-mutation-analyzer.md"
  assert_output "fg-510-mutation-analyzer"
}

@test "fg-515: frontmatter name matches" {
  run sed -n 's/^name: *//p' "$AGENTS_DIR/fg-515-property-test-generator.md"
  assert_output "fg-515-property-test-generator"
}
