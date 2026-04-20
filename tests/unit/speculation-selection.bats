#!/usr/bin/env bats

setup() { SPEC="$BATS_TEST_DIRNAME/../../hooks/_py/speculation.py"; }

@test "GO verdict no efficiency advantage -> selection_score == validator_score" {
  run python3 "$SPEC" compute-selection --validator-score 80 --verdict GO --tokens 1000 --batch-max-tokens 1000
  [ "$status" -eq 0 ]
  [[ "$output" == *'"selection_score": 80.0'* ]]
}

@test "REVISE applies -15 penalty" {
  run python3 "$SPEC" compute-selection --validator-score 80 --verdict REVISE --tokens 1000 --batch-max-tokens 1000
  [ "$status" -eq 0 ]
  [[ "$output" == *'"selection_score": 65.0'* ]]
}

@test "NO-GO is eliminated (selection_score null)" {
  run python3 "$SPEC" compute-selection --validator-score 80 --verdict NO-GO --tokens 1000 --batch-max-tokens 1000
  [ "$status" -eq 0 ]
  [[ "$output" == *'"selection_score": null'* ]]
  [[ "$output" == *'"eliminated": true'* ]]
}

@test "token efficiency bonus tiebreaker" {
  run python3 "$SPEC" compute-selection --validator-score 80 --verdict GO --tokens 500 --batch-max-tokens 1000
  [ "$status" -eq 0 ]
  [[ "$output" == *'"selection_score": 85.0'* ]]
}
