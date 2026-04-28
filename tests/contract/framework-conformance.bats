#!/usr/bin/env bats
# Contract tests: framework conformance against base-template.md requirements.
# Validates content quality beyond mere file existence (covered by module-completeness.bats).

load '../helpers/test-helpers'

# shellcheck source=../lib/module-lists.bash
source "$PLUGIN_ROOT/tests/lib/module-lists.bash"

FRAMEWORKS_DIR="$PLUGIN_ROOT/modules/frameworks"
LEARNINGS_DIR="$PLUGIN_ROOT/shared/learnings"

# ---------------------------------------------------------------------------
# 1. Required files exist (explicit per-framework loop for clear failure messages)
# ---------------------------------------------------------------------------
@test "framework-conformance: all frameworks have required files" {
  local failures=()
  for fw in "${DISCOVERED_FRAMEWORKS[@]}"; do
    for required in conventions.md local-template.md forge-config-template.md rules-override.json known-deprecations.json; do
      if [[ ! -f "$FRAMEWORKS_DIR/$fw/$required" ]]; then
        failures+=("$fw/$required")
      fi
    done
  done
  if (( ${#failures[@]} > 0 )); then
    fail "Missing required framework files: ${failures[*]}"
  fi
}

# ---------------------------------------------------------------------------
# 2. conventions.md has Dos and Don'ts section
# ---------------------------------------------------------------------------
@test "framework-conformance: conventions.md has Dos and Don'ts section" {
  local failures=()
  for fw in "${DISCOVERED_FRAMEWORKS[@]}"; do
    local conv="$FRAMEWORKS_DIR/$fw/conventions.md"
    [[ -f "$conv" ]] || continue
    # Frameworks use combined "## Dos and Don'ts" heading
    if ! grep -q "^## Dos" "$conv"; then
      failures+=("$fw: missing Dos section")
    fi
    if ! grep -qiE "Don.t" "$conv"; then
      failures+=("$fw: missing Don'ts content")
    fi
  done
  if (( ${#failures[@]} > 0 )); then
    fail "conventions.md conformance failures: ${failures[*]}"
  fi
}

# ---------------------------------------------------------------------------
# 3. forge-config-template.md contains total_retries_max
# ---------------------------------------------------------------------------
@test "framework-conformance: forge-config-template.md has total_retries_max" {
  local failures=()
  for fw in "${DISCOVERED_FRAMEWORKS[@]}"; do
    local cfg="$FRAMEWORKS_DIR/$fw/forge-admin config-template.md"
    [[ -f "$cfg" ]] || continue
    if ! grep -q 'total_retries_max' "$cfg"; then
      failures+=("$fw")
    fi
  done
  if (( ${#failures[@]} > 0 )); then
    fail "forge-config-template.md missing total_retries_max: ${failures[*]}"
  fi
}

# ---------------------------------------------------------------------------
# 4. forge-config-template.md contains oscillation_tolerance
# ---------------------------------------------------------------------------
@test "framework-conformance: forge-config-template.md has oscillation_tolerance" {
  local failures=()
  for fw in "${DISCOVERED_FRAMEWORKS[@]}"; do
    local cfg="$FRAMEWORKS_DIR/$fw/forge-admin config-template.md"
    [[ -f "$cfg" ]] || continue
    if ! grep -q 'oscillation_tolerance' "$cfg"; then
      failures+=("$fw")
    fi
  done
  if (( ${#failures[@]} > 0 )); then
    fail "forge-config-template.md missing oscillation_tolerance: ${failures[*]}"
  fi
}

# ---------------------------------------------------------------------------
# 5. known-deprecations.json is valid JSON with v2 schema fields
# ---------------------------------------------------------------------------
@test "framework-conformance: known-deprecations.json is valid v2 schema" {
  local failures=()
  for fw in "${DISCOVERED_FRAMEWORKS[@]}"; do
    local dep="$FRAMEWORKS_DIR/$fw/known-deprecations.json"
    [[ -f "$dep" ]] || continue
    local result
    result="$(python3 - "$dep" <<'PYEOF'
import json, sys
dep_file = sys.argv[1]
try:
    with open(dep_file) as f:
        data = json.load(f)
except (json.JSONDecodeError, IOError) as e:
    print(f"invalid JSON: {e}")
    sys.exit(0)
entries = data.get('deprecations', data) if isinstance(data, dict) else data
if not isinstance(entries, list):
    print("not an array of deprecation entries")
    sys.exit(0)
if len(entries) < 5:
    print(f"only {len(entries)} entries (minimum 5 per CLAUDE.md)")
    sys.exit(0)
for i, e in enumerate(entries):
    for field in ['pattern', 'replacement', 'since']:
        if field not in e:
            print(f"entry[{i}] missing '{field}'")
PYEOF
)"
    if [[ -n "$result" ]]; then
      failures+=("$fw: $result")
    fi
  done
  if (( ${#failures[@]} > 0 )); then
    fail "known-deprecations.json v2 schema failures: ${failures[*]}"
  fi
}

# ---------------------------------------------------------------------------
# 6. rules-override.json is valid JSON
# ---------------------------------------------------------------------------
@test "framework-conformance: rules-override.json is valid JSON" {
  local failures=()
  for fw in "${DISCOVERED_FRAMEWORKS[@]}"; do
    local ro="$FRAMEWORKS_DIR/$fw/rules-override.json"
    [[ -f "$ro" ]] || continue
    if ! python3 -c "import json; json.load(open('$ro'))" 2>/dev/null; then
      failures+=("$fw")
    fi
  done
  if (( ${#failures[@]} > 0 )); then
    fail "Invalid rules-override.json in frameworks: ${failures[*]}"
  fi
}

# ---------------------------------------------------------------------------
# 7. local-template.md has YAML frontmatter with required fields
# ---------------------------------------------------------------------------
@test "framework-conformance: local-template.md has required frontmatter fields" {
  local failures=()
  for fw in "${DISCOVERED_FRAMEWORKS[@]}"; do
    local tpl="$FRAMEWORKS_DIR/$fw/local-template.md"
    [[ -f "$tpl" ]] || continue
    local first_line
    first_line="$(head -1 "$tpl")"
    if [[ "$first_line" != "---" ]]; then
      failures+=("$fw: missing frontmatter opening ---")
      continue
    fi
    if ! grep -q 'components:' "$tpl"; then
      failures+=("$fw: missing components:")
    fi
    if ! grep -q 'commands:' "$tpl"; then
      failures+=("$fw: missing commands:")
    fi
  done
  if (( ${#failures[@]} > 0 )); then
    fail "local-template.md frontmatter failures: ${failures[*]}"
  fi
}

# ---------------------------------------------------------------------------
# 8. local-template.md has correct shared implementation defaults
# ---------------------------------------------------------------------------
@test "framework-conformance: local-template.md has correct implementation defaults" {
  local failures=()
  for fw in "${DISCOVERED_FRAMEWORKS[@]}"; do
    local tpl="$FRAMEWORKS_DIR/$fw/local-template.md"
    [[ -f "$tpl" ]] || continue
    if ! grep -q 'parallel_threshold: 3' "$tpl"; then
      failures+=("$fw: missing parallel_threshold: 3")
    fi
    if ! grep -q 'max_fix_loops: 3' "$tpl"; then
      failures+=("$fw: missing max_fix_loops: 3")
    fi
    if ! grep -q 'tdd: true' "$tpl"; then
      failures+=("$fw: missing tdd: true")
    fi
  done
  if (( ${#failures[@]} > 0 )); then
    fail "local-template.md shared defaults drift: ${failures[*]}"
  fi
}

# ---------------------------------------------------------------------------
# 9. Learnings file exists for each framework
# ---------------------------------------------------------------------------
@test "framework-conformance: learnings file exists for each framework" {
  local missing=()
  for fw in "${DISCOVERED_FRAMEWORKS[@]}"; do
    if [[ ! -f "$LEARNINGS_DIR/$fw.md" ]]; then
      missing+=("$fw")
    fi
  done
  if (( ${#missing[@]} > 0 )); then
    fail "Missing framework learnings files: ${missing[*]}"
  fi
}

# ---------------------------------------------------------------------------
# 10. Learnings file exists for each language
# ---------------------------------------------------------------------------
@test "framework-conformance: learnings file exists for each language" {
  local missing=()
  for lang in "${DISCOVERED_LANGUAGES[@]}"; do
    if [[ ! -f "$LEARNINGS_DIR/$lang.md" ]]; then
      missing+=("$lang")
    fi
  done
  if (( ${#missing[@]} > 0 )); then
    fail "Missing language learnings files: ${missing[*]}"
  fi
}
