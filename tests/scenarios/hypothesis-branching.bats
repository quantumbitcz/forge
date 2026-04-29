#!/usr/bin/env bats
# AC-DEBUG-001..003, AC-DEBUG-006, AC-DEBUG-007: hypothesis branching
# + Bayes update + falsifiability test + serial fallback.
load '../helpers/test-helpers'

F020="$PLUGIN_ROOT/agents/fg-020-bug-investigator.md"
F021="$PLUGIN_ROOT/agents/fg-021-hypothesis-investigator.md"

@test "fg-020 likelihood table covers all 6 (passes_test, confidence) combinations" {
  # six rows: true/high, true/medium, true/low, false/high, false/medium, false/low
  for combo in '0\.95' '0\.75' '0\.50' '0\.05' '0\.20' '0\.40'; do
    run grep -E "$combo" "$F020"
    assert_success
  done
}

@test "fg-020 prunes hypotheses with posterior < 0.10" {
  run grep -E 'posterior.*<.*0\.10|0\.10.*prun' "$F020"
  assert_success
}

@test "fg-021 returns hypothesis_id, evidence list, passes_test, confidence" {
  for field in 'hypothesis_id' 'evidence' 'passes_test' 'confidence'; do
    run grep -F "$field" "$F021"
    assert_success
  done
}

@test "fg-020 documents single tool-use parallel dispatch" {
  run grep -E 'single tool-use block' "$F020"
  assert_success
}

@test "fg-020 honours bug.hypothesis_branching.enabled: false fallback" {
  run grep -F 'single-hypothesis serial' "$F020"
  assert_success
}

@test "every hypothesis has a falsifiability_test field" {
  run grep -F 'falsifiability_test' "$F020"
  assert_success
}
