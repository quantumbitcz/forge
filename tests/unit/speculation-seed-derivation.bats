#!/usr/bin/env bats

setup() { SPEC="$BATS_TEST_DIRNAME/../../hooks/_py/speculation.py"; }

@test "derive-seed is deterministic" {
  a=$(python3 "$SPEC" derive-seed --run-id abc --candidate-id cand-1)
  b=$(python3 "$SPEC" derive-seed --run-id abc --candidate-id cand-1)
  [ "$a" = "$b" ]
}

@test "derive-seed differs by candidate-id" {
  a=$(python3 "$SPEC" derive-seed --run-id abc --candidate-id cand-1)
  b=$(python3 "$SPEC" derive-seed --run-id abc --candidate-id cand-2)
  [ "$a" != "$b" ]
}

@test "derive-seed fits in int32" {
  s=$(python3 "$SPEC" derive-seed --run-id x --candidate-id y)
  [ "$s" -ge 0 ]
  [ "$s" -lt 2147483648 ]
}
