#!/usr/bin/env bash

setup() {
  load '../../helpers/test-helpers'
  AGENTS_DIR="$BATS_TEST_DIRNAME/../../../agents"
}

# Previously untested agents — basic behavioral checks

UNTESTED_AGENTS=(
  fg-101-worktree-manager
  fg-102-conflict-resolver
  fg-103-cross-repo-coordinator
  fg-140-deprecation-refresh
  fg-150-test-bootstrapper
  fg-160-migration-planner
  fg-250-contract-validator
  fg-610-infra-deploy-verifier
  fg-620-deploy-verifier
  fg-650-preview-validator
)

@test "untested-agents: all agent files exist" {
  for a in "${UNTESTED_AGENTS[@]}"; do
    [ -f "$AGENTS_DIR/${a}.md" ] || fail "Missing agent: ${a}"
  done
}

@test "untested-agents: all have valid frontmatter" {
  for a in "${UNTESTED_AGENTS[@]}"; do
    run head -1 "$AGENTS_DIR/${a}.md"
    assert_output "---"
  done
}

@test "untested-agents: all frontmatter names match filenames" {
  for a in "${UNTESTED_AGENTS[@]}"; do
    local name
    name=$(sed -n 's/^name: *//p' "$AGENTS_DIR/${a}.md")
    assert_equal "$name" "$a"
  done
}

@test "untested-agents: all have description in frontmatter" {
  for a in "${UNTESTED_AGENTS[@]}"; do
    run grep -q '^description:' "$AGENTS_DIR/${a}.md"
    assert_success
  done
}

@test "untested-agents: all have tools in frontmatter" {
  for a in "${UNTESTED_AGENTS[@]}"; do
    run grep -q '^tools:' "$AGENTS_DIR/${a}.md"
    assert_success
  done
}
