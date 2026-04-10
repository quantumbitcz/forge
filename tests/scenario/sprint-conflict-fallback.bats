#!/usr/bin/env bats
# Scenario tests: sprint conflict detection fallback

load '../helpers/test-helpers'

CONFLICT_RESOLVER="$PLUGIN_ROOT/agents/fg-102-conflict-resolver.md"

has_path_overlap() {
  local -a paths_a=() paths_b=()
  local separator="---" current="a"
  for arg in "$@"; do
    if [[ "$arg" == "$separator" ]]; then current="b"; continue; fi
    if [[ "$current" == "a" ]]; then paths_a+=("$arg"); else paths_b+=("$arg"); fi
  done
  for pa in "${paths_a[@]}"; do
    for pb in "${paths_b[@]}"; do
      if [[ "$pa" == "$pb"* || "$pb" == "$pa"* ]]; then return 0; fi
    done
  done
  return 1
}

@test "sprint-conflict: overlapping paths detected without graph" {
  run has_path_overlap "src/auth/" --- "src/auth/"
  assert_success
}

@test "sprint-conflict: non-overlapping paths pass without graph" {
  run has_path_overlap "src/auth/" --- "src/billing/"
  assert_failure
}

@test "sprint-conflict: partial path overlap detected" {
  run has_path_overlap "src/shared/utils.ts" --- "src/shared/"
  assert_success
}

@test "sprint-conflict: graph fallback behavior documented" {
  grep -qi "graph.*unavailable\|fallback\|graph.*fail\|file-level" "$CONFLICT_RESOLVER" \
    || fail "Graph fallback behavior not documented in fg-102-conflict-resolver.md"
}

@test "sprint-conflict: same file in two features creates overlap" {
  run has_path_overlap "package.json" --- "package.json"
  assert_success
}

@test "sprint-conflict: deeply nested overlap detected" {
  run has_path_overlap "src/main/kotlin/auth/domain/" --- "src/main/kotlin/auth/domain/User.kt"
  assert_success
}

@test "sprint-conflict: no overlap for sibling directories" {
  run has_path_overlap "src/auth/login/" --- "src/auth/register/"
  assert_failure
}

@test "sprint-conflict: graph fallback section exists in conflict resolver" {
  grep -qi "Graph Fallback\|graph.*fallback\|file.*level.*analysis\|Phase 1" "$CONFLICT_RESOLVER" \
    || fail "Graph fallback section not found in conflict resolver"
}
