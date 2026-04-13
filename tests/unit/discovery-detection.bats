#!/usr/bin/env bats
# Unit tests: detect-project-type.sh — validates language, framework, and type
# detection from directory contents.

load '../helpers/test-helpers'

DETECT_SCRIPT="$PLUGIN_ROOT/shared/discovery/detect-project-type.sh"

# ---------------------------------------------------------------------------
# Helper: extract a JSON field from detect-project-type.sh output
# ---------------------------------------------------------------------------
extract_field() {
  local json="$1" field="$2"
  python3 -c "import json,sys; d=json.loads(sys.argv[1]); v=d.get(sys.argv[2],''); print('' if v is None else v)" "$json" "$field"
}

# ===========================================================================
# 1. Script basics
# ===========================================================================

@test "discovery-detection: script exists and is executable" {
  assert [ -f "$DETECT_SCRIPT" ]
  assert [ -x "$DETECT_SCRIPT" ]
}

@test "discovery-detection: has bash shebang" {
  local first_line
  first_line=$(head -1 "$DETECT_SCRIPT")
  assert_equal "$first_line" "#!/usr/bin/env bash"
}

# ===========================================================================
# 2. Empty / missing directory
# ===========================================================================

@test "discovery-detection: empty directory returns unknown/unknown/unknown" {
  local dir="$TEST_TEMP/empty-project"
  mkdir -p "$dir"

  run bash "$DETECT_SCRIPT" "$dir"
  assert_success

  local type framework language
  type="$(extract_field "$output" "type")"
  framework="$(extract_field "$output" "framework")"
  language="$(extract_field "$output" "language")"
  assert_equal "$type" "unknown"
  assert_equal "$framework" "unknown"
  assert_equal "$language" "unknown"
}

@test "discovery-detection: nonexistent directory returns unknown" {
  run bash "$DETECT_SCRIPT" "$TEST_TEMP/does-not-exist"
  assert_success
  local type
  type="$(extract_field "$output" "type")"
  assert_equal "$type" "unknown"
}

@test "discovery-detection: no argument returns unknown" {
  run bash "$DETECT_SCRIPT"
  assert_success
  local type
  type="$(extract_field "$output" "type")"
  assert_equal "$type" "unknown"
}

# ===========================================================================
# 3. JavaScript / TypeScript frontend detection
# ===========================================================================

@test "discovery-detection: package.json alone returns javascript frontend" {
  local dir="$TEST_TEMP/js-project"
  mkdir -p "$dir"
  echo '{"name":"test"}' > "$dir/package.json"

  run bash "$DETECT_SCRIPT" "$dir"
  assert_success
  local language type
  language="$(extract_field "$output" "language")"
  type="$(extract_field "$output" "type")"
  assert_equal "$language" "javascript"
  assert_equal "$type" "frontend"
}

@test "discovery-detection: package.json + tsconfig.json returns typescript" {
  local dir="$TEST_TEMP/ts-project"
  mkdir -p "$dir"
  echo '{"name":"test"}' > "$dir/package.json"
  touch "$dir/tsconfig.json"

  run bash "$DETECT_SCRIPT" "$dir"
  assert_success
  local language
  language="$(extract_field "$output" "language")"
  assert_equal "$language" "typescript"
}

@test "discovery-detection: package.json + vite + react dep returns react frontend" {
  local dir="$TEST_TEMP/react-project"
  mkdir -p "$dir"
  echo '{"name":"test","dependencies":{"react":"^18"}}' > "$dir/package.json"
  touch "$dir/vite.config.ts"

  run bash "$DETECT_SCRIPT" "$dir"
  assert_success
  local framework type
  framework="$(extract_field "$output" "framework")"
  type="$(extract_field "$output" "type")"
  assert_equal "$framework" "react"
  assert_equal "$type" "frontend"
}

@test "discovery-detection: package.json + next.config.js returns nextjs" {
  local dir="$TEST_TEMP/nextjs-project"
  mkdir -p "$dir"
  echo '{"name":"test","dependencies":{"next":"14.0.0","react":"18.2.0"}}' > "$dir/package.json"
  echo 'module.exports = {};' > "$dir/next.config.js"

  run bash "$DETECT_SCRIPT" "$dir"
  assert_success
  local framework
  framework="$(extract_field "$output" "framework")"
  assert_equal "$framework" "nextjs"
}

@test "discovery-detection: package.json + svelte.config.js returns sveltekit" {
  local dir="$TEST_TEMP/sveltekit-project"
  mkdir -p "$dir"
  echo '{"name":"test"}' > "$dir/package.json"
  touch "$dir/svelte.config.js"

  run bash "$DETECT_SCRIPT" "$dir"
  assert_success
  local framework
  framework="$(extract_field "$output" "framework")"
  assert_equal "$framework" "sveltekit"
}

@test "discovery-detection: package.json + angular.json returns angular with typescript" {
  local dir="$TEST_TEMP/angular-project"
  mkdir -p "$dir"
  echo '{"name":"test"}' > "$dir/package.json"
  printf '{"$schema":"./node_modules/@angular/cli/lib/config/schema.json"}\n' > "$dir/angular.json"

  run bash "$DETECT_SCRIPT" "$dir"
  assert_success
  local framework language
  framework="$(extract_field "$output" "framework")"
  language="$(extract_field "$output" "language")"
  assert_equal "$framework" "angular"
  assert_equal "$language" "typescript"
}

@test "discovery-detection: package.json + nest-cli.json returns nestjs backend" {
  local dir="$TEST_TEMP/nestjs-project"
  mkdir -p "$dir"
  echo '{"name":"test","dependencies":{"@nestjs/core":"10.0.0"}}' > "$dir/package.json"
  echo '{}' > "$dir/nest-cli.json"

  run bash "$DETECT_SCRIPT" "$dir"
  assert_success
  local framework type
  framework="$(extract_field "$output" "framework")"
  type="$(extract_field "$output" "type")"
  assert_equal "$framework" "nestjs"
  assert_equal "$type" "backend"
}

@test "discovery-detection: package.json + express dep returns express backend" {
  local dir="$TEST_TEMP/express-project"
  mkdir -p "$dir"
  echo '{"name":"test","dependencies":{"express":"4.18.0"}}' > "$dir/package.json"

  run bash "$DETECT_SCRIPT" "$dir"
  assert_success
  local framework type
  framework="$(extract_field "$output" "framework")"
  type="$(extract_field "$output" "type")"
  assert_equal "$framework" "express"
  assert_equal "$type" "backend"
}

@test "discovery-detection: package.json + vue dep + vite returns vue frontend" {
  local dir="$TEST_TEMP/vue-project"
  mkdir -p "$dir"
  echo '{"name":"test","dependencies":{"vue":"3.4.0"}}' > "$dir/package.json"
  printf 'import vue from "@vitejs/plugin-vue";\n' > "$dir/vite.config.ts"

  run bash "$DETECT_SCRIPT" "$dir"
  assert_success
  local framework
  framework="$(extract_field "$output" "framework")"
  assert_equal "$framework" "vue"
}

@test "discovery-detection: package.json + svelte dep (no sveltekit config) returns svelte" {
  local dir="$TEST_TEMP/svelte-project"
  mkdir -p "$dir"
  echo '{"name":"test","devDependencies":{"svelte":"5.0.0","@sveltejs/vite-plugin-svelte":"3.0.0"}}' > "$dir/package.json"
  touch "$dir/vite.config.ts"

  run bash "$DETECT_SCRIPT" "$dir"
  assert_success
  local framework
  framework="$(extract_field "$output" "framework")"
  assert_equal "$framework" "svelte"
}

# ===========================================================================
# 4. JVM detection (Kotlin, Java, Gradle, Maven)
# ===========================================================================

@test "discovery-detection: build.gradle.kts + src/main/kotlin returns kotlin backend" {
  local dir="$TEST_TEMP/kotlin-project"
  mkdir -p "$dir/src/main/kotlin"
  echo 'plugins { id("kotlin") }' > "$dir/build.gradle.kts"

  run bash "$DETECT_SCRIPT" "$dir"
  assert_success
  local language type
  language="$(extract_field "$output" "language")"
  type="$(extract_field "$output" "type")"
  assert_equal "$language" "kotlin"
  assert_equal "$type" "backend"
}

@test "discovery-detection: build.gradle.kts + spring dep returns kotlin spring" {
  local dir="$TEST_TEMP/kotlin-spring"
  mkdir -p "$dir/src/main/kotlin"
  printf 'plugins { id("org.springframework.boot") }\n' > "$dir/build.gradle.kts"

  run bash "$DETECT_SCRIPT" "$dir"
  assert_success
  local framework language
  framework="$(extract_field "$output" "framework")"
  language="$(extract_field "$output" "language")"
  assert_equal "$framework" "spring"
  assert_equal "$language" "kotlin"
}

@test "discovery-detection: build.gradle + src/main/java + spring returns java spring" {
  local dir="$TEST_TEMP/java-spring"
  mkdir -p "$dir/src/main/java"
  printf 'plugins { id "org.springframework.boot" }\n' > "$dir/build.gradle"

  run bash "$DETECT_SCRIPT" "$dir"
  assert_success
  local framework language
  framework="$(extract_field "$output" "framework")"
  language="$(extract_field "$output" "language")"
  assert_equal "$framework" "spring"
  assert_equal "$language" "java"
}

@test "discovery-detection: pom.xml + spring returns java spring" {
  local dir="$TEST_TEMP/maven-spring"
  mkdir -p "$dir/src/main/java"
  cat > "$dir/pom.xml" <<'EOF'
<project>
  <groupId>com.example</groupId>
  <artifactId>test</artifactId>
  <parent>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-parent</artifactId>
  </parent>
</project>
EOF

  run bash "$DETECT_SCRIPT" "$dir"
  assert_success
  local framework language
  framework="$(extract_field "$output" "framework")"
  language="$(extract_field "$output" "language")"
  assert_equal "$framework" "spring"
  assert_equal "$language" "java"
}

@test "discovery-detection: pom.xml without spring returns java null framework" {
  local dir="$TEST_TEMP/maven-plain"
  mkdir -p "$dir/src/main/java"
  cat > "$dir/pom.xml" <<'EOF'
<project>
  <groupId>com.example</groupId>
  <artifactId>test</artifactId>
</project>
EOF

  run bash "$DETECT_SCRIPT" "$dir"
  assert_success
  local language
  language="$(extract_field "$output" "language")"
  assert_equal "$language" "java"
  # framework should be null (JSON null)
  python3 -c "import json; d=json.loads('$output'); assert d['framework'] is None, f'Expected null, got {d[\"framework\"]}'"
}

@test "discovery-detection: build.gradle.kts + src/commonMain returns kotlin-multiplatform" {
  local dir="$TEST_TEMP/kmp-project"
  mkdir -p "$dir/src/commonMain"
  printf 'plugins { kotlin("multiplatform") version "2.0.0" }\n' > "$dir/build.gradle.kts"

  run bash "$DETECT_SCRIPT" "$dir"
  assert_success
  local framework type
  framework="$(extract_field "$output" "framework")"
  type="$(extract_field "$output" "type")"
  assert_equal "$framework" "kotlin-multiplatform"
  assert_equal "$type" "kmp"
}

# ===========================================================================
# 5. Rust, Go, Python, Swift detection
# ===========================================================================

@test "discovery-detection: Cargo.toml returns rust backend" {
  local dir="$TEST_TEMP/rust-project"
  mkdir -p "$dir"
  printf '[package]\nname = "test"\nversion = "0.1.0"\nedition = "2021"\n' > "$dir/Cargo.toml"

  run bash "$DETECT_SCRIPT" "$dir"
  assert_success
  local language type
  language="$(extract_field "$output" "language")"
  type="$(extract_field "$output" "type")"
  assert_equal "$language" "rust"
  assert_equal "$type" "backend"
}

@test "discovery-detection: Cargo.toml + axum dep returns axum framework" {
  local dir="$TEST_TEMP/axum-project"
  mkdir -p "$dir"
  printf '[package]\nname = "test"\nversion = "0.1.0"\n\n[dependencies]\naxum = "0.7"\n' > "$dir/Cargo.toml"

  run bash "$DETECT_SCRIPT" "$dir"
  assert_success
  local framework
  framework="$(extract_field "$output" "framework")"
  assert_equal "$framework" "axum"
}

@test "discovery-detection: go.mod returns go backend with go-stdlib" {
  local dir="$TEST_TEMP/go-project"
  mkdir -p "$dir"
  printf 'module example.com/test\n\ngo 1.21\n' > "$dir/go.mod"

  run bash "$DETECT_SCRIPT" "$dir"
  assert_success
  local language framework
  language="$(extract_field "$output" "language")"
  framework="$(extract_field "$output" "framework")"
  assert_equal "$language" "go"
  assert_equal "$framework" "go-stdlib"
}

@test "discovery-detection: go.mod + gin dep returns gin framework" {
  local dir="$TEST_TEMP/gin-project"
  mkdir -p "$dir"
  printf 'module example.com/test\n\ngo 1.21\n\nrequire github.com/gin-gonic/gin v1.9.1\n' > "$dir/go.mod"

  run bash "$DETECT_SCRIPT" "$dir"
  assert_success
  local framework
  framework="$(extract_field "$output" "framework")"
  assert_equal "$framework" "gin"
}

@test "discovery-detection: pyproject.toml + fastapi dep returns python fastapi" {
  local dir="$TEST_TEMP/fastapi-project"
  mkdir -p "$dir"
  printf '[project]\nname = "test"\ndependencies = ["fastapi>=0.100"]\n' > "$dir/pyproject.toml"

  run bash "$DETECT_SCRIPT" "$dir"
  assert_success
  local language framework
  language="$(extract_field "$output" "language")"
  framework="$(extract_field "$output" "framework")"
  assert_equal "$language" "python"
  assert_equal "$framework" "fastapi"
}

@test "discovery-detection: requirements.txt + django returns python django" {
  local dir="$TEST_TEMP/django-project"
  mkdir -p "$dir"
  printf 'django>=5.0\npsycopg2\n' > "$dir/requirements.txt"

  run bash "$DETECT_SCRIPT" "$dir"
  assert_success
  local language framework
  language="$(extract_field "$output" "language")"
  framework="$(extract_field "$output" "framework")"
  assert_equal "$language" "python"
  assert_equal "$framework" "django"
}

@test "discovery-detection: requirements.txt without known framework returns python null" {
  local dir="$TEST_TEMP/python-plain"
  mkdir -p "$dir"
  printf 'requests>=2.28\n' > "$dir/requirements.txt"

  run bash "$DETECT_SCRIPT" "$dir"
  assert_success
  local language
  language="$(extract_field "$output" "language")"
  assert_equal "$language" "python"
  python3 -c "import json; d=json.loads('$output'); assert d['framework'] is None, f'Expected null, got {d[\"framework\"]}'"
}

@test "discovery-detection: Package.swift with xcodeproj returns swift swiftui mobile" {
  local dir="$TEST_TEMP/swift-project"
  mkdir -p "$dir/test.xcodeproj"
  touch "$dir/test.xcodeproj/project.pbxproj"
  printf '// swift-tools-version:5.9\nimport PackageDescription\nlet package = Package(name: "test")\n' > "$dir/Package.swift"

  run bash "$DETECT_SCRIPT" "$dir"
  assert_success
  local language type framework
  language="$(extract_field "$output" "language")"
  type="$(extract_field "$output" "type")"
  framework="$(extract_field "$output" "framework")"
  assert_equal "$language" "swift"
  assert_equal "$type" "mobile"
  assert_equal "$framework" "swiftui"
}

# ===========================================================================
# 6. Infrastructure detection
# ===========================================================================

@test "discovery-detection: k8s directory returns infra k8s" {
  local dir="$TEST_TEMP/infra-project"
  mkdir -p "$dir/k8s"
  touch "$dir/k8s/deployment.yaml"

  run bash "$DETECT_SCRIPT" "$dir"
  assert_success
  local type framework
  type="$(extract_field "$output" "type")"
  framework="$(extract_field "$output" "framework")"
  assert_equal "$type" "infra"
  assert_equal "$framework" "k8s"
}

@test "discovery-detection: Dockerfile only (no k8s) returns infra null framework" {
  local dir="$TEST_TEMP/docker-only"
  mkdir -p "$dir"
  printf 'FROM ubuntu:22.04\nRUN echo hello\n' > "$dir/Dockerfile"

  run bash "$DETECT_SCRIPT" "$dir"
  assert_success
  local type
  type="$(extract_field "$output" "type")"
  assert_equal "$type" "infra"
  python3 -c "import json; d=json.loads('$output'); assert d['framework'] is None, f'Expected null, got {d[\"framework\"]}'"
}

@test "discovery-detection: Makefile + C files returns embedded" {
  local dir="$TEST_TEMP/embedded-project"
  mkdir -p "$dir"
  touch "$dir/Makefile"
  echo 'int main() { return 0; }' > "$dir/main.c"

  run bash "$DETECT_SCRIPT" "$dir"
  assert_success
  local type framework language
  type="$(extract_field "$output" "type")"
  framework="$(extract_field "$output" "framework")"
  language="$(extract_field "$output" "language")"
  assert_equal "$type" "embedded"
  assert_equal "$framework" "embedded"
  assert_equal "$language" "c"
}

@test "discovery-detection: .csproj file returns aspnet csharp" {
  local dir="$TEST_TEMP/dotnet-project"
  mkdir -p "$dir"
  cat > "$dir/TestApp.csproj" <<'EOF'
<Project Sdk="Microsoft.NET.Sdk.Web">
  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
  </PropertyGroup>
</Project>
EOF

  run bash "$DETECT_SCRIPT" "$dir"
  assert_success
  local framework language
  framework="$(extract_field "$output" "framework")"
  language="$(extract_field "$output" "language")"
  assert_equal "$framework" "aspnet"
  assert_equal "$language" "csharp"
}

# ===========================================================================
# 7. Code quality detection
# ===========================================================================

@test "discovery-detection: detekt config detected in code_quality" {
  local dir="$TEST_TEMP/kotlin-detekt"
  mkdir -p "$dir/src/main/kotlin"
  printf 'plugins { kotlin("jvm") }\n' > "$dir/build.gradle.kts"
  touch "$dir/.detekt.yml"

  run bash "$DETECT_SCRIPT" "$dir"
  assert_success
  python3 -c "
import json
d = json.loads('$output')
assert 'detekt' in d.get('code_quality', []), f'Expected detekt in code_quality, got {d.get(\"code_quality\", [])}'
"
}

@test "discovery-detection: eslint config detected in code_quality" {
  local dir="$TEST_TEMP/ts-eslint"
  mkdir -p "$dir"
  echo '{"name":"test"}' > "$dir/package.json"
  touch "$dir/eslint.config.js"

  run bash "$DETECT_SCRIPT" "$dir"
  assert_success
  python3 -c "
import json
d = json.loads('$output')
assert 'eslint' in d.get('code_quality', []), f'Expected eslint in code_quality, got {d.get(\"code_quality\", [])}'
"
}

# ===========================================================================
# 8. Output format validation
# ===========================================================================

@test "discovery-detection: output is valid JSON" {
  local dir="$TEST_TEMP/any-project"
  mkdir -p "$dir"
  echo '{"name":"test"}' > "$dir/package.json"

  run bash "$DETECT_SCRIPT" "$dir"
  assert_success
  python3 -c "import json; json.loads('$output')" || fail "Output is not valid JSON: $output"
}

@test "discovery-detection: output contains required fields (type, framework, language)" {
  local dir="$TEST_TEMP/field-check"
  mkdir -p "$dir"
  echo '{"name":"test"}' > "$dir/package.json"

  run bash "$DETECT_SCRIPT" "$dir"
  assert_success
  python3 -c "
import json
d = json.loads('$output')
assert 'type' in d, 'Missing type field'
assert 'framework' in d, 'Missing framework field'
assert 'language' in d, 'Missing language field'
assert 'code_quality' in d, 'Missing code_quality field'
"
}

@test "discovery-detection: code_quality is always a JSON array" {
  local dir="$TEST_TEMP/array-check"
  mkdir -p "$dir"

  run bash "$DETECT_SCRIPT" "$dir"
  assert_success
  python3 -c "
import json
d = json.loads('$output')
assert isinstance(d.get('code_quality'), list), f'code_quality should be a list, got {type(d.get(\"code_quality\"))}'
"
}

# ===========================================================================
# 9. Edge cases
# ===========================================================================

@test "discovery-detection: Dockerfile + package.json prefers package.json detection" {
  local dir="$TEST_TEMP/mixed-docker-node"
  mkdir -p "$dir"
  echo '{"name":"test","dependencies":{"express":"4.18"}}' > "$dir/package.json"
  printf 'FROM node:20\nCOPY . .\n' > "$dir/Dockerfile"

  run bash "$DETECT_SCRIPT" "$dir"
  assert_success
  local type framework
  type="$(extract_field "$output" "type")"
  framework="$(extract_field "$output" "framework")"
  assert_equal "$type" "backend"
  assert_equal "$framework" "express"
}

@test "discovery-detection: vite config without recognized framework defaults to react" {
  local dir="$TEST_TEMP/vite-unknown"
  mkdir -p "$dir"
  echo '{"name":"test"}' > "$dir/package.json"
  touch "$dir/vite.config.ts"

  run bash "$DETECT_SCRIPT" "$dir"
  assert_success
  local framework
  framework="$(extract_field "$output" "framework")"
  assert_equal "$framework" "react"
}

@test "discovery-detection: Package.swift + vapor keyword returns vapor backend" {
  local dir="$TEST_TEMP/vapor-project"
  mkdir -p "$dir/test.xcodeproj"
  touch "$dir/test.xcodeproj/project.pbxproj"
  printf '// swift-tools-version:5.9\nimport PackageDescription\nlet package = Package(name: "test", dependencies: [.package(url: "vapor", from: "4.0.0")])\n' > "$dir/Package.swift"

  run bash "$DETECT_SCRIPT" "$dir"
  assert_success
  local framework type
  framework="$(extract_field "$output" "framework")"
  type="$(extract_field "$output" "type")"
  assert_equal "$framework" "vapor"
  assert_equal "$type" "backend"
}

@test "discovery-detection: sveltekit config with vite still returns sveltekit (not svelte)" {
  local dir="$TEST_TEMP/sveltekit-vite"
  mkdir -p "$dir"
  echo '{"name":"test","devDependencies":{"svelte":"5.0.0"}}' > "$dir/package.json"
  touch "$dir/vite.config.ts"
  touch "$dir/svelte.config.js"

  run bash "$DETECT_SCRIPT" "$dir"
  assert_success
  local framework
  framework="$(extract_field "$output" "framework")"
  assert_equal "$framework" "sveltekit"
}

@test "discovery-detection: jetpack-compose detected from build.gradle.kts with compose dep" {
  local dir="$TEST_TEMP/compose-project"
  mkdir -p "$dir"
  cat > "$dir/build.gradle.kts" <<'GRADLE'
plugins {
    id("com.android.application")
    kotlin("android")
}
dependencies {
    implementation("androidx.compose.ui:ui:1.5.0")
}
GRADLE

  run bash "$DETECT_SCRIPT" "$dir"
  assert_success
  local framework type
  framework="$(extract_field "$output" "framework")"
  type="$(extract_field "$output" "type")"
  assert_equal "$framework" "jetpack-compose"
  assert_equal "$type" "mobile"
}
