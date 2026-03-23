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
    # Distinguish React vs SvelteKit both using Vite
    if [[ -f "$DIR/svelte.config.js" || -f "$DIR/svelte.config.ts" ]]; then
      framework="sveltekit"
    else
      framework="react"
    fi
  elif [[ -f "$DIR/next.config.js" || -f "$DIR/next.config.ts" || -f "$DIR/next.config.mjs" ]]; then
    framework="nextjs"
  elif [[ -f "$DIR/svelte.config.js" || -f "$DIR/svelte.config.ts" ]]; then
    framework="sveltekit"
  elif [[ -f "$DIR/angular.json" ]]; then
    framework="angular"
    language="typescript"
  else
    # Could still be a backend Node project — check for src/main pattern
    if [[ -d "$DIR/src/main" ]]; then
      type="backend"
      framework="node"
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
    framework="kotlin"
  fi
elif ($has_gradle || $has_gradle_kts) && [[ -d "$DIR/src/main/java" ]]; then
  type="backend"
  language="java"
  if [[ -f "$DIR/build.gradle.kts" ]] && grep -q "spring" "$DIR/build.gradle.kts" 2>/dev/null; then
    framework="spring"
  elif [[ -f "$DIR/build.gradle" ]] && grep -q "spring" "$DIR/build.gradle" 2>/dev/null; then
    framework="spring"
  else
    framework="java"
  fi
elif $has_pom; then
  type="backend"
  language="java"
  if grep -q "spring" "$DIR/pom.xml" 2>/dev/null; then
    framework="spring"
  else
    framework="java"
  fi

# Android mobile
elif ($has_gradle || $has_gradle_kts) && grep -q "android" "${DIR}/build.gradle.kts" 2>/dev/null; then
  type="mobile"
  framework="android"
  language="kotlin"
elif ($has_gradle || $has_gradle_kts) && grep -q "android" "${DIR}/build.gradle" 2>/dev/null; then
  type="mobile"
  framework="android"
  language="java"

# iOS mobile
elif $has_package_swift && ls "$DIR"/*.xcodeproj 2>/dev/null | grep -q .; then
  type="mobile"
  language="swift"
  if grep -q -i "vapor" "$DIR/Package.swift" 2>/dev/null; then
    framework="vapor"
    type="backend"
  else
    framework="swiftui"
  fi
elif ls "$DIR"/*.xcodeproj 2>/dev/null | grep -q .; then
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
    framework="rust"
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
    framework="flask"
  else
    framework="python"
  fi

# Go backend
elif $has_go_mod; then
  type="backend"
  language="go"
  framework="go"
fi

# Infra: helm/k8s/terraform directories take precedence if no src code found
if [[ "$type" == "unknown" ]]; then
  if [[ -d "$DIR/helm" || -d "$DIR/k8s" || -d "$DIR/terraform" || -d "$DIR/charts" ]]; then
    type="infra"
    framework="kubernetes"
    language="yaml"
  elif [[ -f "$DIR/Dockerfile" ]] && [[ ! -f "$DIR/package.json" && ! $has_gradle_kts && ! $has_cargo ]]; then
    type="infra"
    framework="docker"
    language="dockerfile"
  fi
fi

printf '{"type":"%s","framework":"%s","language":"%s"}\n' "$type" "$framework" "$language"
