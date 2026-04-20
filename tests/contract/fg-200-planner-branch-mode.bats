#!/usr/bin/env bats

PLANNER="$BATS_TEST_DIRNAME/../../agents/fg-200-planner.md"

@test "planner has Branch Mode section" {
  grep -q "^## Branch Mode (Speculative)" "$PLANNER"
}

@test "branch mode describes speculative flag contract" {
  grep -q "speculative: true" "$PLANNER"
  grep -q "candidate_id: cand-{N}" "$PLANNER"
  grep -q "emphasis_axis: {simplicity|robustness|velocity}" "$PLANNER"
}

@test "branch mode specifies 200-word challenge brief cap" {
  grep -q "200 words" "$PLANNER"
}

@test "branch mode skips Plan Mode wrappers" {
  grep -q "Skip Plan Mode" "$PLANNER"
}

@test "planner frontmatter unchanged (still has Agent in tools)" {
  head -20 "$PLANNER" | grep -q "name: fg-200-planner"
  head -20 "$PLANNER" | grep -q "tools:"
}
