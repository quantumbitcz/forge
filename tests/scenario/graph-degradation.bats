#!/usr/bin/env bats
# Scenario tests: graceful degradation of shared/graph/* scripts

load '../helpers/test-helpers'

HEALTH_CHECK="$PLUGIN_ROOT/shared/graph/neo4j-health.sh"
INCREMENTAL_UPDATE="$PLUGIN_ROOT/shared/graph/incremental-update.sh"
GENERATE_SEED="$PLUGIN_ROOT/shared/graph/generate-seed.sh"

setup() {
  TEST_TEMP="$(mktemp -d "${TMPDIR:-/tmp}/bats-graph-degradation.XXXXXX")"
  MOCK_BIN="$TEST_TEMP/mock-bin"
  mkdir -p "$MOCK_BIN"
  export PATH="$MOCK_BIN:$PATH"
  mkdir -p "$TEST_TEMP/project"
}

teardown() { rm -rf "$TEST_TEMP"; }

# ---------------------------------------------------------------------------
# 1. neo4j-health.sh returns available:false when no container running
# ---------------------------------------------------------------------------
@test "neo4j-health: returns available:false and exits 1 when no container running" {
  # Mock docker to report unavailable (covers both "docker not available"
  # and "container not running" graceful degradation paths)
  mock_command "docker" 'echo "Cannot connect to the Docker daemon" >&2; exit 1'

  run bash "$HEALTH_CHECK"

  assert_failure
  assert_output --partial '"available": false'
}

# ---------------------------------------------------------------------------
# 2. incremental-update.sh falls back gracefully when no prior build exists
# ---------------------------------------------------------------------------
@test "incremental-update: falls back gracefully when no .last-build-sha exists" {
  local proj="$TEST_TEMP/project"

  # Initialise a minimal git repo with one committed source file
  git -C "$proj" init -q
  git -C "$proj" config user.email "test@example.com"
  git -C "$proj" config user.name "Test"
  printf 'fun main() {}\n' > "$proj/main.kt"
  git -C "$proj" add .
  git -C "$proj" commit -q -m "init"

  # No .forge/graph/.last-build-sha exists → script must not hard-fail
  run bash "$INCREMENTAL_UPDATE" --project-root "$proj"

  # Exit 0 is expected whether it falls back to a full build or emits a comment
  assert_success

  # Output must contain either a Cypher comment (graceful message) or a CREATE
  # statement (full rebuild path) — either proves the script didn't just crash
  [[ "$output" == *"//"* || "$output" == *"CREATE"* ]]
}

# ---------------------------------------------------------------------------
# 3. generate-seed.sh works without Neo4j (--dry-run emits valid Cypher)
# ---------------------------------------------------------------------------
@test "generate-seed: --dry-run produces valid Cypher output without Neo4j" {
  run bash "$GENERATE_SEED" --dry-run

  assert_success
  assert_output --partial 'CREATE'
}
