#!/usr/bin/env bats

setup() { SPEC="$BATS_TEST_DIRNAME/../../hooks/_py/speculation.py"; }

@test "pick-winner auto-picks when delta > threshold" {
  run python3 "$SPEC" pick-winner --auto-pick-threshold-delta 5 --mode interactive --candidate 'cand-1:GO:85:4000' --candidate 'cand-2:GO:75:4000'
  [ "$status" -eq 0 ]
  [[ "$output" == *'"winner_id": "cand-1"'* ]]
  [[ "$output" == *'"needs_confirmation": false'* ]]
}

@test "pick-winner asks user on tie (interactive)" {
  run python3 "$SPEC" pick-winner --auto-pick-threshold-delta 5 --mode interactive --candidate 'cand-1:GO:85:4000' --candidate 'cand-2:GO:82:4000'
  [ "$status" -eq 0 ]
  [[ "$output" == *'"needs_confirmation": true'* ]]
}

@test "pick-winner auto-picks on tie (autonomous)" {
  run python3 "$SPEC" pick-winner --auto-pick-threshold-delta 5 --mode autonomous --candidate 'cand-1:GO:85:4000' --candidate 'cand-2:GO:82:4000'
  [ "$status" -eq 0 ]
  [[ "$output" == *'"winner_id": "cand-1"'* ]]
  [[ "$output" == *'"needs_confirmation": false'* ]]
  [[ "$output" == *'"mode": "autonomous"'* ]]
}

@test "pick-winner surfaces all-NO-GO escalation" {
  run python3 "$SPEC" pick-winner --auto-pick-threshold-delta 5 --mode autonomous --candidate 'cand-1:NO-GO:40:4000' --candidate 'cand-2:NO-GO:45:4000' --candidate 'cand-3:NO-GO:30:4000'
  [ "$status" -eq 0 ]
  [[ "$output" == *'"winner_id": null'* ]]
  [[ "$output" == *'"escalate": "all_no_go"'* ]]
}

@test "pick-winner surfaces all-FAIL escalation when all < 60" {
  run python3 "$SPEC" pick-winner --auto-pick-threshold-delta 5 --mode autonomous --candidate 'cand-1:GO:55:4000' --candidate 'cand-2:GO:50:4000'
  [ "$status" -eq 0 ]
  [[ "$output" == *'"escalate": "all_below_60"'* ]]
}
