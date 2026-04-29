#!/usr/bin/env bats
# AC-FEEDBACK-001..005: defense check verdicts and JSONL writes.
load '../helpers/test-helpers'

F710="$PLUGIN_ROOT/agents/fg-710-post-run.md"

@test "fg-710 documents three verdicts in workflow" {
  run grep -F 'actionable' "$F710"
  assert_success
  run grep -F 'wrong' "$F710"
  assert_success
  run grep -F 'preference' "$F710"
  assert_success
}

@test "fg-710 increments feedback_loop_count only on actionable" {
  run grep -E 'increment.*actionable|actionable.*increment' "$F710"
  assert_success
}

@test "fg-710 documents addressed states for all paths" {
  run grep -F 'actionable_routed' "$F710"
  assert_success
  run grep -F 'defended' "$F710"
  assert_success
  run grep -F 'acknowledged' "$F710"
  assert_success
  run grep -F 'defended_local_only' "$F710"
  assert_success
}

@test "fg-710 weak-evidence downgrade is documented" {
  run grep -F 'FEEDBACK-EVIDENCE-WEAK' "$F710"
  assert_success
}

@test "fg-710 platform unknown fallback is documented" {
  run grep -E 'unknown.*no-op|no-op.*unknown' "$F710"
  assert_success
}
