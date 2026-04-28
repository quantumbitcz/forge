#!/usr/bin/env bats
# Contract tests: module directory completeness (three-layer structure).

load '../helpers/test-helpers'

# Module lists discovered from disk (single source of truth: tests/lib/module-lists.bash)
# shellcheck source=../lib/module-lists.bash
source "$PLUGIN_ROOT/tests/lib/module-lists.bash"

FRAMEWORKS_DIR="$PLUGIN_ROOT/modules/frameworks"
LANGUAGES_DIR="$PLUGIN_ROOT/modules/languages"
TESTING_DIR="$PLUGIN_ROOT/modules/testing"
LEARNINGS_DIR="$PLUGIN_ROOT/shared/learnings"

EXPECTED_FRAMEWORKS=("${DISCOVERED_FRAMEWORKS[@]}")
EXPECTED_LANGUAGES=("${DISCOVERED_LANGUAGES[@]}")
EXPECTED_TESTING_FILES=("${DISCOVERED_TESTING_FILES[@]}")
EXPECTED_LAYERS=("${DISCOVERED_LAYERS[@]}")
EXPECTED_BUILD_SYSTEMS=("${DISCOVERED_BUILD_SYSTEMS[@]}")
EXPECTED_CI_PLATFORMS=("${DISCOVERED_CI_PLATFORMS[@]}")
EXPECTED_CONTAINER_ORCH=("${DISCOVERED_CONTAINER_ORCH[@]}")
REQUIRED_FILES=("${REQUIRED_FRAMEWORK_FILES[@]}")

# ---------------------------------------------------------------------------
# 0. Minimum count guards (catch accidental deletions)
# ---------------------------------------------------------------------------
@test "module-completeness: minimum module counts not violated" {
  guard_min_count "frameworks" "${#EXPECTED_FRAMEWORKS[@]}" "$MIN_FRAMEWORKS"
  guard_min_count "languages" "${#EXPECTED_LANGUAGES[@]}" "$MIN_LANGUAGES"
  guard_min_count "testing files" "${#EXPECTED_TESTING_FILES[@]}" "$MIN_TESTING_FILES"
  guard_min_count "build systems" "${#EXPECTED_BUILD_SYSTEMS[@]}" "$MIN_BUILD_SYSTEMS"
  guard_min_count "CI/CD platforms" "${#EXPECTED_CI_PLATFORMS[@]}" "$MIN_CI_PLATFORMS"
  guard_min_count "container orchestration" "${#EXPECTED_CONTAINER_ORCH[@]}" "$MIN_CONTAINER_ORCH"
}

# ---------------------------------------------------------------------------
# 1. All framework directories discovered from disk exist
# ---------------------------------------------------------------------------
@test "module-completeness: all discovered framework directories exist" {
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
# 4. forge-config-template has total_retries_max + oscillation_tolerance
# ---------------------------------------------------------------------------
@test "module-completeness: forge-config-template has total_retries_max and oscillation_tolerance" {
  local failures=()
  for fw in "${EXPECTED_FRAMEWORKS[@]}"; do
    local tmpl="$FRAMEWORKS_DIR/$fw/forge-admin config-template.md"
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
    fail "forge-config-template missing required fields: ${failures[*]}"
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
@test "module-completeness: all expected language files exist in modules/languages/" {
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
@test "module-completeness: all expected testing files exist in modules/testing/" {
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

# ---------------------------------------------------------------------------
# 12. Every crosscutting module file has a matching learnings file
# ---------------------------------------------------------------------------
@test "module-completeness: every crosscutting module has a learnings file" {
  local missing=()
  for layer in "${EXPECTED_LAYERS[@]}"; do
    local layer_dir="$PLUGIN_ROOT/modules/$layer"
    [[ -d "$layer_dir" ]] || continue
    for f in "$layer_dir"/*.md; do
      [[ -f "$f" ]] || continue
      local name
      name=$(basename "$f" .md)
      if [[ ! -f "$LEARNINGS_DIR/$name.md" ]]; then
        missing+=("$layer/$name")
      fi
    done
  done
  if (( ${#missing[@]} > 0 )); then
    fail "Crosscutting modules missing learnings files: ${missing[*]}"
  fi
}

# ---------------------------------------------------------------------------
# 13. All language files have Dos and Don'ts sections
# ---------------------------------------------------------------------------
@test "module-completeness: all language files have Dos and Don'ts sections" {
  local failures=()
  for lang in "${EXPECTED_LANGUAGES[@]}"; do
    local lang_file="$LANGUAGES_DIR/$lang.md"
    [[ -f "$lang_file" ]] || continue
    if ! grep -q "^## Dos" "$lang_file"; then
      failures+=("$lang: missing Dos")
    fi
    if ! grep -qiE "^## Don" "$lang_file"; then
      failures+=("$lang: missing Don'ts")
    fi
  done
  if (( ${#failures[@]} > 0 )); then
    fail "Language files missing Dos/Don'ts: ${failures[*]}"
  fi
}

# ---------------------------------------------------------------------------
# 14. All build system generic modules exist
# ---------------------------------------------------------------------------
@test "module-completeness: all expected build system modules exist" {
  local missing=()
  for bs in "${EXPECTED_BUILD_SYSTEMS[@]}"; do
    if [[ ! -f "$PLUGIN_ROOT/modules/build-systems/$bs.md" ]]; then
      missing+=("$bs")
    fi
  done
  if (( ${#missing[@]} > 0 )); then
    fail "Missing build system modules: ${missing[*]}"
  fi
}

# ---------------------------------------------------------------------------
# 15. Learnings file exists per build system
# ---------------------------------------------------------------------------
@test "module-completeness: learnings file exists for each build system" {
  local missing=()
  for bs in "${EXPECTED_BUILD_SYSTEMS[@]}"; do
    if [[ ! -f "$LEARNINGS_DIR/$bs.md" ]]; then
      missing+=("$bs")
    fi
  done
  if (( ${#missing[@]} > 0 )); then
    fail "Missing build system learnings files: ${missing[*]}"
  fi
}

# ---------------------------------------------------------------------------
# 16. All CI/CD platform generic modules exist
# ---------------------------------------------------------------------------
@test "module-completeness: all expected CI/CD platform modules exist" {
  local missing=()
  for ci in "${EXPECTED_CI_PLATFORMS[@]}"; do
    if [[ ! -f "$PLUGIN_ROOT/modules/ci-cd/$ci.md" ]]; then
      missing+=("$ci")
    fi
  done
  if (( ${#missing[@]} > 0 )); then
    fail "Missing CI/CD platform modules: ${missing[*]}"
  fi
}

# ---------------------------------------------------------------------------
# 17. Learnings file exists per CI/CD platform
# ---------------------------------------------------------------------------
@test "module-completeness: learnings file exists for each CI/CD platform" {
  local missing=()
  for ci in "${EXPECTED_CI_PLATFORMS[@]}"; do
    if [[ ! -f "$LEARNINGS_DIR/$ci.md" ]]; then
      missing+=("$ci")
    fi
  done
  if (( ${#missing[@]} > 0 )); then
    fail "Missing CI/CD platform learnings files: ${missing[*]}"
  fi
}

# ---------------------------------------------------------------------------
# 18. All container orchestration generic modules exist
# ---------------------------------------------------------------------------
@test "module-completeness: all expected container orchestration modules exist" {
  local missing=()
  for co in "${EXPECTED_CONTAINER_ORCH[@]}"; do
    if [[ ! -f "$PLUGIN_ROOT/modules/container-orchestration/$co.md" ]]; then
      missing+=("$co")
    fi
  done
  if (( ${#missing[@]} > 0 )); then
    fail "Missing container orchestration modules: ${missing[*]}"
  fi
}

# ---------------------------------------------------------------------------
# 19. Learnings file exists per container orchestration tool
# ---------------------------------------------------------------------------
@test "module-completeness: learnings file exists for each container orchestration tool" {
  local missing=()
  for co in "${EXPECTED_CONTAINER_ORCH[@]}"; do
    if [[ ! -f "$LEARNINGS_DIR/$co.md" ]]; then
      missing+=("$co")
    fi
  done
  if (( ${#missing[@]} > 0 )); then
    fail "Missing container orchestration learnings files: ${missing[*]}"
  fi
}
