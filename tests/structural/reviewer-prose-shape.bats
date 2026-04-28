#!/usr/bin/env bats
# AC-REVIEW-001..003: every reviewer emits prose with required headings.
load '../helpers/test-helpers'

REVIEWERS=(
  fg-410-code-reviewer
  fg-411-security-reviewer
  fg-412-architecture-reviewer
  fg-413-frontend-reviewer
  fg-414-license-reviewer
  fg-416-performance-reviewer
  fg-417-dependency-reviewer
  fg-418-docs-consistency-reviewer
  fg-419-infra-deploy-reviewer
)

@test "every reviewer references requesting-code-review pattern" {
  for r in "${REVIEWERS[@]}"; do
    run grep -F 'superpowers:requesting-code-review' "$PLUGIN_ROOT/agents/$r.md"
    assert_success
  done
}

@test "every reviewer has Strengths heading" {
  for r in "${REVIEWERS[@]}"; do
    run grep -E '^## Strengths' "$PLUGIN_ROOT/agents/$r.md"
    assert_success
  done
}

@test "every reviewer has Issues heading with Critical/Important/Minor sub-sections" {
  for r in "${REVIEWERS[@]}"; do
    run grep -E '^## Issues' "$PLUGIN_ROOT/agents/$r.md"
    assert_success
    run grep -F '### Critical (Must Fix)' "$PLUGIN_ROOT/agents/$r.md"
    assert_success
    run grep -F '### Important (Should Fix)' "$PLUGIN_ROOT/agents/$r.md"
    assert_success
    run grep -F '### Minor (Nice to Have)' "$PLUGIN_ROOT/agents/$r.md"
    assert_success
  done
}

@test "every reviewer has Recommendations heading" {
  for r in "${REVIEWERS[@]}"; do
    run grep -E '^## Recommendations' "$PLUGIN_ROOT/agents/$r.md"
    assert_success
  done
}

@test "every reviewer has Assessment with Ready to merge and Reasoning fields" {
  for r in "${REVIEWERS[@]}"; do
    run grep -E '^## Assessment' "$PLUGIN_ROOT/agents/$r.md"
    assert_success
    run grep -F '**Ready to merge:**' "$PLUGIN_ROOT/agents/$r.md"
    assert_success
    run grep -F '**Reasoning:**' "$PLUGIN_ROOT/agents/$r.md"
    assert_success
  done
}

@test "every reviewer documents prose report path" {
  for r in "${REVIEWERS[@]}"; do
    run grep -F '.forge/runs/<run_id>/reports/' "$PLUGIN_ROOT/agents/$r.md"
    assert_success
  done
}

@test "fg-400 writes prose reports under runs reports directory" {
  run grep -F '.forge/runs/<run_id>/reports/<reviewer>.md' "$PLUGIN_ROOT/agents/fg-400-quality-gate.md"
  assert_success
}
