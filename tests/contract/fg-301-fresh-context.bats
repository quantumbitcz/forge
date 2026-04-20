#!/usr/bin/env bats
# Pre-merge smoke test for sub-subagent context isolation.
# Verifies fg-300 dispatches fg-301 with exactly 3 payload fields and no context bleed.

ROOT="${BATS_TEST_DIRNAME}/../.."
IMPL="${ROOT}/agents/fg-300-implementer.md"
CRITIC="${ROOT}/agents/fg-301-implementer-critic.md"

@test "fresh-context: fg-300 dispatches fg-301 via Task tool (sub-subagent)" {
  run grep -E "fg-301-implementer-critic" "$IMPL"
  [ "$status" -eq 0 ]
  run grep -E "sub-subagent|Task tool" "$IMPL"
  [ "$status" -eq 0 ]
}

@test "fresh-context: dispatch payload declares exactly 3 top-level fields" {
  # The payload block must contain exactly 'task:', 'test_code:', 'implementation_diff:' as top-level keys.
  run awk '
    /^```yaml$/ { in_block=1; next }
    /^```$/ && in_block { in_block=0 }
    in_block && /^[a-z_]+:/ { print $1 }
  ' "$IMPL"
  [ "$status" -eq 0 ]
  # Must contain all three; no extras at top level inside the dispatch block.
  [[ "$output" == *"task:"* ]]
  [[ "$output" == *"test_code:"* ]]
  [[ "$output" == *"implementation_diff:"* ]]
}

@test "fresh-context: fg-300 explicitly forbids extra context in dispatch" {
  # Must name at least these forbidden items in the NOT-sent list.
  run grep -E "MUST NOT receive|NOT receive|no inherited" "$IMPL"
  [ "$status" -eq 0 ]
  for forbidden in "PREEMPT" "conventions" "scaffolder" "prior reasoning|prior iterations|prior reflection"; do
    run grep -E "$forbidden" "$IMPL"
    [ "$status" -eq 0 ]
  done
}

@test "fresh-context: fg-301 identity asserts fresh reviewer" {
  run grep -E "fresh reviewer|never seen this codebase" "$CRITIC"
  [ "$status" -eq 0 ]
}

@test "fresh-context: fg-301 forbidden list blocks repo exploration" {
  run grep -E "Do NOT use.*Read.*explore|do not use it to explore" "$CRITIC"
  [ "$status" -eq 0 ]
}

@test "fresh-context: fg-301 has no tools beyond Read" {
  tools_line=$(grep -m1 '^tools:' "$CRITIC")
  [[ "$tools_line" == *"Read"* ]]
  [[ "$tools_line" != *"Edit"* ]]
  [[ "$tools_line" != *"Write"* ]]
  [[ "$tools_line" != *"Bash"* ]]
  [[ "$tools_line" != *"Grep"* ]]
  [[ "$tools_line" != *"Glob"* ]]
  [[ "$tools_line" != *"Task"* ]]
  [[ "$tools_line" != *"WebFetch"* ]]
}

@test "fresh-context: fg-301 instructed not to ask for more info" {
  run grep -E "Do NOT ask for more|decide with what you have" "$CRITIC"
  [ "$status" -eq 0 ]
}

@test "fresh-context: prior reflection iterations explicitly excluded" {
  run grep -E "prior reflection|other tasks" "$IMPL"
  [ "$status" -eq 0 ]
}
