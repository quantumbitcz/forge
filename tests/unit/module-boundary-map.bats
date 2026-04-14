#!/usr/bin/env bats
# Unit tests for shared/graph/module-boundary-map.sh

load '../helpers/test-helpers'

BOUNDARY_MAP="$PLUGIN_ROOT/shared/graph/module-boundary-map.sh"

# ---------------------------------------------------------------------------
# Structural checks
# ---------------------------------------------------------------------------
@test "module-boundary-map: script exists and is executable" {
  assert [ -f "$BOUNDARY_MAP" ]
  assert [ -x "$BOUNDARY_MAP" ]
}

@test "module-boundary-map: has bash4 shebang" {
  head -1 "$BOUNDARY_MAP" | grep -q '#!/usr/bin/env bash'
}

@test "module-boundary-map: sources platform.sh" {
  grep -q 'source.*platform\.sh' "$BOUNDARY_MAP"
}

@test "module-boundary-map: calls require_bash4" {
  grep -q 'require_bash4' "$BOUNDARY_MAP"
}

@test "module-boundary-map: --project-root is required" {
  run "$BOUNDARY_MAP"
  assert_failure
  assert_output --partial "project-root"
}

@test "module-boundary-map: exits 0 for project with no build files" {
  run "$BOUNDARY_MAP" --project-root "${TEST_TEMP}/project"
  assert_success
  # Should output valid JSON with empty modules
  echo "$output" | python3 -c "
import json, sys
data = json.load(sys.stdin)
assert data['modules'] == [], f'Expected empty modules, got {data[\"modules\"]}'
"
}

@test "module-boundary-map: output includes version field" {
  run "$BOUNDARY_MAP" --project-root "${TEST_TEMP}/project"
  assert_success
  echo "$output" | python3 -c "
import json, sys
data = json.load(sys.stdin)
assert data.get('version') == '1.0.0', f'Expected version 1.0.0, got {data.get(\"version\")}'
"
}

# ---------------------------------------------------------------------------
# Maven module discovery
# ---------------------------------------------------------------------------
@test "module-boundary-map: maven single module project" {
  local proj="${TEST_TEMP}/project"
  mkdir -p "$proj/src/main/java"
  cat > "$proj/pom.xml" << 'POMEOF'
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0">
  <groupId>com.example</groupId>
  <artifactId>myapp</artifactId>
  <version>1.0.0</version>
</project>
POMEOF
  run "$BOUNDARY_MAP" --project-root "$proj" --build-system maven
  assert_success
  echo "$output" | python3 -c "
import json, sys
data = json.load(sys.stdin)
assert len(data['modules']) == 1, f'Expected 1 module, got {len(data[\"modules\"])}'
assert data['modules'][0]['name'] == 'myapp'
assert data['modules'][0]['artifact_id'] == 'com.example:myapp'
assert 'src/main/java' in data['modules'][0]['source_dirs']
"
}

@test "module-boundary-map: maven multi-module project" {
  local proj="${TEST_TEMP}/project"
  mkdir -p "$proj/core/src/main/java" "$proj/api/src/main/java" "$proj/api/src/test/java"
  cat > "$proj/pom.xml" << 'POMEOF'
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0">
  <groupId>com.example</groupId>
  <artifactId>parent</artifactId>
  <version>1.0.0</version>
  <packaging>pom</packaging>
  <modules>
    <module>core</module>
    <module>api</module>
  </modules>
</project>
POMEOF
  cat > "$proj/core/pom.xml" << 'POMEOF'
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0">
  <parent>
    <groupId>com.example</groupId>
    <artifactId>parent</artifactId>
    <version>1.0.0</version>
  </parent>
  <artifactId>core</artifactId>
</project>
POMEOF
  cat > "$proj/api/pom.xml" << 'POMEOF'
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0">
  <parent>
    <groupId>com.example</groupId>
    <artifactId>parent</artifactId>
    <version>1.0.0</version>
  </parent>
  <artifactId>api</artifactId>
  <dependencies>
    <dependency>
      <groupId>com.example</groupId>
      <artifactId>core</artifactId>
      <version>1.0.0</version>
    </dependency>
  </dependencies>
</project>
POMEOF
  run "$BOUNDARY_MAP" --project-root "$proj" --build-system maven
  assert_success
  echo "$output" | python3 -c "
import json, sys
data = json.load(sys.stdin)
modules = {m['name']: m for m in data['modules']}
assert 'core' in modules, f'Missing core module, got: {list(modules.keys())}'
assert 'api' in modules, f'Missing api module, got: {list(modules.keys())}'
assert 'core' in modules['api']['depends_on'], f'api should depend on core, got: {modules[\"api\"][\"depends_on\"]}'
assert 'api' in modules['core']['depended_by'], f'core should be depended_by api, got: {modules[\"core\"][\"depended_by\"]}'
"
}

@test "module-boundary-map: maven inherits groupId from parent" {
  local proj="${TEST_TEMP}/project"
  cat > "$proj/pom.xml" << 'POMEOF'
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0">
  <parent>
    <groupId>com.example</groupId>
    <artifactId>parent</artifactId>
    <version>1.0.0</version>
  </parent>
  <artifactId>child</artifactId>
</project>
POMEOF
  run "$BOUNDARY_MAP" --project-root "$proj" --build-system maven
  assert_success
  echo "$output" | python3 -c "
import json, sys
data = json.load(sys.stdin)
assert data['modules'][0]['artifact_id'] == 'com.example:child'
"
}

# ---------------------------------------------------------------------------
# Gradle module discovery
# ---------------------------------------------------------------------------
@test "module-boundary-map: gradle single module without settings.gradle" {
  local proj="${TEST_TEMP}/project"
  mkdir -p "$proj/src/main/kotlin"
  touch "$proj/build.gradle.kts"
  run "$BOUNDARY_MAP" --project-root "$proj" --build-system gradle
  assert_success
  echo "$output" | python3 -c "
import json, sys
data = json.load(sys.stdin)
assert len(data['modules']) == 1
assert data['modules'][0]['name'] == '__root__'
assert 'src/main/kotlin' in data['modules'][0]['source_dirs']
"
}

@test "module-boundary-map: gradle multi-project with settings.gradle.kts" {
  local proj="${TEST_TEMP}/project"
  mkdir -p "$proj/core/src/main/kotlin" "$proj/api/src/main/java" "$proj/api/src/test/java"
  touch "$proj/build.gradle.kts"
  cat > "$proj/settings.gradle.kts" << 'GEOF'
rootProject.name = "myapp"
include("core", "api")
GEOF
  cat > "$proj/core/build.gradle.kts" << 'GEOF'
dependencies {
    implementation("org.example:lib:1.0")
}
GEOF
  cat > "$proj/api/build.gradle.kts" << 'GEOF'
dependencies {
    implementation(project(":core"))
}
GEOF
  run "$BOUNDARY_MAP" --project-root "$proj" --build-system gradle
  assert_success
  echo "$output" | python3 -c "
import json, sys
data = json.load(sys.stdin)
modules = {m['name']: m for m in data['modules']}
assert 'core' in modules, f'Missing core, got: {list(modules.keys())}'
assert 'api' in modules, f'Missing api, got: {list(modules.keys())}'
assert 'core' in modules['api']['depends_on']
"
}

@test "module-boundary-map: gradle settings.gradle groovy include with colons" {
  local proj="${TEST_TEMP}/project"
  mkdir -p "$proj/lib" "$proj/app"
  touch "$proj/build.gradle"
  cat > "$proj/settings.gradle" << 'GEOF'
include ':lib', ':app'
GEOF
  touch "$proj/lib/build.gradle" "$proj/app/build.gradle"
  # Skip Gradle CLI Strategy 1 by hiding gradle from PATH to test file-based parsing
  PATH="/usr/bin:/bin:$(dirname "$(command -v python3)")" run "$BOUNDARY_MAP" --project-root "$proj" --build-system gradle
  assert_success
  echo "$output" | python3 -c "
import json, sys
data = json.load(sys.stdin)
names = [m['name'] for m in data['modules']]
assert 'lib' in names
assert 'app' in names
"
}

# ---------------------------------------------------------------------------
# Cargo workspace discovery
# ---------------------------------------------------------------------------
@test "module-boundary-map: cargo single crate" {
  local proj="${TEST_TEMP}/project"
  mkdir -p "$proj/src"
  cat > "$proj/Cargo.toml" << 'CEOF'
[package]
name = "myapp"
version = "0.1.0"
CEOF
  run "$BOUNDARY_MAP" --project-root "$proj" --build-system cargo
  assert_success
  echo "$output" | python3 -c "
import json, sys
data = json.load(sys.stdin)
assert len(data['modules']) == 1
assert data['modules'][0]['name'] == 'myapp'
assert 'src' in data['modules'][0]['source_dirs']
"
}

@test "module-boundary-map: cargo workspace with members" {
  local proj="${TEST_TEMP}/project"
  mkdir -p "$proj/crates/core/src" "$proj/crates/api/src" "$proj/crates/api/tests"
  cat > "$proj/Cargo.toml" << 'CEOF'
[workspace]
members = ["crates/core", "crates/api"]
CEOF
  cat > "$proj/crates/core/Cargo.toml" << 'CEOF'
[package]
name = "core"
version = "0.1.0"
CEOF
  cat > "$proj/crates/api/Cargo.toml" << 'CEOF'
[package]
name = "api"
version = "0.1.0"

[dependencies]
core = { path = "../core" }
CEOF
  run "$BOUNDARY_MAP" --project-root "$proj" --build-system cargo
  assert_success
  echo "$output" | python3 -c "
import json, sys
data = json.load(sys.stdin)
modules = {m['name']: m for m in data['modules']}
assert 'core' in modules
assert 'api' in modules
assert 'core' in modules['api']['depends_on']
"
}

# ---------------------------------------------------------------------------
# Go workspace/module discovery
# ---------------------------------------------------------------------------
@test "module-boundary-map: go single module" {
  local proj="${TEST_TEMP}/project"
  cat > "$proj/go.mod" << 'GOEOF'
module github.com/example/myapp

go 1.21
GOEOF
  run "$BOUNDARY_MAP" --project-root "$proj" --build-system go
  assert_success
  echo "$output" | python3 -c "
import json, sys
data = json.load(sys.stdin)
assert len(data['modules']) == 1
assert data['modules'][0]['artifact_id'] == 'github.com/example/myapp'
"
}

@test "module-boundary-map: go workspace with multiple modules" {
  local proj="${TEST_TEMP}/project"
  mkdir -p "$proj/backend" "$proj/shared"
  cat > "$proj/go.work" << 'GOEOF'
go 1.21

use (
	./backend
	./shared
)
GOEOF
  cat > "$proj/backend/go.mod" << 'GOEOF'
module github.com/example/backend

go 1.21

require github.com/example/shared v0.0.0
GOEOF
  cat > "$proj/shared/go.mod" << 'GOEOF'
module github.com/example/shared

go 1.21
GOEOF
  run "$BOUNDARY_MAP" --project-root "$proj" --build-system go
  assert_success
  echo "$output" | python3 -c "
import json, sys
data = json.load(sys.stdin)
names = [m['name'] for m in data['modules']]
assert 'backend' in names
assert 'shared' in names
"
}

# ---------------------------------------------------------------------------
# npm/yarn workspace discovery
# ---------------------------------------------------------------------------
@test "module-boundary-map: npm single package" {
  local proj="${TEST_TEMP}/project"
  mkdir -p "$proj/src"
  cat > "$proj/package.json" << 'NEOF'
{"name": "my-app", "version": "1.0.0"}
NEOF
  run "$BOUNDARY_MAP" --project-root "$proj" --build-system npm
  assert_success
  echo "$output" | python3 -c "
import json, sys
data = json.load(sys.stdin)
assert len(data['modules']) == 1
assert data['modules'][0]['name'] == 'my-app'
"
}

@test "module-boundary-map: npm workspace with packages/*" {
  local proj="${TEST_TEMP}/project"
  mkdir -p "$proj/packages/core/src" "$proj/packages/api/src"
  cat > "$proj/package.json" << 'NEOF'
{"name": "my-monorepo", "workspaces": ["packages/*"]}
NEOF
  cat > "$proj/packages/core/package.json" << 'NEOF'
{"name": "@myorg/core"}
NEOF
  cat > "$proj/packages/api/package.json" << 'NEOF'
{"name": "@myorg/api", "dependencies": {"@myorg/core": "workspace:*", "express": "^4.18.0"}}
NEOF
  run "$BOUNDARY_MAP" --project-root "$proj" --build-system npm
  assert_success
  echo "$output" | python3 -c "
import json, sys
data = json.load(sys.stdin)
modules = {m['name']: m for m in data['modules']}
assert '@myorg/core' in modules
assert '@myorg/api' in modules
assert '@myorg/core' in modules['@myorg/api']['depends_on']
"
}

@test "module-boundary-map: pnpm workspace from pnpm-workspace.yaml" {
  local proj="${TEST_TEMP}/project"
  mkdir -p "$proj/packages/ui/src" "$proj/packages/server/src"
  cat > "$proj/package.json" << 'NEOF'
{"name": "pnpm-mono"}
NEOF
  cat > "$proj/pnpm-workspace.yaml" << 'NEOF'
packages:
  - 'packages/*'
NEOF
  cat > "$proj/packages/ui/package.json" << 'NEOF'
{"name": "@mono/ui"}
NEOF
  cat > "$proj/packages/server/package.json" << 'NEOF'
{"name": "@mono/server", "dependencies": {"@mono/ui": "workspace:*"}}
NEOF
  run "$BOUNDARY_MAP" --project-root "$proj" --build-system npm
  assert_success
  echo "$output" | python3 -c "
import json, sys
data = json.load(sys.stdin)
names = [m['name'] for m in data['modules']]
assert '@mono/ui' in names
assert '@mono/server' in names
"
}

# ---------------------------------------------------------------------------
# .NET solution discovery
# ---------------------------------------------------------------------------
@test "module-boundary-map: dotnet single csproj" {
  local proj="${TEST_TEMP}/project"
  cat > "$proj/MyApp.csproj" << 'CSEOF'
<Project Sdk="Microsoft.NET.Sdk.Web">
  <PropertyGroup><TargetFramework>net8.0</TargetFramework></PropertyGroup>
</Project>
CSEOF
  run "$BOUNDARY_MAP" --project-root "$proj" --build-system dotnet
  assert_success
  echo "$output" | python3 -c "
import json, sys
data = json.load(sys.stdin)
assert len(data['modules']) >= 1
assert data['modules'][0]['name'] == 'MyApp'
"
}

@test "module-boundary-map: dotnet solution with project references" {
  local proj="${TEST_TEMP}/project"
  mkdir -p "$proj/src/Api" "$proj/src/Core" "$proj/tests/Api.Tests"
  cat > "$proj/MySolution.sln" << 'SLNEOF'
Microsoft Visual Studio Solution File, Format Version 12.00
Project("{FAE04EC0-301F-11D3-BF4B-00C04F79EFBC}") = "Api", "src\Api\Api.csproj", "{GUID1}"
EndProject
Project("{FAE04EC0-301F-11D3-BF4B-00C04F79EFBC}") = "Core", "src\Core\Core.csproj", "{GUID2}"
EndProject
Project("{FAE04EC0-301F-11D3-BF4B-00C04F79EFBC}") = "Api.Tests", "tests\Api.Tests\Api.Tests.csproj", "{GUID3}"
EndProject
SLNEOF
  cat > "$proj/src/Api/Api.csproj" << 'CSEOF'
<Project Sdk="Microsoft.NET.Sdk.Web">
  <ItemGroup>
    <ProjectReference Include="..\..\src\Core\Core.csproj" />
  </ItemGroup>
</Project>
CSEOF
  cat > "$proj/src/Core/Core.csproj" << 'CSEOF'
<Project Sdk="Microsoft.NET.Sdk" />
CSEOF
  cat > "$proj/tests/Api.Tests/Api.Tests.csproj" << 'CSEOF'
<Project Sdk="Microsoft.NET.Sdk">
  <ItemGroup>
    <ProjectReference Include="..\..\src\Api\Api.csproj" />
  </ItemGroup>
</Project>
CSEOF
  run "$BOUNDARY_MAP" --project-root "$proj" --build-system dotnet
  assert_success
  echo "$output" | python3 -c "
import json, sys
data = json.load(sys.stdin)
modules = {m['name']: m for m in data['modules']}
assert 'Api' in modules
assert 'Core' in modules
assert 'Api.Tests' in modules
assert 'Core' in modules['Api']['depends_on']
assert 'Api' in modules['Api.Tests']['depends_on']
# Tests project should have test_dirs, not source_dirs
assert len(modules['Api.Tests']['test_dirs']) > 0
"
}
