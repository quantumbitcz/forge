#!/usr/bin/env bats

# Covers:

SPEC="$BATS_TEST_DIRNAME/../../hooks/_py/speculation.py"

@test "tie within threshold (interactive) -> needs_confirmation true" {
  run python3 "$SPEC" pick-winner --auto-pick-threshold-delta 5 --mode interactive \
    --candidate 'cand-1:GO:85:4000' --candidate 'cand-2:GO:82:4000'
  [ "$status" -eq 0 ]
  [[ "$output" == *'"needs_confirmation": true'* ]]
  [[ "$output" == *'"reasoning": "tie_interactive_ask_user"'* ]]
}
