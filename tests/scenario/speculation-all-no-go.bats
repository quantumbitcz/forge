#!/usr/bin/env bats

# Covers:

SPEC="$BATS_TEST_DIRNAME/../../hooks/_py/speculation.py"

@test "all NO-GO -> escalate all_no_go, no winner" {
  run python3 "$SPEC" pick-winner --auto-pick-threshold-delta 5 --mode autonomous \
    --candidate 'cand-1:NO-GO:40:4000' --candidate 'cand-2:NO-GO:45:4000' --candidate 'cand-3:NO-GO:30:4000'
  [ "$status" -eq 0 ]
  [[ "$output" == *'"winner_id": null'* ]]
  [[ "$output" == *'"escalate": "all_no_go"'* ]]
}
