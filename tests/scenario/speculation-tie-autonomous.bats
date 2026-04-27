#!/usr/bin/env bats

# Covers:

SPEC="$BATS_TEST_DIRNAME/../../hooks/_py/speculation.py"

@test "tie within threshold (autonomous) -> auto-pick top-1 with AUTO reasoning" {
  run python3 "$SPEC" pick-winner --auto-pick-threshold-delta 5 --mode autonomous \
    --candidate 'cand-1:GO:85:4000' --candidate 'cand-2:GO:82:4000'
  [ "$status" -eq 0 ]
  [[ "$output" == *'"winner_id": "cand-1"'* ]]
  [[ "$output" == *'"needs_confirmation": false'* ]]
  [[ "$output" == *'"reasoning": "tie_autonomous_auto_pick"'* ]]
}
