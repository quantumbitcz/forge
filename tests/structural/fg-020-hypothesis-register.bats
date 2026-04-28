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
  # Match either the canonical "P(H_i | E)" form or any equivalent
  # Bayesian posterior expression: P(<hyp> | <evidence>). Also accept
  # the literal word "Bayes" in case the formula gets reformatted.
  run grep -E 'Bayes|P\([A-Za-z_]+[^|]*\|[^)]+\)' "$F020"
  assert_success
}

@test "fg-020 likelihood table includes 0.95 row" {
  # Tighten: the value must appear inside an actual table cell, not in
  # narrative prose elsewhere. Match a pipe-delimited cell.
  run grep -E '\|[[:space:]]*\*?\*?0\.95\*?\*?[[:space:]]*\|' "$F020"
  assert_success
}

@test "fg-020 likelihood table includes 0.75 row" {
  run grep -E '\|[[:space:]]*\*?\*?0\.75\*?\*?[[:space:]]*\|' "$F020"
  assert_success
}

@test "fg-020 likelihood table includes 0.50 row" {
  run grep -E '\|[[:space:]]*\*?\*?0\.50\*?\*?[[:space:]]*\|' "$F020"
  assert_success
}

@test "fg-020 likelihood table includes 0.05 row" {
  run grep -E '\|[[:space:]]*\*?\*?0\.05\*?\*?[[:space:]]*\|' "$F020"
  assert_success
}

@test "fg-020 likelihood table includes 0.20 row" {
  run grep -E '\|[[:space:]]*\*?\*?0\.20\*?\*?[[:space:]]*\|' "$F020"
  assert_success
}

@test "fg-020 likelihood table includes 0.40 row" {
  run grep -E '\|[[:space:]]*\*?\*?0\.40\*?\*?[[:space:]]*\|' "$F020"
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
