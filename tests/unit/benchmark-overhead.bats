#!/usr/bin/env bats
# Token-overhead benchmark sanity for injection hardening.

setup() { ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"; }

@test "benchmark script runs and reports finite numbers" {
  run bash "$ROOT/tools/benchmark-injection-overhead.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"block bytes"* ]]
  [[ "$output" == *"typical per-run"* ]]
}

@test "estimated per-run overhead is under 10,000 tokens" {
  run bash "$ROOT/tools/benchmark-injection-overhead.sh"
  [ "$status" -eq 0 ]
  # Extract the per-run token count: line is `... ~NNNN tokens`
  n=$(echo "$output" | sed -nE 's/.*~([0-9]+) tokens.*/\1/p')
  [ -n "$n" ]
  [ "$n" -lt 10000 ]
}
