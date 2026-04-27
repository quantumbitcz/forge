#!/usr/bin/env bash

# Covers:

setup() {
  load '../helpers/test-helpers'
  SHARED_DIR="$BATS_TEST_DIRNAME/../../shared"
}

@test "learned-rules-lifecycle: promotion doc references candidate schema" {
  run grep -q '"id"' "$SHARED_DIR/learnings/rule-promotion.md"
  assert_success
}

@test "learned-rules-lifecycle: promotion doc references promoted rule format" {
  run grep -q '"promoted_from"' "$SHARED_DIR/learnings/rule-promotion.md"
  assert_success
}

@test "learned-rules-lifecycle: rule-promotion.md references forge-log.md for audit" {
  run grep -q 'forge-log' "$SHARED_DIR/learnings/rule-promotion.md"
  assert_success
}
