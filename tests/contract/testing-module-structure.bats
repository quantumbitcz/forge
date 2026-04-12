#!/usr/bin/env bats
# Contract test: testing module structural validation.
# Each testing module in modules/testing/ must exist, be non-empty,
# and contain convention/integration guidance.

load '../helpers/test-helpers'

source "$PLUGIN_ROOT/tests/lib/module-lists.bash"

@test "testing-modules: minimum count guard (>= $MIN_TESTING_FILES)" {
  guard_min_count "testing" "${#DISCOVERED_TESTING_FILES[@]}" "$MIN_TESTING_FILES"
}

@test "testing-modules: all discovered modules are non-empty" {
  local failures=()
  for mod in "${DISCOVERED_TESTING_FILES[@]}"; do
    local file="$PLUGIN_ROOT/modules/testing/${mod}"
    [[ -s "$file" ]] || failures+=("${mod}: file is empty or missing")
  done
  if (( ${#failures[@]} > 0 )); then
    printf '%s\n' "${failures[@]}"
    fail "Empty/missing testing modules: ${#failures[@]}"
  fi
}

@test "testing-modules: each module contains required sections" {
  local failures=()
  for mod in "${DISCOVERED_TESTING_FILES[@]}"; do
    local file="$PLUGIN_ROOT/modules/testing/${mod}"
    [[ -f "$file" ]] || continue

    # Must have at least one level-2 heading
    grep -q "^## " "$file" || failures+=("${mod}: no ## heading")

    # Must have convention or integration content (at least 20 lines)
    local lines
    lines="$(wc -l < "$file" | tr -d ' ')"
    (( lines >= 20 )) || failures+=("${mod}: too short (${lines} lines, expected >= 20)")
  done
  if (( ${#failures[@]} > 0 )); then
    printf '%s\n' "${failures[@]}"
    fail "Testing module violations: ${#failures[@]}"
  fi
}
