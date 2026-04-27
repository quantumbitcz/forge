#!/usr/bin/env bats

setup() {
  PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}

@test "fg-301-implementer-judge declares three-input contract" {
  AGENT="$PROJECT_ROOT/agents/fg-301-implementer-judge.md"
  for token in 'task' 'test_code' 'implementation_diff'; do
    run grep -F "$token" "$AGENT"
    [ "$status" -eq 0 ]
  done
}

@test "fg-301-implementer-judge forbids repo exploration with Read" {
  AGENT="$PROJECT_ROOT/agents/fg-301-implementer-judge.md"
  run grep -iF 'Do NOT use `Read` to explore' "$AGENT"
  [ "$status" -eq 0 ]
}

@test "fg-301-implementer-judge forbids receiving PREEMPT / conventions / scaffolder output" {
  AGENT="$PROJECT_ROOT/agents/fg-301-implementer-judge.md"
  run grep -F 'PREEMPT' "$AGENT"
  [ "$status" -eq 0 ]
  run grep -iF 'conventions' "$AGENT"
  [ "$status" -eq 0 ]
}
