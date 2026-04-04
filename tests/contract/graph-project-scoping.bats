#!/usr/bin/env bats
# Contract tests: graph scripts scope operations by project_id.

load '../helpers/test-helpers'

GRAPH_DIR="$PLUGIN_ROOT/shared/graph"

# ---------------------------------------------------------------------------
# 1. build-project-graph.sh accepts --project-id parameter
# ---------------------------------------------------------------------------
@test "graph-project-scoping: build-project-graph.sh accepts --project-id" {
  grep -q '\-\-project-id' "$GRAPH_DIR/build-project-graph.sh"
}

# ---------------------------------------------------------------------------
# 2. build-project-graph.sh scoped DELETE uses project_id
# ---------------------------------------------------------------------------
@test "graph-project-scoping: build-project-graph.sh DELETE scoped by project_id" {
  if grep -q 'DETACH DELETE' "$GRAPH_DIR/build-project-graph.sh"; then
    local unscoped
    unscoped=$(grep 'DETACH DELETE' "$GRAPH_DIR/build-project-graph.sh" | grep -v 'project_id' || true)
    if [[ -n "$unscoped" ]]; then
      fail "build-project-graph.sh has unscoped DETACH DELETE: $unscoped"
    fi
  fi
}

# ---------------------------------------------------------------------------
# 3. build-project-graph.sh CREATE statements include project_id
# ---------------------------------------------------------------------------
@test "graph-project-scoping: build-project-graph.sh CREATE includes project_id" {
  local creates
  creates=$(grep -c 'CREATE.*Project.*project_id' "$GRAPH_DIR/build-project-graph.sh" || true)
  [[ "$creates" -gt 0 ]]
}

# ---------------------------------------------------------------------------
# 4. build-project-graph.sh accepts --component parameter
# ---------------------------------------------------------------------------
@test "graph-project-scoping: build-project-graph.sh accepts --component" {
  grep -q '\-\-component' "$GRAPH_DIR/build-project-graph.sh"
}

# ---------------------------------------------------------------------------
# 5. enrich-symbols.sh includes project_id in MERGE statements
# ---------------------------------------------------------------------------
@test "graph-project-scoping: enrich-symbols.sh MERGE includes project_id" {
  local merges
  merges=$(grep -c 'MERGE.*project_id' "$GRAPH_DIR/enrich-symbols.sh" || true)
  [[ "$merges" -gt 0 ]]
}

# ---------------------------------------------------------------------------
# 6. query-patterns.md: all Project* queries include project_id filter
# ---------------------------------------------------------------------------
@test "graph-project-scoping: all project queries in query-patterns.md use project_id" {
  local matches
  matches=$(grep -E 'MATCH.*\(.*:(Project|Doc)\w+' "$GRAPH_DIR/query-patterns.md" || true)
  if [[ -z "$matches" ]]; then
    skip "No project node matches found"
  fi
  local unscoped
  unscoped=$(echo "$matches" | grep -v 'project_id' | grep -v 'seed' | grep -v '^--' || true)
  if [[ -n "$unscoped" ]]; then
    fail "Unscoped project queries in query-patterns.md: $unscoped"
  fi
}

# ---------------------------------------------------------------------------
# 7. update-project-graph.sh exists and accepts --project-id
# ---------------------------------------------------------------------------
@test "graph-project-scoping: update-project-graph.sh exists" {
  [[ -f "$GRAPH_DIR/update-project-graph.sh" ]]
}

@test "graph-project-scoping: update-project-graph.sh accepts --project-id" {
  grep -q '\-\-project-id' "$GRAPH_DIR/update-project-graph.sh"
}

# ---------------------------------------------------------------------------
# 8. generate-seed.sh does NOT use project_id (seed is global)
# ---------------------------------------------------------------------------
@test "graph-project-scoping: generate-seed.sh does not use project_id" {
  ! grep -q 'project_id' "$GRAPH_DIR/generate-seed.sh"
}
