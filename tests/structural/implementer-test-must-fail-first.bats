#!/usr/bin/env bats
# AC-POLISH-001: implementer aborts on TEST-NOT-FAILING.
load '../helpers/test-helpers'

F300="$PLUGIN_ROOT/agents/fg-300-implementer.md"

@test "fg-300 references test-driven-development pattern" {
  run grep -F 'superpowers:test-driven-development' "$F300"
  assert_success
}

@test "fg-300 documents test-must-fail-first check" {
  run grep -iE 'test must fail first|test-must-fail-first' "$F300"
  assert_success
}

@test "fg-300 emits TEST-NOT-FAILING finding" {
  run grep -F 'TEST-NOT-FAILING' "$F300"
  assert_success
}

@test "fg-300 categorises TEST-NOT-FAILING as CRITICAL" {
  run grep -E 'TEST-NOT-FAILING.*CRITICAL|CRITICAL.*TEST-NOT-FAILING' "$F300"
  assert_success
}

@test "fg-300 aborts task on test-must-fail-first violation" {
  # The agent's TEST-NOT-FAILING block lists "Log a CRITICAL finding
  # TEST-NOT-FAILING" and "Abort the task" within a few lines of each
  # other. Match a 5-line proximity window in either direction,
  # case-insensitive.
  run bash -c "grep -i -A 5 'TEST-NOT-FAILING' '$F300' | grep -iq abort"
  assert_success
  run bash -c "grep -i -B 5 'abort.*task' '$F300' | grep -q TEST-NOT-FAILING"
  assert_success
}
