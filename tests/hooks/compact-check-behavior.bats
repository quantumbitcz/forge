#!/usr/bin/env bats

setup() {
  load '../helpers/test-helpers'
  HOOK_SCRIPT="$BATS_TEST_DIRNAME/../../shared/forge-compact-check.sh"
}

@test "compact-check: suggests compaction at threshold (multiple of 5)" {
  local forge_dir="${TEST_TEMP}/project/.forge"
  mkdir -p "$forge_dir"
  # Set counter to 4 so next increment (to 5) triggers suggestion
  echo "4" > "$forge_dir/.token-estimate"

  run bash "$HOOK_SCRIPT" --forge-dir "$forge_dir"
  assert_success

  # The script writes suggestion at multiples of 5
  assert [ -f "$forge_dir/.compact-suggestion" ]
  run grep -q 'compact' "$forge_dir/.compact-suggestion"
  assert_success
}

@test "compact-check: does not suggest below threshold" {
  local forge_dir="${TEST_TEMP}/project/.forge"
  mkdir -p "$forge_dir"
  # Set counter to 1 so next increment (to 2) does NOT trigger suggestion
  echo "1" > "$forge_dir/.token-estimate"

  run bash "$HOOK_SCRIPT" --forge-dir "$forge_dir"
  assert_success

  # No suggestion file should exist (or if it existed before, content should not be refreshed)
  if [[ -f "$forge_dir/.compact-suggestion" ]]; then
    # If suggestion was created, it should not match count=2
    run grep -q '2 agent dispatches' "$forge_dir/.compact-suggestion"
    assert_failure
  fi
}

@test "compact-check: handles missing counter file" {
  local forge_dir="${TEST_TEMP}/project/.forge"
  mkdir -p "$forge_dir"
  # No .token-estimate file — should start from 0

  run bash "$HOOK_SCRIPT" --forge-dir "$forge_dir"
  assert_success

  # Counter should have been created with value 1
  assert [ -f "$forge_dir/.token-estimate" ]
  local count
  count=$(cat "$forge_dir/.token-estimate")
  assert [ "$count" = "1" ]
}
