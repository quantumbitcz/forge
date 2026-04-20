#!/usr/bin/env bats

CACHE="$BATS_TEST_DIRNAME/../../shared/plan-cache.md"

@test "plan-cache doc bumped to v2.0" {
  grep -q 'schema_version.*2.0' "$CACHE"
}

@test "v2 schema documents primary_plan + candidates fields" {
  grep -q "primary_plan" "$CACHE"
  grep -q "candidates" "$CACHE"
  grep -q "speculation_used" "$CACHE"
}

@test "v1 entries rejected with schema mismatch note" {
  grep -q "schema mismatch" "$CACHE" || grep -q "v1.*invalidated" "$CACHE"
}

@test "non-speculative runs omit candidates array" {
  grep -q "speculation_used: false" "$CACHE" || grep -q '"speculation_used": false' "$CACHE"
}
