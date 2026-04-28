#!/usr/bin/env bats
# AC-BRANCH-001..005: PR-finishing dialog + cleanup checklist.
load '../helpers/test-helpers'

PR="$PLUGIN_ROOT/agents/fg-600-pr-builder.md"

@test "fg-600 references finishing-a-development-branch pattern" {
  run grep -F 'finishing-a-development-branch' "$PR"
  assert_success
}

@test "fg-600 has open-pr option" {
  run grep -F '[open-pr]' "$PR"
  assert_success
}

@test "fg-600 has open-pr-draft option" {
  run grep -F '[open-pr-draft]' "$PR"
  assert_success
}

@test "fg-600 has direct-push option" {
  run grep -F '[direct-push]' "$PR"
  assert_success
}

@test "fg-600 has stash option" {
  run grep -F '[stash]' "$PR"
  assert_success
}

@test "fg-600 has abandon option" {
  run grep -F '[abandon]' "$PR"
  assert_success
}

@test "fg-600 default strategy is open-pr" {
  run grep -E 'Default.*\[open-pr\]|default.*open-pr' "$PR"
  assert_success
}

@test "fg-600 references AskUserQuestion" {
  run grep -F 'AskUserQuestion' "$PR"
  assert_success
}

@test "fg-600 cleanup checklist contains worktree deletion" {
  run grep -F 'fg-101-worktree-manager' "$PR"
  assert_success
}

@test "fg-600 cleanup checklist contains run-history update" {
  run grep -F 'run-history.db' "$PR"
  assert_success
}

@test "fg-600 cleanup checklist contains Linear/GitHub link update" {
  run grep -E 'Linear/GitHub|Linear.*GitHub|GitHub.*Linear' "$PR"
  assert_success
}

@test "fg-600 cleanup checklist contains feature-flag TODO" {
  run grep -F 'feature flag' "$PR"
  assert_success
}

@test "fg-600 cleanup checklist contains schedule follow-up" {
  run grep -F 'schedule' "$PR"
  assert_success
}

@test "fg-600 abandon requires second confirmation" {
  run grep -E 'second confirmation|confirm.*twice' "$PR"
  assert_success
}

@test "fg-600 honours pr_builder.default_strategy in autonomous mode" {
  run grep -F 'pr_builder.default_strategy' "$PR"
  assert_success
}

@test "fg-600 honours pr_builder.cleanup_checklist_enabled" {
  run grep -F 'pr_builder.cleanup_checklist_enabled' "$PR"
  assert_success
}
