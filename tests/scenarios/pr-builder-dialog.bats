#!/usr/bin/env bats
# AC-BRANCH-001..005: PR-builder dialog + cleanup + abandon confirmation.
load '../helpers/test-helpers'

PR="$PLUGIN_ROOT/agents/fg-600-pr-builder.md"

@test "fg-600 dialog has exactly five options" {
  local count=0
  for opt in '\[open-pr\]' '\[open-pr-draft\]' '\[direct-push\]' '\[stash\]' '\[abandon\]'; do
    run grep -E "$opt" "$PR"
    assert_success
    count=$((count + 1))
  done
  assert [ "$count" -eq 5 ]
}

@test "fg-600 default is open-pr (interactive)" {
  run grep -E 'default.*open-pr[^-]' "$PR"
  assert_success
}

@test "fg-600 abandon requires second AskUserQuestion" {
  # The agent prompt mentions a SECOND AskUserQuestion call for abandon
  run grep -E 'SECOND AskUserQuestion|second confirmation' "$PR"
  assert_success
}

@test "fg-600 abandon is never an autonomous default" {
  run grep -E 'never.*autonomous default|abandon.*interactive[ -]only' "$PR"
  assert_success
}

@test "fg-600 cleanup checklist runs after each non-stash strategy" {
  run grep -E 'cleanup checklist.*Step 5|Step 5.*cleanup' "$PR"
  assert_success
}

@test "fg-600 cleanup_checklist_enabled false skips cleanup but not PR creation" {
  run grep -E 'cleanup_checklist_enabled.*false.*skip|skip.*cleanup.*not.*PR' "$PR"
  assert_success
}
