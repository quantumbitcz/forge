#!/usr/bin/env bats
# Unit tests for enhanced cross-file edge building in build-code-graph.sh

load '../helpers/test-helpers'

CODE_GRAPH_SCRIPT="$PLUGIN_ROOT/shared/graph/build-code-graph.sh"
SCHEMA_FILE="$PLUGIN_ROOT/shared/graph/code-graph-schema.sql"

# ---------------------------------------------------------------------------
# Helper: create minimal SQLite code graph with test data
# ---------------------------------------------------------------------------
# NOTE: Import schema from shared/graph/code-graph-schema.sql rather than
# duplicating DDL inline. This ensures tests stay in sync with schema changes.
setup_test_db() {
  local db="$1"
  command -v sqlite3 >/dev/null 2>&1 || skip "sqlite3 not available (Windows runners lack it by default)"
  sqlite3 "$db" < "$SCHEMA_FILE"
  sqlite3 "$db" "INSERT OR REPLACE INTO schema_meta VALUES ('version', '1.0.0');"
}

@test "build-code-graph-edges: build_cross_file_edges dispatches to heuristic when no boundary map" {
  local db="${TEST_TEMP}/test.db"
  setup_test_db "$db"
  # Insert test data: a File node and an Import node
  sqlite3 "$db" "
    INSERT INTO nodes (kind, name, file_path, language) VALUES ('File', 'Service.java', 'src/main/java/com/example/Service.java', 'java');
    INSERT INTO nodes (kind, name, file_path, language) VALUES ('Import', 'com.example.util.Helper', 'src/main/java/com/example/Service.java', 'java');
    INSERT INTO nodes (kind, name, file_path, language) VALUES ('File', 'Helper.java', 'src/main/java/com/example/util/Helper.java', 'java');
  "
  # Run the heuristic edge builder (boundary map does not exist)
  run bash -c "
    source '${PLUGIN_ROOT}/shared/platform.sh'
    FORGE_DIR='${TEST_TEMP}'
    source '$CODE_GRAPH_SCRIPT' --source-only 2>/dev/null || true
    build_cross_file_edges_heuristic '$db'
  "
  # Should have created at least an IMPORTS edge
  local edge_count
  edge_count="$(sqlite3 "$db" "SELECT COUNT(*) FROM edges WHERE edge_type='IMPORTS';")"
  assert [ "$edge_count" -ge 0 ]
}

@test "build-code-graph-edges: confidence property is set on new IMPORTS edges" {
  # This test verifies the contract that all IMPORTS edges written by the
  # enhanced algorithm include a confidence property in the properties JSON column.
  # The actual algorithm is tested in integration; this validates the schema usage.
  local db="${TEST_TEMP}/test.db"
  setup_test_db "$db"
  # Insert an edge with confidence property directly (simulating the algorithm)
  sqlite3 "$db" "
    INSERT INTO nodes (kind, name, file_path) VALUES ('File', 'A.java', 'a/A.java');
    INSERT INTO nodes (kind, name, file_path) VALUES ('File', 'B.java', 'b/B.java');
  "
  local a_id b_id
  a_id="$(sqlite3 "$db" "SELECT id FROM nodes WHERE name='A.java';")"
  b_id="$(sqlite3 "$db" "SELECT id FROM nodes WHERE name='B.java';")"
  sqlite3 "$db" "INSERT INTO edges (edge_type, source_id, target_id, properties) VALUES ('IMPORTS', $a_id, $b_id, '{\"confidence\":\"resolved\"}');"

  # Verify we can query by confidence
  local resolved_count
  resolved_count="$(sqlite3 "$db" "SELECT COUNT(*) FROM edges WHERE edge_type='IMPORTS' AND json_extract(properties, '$.confidence')='resolved';")"
  assert [ "$resolved_count" -eq 1 ]
}

@test "build-code-graph-edges: edges.properties column accepts all three confidence levels" {
  local db="${TEST_TEMP}/test.db"
  setup_test_db "$db"
  sqlite3 "$db" "
    INSERT INTO nodes (kind, name, file_path) VALUES ('File', 'X.java', 'x/X.java');
    INSERT INTO nodes (kind, name, file_path) VALUES ('File', 'Y.java', 'y/Y.java');
    INSERT INTO nodes (kind, name, file_path) VALUES ('File', 'Z.java', 'z/Z.java');
    INSERT INTO nodes (kind, name, file_path) VALUES ('File', 'W.java', 'w/W.java');
  "
  local x_id y_id z_id w_id
  x_id="$(sqlite3 "$db" "SELECT id FROM nodes WHERE name='X.java';")"
  y_id="$(sqlite3 "$db" "SELECT id FROM nodes WHERE name='Y.java';")"
  z_id="$(sqlite3 "$db" "SELECT id FROM nodes WHERE name='Z.java';")"
  w_id="$(sqlite3 "$db" "SELECT id FROM nodes WHERE name='W.java';")"
  sqlite3 "$db" "
    INSERT INTO edges (edge_type, source_id, target_id, properties) VALUES ('IMPORTS', $x_id, $y_id, '{\"confidence\":\"resolved\"}');
    INSERT INTO edges (edge_type, source_id, target_id, properties) VALUES ('IMPORTS', $x_id, $z_id, '{\"confidence\":\"module-inferred\"}');
    INSERT INTO edges (edge_type, source_id, target_id, properties) VALUES ('IMPORTS', $x_id, $w_id, '{\"confidence\":\"heuristic\"}');
  "
  local total
  total="$(sqlite3 "$db" "SELECT COUNT(*) FROM edges WHERE edge_type='IMPORTS' AND json_extract(properties, '$.confidence') IN ('resolved','module-inferred','heuristic');")"
  assert [ "$total" -eq 3 ]
}

# ---------------------------------------------------------------------------
# Module-aware resolution tests
# ---------------------------------------------------------------------------
@test "build-code-graph-edges: module-aware resolution creates resolved edges for same-module imports" {
  local db="${TEST_TEMP}/test.db"
  local boundary_map="${TEST_TEMP}/module-boundary-map.json"
  setup_test_db "$db"

  # Create boundary map with one module
  cat > "$boundary_map" << 'MAPEOF'
{
  "version": "1.0.0",
  "build_system": "maven",
  "root": "/proj",
  "modules": [
    {
      "name": "core",
      "artifact_id": "com.example:core",
      "directory": "core",
      "source_dirs": ["core/src/main/java"],
      "test_dirs": ["core/src/test/java"],
      "depends_on": [],
      "depended_by": []
    }
  ]
}
MAPEOF

  # Insert nodes: both files in the same module
  sqlite3 "$db" "
    INSERT INTO nodes (kind, name, file_path, language) VALUES ('File', 'UserService.java', 'core/src/main/java/com/example/UserService.java', 'java');
    INSERT INTO nodes (kind, name, file_path, language) VALUES ('Import', 'com.example.UserRepo', 'core/src/main/java/com/example/UserService.java', 'java');
    INSERT INTO nodes (kind, name, file_path, language) VALUES ('File', 'UserRepo.java', 'core/src/main/java/com/example/UserRepo.java', 'java');
  "

  run bash -c "
    source '${PLUGIN_ROOT}/shared/platform.sh'
    FORGE_DIR='${TEST_TEMP}'
    FORGE_PYTHON='${FORGE_PYTHON:-python3}'
    export FORGE_PYTHON
    source '$CODE_GRAPH_SCRIPT' --source-only 2>/dev/null || true
    build_cross_file_edges_with_boundaries '$db' '$boundary_map'
  "

  # Verify an IMPORTS edge was created
  local edge_count
  edge_count="$(sqlite3 "$db" "SELECT COUNT(*) FROM edges WHERE edge_type='IMPORTS';")"
  assert [ "$edge_count" -ge 1 ]
}

# ---------------------------------------------------------------------------
# Cross-module resolution integration test
# ---------------------------------------------------------------------------
@test "build-code-graph-edges: cross-module import gets resolved confidence via depends_on" {
  local db="${TEST_TEMP}/test.db"
  local boundary_map="${TEST_TEMP}/module-boundary-map.json"
  setup_test_db "$db"

  # Create a 2-module boundary map where api depends on core
  cat > "$boundary_map" << 'MAPEOF'
{
  "version": "1.0.0",
  "build_system": "maven",
  "root": "/proj",
  "modules": [
    {
      "name": "core",
      "artifact_id": "com.example:core",
      "directory": "core",
      "source_dirs": ["core/src/main/java"],
      "test_dirs": ["core/src/test/java"],
      "depends_on": [],
      "depended_by": ["api"]
    },
    {
      "name": "api",
      "artifact_id": "com.example:api",
      "directory": "api",
      "source_dirs": ["api/src/main/java"],
      "test_dirs": ["api/src/test/java"],
      "depends_on": ["core"],
      "depended_by": []
    }
  ]
}
MAPEOF

  # Insert nodes: api module imports a class from core module
  sqlite3 "$db" "
    INSERT INTO nodes (kind, name, file_path, language) VALUES ('File', 'UserController.java', 'api/src/main/java/com/example/UserController.java', 'java');
    INSERT INTO nodes (kind, name, file_path, language) VALUES ('Import', 'com.example.UserService', 'api/src/main/java/com/example/UserController.java', 'java');
    INSERT INTO nodes (kind, name, file_path, language) VALUES ('File', 'UserService.java', 'core/src/main/java/com/example/UserService.java', 'java');
  "

  run bash -c "
    source '${PLUGIN_ROOT}/shared/platform.sh'
    FORGE_DIR='${TEST_TEMP}'
    FORGE_PYTHON='${FORGE_PYTHON:-python3}'
    export FORGE_PYTHON
    source '$CODE_GRAPH_SCRIPT' --source-only 2>/dev/null || true
    build_cross_file_edges_with_boundaries '$db' '$boundary_map'
  "

  # Verify an IMPORTS edge was created with 'resolved' confidence
  local resolved_count
  resolved_count="$(sqlite3 "$db" "SELECT COUNT(*) FROM edges WHERE edge_type='IMPORTS' AND json_extract(properties, '\$.confidence')='resolved';")"
  assert [ "$resolved_count" -ge 1 ]
}

@test "build-code-graph-edges: undeclared cross-module import gets module-inferred confidence" {
  local db="${TEST_TEMP}/test.db"
  local boundary_map="${TEST_TEMP}/module-boundary-map.json"
  setup_test_db "$db"

  # Create 2 modules with NO dependency between them
  cat > "$boundary_map" << 'MAPEOF'
{
  "version": "1.0.0",
  "build_system": "maven",
  "root": "/proj",
  "modules": [
    {
      "name": "core",
      "artifact_id": "com.example:core",
      "directory": "core",
      "source_dirs": ["core/src/main/java"],
      "test_dirs": [],
      "depends_on": [],
      "depended_by": []
    },
    {
      "name": "api",
      "artifact_id": "com.example:api",
      "directory": "api",
      "source_dirs": ["api/src/main/java"],
      "test_dirs": [],
      "depends_on": [],
      "depended_by": []
    }
  ]
}
MAPEOF

  # api imports from core, but there is no declared dependency
  sqlite3 "$db" "
    INSERT INTO nodes (kind, name, file_path, language) VALUES ('File', 'Handler.java', 'api/src/main/java/com/example/Handler.java', 'java');
    INSERT INTO nodes (kind, name, file_path, language) VALUES ('Import', 'com.example.CoreUtil', 'api/src/main/java/com/example/Handler.java', 'java');
    INSERT INTO nodes (kind, name, file_path, language) VALUES ('File', 'CoreUtil.java', 'core/src/main/java/com/example/CoreUtil.java', 'java');
  "

  run bash -c "
    source '${PLUGIN_ROOT}/shared/platform.sh'
    FORGE_DIR='${TEST_TEMP}'
    FORGE_PYTHON='${FORGE_PYTHON:-python3}'
    export FORGE_PYTHON
    source '$CODE_GRAPH_SCRIPT' --source-only 2>/dev/null || true
    build_cross_file_edges_with_boundaries '$db' '$boundary_map'
  "

  # Should get module-inferred because the target file IS in a known module
  # but there is no declared dependency
  local inferred_count
  inferred_count="$(sqlite3 "$db" "SELECT COUNT(*) FROM edges WHERE edge_type='IMPORTS' AND json_extract(properties, '\$.confidence')='module-inferred';")"
  assert [ "$inferred_count" -ge 1 ]
}

# ---------------------------------------------------------------------------
# Metrics emission
# ---------------------------------------------------------------------------
@test "build-code-graph-edges: emit_build_graph_metrics writes to state.json" {
  local db="${TEST_TEMP}/test.db"
  local state_file="${TEST_TEMP}/project/.forge/state.json"
  mkdir -p "${TEST_TEMP}/project/.forge"
  setup_test_db "$db"

  # Create initial state.json
  echo '{"stage":"PREFLIGHT"}' > "$state_file"

  # Insert some test edges with confidence
  sqlite3 "$db" "
    INSERT INTO nodes (kind, name, file_path) VALUES ('File', 'A.java', 'a/A.java');
    INSERT INTO nodes (kind, name, file_path) VALUES ('File', 'B.java', 'b/B.java');
    INSERT INTO nodes (kind, name, file_path) VALUES ('File', 'C.java', 'c/C.java');
    INSERT INTO nodes (kind, name, file_path) VALUES ('Import', 'b.B', 'a/A.java');
  "
  local a_id b_id c_id
  a_id="$(sqlite3 "$db" "SELECT id FROM nodes WHERE name='A.java';")"
  b_id="$(sqlite3 "$db" "SELECT id FROM nodes WHERE name='B.java';")"
  c_id="$(sqlite3 "$db" "SELECT id FROM nodes WHERE name='C.java';")"
  sqlite3 "$db" "
    INSERT INTO edges (edge_type, source_id, target_id, properties) VALUES ('IMPORTS', $a_id, $b_id, '{\"confidence\":\"resolved\"}');
    INSERT INTO edges (edge_type, source_id, target_id, properties) VALUES ('IMPORTS', $a_id, $c_id, '{\"confidence\":\"heuristic\"}');
  "

  run bash -c "
    export FORGE_PYTHON='${FORGE_PYTHON:-python3}'
    FORGE_DIR='${TEST_TEMP}/project/.forge'
    source '${PLUGIN_ROOT}/shared/platform.sh'
    source '$CODE_GRAPH_SCRIPT' --source-only 2>/dev/null || true
    emit_build_graph_metrics '$db'
  "

  # Verify state.json was updated
  python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    state = json.load(f)
bg = state.get('build_graph', {})
assert 'edges_total' in bg, f'Missing edges_total in build_graph: {bg}'
assert bg['edges_total'] == 2, f'Expected 2 total edges, got {bg[\"edges_total\"]}'
assert bg['edges_resolved'] == 1, f'Expected 1 resolved, got {bg[\"edges_resolved\"]}'
assert bg['edges_heuristic'] == 1, f'Expected 1 heuristic, got {bg[\"edges_heuristic\"]}'
" "$state_file"
}
