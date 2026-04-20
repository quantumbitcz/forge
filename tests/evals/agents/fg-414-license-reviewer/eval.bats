#!/usr/bin/env bats
# Eval: fg-414-license-reviewer — structural validation and license-policy coverage

load '../../../helpers/test-helpers'
load '../../framework'

AGENT_DIR="$BATS_TEST_DIRNAME"
AGENT_NAME="fg-414-license-reviewer"

@test "eval:${AGENT_NAME}: all input files are well-formed" {
  for input in "$AGENT_DIR"/inputs/*.md; do
    run validate_input_file "$input"
    assert_success
  done
}

@test "eval:${AGENT_NAME}: all expected files are well-formed" {
  for expected in "$AGENT_DIR"/expected/*.expected; do
    run validate_expected_file "$expected"
    assert_success
  done
}

@test "eval:${AGENT_NAME}: input/expected pairs match" {
  run count_input_expected_pairs "$AGENT_DIR"
  assert_success
}

@test "eval:${AGENT_NAME}: expected patterns are internally consistent" {
  for expected in "$AGENT_DIR"/expected/*.expected; do
    local min max
    min=$(grep '^MIN_FINDINGS:' "$expected" | head -1 | awk '{print $2}') || min=""
    max=$(grep '^MAX_FINDINGS:' "$expected" | head -1 | awk '{print $2}') || max=""
    if [[ -n "$min" && -n "$max" ]]; then
      (( min <= max )) || fail "Inconsistent: MIN_FINDINGS=$min > MAX_FINDINGS=$max in $(basename "$expected")"
    fi
  done
}

@test "eval:${AGENT_NAME}: conventions cover tested patterns" {
  for input in "$AGENT_DIR"/inputs/*.md; do
    run check_convention_coverage "$AGENT_DIR" "$input"
    assert_success
  done
}

@test "eval:${AGENT_NAME}: has at least 4 eval pairs" {
  local count
  count=$(ls "$AGENT_DIR"/inputs/*.md 2>/dev/null | wc -l | tr -d ' ')
  (( count >= 4 ))
}
