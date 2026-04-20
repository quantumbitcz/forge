#!/usr/bin/env bats

setup() {
  SPEC="$BATS_TEST_DIRNAME/../../hooks/_py/speculation.py"
  TMP=$(mktemp -d)
  printf 'plan content alpha beta gamma delta epsilon zeta' > "$TMP/p1.md"
  printf 'plan content alpha beta gamma delta epsilon zeta' > "$TMP/p2.md"
  printf 'wholly different plan focused on optional other path' > "$TMP/p3.md"
}

teardown() { rm -rf "$TMP"; }

@test "identical plans -> diversity 0, degraded true" {
  run python3 "$SPEC" check-diversity --plan "$TMP/p1.md" --plan "$TMP/p2.md" --min-diversity-score 0.15
  [ "$status" -eq 0 ]
  [[ "$output" == *'"diversity": 0'* ]]
  [[ "$output" == *'"degraded": true'* ]]
}

@test "distinct plans -> diversity > 0.15, degraded false" {
  run python3 "$SPEC" check-diversity --plan "$TMP/p1.md" --plan "$TMP/p3.md" --min-diversity-score 0.15
  [ "$status" -eq 0 ]
  [[ "$output" == *'"degraded": false'* ]]
}

@test "three plans: two identical + one distinct -> max pairwise overlap dominates" {
  run python3 "$SPEC" check-diversity --plan "$TMP/p1.md" --plan "$TMP/p2.md" --plan "$TMP/p3.md" --min-diversity-score 0.15
  [ "$status" -eq 0 ]
  [[ "$output" == *'"degraded": true'* ]]
}

@test "diversity threshold configurable" {
  run python3 "$SPEC" check-diversity --plan "$TMP/p1.md" --plan "$TMP/p3.md" --min-diversity-score 0.99
  [ "$status" -eq 0 ]
  [[ "$output" == *'"degraded": true'* ]]
}
