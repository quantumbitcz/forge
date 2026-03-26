#!/usr/bin/env bats
# Contract tests: module directory completeness (three-layer structure).

load '../helpers/test-helpers'

FRAMEWORKS_DIR="$PLUGIN_ROOT/modules/frameworks"
LANGUAGES_DIR="$PLUGIN_ROOT/modules/languages"
TESTING_DIR="$PLUGIN_ROOT/modules/testing"
LEARNINGS_DIR="$PLUGIN_ROOT/shared/learnings"

EXPECTED_LAYERS=(
  databases
  persistence
  migrations
  api-protocols
  messaging
  caching
  search
  storage
  auth
  observability
)

EXPECTED_FRAMEWORKS=(
  spring
  react
  fastapi
  axum
  swiftui
  vapor
  express
  sveltekit
  k8s
  embedded
  go-stdlib
  aspnet
  django
  nextjs
  gin
  jetpack-compose
  kotlin-multiplatform
  angular
  nestjs
  vue
  svelte
)

EXPECTED_LANGUAGES=(
  kotlin
  java
  typescript
  python
  go
  rust
  swift
  c
  csharp
  ruby
  php
  dart
  elixir
  scala
  cpp
)

EXPECTED_TESTING_FILES=(
  kotest.md
  junit5.md
  vitest.md
  jest.md
  pytest.md
  go-testing.md
  xctest.md
  rust-test.md
  xunit-nunit.md
  testcontainers.md
  playwright.md
  cypress.md
  cucumber.md
)

REQUIRED_FILES=(
  conventions.md
  local-template.md
  pipeline-config-template.md
  rules-override.json
  known-deprecations.json
)

# ---------------------------------------------------------------------------
# 1. All 21 framework directories exist
# ---------------------------------------------------------------------------
@test "module-completeness: all 21 expected framework directories exist" {
  local missing=()
  for fw in "${EXPECTED_FRAMEWORKS[@]}"; do
    if [[ ! -d "$FRAMEWORKS_DIR/$fw" ]]; then
      missing+=("$fw")
    fi
  done
  if (( ${#missing[@]} > 0 )); then
    fail "Missing framework directories: ${missing[*]}"
  fi
}

# ---------------------------------------------------------------------------
# 2. Each framework has 5 required files
# ---------------------------------------------------------------------------
@test "module-completeness: each framework has all 5 required files" {
  local failures=()
  for fw in "${EXPECTED_FRAMEWORKS[@]}"; do
    for required_file in "${REQUIRED_FILES[@]}"; do
      if [[ ! -f "$FRAMEWORKS_DIR/$fw/$required_file" ]]; then
        failures+=("$fw/$required_file")
      fi
    done
  done
  if (( ${#failures[@]} > 0 )); then
    fail "Missing required framework files: ${failures[*]}"
  fi
}

# ---------------------------------------------------------------------------
# 3. conventions.md has Don'ts section
# ---------------------------------------------------------------------------
@test "module-completeness: conventions.md has Don'ts section" {
  local failures=()
  for fw in "${EXPECTED_FRAMEWORKS[@]}"; do
    local conv_file="$FRAMEWORKS_DIR/$fw/conventions.md"
    if [[ ! -f "$conv_file" ]]; then
      continue
    fi
    # Look for case-insensitive variant of "don't" or "donts" or "Do Not"
    if ! grep -qiE "don'?t|do not" "$conv_file"; then
      failures+=("$fw")
    fi
  done
  if (( ${#failures[@]} > 0 )); then
    fail "conventions.md missing Don'ts section in frameworks: ${failures[*]}"
  fi
}

# ---------------------------------------------------------------------------
# 4. pipeline-config-template has total_retries_max + oscillation_tolerance
# ---------------------------------------------------------------------------
@test "module-completeness: pipeline-config-template has total_retries_max and oscillation_tolerance" {
  local failures=()
  for fw in "${EXPECTED_FRAMEWORKS[@]}"; do
    local tmpl="$FRAMEWORKS_DIR/$fw/pipeline-config-template.md"
    if [[ ! -f "$tmpl" ]]; then
      continue
    fi
    local missing_fields=()
    grep -q "total_retries_max" "$tmpl" || missing_fields+=("total_retries_max")
    grep -q "oscillation_tolerance" "$tmpl" || missing_fields+=("oscillation_tolerance")
    if (( ${#missing_fields[@]} > 0 )); then
      failures+=("$fw: missing ${missing_fields[*]}")
    fi
  done
  if (( ${#failures[@]} > 0 )); then
    fail "pipeline-config-template missing required fields: ${failures[*]}"
  fi
}

# ---------------------------------------------------------------------------
# 5. local-template has linear: section
# ---------------------------------------------------------------------------
@test "module-completeness: local-template has linear: section" {
  local failures=()
  for fw in "${EXPECTED_FRAMEWORKS[@]}"; do
    local tmpl="$FRAMEWORKS_DIR/$fw/local-template.md"
    if [[ ! -f "$tmpl" ]]; then
      continue
    fi
    if ! grep -q "linear:" "$tmpl"; then
      failures+=("$fw")
    fi
  done
  if (( ${#failures[@]} > 0 )); then
    fail "local-template missing linear: section in frameworks: ${failures[*]}"
  fi
}

# ---------------------------------------------------------------------------
# 6. Learnings file exists per framework
# ---------------------------------------------------------------------------
@test "module-completeness: learnings file exists for each framework" {
  local missing=()
  for fw in "${EXPECTED_FRAMEWORKS[@]}"; do
    if [[ ! -f "$LEARNINGS_DIR/$fw.md" ]]; then
      missing+=("$fw")
    fi
  done
  if (( ${#missing[@]} > 0 )); then
    fail "Missing learnings files: ${missing[*]}"
  fi
}

# ---------------------------------------------------------------------------
# 7. All 9 language files exist in modules/languages/
# ---------------------------------------------------------------------------
@test "module-completeness: all 9 language files exist in modules/languages/" {
  local missing=()
  for lang in "${EXPECTED_LANGUAGES[@]}"; do
    if [[ ! -f "$LANGUAGES_DIR/$lang.md" ]]; then
      missing+=("$lang.md")
    fi
  done
  if (( ${#missing[@]} > 0 )); then
    fail "Missing language files: ${missing[*]}"
  fi
}

# ---------------------------------------------------------------------------
# 8. All 11 testing files exist in modules/testing/
# ---------------------------------------------------------------------------
@test "module-completeness: all 11 testing files exist in modules/testing/" {
  local missing=()
  for tf in "${EXPECTED_TESTING_FILES[@]}"; do
    if [[ ! -f "$TESTING_DIR/$tf" ]]; then
      missing+=("$tf")
    fi
  done
  if (( ${#missing[@]} > 0 )); then
    fail "Missing testing files: ${missing[*]}"
  fi
}

# ---------------------------------------------------------------------------
# 9. Learnings file exists per language
# ---------------------------------------------------------------------------
@test "module-completeness: learnings file exists for each language" {
  local missing=()
  for lang in "${EXPECTED_LANGUAGES[@]}"; do
    if [[ ! -f "$LEARNINGS_DIR/$lang.md" ]]; then
      missing+=("$lang")
    fi
  done
  if (( ${#missing[@]} > 0 )); then
    fail "Missing language learnings files: ${missing[*]}"
  fi
}

# ---------------------------------------------------------------------------
# 10. Learnings file exists per testing framework
# ---------------------------------------------------------------------------
@test "module-completeness: learnings file exists for each testing framework" {
  local missing=()
  for tf in "${EXPECTED_TESTING_FILES[@]}"; do
    local name="${tf%.md}"
    if [[ ! -f "$LEARNINGS_DIR/$name.md" ]]; then
      missing+=("$name")
    fi
  done
  if (( ${#missing[@]} > 0 )); then
    fail "Missing testing learnings files: ${missing[*]}"
  fi
}

# ---------------------------------------------------------------------------
# 11. Learnings file exists per crosscutting layer
# ---------------------------------------------------------------------------
@test "module-completeness: learnings file exists for each crosscutting layer" {
  local missing=()
  for layer in "${EXPECTED_LAYERS[@]}"; do
    if [[ ! -f "$LEARNINGS_DIR/$layer.md" ]]; then
      missing+=("$layer")
    fi
  done
  if (( ${#missing[@]} > 0 )); then
    fail "Missing crosscutting layer learnings files: ${missing[*]}"
  fi
}
