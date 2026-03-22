#!/usr/bin/env bats
# Contract tests: module directory completeness.

load '../helpers/test-helpers'

MODULES_DIR="$PLUGIN_ROOT/modules"
LEARNINGS_DIR="$PLUGIN_ROOT/shared/learnings"

EXPECTED_MODULES=(
  c-embedded
  go-stdlib
  infra-k8s
  java-spring
  kotlin-spring
  python-fastapi
  react-vite
  rust-axum
  swift-ios
  swift-vapor
  typescript-node
  typescript-svelte
)

REQUIRED_FILES=(
  conventions.md
  local-template.md
  pipeline-config-template.md
  rules-override.json
  known-deprecations.json
)

# ---------------------------------------------------------------------------
# 1. All 12 modules exist
# ---------------------------------------------------------------------------
@test "module-completeness: all 12 expected modules exist" {
  local missing=()
  for module in "${EXPECTED_MODULES[@]}"; do
    if [[ ! -d "$MODULES_DIR/$module" ]]; then
      missing+=("$module")
    fi
  done
  if (( ${#missing[@]} > 0 )); then
    fail "Missing module directories: ${missing[*]}"
  fi
}

# ---------------------------------------------------------------------------
# 2. Each module has 5 required files
# ---------------------------------------------------------------------------
@test "module-completeness: each module has all 5 required files" {
  local failures=()
  for module in "${EXPECTED_MODULES[@]}"; do
    for required_file in "${REQUIRED_FILES[@]}"; do
      if [[ ! -f "$MODULES_DIR/$module/$required_file" ]]; then
        failures+=("$module/$required_file")
      fi
    done
  done
  if (( ${#failures[@]} > 0 )); then
    fail "Missing required module files: ${failures[*]}"
  fi
}

# ---------------------------------------------------------------------------
# 3. conventions.md has Don'ts section
# ---------------------------------------------------------------------------
@test "module-completeness: conventions.md has Don'ts section" {
  local failures=()
  for module in "${EXPECTED_MODULES[@]}"; do
    local conv_file="$MODULES_DIR/$module/conventions.md"
    if [[ ! -f "$conv_file" ]]; then
      continue
    fi
    # Look for case-insensitive variant of "don't" or "donts" or "Do Not"
    if ! grep -qiE "don'?t|do not" "$conv_file"; then
      failures+=("$module")
    fi
  done
  if (( ${#failures[@]} > 0 )); then
    fail "conventions.md missing Don'ts section in modules: ${failures[*]}"
  fi
}

# ---------------------------------------------------------------------------
# 4. pipeline-config-template has total_retries_max + oscillation_tolerance
# ---------------------------------------------------------------------------
@test "module-completeness: pipeline-config-template has total_retries_max and oscillation_tolerance" {
  local failures=()
  for module in "${EXPECTED_MODULES[@]}"; do
    local tmpl="$MODULES_DIR/$module/pipeline-config-template.md"
    if [[ ! -f "$tmpl" ]]; then
      continue
    fi
    local missing_fields=()
    grep -q "total_retries_max" "$tmpl" || missing_fields+=("total_retries_max")
    grep -q "oscillation_tolerance" "$tmpl" || missing_fields+=("oscillation_tolerance")
    if (( ${#missing_fields[@]} > 0 )); then
      failures+=("$module: missing ${missing_fields[*]}")
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
  for module in "${EXPECTED_MODULES[@]}"; do
    local tmpl="$MODULES_DIR/$module/local-template.md"
    if [[ ! -f "$tmpl" ]]; then
      continue
    fi
    if ! grep -q "linear:" "$tmpl"; then
      failures+=("$module")
    fi
  done
  if (( ${#failures[@]} > 0 )); then
    fail "local-template missing linear: section in modules: ${failures[*]}"
  fi
}

# ---------------------------------------------------------------------------
# 6. Learnings file exists per module
# ---------------------------------------------------------------------------
@test "module-completeness: learnings file exists for each module" {
  local missing=()
  for module in "${EXPECTED_MODULES[@]}"; do
    if [[ ! -f "$LEARNINGS_DIR/$module.md" ]]; then
      missing+=("$module")
    fi
  done
  if (( ${#missing[@]} > 0 )); then
    fail "Missing learnings files: ${missing[*]}"
  fi
}
