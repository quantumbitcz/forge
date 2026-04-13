#!/usr/bin/env bash

setup() {
  load '../../helpers/test-helpers'
  AGENTS_DIR="$BATS_TEST_DIRNAME/../../../agents"
}

@test "fg-090: documents independence analysis" {
  run grep -qi 'independen\|parallel\|conflict' "$AGENTS_DIR/fg-090-sprint-orchestrator.md"
  assert_success
}

@test "fg-090: documents per-feature worktrees" {
  run grep -qi 'worktree' "$AGENTS_DIR/fg-090-sprint-orchestrator.md"
  assert_success
}

@test "fg-090: has Agent in tools for pipeline dispatch" {
  run grep -q 'Agent' "$AGENTS_DIR/fg-090-sprint-orchestrator.md"
  assert_success
}

@test "fg-090: frontmatter name matches" {
  run sed -n 's/^name: *//p' "$AGENTS_DIR/fg-090-sprint-orchestrator.md"
  assert_output "fg-090-sprint-orchestrator"
}
