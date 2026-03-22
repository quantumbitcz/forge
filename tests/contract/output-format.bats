#!/usr/bin/env bats
# Contract tests: check engine output format compliance.
# Tests run run-patterns.sh against a real temp file in a temp git repo.

load '../helpers/test-helpers'

RUN_PATTERNS="$PLUGIN_ROOT/shared/checks/layer-1-fast/run-patterns.sh"
KOTLIN_RULES="$PLUGIN_ROOT/shared/checks/layer-1-fast/patterns/kotlin.json"

# Known category prefixes from output-format.md
KNOWN_PREFIXES="^(ARCH|SEC|PERF|QUAL|CONV|DOC|TEST|HEX|THEME|INFRA|ASYNC|CONTRACT)-"

# Each test gets its own temp git repo via setup() from test-helpers.
# We create a dedicated project dir for these tests.

_make_kotlin_file() {
  local content="$1"
  local kt_file="${TEST_TEMP}/project/src/Test.kt"
  mkdir -p "$(dirname "$kt_file")"
  printf '%s' "$content" > "$kt_file"
  git -C "${TEST_TEMP}/project" add src/Test.kt 2>/dev/null || true
  printf '%s' "$kt_file"
}

# ---------------------------------------------------------------------------
# 1. Pattern findings match format spec
#    Format: file:line | CATEGORY-CODE | SEVERITY | message | fix_hint
# ---------------------------------------------------------------------------
@test "output-format: findings match file:line | CATEGORY-CODE | SEVERITY | message | fix_hint" {
  local kt_file
  kt_file="$(_make_kotlin_file 'val x = obj!!'$'\n')"

  run bash "$RUN_PATTERNS" "$kt_file" "$KOTLIN_RULES"
  assert_success

  # Should have at least one finding
  [[ -n "$output" ]] || fail "Expected at least one finding from !! in kotlin file"

  # Validate each non-empty line matches the format
  assert_finding_format "$output"
}

# ---------------------------------------------------------------------------
# 2. SEVERITY values are exactly CRITICAL, WARNING, or INFO
# ---------------------------------------------------------------------------
@test "output-format: severity values are exactly CRITICAL WARNING or INFO" {
  local kt_file
  # !! -> WARNING, hardcoded credential -> CRITICAL, abbreviated name -> INFO
  kt_file="$(_make_kotlin_file 'val x = obj!!'$'\n''val password = "secret123"'$'\n''val longName = "ok"'$'\n')"

  run bash "$RUN_PATTERNS" "$kt_file" "$KOTLIN_RULES"
  assert_success

  local invalid_severities=()
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    # Extract the 3rd pipe-delimited field (severity), trimming spaces
    local severity
    severity="$(printf '%s' "$line" | awk -F' \\| ' '{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $3); print $3}')"
    if [[ "$severity" != "CRITICAL" && "$severity" != "WARNING" && "$severity" != "INFO" ]]; then
      invalid_severities+=("$severity in: $line")
    fi
  done <<< "$output"

  if (( ${#invalid_severities[@]} > 0 )); then
    fail "Invalid severity values: ${invalid_severities[*]}"
  fi
}

# ---------------------------------------------------------------------------
# 3. CATEGORY matches known prefixes
# ---------------------------------------------------------------------------
@test "output-format: category codes match known prefixes" {
  local kt_file
  kt_file="$(_make_kotlin_file 'val x = obj!!'$'\n''val password = "secret123"'$'\n')"

  run bash "$RUN_PATTERNS" "$kt_file" "$KOTLIN_RULES"
  assert_success

  local invalid_categories=()
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    # Extract the 2nd pipe-delimited field (category-code), trimming spaces
    local category
    category="$(printf '%s' "$line" | awk -F' \\| ' '{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2}')"
    if ! printf '%s' "$category" | grep -qE "$KNOWN_PREFIXES"; then
      invalid_categories+=("$category in: $line")
    fi
  done <<< "$output"

  if (( ${#invalid_categories[@]} > 0 )); then
    fail "Unknown category prefixes: ${invalid_categories[*]}"
  fi
}

# ---------------------------------------------------------------------------
# 4. Line number is an integer >= 0
# ---------------------------------------------------------------------------
@test "output-format: line numbers are non-negative integers" {
  local kt_file
  kt_file="$(_make_kotlin_file 'val x = obj!!'$'\n')"

  run bash "$RUN_PATTERNS" "$kt_file" "$KOTLIN_RULES"
  assert_success

  local invalid_lines=()
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    # Extract file:line_no prefix (first field before first space-pipe)
    local file_lineno
    file_lineno="$(printf '%s' "$line" | awk -F' \\| ' '{print $1}')"
    # Line number is the part after the last colon
    local lineno
    lineno="$(printf '%s' "$file_lineno" | rev | cut -d: -f1 | rev)"
    if ! printf '%s' "$lineno" | grep -qE '^[0-9]+$'; then
      invalid_lines+=("lineno='$lineno' in: $line")
    fi
  done <<< "$output"

  if (( ${#invalid_lines[@]} > 0 )); then
    fail "Invalid line numbers: ${invalid_lines[*]}"
  fi
}

# ---------------------------------------------------------------------------
# 5. Dedup-key uniqueness: (file, line, category) combinations are unique
# ---------------------------------------------------------------------------
@test "output-format: no duplicate (file, line, category) dedup keys" {
  local kt_file
  # Multiple different findings — each (file, line, category) pair should be unique
  kt_file="$(_make_kotlin_file 'val x = obj!!'$'\n''val password = "secret123"'$'\n''val threadObj = Thread.sleep(100)'$'\n')"

  run bash "$RUN_PATTERNS" "$kt_file" "$KOTLIN_RULES"
  assert_success

  local dedup_keys=()
  local duplicates=()
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    # Extract file:line (field 1) and category (field 2)
    local file_lineno
    file_lineno="$(printf '%s' "$line" | awk -F' \\| ' '{print $1}')"
    local category
    category="$(printf '%s' "$line" | awk -F' \\| ' '{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2}')"
    local key="${file_lineno}::${category}"
    # Check if key already seen
    local found=0
    for existing in "${dedup_keys[@]:-}"; do
      if [[ "$existing" == "$key" ]]; then
        found=1
        break
      fi
    done
    if (( found )); then
      duplicates+=("$key")
    else
      dedup_keys+=("$key")
    fi
  done <<< "$output"

  if (( ${#duplicates[@]} > 0 )); then
    fail "Duplicate dedup keys (file:line::category): ${duplicates[*]}"
  fi
}
