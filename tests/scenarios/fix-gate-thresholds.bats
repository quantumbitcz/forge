#!/usr/bin/env bats
# AC-DEBUG-004: fix gate cases at posteriors 0.49 / 0.74 / 0.76 / 0.95
# against default threshold 0.75 (only last two pass) and threshold 0.50
# (also 0.74 passes).
load '../helpers/test-helpers'

gate() {
  local posterior=$1 threshold=$2
  python3 -c "
posterior=$posterior
threshold=$threshold
passes_test=True
passed = passes_test and posterior >= threshold
print('true' if passed else 'false')
"
}

@test "posterior 0.49 with default threshold 0.75 -> false" {
  run gate 0.49 0.75
  assert_output 'false'
}

@test "posterior 0.74 with default threshold 0.75 -> false" {
  run gate 0.74 0.75
  assert_output 'false'
}

@test "posterior 0.76 with default threshold 0.75 -> true" {
  run gate 0.76 0.75
  assert_output 'true'
}

@test "posterior 0.95 with default threshold 0.75 -> true" {
  run gate 0.95 0.75
  assert_output 'true'
}

@test "posterior 0.74 with threshold 0.50 -> true" {
  run gate 0.74 0.50
  assert_output 'true'
}

@test "posterior 0.49 with threshold 0.50 -> false" {
  run gate 0.49 0.50
  assert_output 'false'
}
