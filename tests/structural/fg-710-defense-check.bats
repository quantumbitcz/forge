#!/usr/bin/env bats
# AC-FEEDBACK-001..005, AC-FEEDBACK-007: defense check sub-agent +
# multi-platform dispatch. (AC-FEEDBACK-006 is owned by C2, PREFLIGHT.)
load '../helpers/test-helpers'

POST="$PLUGIN_ROOT/agents/fg-710-post-run.md"

@test "fg-710 references receiving-code-review pattern" {
  run grep -F 'superpowers:receiving-code-review' "$POST"
  assert_success
}

@test "fg-710 documents defense check sub-agent dispatch" {
  run grep -F 'defense check' "$POST"
  assert_success
}

@test "fg-710 lists three verdicts: actionable, wrong, preference" {
  run grep -E 'actionable.*wrong.*preference|wrong.*preference.*actionable' "$POST"
  assert_success
}

@test "fg-710 reads state.platform.name" {
  run grep -F 'state.platform.name' "$POST"
  assert_success
}

@test "fg-710 dispatches to github adapter" {
  run grep -F 'shared/platform_adapters/github' "$POST"
  assert_success
}

@test "fg-710 dispatches to gitlab adapter" {
  run grep -F 'shared/platform_adapters/gitlab' "$POST"
  assert_success
}

@test "fg-710 dispatches to bitbucket adapter" {
  run grep -F 'shared/platform_adapters/bitbucket' "$POST"
  assert_success
}

@test "fg-710 dispatches to gitea adapter" {
  run grep -F 'shared/platform_adapters/gitea' "$POST"
  assert_success
}

@test "fg-710 documents unknown-platform fallback" {
  run grep -F 'platform: unknown' "$POST"
  assert_success
}

@test "fg-710 writes feedback-decisions.jsonl" {
  run grep -F '.forge/runs/<run_id>/feedback-decisions.jsonl' "$POST"
  assert_success
}

@test "fg-710 documents feedback_loop_count semantics" {
  run grep -F 'feedback_loop_count' "$POST"
  assert_success
}

@test "fg-710 only increments feedback_loop_count for actionable" {
  run grep -E 'only.*actionable.*increment|increment.*only.*actionable' "$POST"
  assert_success
}

@test "fg-710 logs defended_local_only when adapter unavailable" {
  run grep -F 'defended_local_only' "$POST"
  assert_success
}
