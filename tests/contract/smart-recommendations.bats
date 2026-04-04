#!/usr/bin/env bats
# Contract tests: code-quality module frontmatter for smart tool recommendations.

load '../helpers/test-helpers'

CODE_QUALITY_DIR="$PLUGIN_ROOT/modules/code-quality"

# ---------------------------------------------------------------------------
# 1. All modules have YAML frontmatter (first line is ---)
# ---------------------------------------------------------------------------
@test "smart-recommendations: all code-quality modules start with --- on line 1" {
  local failures=()
  for module_file in "$CODE_QUALITY_DIR"/*.md; do
    local first_line
    first_line="$(head -1 "$module_file")"
    if [[ "$first_line" != "---" ]]; then
      failures+=("$(basename "$module_file")")
    fi
  done
  if (( ${#failures[@]} > 0 )); then
    fail "Code-quality modules missing frontmatter opening ---: ${failures[*]}"
  fi
}

# ---------------------------------------------------------------------------
# 2. All modules have required frontmatter fields
# ---------------------------------------------------------------------------
@test "smart-recommendations: all modules have name: field" {
  local failures=()
  for module_file in "$CODE_QUALITY_DIR"/*.md; do
    if ! grep -qE '^name:' "$module_file"; then
      failures+=("$(basename "$module_file")")
    fi
  done
  if (( ${#failures[@]} > 0 )); then
    fail "Code-quality modules missing name: field: ${failures[*]}"
  fi
}

@test "smart-recommendations: all modules have categories: field" {
  local failures=()
  for module_file in "$CODE_QUALITY_DIR"/*.md; do
    if ! grep -qE '^categories:' "$module_file"; then
      failures+=("$(basename "$module_file")")
    fi
  done
  if (( ${#failures[@]} > 0 )); then
    fail "Code-quality modules missing categories: field: ${failures[*]}"
  fi
}

@test "smart-recommendations: all modules have languages: field" {
  local failures=()
  for module_file in "$CODE_QUALITY_DIR"/*.md; do
    if ! grep -qE '^languages:' "$module_file"; then
      failures+=("$(basename "$module_file")")
    fi
  done
  if (( ${#failures[@]} > 0 )); then
    fail "Code-quality modules missing languages: field: ${failures[*]}"
  fi
}

@test "smart-recommendations: all modules have exclusive_group: field" {
  local failures=()
  for module_file in "$CODE_QUALITY_DIR"/*.md; do
    if ! grep -qE '^exclusive_group:' "$module_file"; then
      failures+=("$(basename "$module_file")")
    fi
  done
  if (( ${#failures[@]} > 0 )); then
    fail "Code-quality modules missing exclusive_group: field: ${failures[*]}"
  fi
}

@test "smart-recommendations: all modules have recommendation_score: field" {
  local failures=()
  for module_file in "$CODE_QUALITY_DIR"/*.md; do
    if ! grep -qE '^recommendation_score:' "$module_file"; then
      failures+=("$(basename "$module_file")")
    fi
  done
  if (( ${#failures[@]} > 0 )); then
    fail "Code-quality modules missing recommendation_score: field: ${failures[*]}"
  fi
}

@test "smart-recommendations: all modules have detection_files: field" {
  local failures=()
  for module_file in "$CODE_QUALITY_DIR"/*.md; do
    if ! grep -qE '^detection_files:' "$module_file"; then
      failures+=("$(basename "$module_file")")
    fi
  done
  if (( ${#failures[@]} > 0 )); then
    fail "Code-quality modules missing detection_files: field: ${failures[*]}"
  fi
}

# ---------------------------------------------------------------------------
# 3. recommendation_score values are integers in range 1-100
# ---------------------------------------------------------------------------
@test "smart-recommendations: recommendation_score is integer 1-100" {
  local failures=()
  for module_file in "$CODE_QUALITY_DIR"/*.md; do
    local score
    score="$(grep -m1 '^recommendation_score:' "$module_file" | sed 's/recommendation_score: *//')"
    if ! [[ "$score" =~ ^[0-9]+$ ]] || (( score < 1 || score > 100 )); then
      failures+=("$(basename "$module_file") (score='$score')")
    fi
  done
  if (( ${#failures[@]} > 0 )); then
    fail "Code-quality modules with invalid recommendation_score: ${failures[*]}"
  fi
}

# ---------------------------------------------------------------------------
# 4. name: matches filename without .md extension
# ---------------------------------------------------------------------------
@test "smart-recommendations: name field matches filename" {
  local failures=()
  for module_file in "$CODE_QUALITY_DIR"/*.md; do
    local basename_no_ext
    basename_no_ext="$(basename "$module_file" .md)"
    local name_field
    name_field="$(grep -m1 '^name:' "$module_file" | sed 's/name: *//')"
    if [[ "$name_field" != "$basename_no_ext" ]]; then
      failures+=("$(basename "$module_file") (name='$name_field')")
    fi
  done
  if (( ${#failures[@]} > 0 )); then
    fail "Code-quality modules where name: does not match filename: ${failures[*]}"
  fi
}

# ---------------------------------------------------------------------------
# 5. Known exclusive groups exist with exactly one score-90 default winner
# ---------------------------------------------------------------------------
@test "smart-recommendations: kotlin-formatter group has exactly one score-90 tool" {
  local winners=()
  for module_file in "$CODE_QUALITY_DIR"/*.md; do
    local group score
    group="$(grep -m1 '^exclusive_group:' "$module_file" | sed 's/exclusive_group: *//')"
    score="$(grep -m1 '^recommendation_score:' "$module_file" | sed 's/recommendation_score: *//')"
    if [[ "$group" == "kotlin-formatter" ]] && [[ "$score" == "90" ]]; then
      winners+=("$(basename "$module_file")")
    fi
  done
  if (( ${#winners[@]} == 0 )); then
    fail "kotlin-formatter group has no score-90 default winner"
  fi
  if (( ${#winners[@]} > 1 )); then
    fail "kotlin-formatter group has multiple score-90 winners: ${winners[*]}"
  fi
}

@test "smart-recommendations: js-formatter group has at least one member" {
  # biome (the default winner) lives in js-linter group since it covers both linting and formatting;
  # js-formatter group holds alternatives like prettier. At minimum one formatter tool must exist.
  local members=()
  for module_file in "$CODE_QUALITY_DIR"/*.md; do
    local group cats
    group="$(grep -m1 '^exclusive_group:' "$module_file" | sed 's/exclusive_group: *//')"
    cats="$(grep -m1 '^categories:' "$module_file" | sed 's/categories: *//')"
    if [[ "$group" == "js-formatter" ]] || { [[ "$group" == "js-linter" ]] && [[ "$cats" == *"formatter"* ]]; }; then
      members+=("$(basename "$module_file")")
    fi
  done
  if (( ${#members[@]} == 0 )); then
    fail "No JS formatter tool found (js-formatter group or js-linter with formatter category)"
  fi
}

@test "smart-recommendations: js-linter group has exactly one score-90 tool" {
  local winners=()
  for module_file in "$CODE_QUALITY_DIR"/*.md; do
    local group score
    group="$(grep -m1 '^exclusive_group:' "$module_file" | sed 's/exclusive_group: *//')"
    score="$(grep -m1 '^recommendation_score:' "$module_file" | sed 's/recommendation_score: *//')"
    if [[ "$group" == "js-linter" ]] && [[ "$score" == "90" ]]; then
      winners+=("$(basename "$module_file")")
    fi
  done
  if (( ${#winners[@]} == 0 )); then
    fail "js-linter group has no score-90 default winner"
  fi
  if (( ${#winners[@]} > 1 )); then
    fail "js-linter group has multiple score-90 winners: ${winners[*]}"
  fi
}

@test "smart-recommendations: python-formatter group has at least one tool" {
  local members=()
  for module_file in "$CODE_QUALITY_DIR"/*.md; do
    local group
    group="$(grep -m1 '^exclusive_group:' "$module_file" | sed 's/exclusive_group: *//')"
    if [[ "$group" == "python-formatter" ]]; then
      members+=("$(basename "$module_file")")
    fi
  done
  if (( ${#members[@]} == 0 )); then
    fail "python-formatter group has no members"
  fi
}

@test "smart-recommendations: python-linter group has exactly one score-90 tool" {
  local winners=()
  for module_file in "$CODE_QUALITY_DIR"/*.md; do
    local group score
    group="$(grep -m1 '^exclusive_group:' "$module_file" | sed 's/exclusive_group: *//')"
    score="$(grep -m1 '^recommendation_score:' "$module_file" | sed 's/recommendation_score: *//')"
    if [[ "$group" == "python-linter" ]] && [[ "$score" == "90" ]]; then
      winners+=("$(basename "$module_file")")
    fi
  done
  if (( ${#winners[@]} == 0 )); then
    fail "python-linter group has no score-90 default winner"
  fi
  if (( ${#winners[@]} > 1 )); then
    fail "python-linter group has multiple score-90 winners: ${winners[*]}"
  fi
}

# ---------------------------------------------------------------------------
# 6. categories contain only valid values
# ---------------------------------------------------------------------------
@test "smart-recommendations: categories contain only valid values" {
  local valid_categories=("linter" "formatter" "coverage" "doc-generator" "security-scanner" "mutation-tester")
  local failures=()
  for module_file in "$CODE_QUALITY_DIR"/*.md; do
    local cats_line
    cats_line="$(grep -m1 '^categories:' "$module_file" | sed 's/categories: *//')"
    # Strip [ ] brackets and split by comma
    local cats_raw
    cats_raw="${cats_line//[[\]]/}"
    IFS=',' read -ra cats <<< "$cats_raw"
    for cat in "${cats[@]}"; do
      cat="${cat// /}"
      local valid=false
      for valid_cat in "${valid_categories[@]}"; do
        if [[ "$cat" == "$valid_cat" ]]; then
          valid=true
          break
        fi
      done
      if [[ "$valid" == "false" ]]; then
        failures+=("$(basename "$module_file") (invalid category: '$cat')")
      fi
    done
  done
  if (( ${#failures[@]} > 0 )); then
    fail "Code-quality modules with invalid categories: ${failures[*]}"
  fi
}

# ---------------------------------------------------------------------------
# 7. Minimum module count guard
# ---------------------------------------------------------------------------
@test "smart-recommendations: minimum 60 code-quality modules present" {
  local count
  count="$(ls -1 "$CODE_QUALITY_DIR"/*.md 2>/dev/null | wc -l | tr -d ' ')"
  if (( count < 60 )); then
    fail "Expected at least 60 code-quality modules, found $count — accidental deletion?"
  fi
}
