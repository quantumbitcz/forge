#!/usr/bin/env bats
# AC-DEBUG-001..006: fg-020 hypothesis register, parallel dispatch,
# Bayes update, fix gate at 0.75.
load '../helpers/test-helpers'

F020="$PLUGIN_ROOT/agents/fg-020-bug-investigator.md"

@test "fg-020 references systematic-debugging pattern" {
  run grep -F 'superpowers:systematic-debugging' "$F020"
  assert_success
}

@test "fg-020 documents hypothesis register schema" {
  run grep -F 'hypotheses' "$F020"
  assert_success
}

@test "fg-020 requires falsifiability_test on every hypothesis" {
  run grep -F 'falsifiability_test' "$F020"
  assert_success
}

@test "fg-020 requires evidence_required on every hypothesis" {
  run grep -F 'evidence_required' "$F020"
  assert_success
}

@test "fg-020 documents Bayes update formula" {
  run grep -E 'P\(H_i \| E\)' "$F020"
  assert_success
}

@test "fg-020 likelihood table includes 0.95 row" {
  run grep -F '0.95' "$F020"
  assert_success
}

@test "fg-020 likelihood table includes 0.75 row" {
  run grep -F '0.75' "$F020"
  assert_success
}

@test "fg-020 likelihood table includes 0.50 row" {
  run grep -F '0.50' "$F020"
  assert_success
}

@test "fg-020 likelihood table includes 0.05 row" {
  run grep -F '0.05' "$F020"
  assert_success
}

@test "fg-020 likelihood table includes 0.20 row" {
  run grep -F '0.20' "$F020"
  assert_success
}

@test "fg-020 likelihood table includes 0.40 row" {
  run grep -F '0.40' "$F020"
  assert_success
}

@test "fg-020 prunes hypotheses below 0.10" {
  run grep -F '0.10' "$F020"
  assert_success
}

@test "fg-020 fix gate threshold default 0.75" {
  run grep -E 'default.*0\.75|fix_gate_threshold.*0\.75' "$F020"
  assert_success
}

@test "fg-020 sets state.bug.fix_gate_passed" {
  run grep -F 'state.bug.fix_gate_passed' "$F020"
  assert_success
}

@test "fg-020 dispatches fg-021 sub-investigators" {
  run grep -F 'fg-021-hypothesis-investigator' "$F020"
  assert_success
}
