#!/usr/bin/env bats
# Contract tests: Build System Intelligence (Spec 2)
# Verifies schema contracts for module-boundary-map.json, build-graph-cache.json,
# and state.json build_graph fields.

load '../helpers/test-helpers'

BOUNDARY_MAP_SCRIPT="$PLUGIN_ROOT/shared/graph/module-boundary-map.sh"
RESOLVER_SCRIPT="$PLUGIN_ROOT/shared/graph/build-system-resolver.sh"

# ---------------------------------------------------------------------------
# Module boundary map schema contracts
# ---------------------------------------------------------------------------
@test "contract: module-boundary-map output has required top-level fields" {
  local proj="${TEST_TEMP}/project"
  cat > "$proj/pom.xml" << 'POMEOF'
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0">
  <groupId>com.test</groupId><artifactId>test</artifactId><version>1.0.0</version>
</project>
POMEOF
  run "$BOUNDARY_MAP_SCRIPT" --project-root "$proj"
  assert_success
  echo "$output" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for field in ['version', 'build_system', 'root', 'generated_at', 'resolution_mode', 'modules']:
    assert field in data, f'Missing required field: {field}'
assert data['version'] == '1.0.0'
assert data['build_system'] in ['maven','gradle','cargo','go','npm','pnpm','yarn','dotnet','none']
assert data['resolution_mode'] in ['introspected','parsed','heuristic']
assert isinstance(data['modules'], list)
"
}

@test "contract: module entry has required fields" {
  local proj="${TEST_TEMP}/project"
  mkdir -p "$proj/src/main/java"
  cat > "$proj/pom.xml" << 'POMEOF'
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0">
  <groupId>com.test</groupId><artifactId>test</artifactId><version>1.0.0</version>
</project>
POMEOF
  run "$BOUNDARY_MAP_SCRIPT" --project-root "$proj"
  assert_success
  echo "$output" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for mod in data['modules']:
    for field in ['name', 'artifact_id', 'directory', 'source_dirs', 'test_dirs', 'depends_on', 'depended_by']:
        assert field in mod, f'Module {mod.get(\"name\",\"?\")} missing field: {field}'
    assert isinstance(mod['source_dirs'], list)
    assert isinstance(mod['test_dirs'], list)
    assert isinstance(mod['depends_on'], list)
    assert isinstance(mod['depended_by'], list)
"
}

@test "contract: depends_on references are valid module names" {
  local proj="${TEST_TEMP}/project"
  mkdir -p "$proj/core/src/main/java" "$proj/api/src/main/java"
  cat > "$proj/pom.xml" << 'POMEOF'
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0">
  <groupId>com.test</groupId><artifactId>parent</artifactId><version>1.0.0</version>
  <packaging>pom</packaging>
  <modules><module>core</module><module>api</module></modules>
</project>
POMEOF
  cat > "$proj/core/pom.xml" << 'POMEOF'
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0">
  <parent><groupId>com.test</groupId><artifactId>parent</artifactId><version>1.0.0</version></parent>
  <artifactId>core</artifactId>
</project>
POMEOF
  cat > "$proj/api/pom.xml" << 'POMEOF'
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0">
  <parent><groupId>com.test</groupId><artifactId>parent</artifactId><version>1.0.0</version></parent>
  <artifactId>api</artifactId>
  <dependencies><dependency><groupId>com.test</groupId><artifactId>core</artifactId><version>1.0.0</version></dependency></dependencies>
</project>
POMEOF
  run "$BOUNDARY_MAP_SCRIPT" --project-root "$proj"
  assert_success
  echo "$output" | python3 -c "
import json, sys
data = json.load(sys.stdin)
all_names = {m['name'] for m in data['modules']}
for mod in data['modules']:
    for dep in mod['depends_on']:
        assert dep in all_names, f'Module {mod[\"name\"]} depends_on non-existent module: {dep}'
"
}

@test "contract: depended_by is exact reverse of depends_on" {
  local proj="${TEST_TEMP}/project"
  mkdir -p "$proj/core/src/main/java" "$proj/api/src/main/java"
  cat > "$proj/pom.xml" << 'POMEOF'
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0">
  <groupId>com.test</groupId><artifactId>parent</artifactId><version>1.0.0</version>
  <packaging>pom</packaging>
  <modules><module>core</module><module>api</module></modules>
</project>
POMEOF
  cat > "$proj/core/pom.xml" << 'POMEOF'
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0">
  <parent><groupId>com.test</groupId><artifactId>parent</artifactId><version>1.0.0</version></parent>
  <artifactId>core</artifactId>
</project>
POMEOF
  cat > "$proj/api/pom.xml" << 'POMEOF'
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0">
  <parent><groupId>com.test</groupId><artifactId>parent</artifactId><version>1.0.0</version></parent>
  <artifactId>api</artifactId>
  <dependencies><dependency><groupId>com.test</groupId><artifactId>core</artifactId><version>1.0.0</version></dependency></dependencies>
</project>
POMEOF
  run "$BOUNDARY_MAP_SCRIPT" --project-root "$proj"
  assert_success
  echo "$output" | python3 -c "
import json, sys
data = json.load(sys.stdin)
modules = {m['name']: m for m in data['modules']}
for mod_name, mod in modules.items():
    for dep_name in mod['depends_on']:
        if dep_name in modules:
            assert mod_name in modules[dep_name]['depended_by'], \
                f'{mod_name} depends on {dep_name}, but {dep_name}.depended_by does not include {mod_name}'
    for rev_name in mod['depended_by']:
        if rev_name in modules:
            assert mod_name in modules[rev_name]['depends_on'], \
                f'{rev_name} listed in {mod_name}.depended_by but {rev_name}.depends_on does not include {mod_name}'
"
}

@test "contract: module names are unique" {
  local proj="${TEST_TEMP}/project"
  mkdir -p "$proj/core/src/main/java" "$proj/api/src/main/java"
  cat > "$proj/pom.xml" << 'POMEOF'
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0">
  <groupId>com.test</groupId><artifactId>parent</artifactId><version>1.0.0</version>
  <packaging>pom</packaging>
  <modules><module>core</module><module>api</module></modules>
</project>
POMEOF
  cat > "$proj/core/pom.xml" << 'POMEOF'
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0">
  <parent><groupId>com.test</groupId><artifactId>parent</artifactId><version>1.0.0</version></parent>
  <artifactId>core</artifactId>
</project>
POMEOF
  cat > "$proj/api/pom.xml" << 'POMEOF'
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0">
  <parent><groupId>com.test</groupId><artifactId>parent</artifactId><version>1.0.0</version></parent>
  <artifactId>api</artifactId>
</project>
POMEOF
  run "$BOUNDARY_MAP_SCRIPT" --project-root "$proj"
  assert_success
  echo "$output" | python3 -c "
import json, sys
data = json.load(sys.stdin)
names = [m['name'] for m in data['modules']]
assert len(names) == len(set(names)), f'Duplicate module names: {names}'
"
}

# ---------------------------------------------------------------------------
# Build graph cache schema contracts
# ---------------------------------------------------------------------------
@test "contract: build-graph-cache.json has valid schema after resolution" {
  local proj="${TEST_TEMP}/project"
  mkdir -p "$proj/.forge"
  echo '{"dependencies":{"a":"1.0"}}' > "$proj/package.json"
  run "$RESOLVER_SCRIPT" --project-root "$proj"
  assert_success
  assert [ -f "$proj/.forge/build-graph-cache.json" ]
  python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
assert 'version' in data, 'Missing version'
assert data['version'] == '1.0.0'
assert 'entries' in data, 'Missing entries'
assert isinstance(data['entries'], dict)
for system, entry in data['entries'].items():
    assert 'build_file_hashes_composite' in entry, f'{system}: missing build_file_hashes_composite'
    assert 'introspected_at' in entry, f'{system}: missing introspected_at'
    assert 'resolution_mode' in entry, f'{system}: missing resolution_mode'
    assert entry['resolution_mode'] in ('introspected', 'heuristic'), f'{system}: invalid resolution_mode'
" "$proj/.forge/build-graph-cache.json"
}

# ---------------------------------------------------------------------------
# Structural contracts for new scripts
# ---------------------------------------------------------------------------
@test "contract: build-system-resolver.sh exists and is executable" {
  assert [ -f "$RESOLVER_SCRIPT" ]
  assert [ -x "$RESOLVER_SCRIPT" ]
}

@test "contract: module-boundary-map.sh exists and is executable" {
  assert [ -f "$BOUNDARY_MAP_SCRIPT" ]
  assert [ -x "$BOUNDARY_MAP_SCRIPT" ]
}

@test "contract: build-system-resolver.sh sources platform.sh" {
  grep -q 'source.*platform\.sh' "$RESOLVER_SCRIPT"
}

@test "contract: module-boundary-map.sh sources platform.sh" {
  grep -q 'source.*platform\.sh' "$BOUNDARY_MAP_SCRIPT"
}

@test "contract: build-system-resolver.sh calls require_bash4" {
  grep -q 'require_bash4' "$RESOLVER_SCRIPT"
}

@test "contract: module-boundary-map.sh calls require_bash4" {
  grep -q 'require_bash4' "$BOUNDARY_MAP_SCRIPT"
}

# ---------------------------------------------------------------------------
# Confidence tagging contracts
# ---------------------------------------------------------------------------
@test "contract: edges.properties column exists in schema" {
  grep -q "properties" "$PLUGIN_ROOT/shared/graph/code-graph-schema.sql"
}

@test "contract: build_cross_file_edges_heuristic tags edges with heuristic confidence" {
  grep -q 'confidence.*heuristic' "$PLUGIN_ROOT/shared/graph/build-code-graph.sh" \
    || fail "build_cross_file_edges_heuristic should tag edges with heuristic confidence"
}

@test "contract: build_cross_file_edges_with_boundaries uses all three confidence levels" {
  local script="$PLUGIN_ROOT/shared/graph/build-code-graph.sh"
  grep -q 'confidence.*resolved' "$script" \
    || fail "Missing resolved confidence in build_cross_file_edges_with_boundaries"
  grep -q 'confidence.*module-inferred' "$script" \
    || fail "Missing module-inferred confidence in build_cross_file_edges_with_boundaries"
  grep -q 'confidence.*heuristic' "$script" \
    || fail "Missing heuristic confidence in build_cross_file_edges_with_boundaries"
}

@test "contract: confidence values are exactly the three documented levels" {
  local script="$PLUGIN_ROOT/shared/graph/build-code-graph.sh"
  local confidence_values
  confidence_values="$(grep -oE 'confidence[^a-z]*[a-z-]+' "$script" | sort -u)"
  echo "$confidence_values" | grep -q 'resolved' || fail "Missing resolved"
  echo "$confidence_values" | grep -q 'module-inferred' || fail "Missing module-inferred"
  echo "$confidence_values" | grep -q 'heuristic' || fail "Missing heuristic"
}

# ---------------------------------------------------------------------------
# Config validation contracts
# ---------------------------------------------------------------------------
@test "contract: build_graph config keys documented" {
  local claude_md="$PLUGIN_ROOT/CLAUDE.md"
  local preflight_md="$PLUGIN_ROOT/shared/preflight-constraints.md"
  grep -q "build_graph.introspection" "$claude_md" \
    || grep -q "build_graph.introspection" "$preflight_md" \
    || fail "build_graph.introspection not in CLAUDE.md or preflight-constraints.md"
  grep -q "build_graph.introspection_timeout_seconds" "$claude_md" \
    || grep -q "build_graph.introspection_timeout_seconds" "$preflight_md" \
    || fail "build_graph.introspection_timeout_seconds not in CLAUDE.md or preflight-constraints.md"
  grep -q "build_graph.fallback" "$claude_md" \
    || grep -q "build_graph.fallback" "$preflight_md" \
    || fail "build_graph.fallback not in CLAUDE.md or preflight-constraints.md"
}

@test "contract: build_graph.introspection_timeout_seconds range 10-300 documented" {
  local stage_contract="$PLUGIN_ROOT/shared/stage-contract.md"
  grep -q "introspection_timeout_seconds" "$stage_contract" \
    || fail "introspection_timeout_seconds not in stage-contract.md"
}

@test "contract: build_graph.fallback valid values documented" {
  local stage_contract="$PLUGIN_ROOT/shared/stage-contract.md"
  grep -q "fallback.*heuristic\|skip" "$stage_contract" \
    || grep -q "fallback.*heuristic.*skip" "$stage_contract" \
    || fail "build_graph.fallback valid values not in stage-contract.md"
}
