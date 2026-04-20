#!/usr/bin/env bats

setup() { SPEC="$BATS_TEST_DIRNAME/../../hooks/_py/speculation.py"; }

@test "cost estimation cold start uses default" {
  run python3 "$SPEC" estimate-cost --baseline 4000 --n 3 --ceiling 2.5
  [ "$status" -eq 0 ]
  [[ "$output" == *'"estimated": 17500'* ]]
  [[ "$output" == *'"abort": true'* ]]
}

@test "cost estimation with history uses last-10 mean" {
  run python3 "$SPEC" estimate-cost --baseline 4000 --n 3 --ceiling 2.5 --recent-tokens 3000,3200,3100,3050,3150,3100,3000,3100,3100,3200
  [ "$status" -eq 0 ]
  [[ "$output" == *'"estimated": 13300'* ]]
  [[ "$output" == *'"abort": true'* ]]
}

@test "cost estimation under ceiling does not abort" {
  run python3 "$SPEC" estimate-cost --baseline 4000 --n 2 --ceiling 2.5 --recent-tokens 2800
  [ "$status" -eq 0 ]
  [[ "$output" == *'"abort": false'* ]]
}

@test "cost estimation window caps at last 10" {
  run python3 "$SPEC" estimate-cost --baseline 4000 --n 3 --ceiling 2.5 --recent-tokens 9999,9999,9999,9999,9999,3000,3000,3000,3000,3000
  [ "$status" -eq 0 ]
  [[ "$output" == *'"window_used": 10'* ]]
}
