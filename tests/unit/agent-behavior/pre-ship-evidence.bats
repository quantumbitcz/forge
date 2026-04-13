#!/usr/bin/env bash

setup() {
  load '../../helpers/test-helpers'
  AGENTS_DIR="$BATS_TEST_DIRNAME/../../../agents"
}

@test "fg-590: documents evidence.json artifact" {
  run grep -qi 'evidence\.json\|evidence' "$AGENTS_DIR/fg-590-pre-ship-verifier.md"
  assert_success
}

@test "fg-590: documents SHIP/BLOCK verdict" {
  local agent="$AGENTS_DIR/fg-590-pre-ship-verifier.md"
  run grep -q 'SHIP' "$agent"
  assert_success
  run grep -q 'BLOCK' "$agent"
  assert_success
}

@test "fg-590: has Agent in tools for reviewer dispatch" {
  run grep -q 'Agent' "$AGENTS_DIR/fg-590-pre-ship-verifier.md"
  assert_success
}

@test "fg-590: frontmatter name matches" {
  run sed -n 's/^name: *//p' "$AGENTS_DIR/fg-590-pre-ship-verifier.md"
  assert_output "fg-590-pre-ship-verifier"
}
