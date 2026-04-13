#!/usr/bin/env bash

setup() {
  load '../../helpers/test-helpers'
  AGENTS_DIR="$BATS_TEST_DIRNAME/../../../agents"
}

@test "fg-700: documents learning extraction" {
  run grep -qi 'learn\|PREEMPT\|retrospective\|rule.*candidate' "$AGENTS_DIR/fg-700-retrospective.md"
  assert_success
}

@test "fg-700: documents rule candidate extraction (S10)" {
  run grep -qi 'learned-candidates\|Learning Extraction' "$AGENTS_DIR/fg-700-retrospective.md"
  assert_success
}

@test "fg-700: frontmatter name matches" {
  run sed -n 's/^name: *//p' "$AGENTS_DIR/fg-700-retrospective.md"
  assert_output "fg-700-retrospective"
}

@test "fg-710: frontmatter name matches" {
  run sed -n 's/^name: *//p' "$AGENTS_DIR/fg-710-post-run.md"
  assert_output "fg-710-post-run"
}
