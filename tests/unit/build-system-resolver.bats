#!/usr/bin/env bats
# Unit tests for shared/graph/build-system-resolver.sh

load '../helpers/test-helpers'

RESOLVER="$PLUGIN_ROOT/shared/graph/build-system-resolver.sh"

# ---------------------------------------------------------------------------
# Structural checks
# ---------------------------------------------------------------------------
@test "build-system-resolver: script exists and is executable" {
  assert [ -f "$RESOLVER" ]
  assert [ -x "$RESOLVER" ]
}

@test "build-system-resolver: has bash4 shebang" {
  head -1 "$RESOLVER" | grep -q '#!/usr/bin/env bash'
}

@test "build-system-resolver: sources platform.sh" {
  grep -q 'source.*platform\.sh' "$RESOLVER"
}

@test "build-system-resolver: calls require_bash4" {
  grep -q 'require_bash4' "$RESOLVER"
}

# ---------------------------------------------------------------------------
# Detection tests
# ---------------------------------------------------------------------------
@test "build-system-resolver: detects maven from pom.xml" {
  local proj="${TEST_TEMP}/project"
  touch "$proj/pom.xml"
  run bash -c "source '$RESOLVER' --source-only && detect_build_systems '$proj'"
  assert_success
  assert_output --partial "maven"
}

@test "build-system-resolver: detects gradle from build.gradle.kts" {
  local proj="${TEST_TEMP}/project"
  touch "$proj/build.gradle.kts"
  run bash -c "source '$RESOLVER' --source-only && detect_build_systems '$proj'"
  assert_success
  assert_output --partial "gradle"
}

@test "build-system-resolver: detects gradle from build.gradle without settings.gradle" {
  local proj="${TEST_TEMP}/project"
  touch "$proj/build.gradle"
  run bash -c "source '$RESOLVER' --source-only && detect_build_systems '$proj'"
  assert_success
  assert_output --partial "gradle"
}

@test "build-system-resolver: detects npm from package.json" {
  local proj="${TEST_TEMP}/project"
  echo '{}' > "$proj/package.json"
  run bash -c "source '$RESOLVER' --source-only && detect_build_systems '$proj'"
  assert_success
  assert_output --partial "npm"
}

@test "build-system-resolver: detects pnpm from pnpm-lock.yaml" {
  local proj="${TEST_TEMP}/project"
  echo '{}' > "$proj/package.json"
  touch "$proj/pnpm-lock.yaml"
  run bash -c "source '$RESOLVER' --source-only && detect_build_systems '$proj'"
  assert_success
  assert_output --partial "pnpm"
}

@test "build-system-resolver: detects yarn from yarn.lock" {
  local proj="${TEST_TEMP}/project"
  echo '{}' > "$proj/package.json"
  touch "$proj/yarn.lock"
  run bash -c "source '$RESOLVER' --source-only && detect_build_systems '$proj'"
  assert_success
  assert_output --partial "yarn"
}

@test "build-system-resolver: detects go from go.mod" {
  local proj="${TEST_TEMP}/project"
  echo "module example.com/mymod" > "$proj/go.mod"
  run bash -c "source '$RESOLVER' --source-only && detect_build_systems '$proj'"
  assert_success
  assert_output --partial "go"
}

@test "build-system-resolver: detects go from go.work" {
  local proj="${TEST_TEMP}/project"
  echo "go 1.21" > "$proj/go.work"
  run bash -c "source '$RESOLVER' --source-only && detect_build_systems '$proj'"
  assert_success
  assert_output --partial "go"
}

@test "build-system-resolver: detects cargo from Cargo.toml" {
  local proj="${TEST_TEMP}/project"
  echo '[package]' > "$proj/Cargo.toml"
  run bash -c "source '$RESOLVER' --source-only && detect_build_systems '$proj'"
  assert_success
  assert_output --partial "cargo"
}

@test "build-system-resolver: detects dotnet from sln file" {
  local proj="${TEST_TEMP}/project"
  touch "$proj/MyApp.sln"
  run bash -c "source '$RESOLVER' --source-only && detect_build_systems '$proj'"
  assert_success
  assert_output --partial "dotnet"
}

@test "build-system-resolver: detects dotnet from csproj file" {
  local proj="${TEST_TEMP}/project"
  touch "$proj/MyApp.csproj"
  run bash -c "source '$RESOLVER' --source-only && detect_build_systems '$proj'"
  assert_success
  assert_output --partial "dotnet"
}

@test "build-system-resolver: detects multiple build systems" {
  local proj="${TEST_TEMP}/project"
  echo "module example.com/backend" > "$proj/go.mod"
  echo '{}' > "$proj/package.json"
  run bash -c "source '$RESOLVER' --source-only && detect_build_systems '$proj'"
  assert_success
  assert_output --partial "npm"
  assert_output --partial "go"
}

@test "build-system-resolver: returns empty for project with no build files" {
  local proj="${TEST_TEMP}/project"
  run bash -c "source '$RESOLVER' --source-only && detect_build_systems '$proj'"
  assert_success
  assert_output ""
}

@test "build-system-resolver: --project-root is required" {
  run "$RESOLVER"
  assert_failure
  assert_output --partial "project-root"
}

@test "build-system-resolver: exits 0 when no build systems detected" {
  run "$RESOLVER" --project-root "${TEST_TEMP}/project"
  assert_success
}

# ---------------------------------------------------------------------------
# Maven introspection
# ---------------------------------------------------------------------------
@test "build-system-resolver: maven fallback parses pom.xml dependencies" {
  local proj="${TEST_TEMP}/project"
  cat > "$proj/pom.xml" << 'POMEOF'
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <groupId>com.example</groupId>
  <artifactId>myapp</artifactId>
  <version>1.0.0</version>
  <dependencies>
    <dependency>
      <groupId>org.springframework</groupId>
      <artifactId>spring-context</artifactId>
      <version>6.1.4</version>
    </dependency>
    <dependency>
      <groupId>junit</groupId>
      <artifactId>junit</artifactId>
      <version>4.13.2</version>
      <scope>test</scope>
    </dependency>
  </dependencies>
</project>
POMEOF
  # Use fallback (mvn not available in test)
  run bash -c "source '$RESOLVER' --source-only && fallback_maven '$proj'"
  assert_success
  assert_output --partial "spring-context"
  assert_output --partial "junit"
}

@test "build-system-resolver: maven fallback handles parent POM groupId inheritance" {
  local proj="${TEST_TEMP}/project"
  cat > "$proj/pom.xml" << 'POMEOF'
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0">
  <modelVersion>4.0.0</modelVersion>
  <parent>
    <groupId>com.example</groupId>
    <artifactId>parent</artifactId>
    <version>1.0.0</version>
  </parent>
  <artifactId>child</artifactId>
  <dependencies>
    <dependency>
      <groupId>com.example</groupId>
      <artifactId>core</artifactId>
      <version>1.0.0</version>
    </dependency>
  </dependencies>
</project>
POMEOF
  run bash -c "source '$RESOLVER' --source-only && fallback_maven '$proj'"
  assert_success
  assert_output --partial "com.example"
  assert_output --partial "core"
}

@test "build-system-resolver: maven fallback handles empty dependencies" {
  local proj="${TEST_TEMP}/project"
  cat > "$proj/pom.xml" << 'POMEOF'
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0">
  <modelVersion>4.0.0</modelVersion>
  <groupId>com.example</groupId>
  <artifactId>empty</artifactId>
  <version>1.0.0</version>
</project>
POMEOF
  run bash -c "source '$RESOLVER' --source-only && fallback_maven '$proj'"
  assert_success
  # Should return valid JSON (empty array)
  echo "$output" | python3 -c "import json,sys; json.load(sys.stdin)"
}

# ---------------------------------------------------------------------------
# Gradle introspection
# ---------------------------------------------------------------------------
@test "build-system-resolver: gradle fallback parses build.gradle.kts dependencies" {
  local proj="${TEST_TEMP}/project"
  cat > "$proj/build.gradle.kts" << 'GEOF'
dependencies {
    implementation("org.springframework.boot:spring-boot-starter-web:3.2.0")
    testImplementation("org.junit.jupiter:junit-jupiter:5.10.0")
    api("com.google.guava:guava:32.1.3-jre")
    runtimeOnly("org.postgresql:postgresql:42.7.1")
}
GEOF
  run bash -c "source '$RESOLVER' --source-only && fallback_gradle '$proj'"
  assert_success
  assert_output --partial "spring-boot-starter-web"
  assert_output --partial "junit-jupiter"
  assert_output --partial "guava"
  assert_output --partial "postgresql"
}

@test "build-system-resolver: gradle fallback parses build.gradle groovy syntax" {
  local proj="${TEST_TEMP}/project"
  cat > "$proj/build.gradle" << 'GEOF'
dependencies {
    implementation 'org.apache.kafka:kafka-clients:3.6.0'
    testImplementation 'io.mockk:mockk:1.13.8'
}
GEOF
  run bash -c "source '$RESOLVER' --source-only && fallback_gradle '$proj'"
  assert_success
  assert_output --partial "kafka-clients"
  assert_output --partial "mockk"
}

@test "build-system-resolver: gradle fallback walks subproject build files" {
  local proj="${TEST_TEMP}/project"
  mkdir -p "$proj/core" "$proj/api"
  cat > "$proj/settings.gradle.kts" << 'GEOF'
include("core", "api")
GEOF
  cat > "$proj/core/build.gradle.kts" << 'GEOF'
dependencies {
    implementation("com.example:shared:1.0.0")
}
GEOF
  cat > "$proj/api/build.gradle.kts" << 'GEOF'
dependencies {
    implementation(project(":core"))
    implementation("io.ktor:ktor-core:2.3.0")
}
GEOF
  run bash -c "source '$RESOLVER' --source-only && fallback_gradle '$proj'"
  assert_success
  assert_output --partial "shared"
  assert_output --partial "ktor-core"
}

# ---------------------------------------------------------------------------
# npm/pnpm/yarn introspection
# ---------------------------------------------------------------------------
@test "build-system-resolver: npm fallback parses package.json" {
  local proj="${TEST_TEMP}/project"
  cat > "$proj/package.json" << 'NPMEOF'
{
  "name": "my-app",
  "version": "1.0.0",
  "dependencies": {
    "express": "^4.18.2",
    "lodash": "^4.17.21"
  },
  "devDependencies": {
    "jest": "^29.7.0"
  }
}
NPMEOF
  run bash -c "source '$RESOLVER' --source-only && fallback_npm '$proj'"
  assert_success
  assert_output --partial "express"
  assert_output --partial "lodash"
  assert_output --partial "jest"
}

@test "build-system-resolver: npm fallback handles workspace package.json files" {
  local proj="${TEST_TEMP}/project"
  mkdir -p "$proj/packages/core" "$proj/packages/api"
  cat > "$proj/package.json" << 'NPMEOF'
{
  "name": "my-monorepo",
  "workspaces": ["packages/*"]
}
NPMEOF
  cat > "$proj/packages/core/package.json" << 'NPMEOF'
{
  "name": "@myorg/core",
  "dependencies": { "zod": "^3.22.0" }
}
NPMEOF
  cat > "$proj/packages/api/package.json" << 'NPMEOF'
{
  "name": "@myorg/api",
  "dependencies": { "@myorg/core": "workspace:*", "fastify": "^4.25.0" }
}
NPMEOF
  run bash -c "source '$RESOLVER' --source-only && fallback_npm '$proj'"
  assert_success
  assert_output --partial "zod"
  assert_output --partial "fastify"
}

@test "build-system-resolver: npm fallback handles empty package.json" {
  local proj="${TEST_TEMP}/project"
  echo '{}' > "$proj/package.json"
  run bash -c "source '$RESOLVER' --source-only && fallback_npm '$proj'"
  assert_success
  echo "$output" | python3 -c "import json,sys; json.load(sys.stdin)"
}

# ---------------------------------------------------------------------------
# Go introspection
# ---------------------------------------------------------------------------
@test "build-system-resolver: go fallback parses go.mod require block" {
  local proj="${TEST_TEMP}/project"
  cat > "$proj/go.mod" << 'GOEOF'
module github.com/example/myapp

go 1.21

require (
	github.com/gin-gonic/gin v1.9.1
	github.com/stretchr/testify v1.8.4
)

require (
	golang.org/x/text v0.14.0 // indirect
)
GOEOF
  run bash -c "source '$RESOLVER' --source-only && fallback_go '$proj'"
  assert_success
  assert_output --partial "gin"
  assert_output --partial "testify"
  assert_output --partial "golang.org/x/text"
}

@test "build-system-resolver: go fallback handles single-line require" {
  local proj="${TEST_TEMP}/project"
  cat > "$proj/go.mod" << 'GOEOF'
module github.com/example/simple

go 1.21

require github.com/pkg/errors v0.9.1
GOEOF
  run bash -c "source '$RESOLVER' --source-only && fallback_go '$proj'"
  assert_success
  assert_output --partial "errors"
}

# ---------------------------------------------------------------------------
# Cargo introspection
# ---------------------------------------------------------------------------
@test "build-system-resolver: cargo fallback parses Cargo.toml dependencies" {
  local proj="${TEST_TEMP}/project"
  cat > "$proj/Cargo.toml" << 'CARGOEOF'
[package]
name = "myapp"
version = "0.1.0"

[dependencies]
serde = { version = "1.0", features = ["derive"] }
tokio = { version = "1.35", features = ["full"] }

[dev-dependencies]
criterion = "0.5"
CARGOEOF
  run bash -c "source '$RESOLVER' --source-only && fallback_cargo '$proj'"
  assert_success
  assert_output --partial "serde"
  assert_output --partial "tokio"
  assert_output --partial "criterion"
}

@test "build-system-resolver: cargo fallback handles simple string versions" {
  local proj="${TEST_TEMP}/project"
  cat > "$proj/Cargo.toml" << 'CARGOEOF'
[package]
name = "simple"
version = "0.1.0"

[dependencies]
rand = "0.8"
CARGOEOF
  run bash -c "source '$RESOLVER' --source-only && fallback_cargo '$proj'"
  assert_success
  assert_output --partial "rand"
}

# ---------------------------------------------------------------------------
# .NET introspection
# ---------------------------------------------------------------------------
@test "build-system-resolver: dotnet fallback parses csproj PackageReference" {
  local proj="${TEST_TEMP}/project"
  cat > "$proj/MyApp.csproj" << 'CSEOF'
<Project Sdk="Microsoft.NET.Sdk.Web">
  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
  </PropertyGroup>
  <ItemGroup>
    <PackageReference Include="Newtonsoft.Json" Version="13.0.3" />
    <PackageReference Include="Serilog" Version="3.1.1" />
  </ItemGroup>
</Project>
CSEOF
  run bash -c "source '$RESOLVER' --source-only && fallback_dotnet '$proj'"
  assert_success
  assert_output --partial "Newtonsoft.Json"
  assert_output --partial "Serilog"
}

@test "build-system-resolver: dotnet fallback finds csproj in subdirectories" {
  local proj="${TEST_TEMP}/project"
  mkdir -p "$proj/src/Api" "$proj/src/Core"
  cat > "$proj/MySolution.sln" << 'SLNEOF'
Microsoft Visual Studio Solution File
Project("{FAE04EC0-301F-11D3-BF4B-00C04F79EFBC}") = "Api", "src\Api\Api.csproj", "{GUID1}"
EndProject
Project("{FAE04EC0-301F-11D3-BF4B-00C04F79EFBC}") = "Core", "src\Core\Core.csproj", "{GUID2}"
EndProject
SLNEOF
  cat > "$proj/src/Api/Api.csproj" << 'CSEOF'
<Project Sdk="Microsoft.NET.Sdk.Web">
  <ItemGroup>
    <PackageReference Include="Microsoft.AspNetCore.OpenApi" Version="8.0.0" />
  </ItemGroup>
</Project>
CSEOF
  cat > "$proj/src/Core/Core.csproj" << 'CSEOF'
<Project Sdk="Microsoft.NET.Sdk">
  <ItemGroup>
    <PackageReference Include="FluentValidation" Version="11.8.0" />
  </ItemGroup>
</Project>
CSEOF
  run bash -c "source '$RESOLVER' --source-only && fallback_dotnet '$proj'"
  assert_success
  assert_output --partial "Microsoft.AspNetCore.OpenApi"
  assert_output --partial "FluentValidation"
}

# ---------------------------------------------------------------------------
# Caching
# ---------------------------------------------------------------------------
@test "build-system-resolver: cache file created after resolution" {
  local proj="${TEST_TEMP}/project"
  mkdir -p "$proj/.forge"
  cat > "$proj/pom.xml" << 'POMEOF'
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0">
  <modelVersion>4.0.0</modelVersion>
  <groupId>com.example</groupId>
  <artifactId>myapp</artifactId>
  <version>1.0.0</version>
  <dependencies>
    <dependency>
      <groupId>junit</groupId>
      <artifactId>junit</artifactId>
      <version>4.13.2</version>
    </dependency>
  </dependencies>
</project>
POMEOF
  run "$RESOLVER" --project-root "$proj"
  assert_success
  assert [ -f "$proj/.forge/build-graph-cache.json" ]
  # Validate it is valid JSON
  python3 -m json.tool "$proj/.forge/build-graph-cache.json" > /dev/null
}

@test "build-system-resolver: cache is valid after unchanged build files" {
  local proj="${TEST_TEMP}/project"
  mkdir -p "$proj/.forge"
  echo '{}' > "$proj/package.json"

  # First run: builds cache
  run "$RESOLVER" --project-root "$proj"
  assert_success

  # Second run: should report cache hit
  run "$RESOLVER" --project-root "$proj"
  assert_success
  assert_output --partial "Cache hit"
}

@test "build-system-resolver: cache invalidated when build file changes" {
  local proj="${TEST_TEMP}/project"
  mkdir -p "$proj/.forge"
  echo '{"dependencies":{"a":"1.0.0"}}' > "$proj/package.json"

  # First run
  run "$RESOLVER" --project-root "$proj"
  assert_success

  # Modify package.json
  echo '{"dependencies":{"a":"2.0.0"}}' > "$proj/package.json"

  # Second run should NOT report cache hit
  run "$RESOLVER" --project-root "$proj"
  assert_success
  assert_output --partial "Introspecting"
}

@test "build-system-resolver: --force-refresh bypasses cache" {
  local proj="${TEST_TEMP}/project"
  mkdir -p "$proj/.forge"
  echo '{}' > "$proj/package.json"

  # First run
  run "$RESOLVER" --project-root "$proj"
  assert_success

  # Second run with --force-refresh
  run "$RESOLVER" --project-root "$proj" --force-refresh
  assert_success
  assert_output --partial "Introspecting"
}

@test "build-system-resolver: compute_build_file_hashes returns empty for no-build project" {
  local proj="${TEST_TEMP}/project"
  run bash -c "source '$RESOLVER' --source-only && compute_build_file_hashes 'maven' '$proj'"
  assert_success
  assert_output ""
}
