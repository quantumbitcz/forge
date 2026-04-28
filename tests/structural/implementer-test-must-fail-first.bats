#!/usr/bin/env bats
# AC-POLISH-001: implementer aborts on TEST-NOT-FAILING.
load '../helpers/test-helpers'

F300="$PLUGIN_ROOT/agents/fg-300-implementer.md"

@test "fg-300 references test-driven-development pattern" {
  run grep -F 'superpowers:test-driven-development' "$F300"
  assert_success
}

@test "fg-300 documents test-must-fail-first check" {
  run grep -E 'test must fail first|test-must-fail-first' "$F300"
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
  run grep -E 'abort.*TEST-NOT-FAILING|TEST-NOT-FAILING.*abort' "$F300"
  assert_success
}
