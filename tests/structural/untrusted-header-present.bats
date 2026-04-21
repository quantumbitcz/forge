#!/usr/bin/env bats
# Every fg-* agent carries the canonical Untrusted Data Policy.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}

@test "all fg-* agents carry canonical Untrusted Data Policy header" {
  run "$ROOT/tools/verify-untrusted-header.sh"
  if [ "$status" -ne 0 ]; then
    echo "$output"
    return 1
  fi
}

@test "agent count is exactly 42" {
  count="$(find "$ROOT/agents" -maxdepth 1 -name 'fg-*.md' -type f | wc -l | tr -d ' ')"
  [ "$count" = "42" ]
}
