#!/usr/bin/env bats
# AC-PLAN-009: high-risk tasks carry justification ≥30 words.
load '../helpers/test-helpers'

FIX="$PLUGIN_ROOT/tests/fixtures/phase-D/synthetic-broken-plans"

count_justification_words() {
  # Extract the Risk justification block (inline + any continuation
  # lines until the next bold field marker or task boundary) and count
  # whitespace-separated words. The marker itself can carry the body on
  # the same line, so we strip the marker and emit the remainder before
  # entering capture mode.
  awk '
    /^\*\*Risk justification:\*\*/ {
      sub(/^\*\*Risk justification:\*\*[[:space:]]*/, "")
      capturing=1
      if (length($0) > 0) print
      next
    }
    capturing && /^\*\*/ { capturing=0 }
    capturing && /^### Task/ { capturing=0 }
    capturing { print }
  ' "$1" | wc -w
}

@test "missing-risk-justification fixture has zero justification words" {
  run count_justification_words "$FIX/missing-risk-justification.md"
  assert_success
  assert [ "$output" -eq 0 ]
}

@test "short-risk-justification fixture has fewer than 30 words" {
  run count_justification_words "$FIX/short-risk-justification.md"
  assert_success
  assert [ "$output" -lt 30 ]
}
