#!/usr/bin/env bats

@test "pagerank-sql.md exists with algorithm description" {
  local f="${BATS_TEST_DIRNAME}/../../shared/graph/pagerank-sql.md"
  [ -f "$f" ]
  grep -q "damping" "$f"
  grep -q "0\.85" "$f"
  grep -q "recency_multiplier" "$f"
  grep -q "keyword_overlap" "$f"
}

@test "pagerank-sql.md lists all 7 edge-type weights" {
  local f="${BATS_TEST_DIRNAME}/../../shared/graph/pagerank-sql.md"
  for w in CALLS REFERENCES IMPORTS INHERITS IMPLEMENTS TESTS CONTAINS; do
    grep -q "$w" "$f"
  done
}

@test "pagerank-sql.md documents bypass event taxonomy" {
  local f="${BATS_TEST_DIRNAME}/../../shared/graph/pagerank-sql.md"
  grep -q "sparse_graph" "$f"
  grep -q "missing_graph" "$f"
  grep -q "solve_diverged" "$f"
  grep -q "corrupt_cache" "$f"
}
