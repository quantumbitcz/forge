#!/usr/bin/env bats
# Every fg-* agent carries the canonical Untrusted Data Policy.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  # shellcheck source=../lib/module-lists.bash
  source "$ROOT/tests/lib/module-lists.bash"
}

@test "all fg-* agents carry canonical Untrusted Data Policy header" {
  run "$ROOT/tools/verify-untrusted-header.sh"
  if [ "$status" -ne 0 ]; then
    echo "$output"
    return 1
  fi
}

@test "agent count is at least MIN_AGENTS" {
  count="$(find "$ROOT/agents" -maxdepth 1 -name 'fg-*.md' -type f | wc -l | tr -d ' ')"
  [ "$count" -ge "$MIN_AGENTS" ]
}
