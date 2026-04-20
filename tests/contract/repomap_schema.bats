#!/usr/bin/env bats

load "${BATS_TEST_DIRNAME}/../lib/bats-support/load"
load "${BATS_TEST_DIRNAME}/../lib/bats-assert/load"

@test "code-graph-schema.sql declares ranked_files_cache with 4-col PK" {
  grep -q "CREATE TABLE.*ranked_files_cache" "${BATS_TEST_DIRNAME}/../../shared/graph/code-graph-schema.sql"
  grep -q "PRIMARY KEY *( *graph_sha *, *keywords_hash *, *budget *, *top_k *)" \
    "${BATS_TEST_DIRNAME}/../../shared/graph/code-graph-schema.sql"
}

@test "code-graph-schema.sql declares idx_nodes_last_modified" {
  grep -q "CREATE INDEX.*idx_nodes_last_modified" \
    "${BATS_TEST_DIRNAME}/../../shared/graph/code-graph-schema.sql"
}

@test "code-graph-schema.sql version bumped to 1.1.0" {
  grep -q "schema_version.*1\.1\.0" \
    "${BATS_TEST_DIRNAME}/../../shared/graph/code-graph-schema.sql"
}

@test "schema applies cleanly in a fresh sqlite DB" {
  local tmpdb="$(mktemp -u).db"
  sqlite3 "$tmpdb" < "${BATS_TEST_DIRNAME}/../../shared/graph/code-graph-schema.sql"
  run sqlite3 "$tmpdb" ".schema ranked_files_cache"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ranked_files_cache"* ]]
  rm -f "$tmpdb"
}
