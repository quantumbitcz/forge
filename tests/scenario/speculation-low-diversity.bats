#!/usr/bin/env bats

# Covers:

setup() {
  SPEC="$BATS_TEST_DIRNAME/../../hooks/_py/speculation.py"
  TMP=$(mktemp -d)
  printf 'implement feature using adapter pattern with caching layer' > "$TMP/p1.md"
  printf 'implement feature using adapter pattern with caching layer' > "$TMP/p2.md"
  printf 'implement feature using adapter pattern with caching layer' > "$TMP/p3.md"
}
teardown() { rm -rf "$TMP"; }

@test "identical plans trigger degraded=true with low_diversity reason" {
  run python3 "$SPEC" check-diversity --plan "$TMP/p1.md" --plan "$TMP/p2.md" --plan "$TMP/p3.md" --min-diversity-score 0.15
  [ "$status" -eq 0 ]
  [[ "$output" == *'"degraded": true'* ]]
  [[ "$output" == *'"max_pairwise_overlap": 1.0'* ]]
}
