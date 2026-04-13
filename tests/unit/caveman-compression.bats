#!/usr/bin/env bash

setup() {
  load '../helpers/test-helpers'
  SHARED_DIR="$BATS_TEST_DIRNAME/../../shared"
}

@test "caveman: input-compression.md exists" {
  assert [ -f "$SHARED_DIR/input-compression.md" ]
}

@test "caveman: input-compression defines 3 intensity levels" {
  run grep -c 'conservative\|aggressive\|ultra' "$SHARED_DIR/input-compression.md"
  assert_success
  [[ "$output" -ge 3 ]]
}

@test "caveman: input-compression preserves code blocks rule" {
  run grep -i 'code block' "$SHARED_DIR/input-compression.md"
  assert_success
}

@test "caveman: input-compression preserves inline code rule" {
  run grep -i 'inline code\|backtick' "$SHARED_DIR/input-compression.md"
  assert_success
}

@test "caveman: input-compression defines remove rules" {
  run grep -i 'articles\|filler\|pleasantries\|hedging' "$SHARED_DIR/input-compression.md"
  assert_success
}

@test "caveman: input-compression has before/after examples" {
  run grep -ic 'before\|after' "$SHARED_DIR/input-compression.md"
  assert_success
  [[ "$output" -ge 4 ]]
}
