#!/usr/bin/env bats

# Covers:

SPEC="$BATS_TEST_DIRNAME/../../hooks/_py/speculation.py"

@test "cost estimation above 2.5x ceiling triggers abort" {
  run python3 "$SPEC" estimate-cost --baseline 4000 --n 3 --ceiling 2.5
  [ "$status" -eq 0 ]
  [[ "$output" == *'"abort": true'* ]]
}

@test "cost estimation just under ceiling does not abort" {
  run python3 "$SPEC" estimate-cost --baseline 10000 --n 2 --ceiling 2.5 --recent-tokens 3000
  [ "$status" -eq 0 ]
  [[ "$output" == *'"abort": false'* ]]
}
