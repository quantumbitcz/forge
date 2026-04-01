#!/usr/bin/env bash
# Detect project type and framework from directory contents
# Usage: detect-project-type.sh <directory>
# Output: JSON {"type": "frontend", "framework": "react", "language": "typescript"}

set -euo pipefail

DIR="${1:-}"

if [[ -z "$DIR" || ! -d "$DIR" ]]; then
  printf '{"type":"unknown","framework":"unknown","language":"unknown"}\n'
  exit 0
fi

type="unknown"
framework="unknown"
language="unknown"

# ── Language detection ────────────────────────────────────────────────────────

has_package_json=false
has_ts_config=false
has_gradle_kts=false
has_gradle=false
has_pom=false
has_cargo=false
has_requirements=false
has_go_mod=false
has_package_swift=false

[[ -f "$DIR/package.json" ]]        && has_package_json=true
[[ -f "$DIR/tsconfig.json" ]]       && has_ts_config=true
[[ -f "$DIR/build.gradle.kts" ]]    && has_gradle_kts=true
[[ -f "$DIR/build.gradle" ]]        && has_gradle=true
[[ -f "$DIR/pom.xml" ]]             && has_pom=true
[[ -f "$DIR/Cargo.toml" ]]          && has_cargo=true
[[ -f "$DIR/requirements.txt" || -f "$DIR/pyproject.toml" ]] && has_requirements=true
[[ -f "$DIR/go.mod" ]]              && has_go_mod=true
[[ -f "$DIR/Package.swift" ]]       && has_package_swift=true

# ── Type + framework detection ────────────────────────────────────────────────

# Frontend: package.json + vite/next/svelte/angular config
if $has_package_json; then
  language="javascript"
  $has_ts_config && language="typescript"
  type="frontend"

  if [[ -f "$DIR/vite.config.ts" || -f "$DIR/vite.config.js" || -f "$DIR/vite.config.mts" ]]; then
    # Distinguish Vite-based frameworks by their config files
    if [[ -f "$DIR/svelte.config.js" || -f "$DIR/svelte.config.ts" ]]; then
      framework="sveltekit"
    elif grep -qE '"vue"|"@vitejs/plugin-vue"' "$DIR/package.json" 2>/dev/null; then
      framework="vue"
    elif grep -qE '"svelte"|"@sveltejs/vite-plugin-svelte"' "$DIR/package.json" 2>/dev/null; then
      framework="svelte"
    elif grep -qE '"react"|"@vitejs/plugin-react"' "$DIR/package.json" 2>/dev/null; then
      framework="react"
    else
      # Vite without a recognized framework — default to react (most common)
      framework="react"
    fi
  elif [[ -f "$DIR/next.config.js" || -f "$DIR/next.config.ts" || -f "$DIR/next.config.mjs" ]]; then
    framework="nextjs"
  elif [[ -f "$DIR/svelte.config.js" || -f "$DIR/svelte.config.ts" ]]; then
    framework="sveltekit"
  elif [[ -f "$DIR/angular.json" ]]; then
    framework="angular"
    language="typescript"
  elif [[ -f "$DIR/nest-cli.json" ]]; then
    type="backend"
    framework="nestjs"
  elif grep -qE '"express"' "$DIR/package.json" 2>/dev/null; then
    type="backend"
    framework="express"
  else
    # Could still be a backend Node project — check for src/main pattern or server-like markers
    # Fastify/Koa/Hapi mapped to express (closest available framework module)
    if [[ -d "$DIR/src/main" ]] || grep -qE '"fastify"|"koa"|"hapi"' "$DIR/package.json" 2>/dev/null; then
      type="backend"
      framework="express"
    fi
  fi
fi

# Kotlin Multiplatform (before generic backend check)
if $has_gradle_kts && [[ -d "$DIR/src/commonMain" ]]; then
  type="kmp"
  framework="kotlin-multiplatform"
  language="kotlin"

# Kotlin/Spring or Java/Spring backend
elif $has_gradle_kts && [[ -d "$DIR/src/main/kotlin" ]]; then
  type="backend"
  language="kotlin"
  if grep -q "spring" "$DIR/build.gradle.kts" 2>/dev/null; then
    framework="spring"
  else
    framework="null"
  fi
elif ($has_gradle || $has_gradle_kts) && [[ -d "$DIR/src/main/java" ]]; then
  type="backend"
  language="java"
  if [[ -f "$DIR/build.gradle.kts" ]] && grep -q "spring" "$DIR/build.gradle.kts" 2>/dev/null; then
    framework="spring"
  elif [[ -f "$DIR/build.gradle" ]] && grep -q "spring" "$DIR/build.gradle" 2>/dev/null; then
    framework="spring"
  else
    framework="null"
  fi
elif $has_pom; then
  type="backend"
  language="java"
  if grep -q "spring" "$DIR/pom.xml" 2>/dev/null; then
    framework="spring"
  else
    framework="null"
  fi

# Jetpack Compose mobile (before generic android — compose is more specific)
# Check both Kotlin DSL (build.gradle.kts) and Groovy DSL (build.gradle)
elif ($has_gradle_kts || $has_gradle) && \
     { grep -qE 'org\.jetbrains\.compose|androidx\.compose' "$DIR/build.gradle.kts" 2>/dev/null || \
       grep -qE 'org\.jetbrains\.compose|androidx\.compose' "$DIR/build.gradle" 2>/dev/null; }; then
  type="mobile"
  framework="jetpack-compose"
  language="kotlin"

# Android mobile — maps to jetpack-compose (closest available module).
# No separate "android" framework module exists; jetpack-compose covers modern Android dev.
# pipeline-init presents this to the user for confirmation and allows override.
elif ($has_gradle || $has_gradle_kts) && grep -q "android" "${DIR}/build.gradle.kts" 2>/dev/null; then
  type="mobile"
  framework="jetpack-compose"
  language="kotlin"
elif ($has_gradle || $has_gradle_kts) && grep -q "android" "${DIR}/build.gradle" 2>/dev/null; then
  type="mobile"
  framework="jetpack-compose"
  language="java"

# iOS mobile
elif $has_package_swift && compgen -G "$DIR"/*.xcodeproj >/dev/null 2>&1; then
  type="mobile"
  language="swift"
  if grep -q -i "vapor" "$DIR/Package.swift" 2>/dev/null; then
    framework="vapor"
    type="backend"
  else
    framework="swiftui"
  fi
elif compgen -G "$DIR"/*.xcodeproj >/dev/null 2>&1; then
  type="mobile"
  framework="swiftui"
  language="swift"

# Rust backend
elif $has_cargo; then
  type="backend"
  language="rust"
  if grep -q "axum" "$DIR/Cargo.toml" 2>/dev/null; then
    framework="axum"
  else
    framework="null"
  fi

# Python backend
elif $has_requirements; then
  type="backend"
  language="python"
  if grep -qi "django" "$DIR/requirements.txt" 2>/dev/null || grep -qi "django" "$DIR/pyproject.toml" 2>/dev/null; then
    framework="django"
  elif grep -qi "fastapi" "$DIR/requirements.txt" 2>/dev/null || grep -qi "fastapi" "$DIR/pyproject.toml" 2>/dev/null; then
    framework="fastapi"
  elif grep -qi "flask" "$DIR/requirements.txt" 2>/dev/null || grep -qi "flask" "$DIR/pyproject.toml" 2>/dev/null; then
    framework="null"
  else
    framework="null"
  fi

# Go backend
elif $has_go_mod; then
  type="backend"
  language="go"
  if grep -q 'gin-gonic/gin' "$DIR/go.mod" 2>/dev/null; then
    framework="gin"
  else
    framework="go-stdlib"
  fi
fi

# ASP.NET / .NET backend
if [[ "$type" == "unknown" ]]; then
  if compgen -G "$DIR"/*.csproj >/dev/null 2>&1 || compgen -G "$DIR"/*.sln >/dev/null 2>&1; then
    type="backend"
    framework="aspnet"
    language="csharp"
  fi
fi

# Embedded C/C++ (Makefile + C source files, no higher-level framework detected)
if [[ "$type" == "unknown" ]]; then
  if [[ -f "$DIR/Makefile" || -f "$DIR/CMakeLists.txt" ]] && compgen -G "$DIR"/*.c >/dev/null 2>&1; then
    type="embedded"
    framework="embedded"
    language="c"
  fi
fi

# Infra: helm/k8s/terraform directories take precedence if no src code found
if [[ "$type" == "unknown" ]]; then
  if [[ -d "$DIR/helm" || -d "$DIR/k8s" || -d "$DIR/terraform" || -d "$DIR/charts" ]]; then
    type="infra"
    framework="k8s"
    language="yaml"
  elif [[ -f "$DIR/Dockerfile" ]] && [[ ! -f "$DIR/package.json" && ! $has_gradle_kts && ! $has_cargo ]]; then
    # Standalone Dockerfile without k8s manifests — no framework module applies.
    # k8s conventions (Helm, pod security) don't apply to plain containerized apps.
    type="infra"
    framework="null"
    language="dockerfile"
  fi
fi

# ── Code quality tool detection ───────────────────────────────────────────────

detected_code_quality=()

# Linting / analysis
[[ -f "$DIR/.detekt.yml" || -f "$DIR/detekt.yml" ]] && detected_code_quality+=("detekt")
if [[ -f "$DIR/.editorconfig" ]] && grep -q "ktlint_" "$DIR/.editorconfig" 2>/dev/null; then
  detected_code_quality+=("ktlint")
fi
if compgen -G "$DIR/eslint.config."* >/dev/null 2>&1 || compgen -G "$DIR/.eslintrc."* >/dev/null 2>&1 || [[ -f "$DIR/.eslintrc" ]] || \
   ( [[ -f "$DIR/package.json" ]] && grep -q '"eslintConfig"' "$DIR/package.json" 2>/dev/null ); then
  detected_code_quality+=("eslint")
fi
[[ -f "$DIR/biome.json" || -f "$DIR/biome.jsonc" ]] && detected_code_quality+=("biome")
if [[ -f "$DIR/ruff.toml" ]] || ( [[ -f "$DIR/pyproject.toml" ]] && grep -q "\[tool.ruff\]" "$DIR/pyproject.toml" 2>/dev/null ); then
  detected_code_quality+=("ruff")
fi
[[ -f "$DIR/.golangci.yml" || -f "$DIR/.golangci.yaml" ]] && detected_code_quality+=("golangci-lint")
[[ -f "$DIR/clippy.toml" || -f "$DIR/.clippy.toml" ]] && detected_code_quality+=("clippy")
[[ -f "$DIR/.swiftlint.yml" || -f "$DIR/.swiftlint.yaml" ]] && detected_code_quality+=("swiftlint")
[[ -f "$DIR/.credo.exs" ]] && detected_code_quality+=("credo")
[[ -f "$DIR/.rubocop.yml" || -f "$DIR/.rubocop.yaml" ]] && detected_code_quality+=("rubocop")
[[ -f "$DIR/phpstan.neon" || -f "$DIR/phpstan.neon.dist" ]] && detected_code_quality+=("phpstan")
[[ -f "$DIR/analysis_options.yaml" ]] && detected_code_quality+=("dart-analyzer")
[[ -f "$DIR/.scalafmt.conf" ]] && detected_code_quality+=("scalafmt")
[[ -f "$DIR/.scalafix.conf" ]] && detected_code_quality+=("scalafix")
if compgen -G "$DIR"/*.csproj >/dev/null 2>&1 && grep -ql "Analyzer" "$DIR"/*.csproj 2>/dev/null; then
  detected_code_quality+=("roslyn-analyzers")
fi
[[ -f "$DIR/checkstyle.xml" ]] && detected_code_quality+=("checkstyle")
[[ -f "$DIR/pmd.xml" || -f "$DIR/ruleset.xml" ]] && detected_code_quality+=("pmd")
[[ -f "$DIR/spotbugs-exclude.xml" ]] && detected_code_quality+=("spotbugs")
if [[ -f "$DIR/build.gradle.kts" ]] && grep -q "errorprone" "$DIR/build.gradle.kts" 2>/dev/null; then
  detected_code_quality+=("errorprone")
fi
[[ -f "$DIR/.pylintrc" || -f "$DIR/pylintrc" ]] && detected_code_quality+=("pylint")
[[ -f "$DIR/mypy.ini" || -f "$DIR/.mypy.ini" ]] && detected_code_quality+=("mypy")

# Formatting
if compgen -G "$DIR/.prettierrc"* >/dev/null 2>&1 || [[ -f "$DIR/.prettierrc" ]] || \
   ( [[ -f "$DIR/package.json" ]] && grep -q '"prettier"' "$DIR/package.json" 2>/dev/null ); then
  detected_code_quality+=("prettier")
fi
if [[ -f "$DIR/pyproject.toml" ]] && grep -q "\[tool.black\]" "$DIR/pyproject.toml" 2>/dev/null; then
  detected_code_quality+=("black")
fi
if [[ -f "$DIR/build.gradle.kts" ]] && grep -q "spotless" "$DIR/build.gradle.kts" 2>/dev/null; then
  detected_code_quality+=("spotless")
fi
[[ -f "$DIR/rustfmt.toml" || -f "$DIR/.rustfmt.toml" ]] && detected_code_quality+=("rustfmt")

# Coverage
if ( [[ -f "$DIR/build.gradle.kts" ]] && grep -q "jacoco" "$DIR/build.gradle.kts" 2>/dev/null ) || \
   ( [[ -f "$DIR/build.gradle" ]] && grep -q "jacoco" "$DIR/build.gradle" 2>/dev/null ) || \
   ( [[ -f "$DIR/pom.xml" ]] && grep -q "jacoco" "$DIR/pom.xml" 2>/dev/null ); then
  detected_code_quality+=("jacoco")
fi
if [[ -f "$DIR/.nycrc" || -f "$DIR/.nycrc.json" ]] || \
   ( [[ -f "$DIR/package.json" ]] && grep -qE '"nyc"|"c8"' "$DIR/package.json" 2>/dev/null ); then
  detected_code_quality+=("istanbul")
fi
if [[ -f "$DIR/pyproject.toml" ]] && grep -q "\[tool.coverage\]" "$DIR/pyproject.toml" 2>/dev/null || \
   [[ -f "$DIR/.coveragerc" ]]; then
  detected_code_quality+=("coverage-py")
fi
if compgen -G "$DIR"/*.csproj >/dev/null 2>&1 && grep -ql "coverlet" "$DIR"/*.csproj 2>/dev/null; then
  detected_code_quality+=("coverlet")
fi

# Security / dependency scanning
if ( [[ -f "$DIR/build.gradle.kts" ]] && grep -q "dependencyCheck" "$DIR/build.gradle.kts" 2>/dev/null ) || \
   ( [[ -f "$DIR/build.gradle" ]] && grep -q "dependencyCheck" "$DIR/build.gradle" 2>/dev/null ) || \
   ( [[ -f "$DIR/pom.xml" ]] && grep -q "dependency-check" "$DIR/pom.xml" 2>/dev/null ); then
  detected_code_quality+=("owasp-dependency-check")
fi
[[ -f "$DIR/.snyk" ]] && detected_code_quality+=("snyk")
[[ -f "$DIR/.trivy.yaml" || -f "$DIR/trivy.yaml" ]] && detected_code_quality+=("trivy")

# Build code_quality JSON array
code_quality_json="["
first=true
for tool in ${detected_code_quality[@]+"${detected_code_quality[@]}"}; do
  $first || code_quality_json+=","
  code_quality_json+="\"$tool\""
  first=false
done
code_quality_json+="]"

# Output JSON — null framework is JSON null, not string "null"
if [[ "$framework" == "null" ]]; then
  printf '{"type":"%s","framework":null,"language":"%s","code_quality":%s}\n' \
    "$type" "$language" "$code_quality_json"
else
  printf '{"type":"%s","framework":"%s","language":"%s","code_quality":%s}\n' \
    "$type" "$framework" "$language" "$code_quality_json"
fi
