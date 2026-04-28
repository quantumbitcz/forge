#!/usr/bin/env bats
# Test-floor counts (accidental-deletion guard for test directories).
# Sources MIN_*_TESTS from tests/lib/module-lists.bash and asserts the
# current file counts under tests/{unit,contract,structural,scenarios}/
# meet the declared floor. Bump the floor in module-lists.bash when
# adding new tests; this file does not need to change.
load '../helpers/test-helpers'

source "$PLUGIN_ROOT/tests/lib/module-lists.bash"

count_files() {
  local dir="$1"; shift
  local count=0
  while IFS= read -r _; do
    count=$((count + 1))
  done < <(find "$PLUGIN_ROOT/$dir" -type f \( "$@" \) -not -path '*__pycache__*' 2>/dev/null)
  echo "$count"
}

@test "tests/unit meets MIN_UNIT_TESTS floor" {
  local actual
  actual="$(count_files tests/unit -name '*.bats' -o -name '*.py')"
  guard_min_count "tests/unit" "$actual" "$MIN_UNIT_TESTS"
}

@test "tests/contract meets MIN_CONTRACT_TESTS floor" {
  local actual
  actual="$(count_files tests/contract -name '*.bats' -o -name '*.py')"
  guard_min_count "tests/contract" "$actual" "$MIN_CONTRACT_TESTS"
}

@test "tests/structural meets MIN_STRUCTURAL_TESTS floor" {
  local actual
  actual="$(count_files tests/structural -name '*.bats')"
  guard_min_count "tests/structural" "$actual" "$MIN_STRUCTURAL_TESTS"
}

@test "tests/scenarios meets MIN_SCENARIO_TESTS floor" {
  local actual
  actual="$(count_files tests/scenarios -name '*.bats')"
  guard_min_count "tests/scenarios" "$actual" "$MIN_SCENARIO_TESTS"
}
