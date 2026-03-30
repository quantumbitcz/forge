#!/usr/bin/env bats
# Scenario: Edge case handling for pipeline operations.

load '../helpers/test-helpers'

setup() {
  TMPWORK="$(mktemp -d "${TMPDIR:-/tmp}/bats-edge.XXXXXX")"
}

teardown() {
  rm -rf "$TMPWORK"
}

# ---------------------------------------------------------------------------
# 1. Engine handles empty files-changed list gracefully
# ---------------------------------------------------------------------------
@test "edge-case: engine --verify with no files returns success" {
  run "$PLUGIN_ROOT/shared/checks/engine.sh" --verify --project-root "$TMPWORK" --files-changed
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# 2. Engine handles non-existent file path gracefully
# ---------------------------------------------------------------------------
@test "edge-case: engine --verify with non-existent file returns success" {
  run "$PLUGIN_ROOT/shared/checks/engine.sh" --verify --project-root "$TMPWORK" --files-changed "$TMPWORK/does-not-exist.kt"
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# 3. Neo4j health check returns gracefully when docker unavailable
# ---------------------------------------------------------------------------
@test "edge-case: neo4j-health handles missing docker" {
  # Create a mock PATH without docker
  local mock_bin="$TMPWORK/mock-bin"
  mkdir -p "$mock_bin"
  # Only include basic commands, not docker
  ln -sf "$(command -v bash)" "$mock_bin/bash"
  ln -sf "$(command -v echo)" "$mock_bin/echo"

  PATH="$mock_bin" run "$PLUGIN_ROOT/shared/graph/neo4j-health.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *'"available": false'* ]]
}

# ---------------------------------------------------------------------------
# 4. Component cache handles empty cache file
# ---------------------------------------------------------------------------
@test "edge-case: engine handles empty component cache" {
  mkdir -p "$TMPWORK/.pipeline"
  touch "$TMPWORK/.pipeline/.component-cache"

  # Create a dummy source file
  echo "fun main() {}" > "$TMPWORK/test.kt"

  TOOL_INPUT='{"file_path":"'"$TMPWORK/test.kt"'"}' run "$PLUGIN_ROOT/shared/checks/engine.sh" --hook
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# 5. Component cache handles malformed entries
# ---------------------------------------------------------------------------
@test "edge-case: engine handles malformed component cache entries" {
  mkdir -p "$TMPWORK/.pipeline"
  printf '=component\nprefix=\n\n# comment line\nvalid=spring\n' > "$TMPWORK/.pipeline/.component-cache"

  mkdir -p "$TMPWORK/valid"
  echo "fun main() {}" > "$TMPWORK/valid/test.kt"

  TOOL_INPUT='{"file_path":"'"$TMPWORK/valid/test.kt"'"}' run "$PLUGIN_ROOT/shared/checks/engine.sh" --hook
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# 6. Discover projects handles non-git directory
# ---------------------------------------------------------------------------
@test "edge-case: discover-projects handles non-git directory" {
  mkdir -p "$TMPWORK/not-a-repo"
  run "$PLUGIN_ROOT/shared/discovery/discover-projects.sh" "$TMPWORK/not-a-repo"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[]"* ]]
}

# ---------------------------------------------------------------------------
# 7. Depth validation clamps negative values
# ---------------------------------------------------------------------------
@test "edge-case: discover-projects clamps negative depth" {
  mkdir -p "$TMPWORK/repo"
  cd "$TMPWORK/repo" && git init -q
  run "$PLUGIN_ROOT/shared/discovery/discover-projects.sh" "$TMPWORK/repo" --depth -5
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# 8. Platform detection returns known value
# ---------------------------------------------------------------------------
@test "edge-case: platform.sh detects a known OS" {
  source "$PLUGIN_ROOT/shared/platform.sh"
  [[ "$PIPELINE_OS" == "darwin" || "$PIPELINE_OS" == "linux" || "$PIPELINE_OS" == "windows" || "$PIPELINE_OS" == "unknown" ]]
}
