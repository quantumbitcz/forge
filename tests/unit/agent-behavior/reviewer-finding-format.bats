#!/usr/bin/env bash

setup() {
  load '../../helpers/test-helpers'
  AGENTS_DIR="$BATS_TEST_DIRNAME/../../../agents"
}

REVIEWERS=(
  fg-410-code-reviewer
  fg-411-security-reviewer
  fg-412-architecture-reviewer
  fg-413-frontend-reviewer
  fg-416-performance-reviewer
  fg-417-dependency-reviewer
  fg-418-docs-consistency-reviewer
  fg-419-infra-deploy-reviewer
)

@test "reviewers: all 8 reviewer agent files exist" {
  for r in "${REVIEWERS[@]}"; do
    [ -f "$AGENTS_DIR/${r}.md" ] || fail "Missing reviewer: ${r}"
  done
}

@test "reviewers: all have pipe-delimited output format reference" {
  for r in "${REVIEWERS[@]}"; do
    run grep -qi 'pipe.delimited\|output.format\|finding.*format' "$AGENTS_DIR/${r}.md"
    assert_success
  done
}

@test "reviewers: all document confidence field" {
  for r in "${REVIEWERS[@]}"; do
    run grep -qi 'confidence' "$AGENTS_DIR/${r}.md"
    assert_success
  done
}

@test "reviewers: all reference reviewer-boundaries.md" {
  for r in "${REVIEWERS[@]}"; do
    run grep -qi 'reviewer-boundaries\|boundaries' "$AGENTS_DIR/${r}.md"
    assert_success
  done
}

@test "reviewers: frontmatter names match filenames" {
  for r in "${REVIEWERS[@]}"; do
    local name
    name=$(sed -n 's/^name: *//p' "$AGENTS_DIR/${r}.md")
    assert_equal "$name" "$r"
  done
}

@test "reviewers: none have Agent in tools (Tier 4 = no dispatch)" {
  for r in "${REVIEWERS[@]}"; do
    # Reviewers should NOT dispatch sub-agents
    local tools_line
    tools_line=$(grep -A1 '^tools:' "$AGENTS_DIR/${r}.md" | tail -1)
    run echo "$tools_line"
    refute_output --partial "Agent"
  done
}
