#!/usr/bin/env bats
# Contract tests: known-deprecations.json schema v2 compliance.

load '../helpers/test-helpers'

MODULES_DIR="$PLUGIN_ROOT/modules/frameworks"

EXPECTED_MODULES=(
  axum
  embedded
  express
  fastapi
  go-stdlib
  k8s
  react
  spring
  sveltekit
  swiftui
  vapor
)

# ---------------------------------------------------------------------------
# Helper: run a python3 validation over all deprecation files
# ---------------------------------------------------------------------------
_run_python_check() {
  local script="$1"
  python3 -c "$script" "$MODULES_DIR" "${EXPECTED_MODULES[@]}"
}

# ---------------------------------------------------------------------------
# 1. All are schema v2 (version: 2)
# ---------------------------------------------------------------------------
@test "deprecation-schema: all modules have version: 2" {
  local failures=()
  for module in "${EXPECTED_MODULES[@]}"; do
    local dep_file="$MODULES_DIR/$module/known-deprecations.json"
    if [[ ! -f "$dep_file" ]]; then
      failures+=("$module: file missing")
      continue
    fi
    local version
    version="$(python3 -c "import json; d=json.load(open('$dep_file')); print(d.get('version',''))")"
    if [[ "$version" != "2" ]]; then
      failures+=("$module: version=$version")
    fi
  done
  if (( ${#failures[@]} > 0 )); then
    fail "Modules with wrong schema version: ${failures[*]}"
  fi
}

# ---------------------------------------------------------------------------
# 2. Required v2 fields present (pattern, replacement, package, since, applies_from, applies_to)
# ---------------------------------------------------------------------------
@test "deprecation-schema: all entries have required v2 fields" {
  local failures=()
  local required_fields=("pattern" "replacement" "package" "since" "applies_from" "applies_to")
  for module in "${EXPECTED_MODULES[@]}"; do
    local dep_file="$MODULES_DIR/$module/known-deprecations.json"
    [[ ! -f "$dep_file" ]] && continue
    local result
    result="$(python3 - "$dep_file" "${required_fields[@]}" <<'PYEOF'
import json, sys
dep_file = sys.argv[1]
required = sys.argv[2:]
with open(dep_file) as f:
    data = json.load(f)
issues = []
for i, entry in enumerate(data.get('deprecations', [])):
    for field in required:
        if field not in entry:
            issues.append(f"entry[{i}] missing '{field}'")
if issues:
    print('\n'.join(issues))
PYEOF
)"
    if [[ -n "$result" ]]; then
      failures+=("$module: $result")
    fi
  done
  if (( ${#failures[@]} > 0 )); then
    fail "Deprecation entries missing required fields: ${failures[*]}"
  fi
}

# ---------------------------------------------------------------------------
# 3. added and addedBy present
# ---------------------------------------------------------------------------
@test "deprecation-schema: all entries have added and addedBy fields" {
  local failures=()
  for module in "${EXPECTED_MODULES[@]}"; do
    local dep_file="$MODULES_DIR/$module/known-deprecations.json"
    [[ ! -f "$dep_file" ]] && continue
    local result
    result="$(python3 - "$dep_file" <<'PYEOF'
import json, sys
dep_file = sys.argv[1]
with open(dep_file) as f:
    data = json.load(f)
issues = []
for i, entry in enumerate(data.get('deprecations', [])):
    if 'added' not in entry:
        issues.append(f"entry[{i}] missing 'added'")
    if 'addedBy' not in entry:
        issues.append(f"entry[{i}] missing 'addedBy'")
if issues:
    print('\n'.join(issues))
PYEOF
)"
    if [[ -n "$result" ]]; then
      failures+=("$module: $result")
    fi
  done
  if (( ${#failures[@]} > 0 )); then
    fail "Deprecation entries missing added/addedBy fields: ${failures[*]}"
  fi
}

# ---------------------------------------------------------------------------
# 4. No empty patterns
# ---------------------------------------------------------------------------
@test "deprecation-schema: no entries have empty pattern field" {
  local failures=()
  for module in "${EXPECTED_MODULES[@]}"; do
    local dep_file="$MODULES_DIR/$module/known-deprecations.json"
    [[ ! -f "$dep_file" ]] && continue
    local result
    result="$(python3 - "$dep_file" <<'PYEOF'
import json, sys
dep_file = sys.argv[1]
with open(dep_file) as f:
    data = json.load(f)
issues = []
for i, entry in enumerate(data.get('deprecations', [])):
    pattern = entry.get('pattern', None)
    if pattern is None or str(pattern).strip() == '':
        issues.append(f"entry[{i}] has empty or missing pattern")
if issues:
    print('\n'.join(issues))
PYEOF
)"
    if [[ -n "$result" ]]; then
      failures+=("$module: $result")
    fi
  done
  if (( ${#failures[@]} > 0 )); then
    fail "Deprecation entries with empty patterns: ${failures[*]}"
  fi
}

# ---------------------------------------------------------------------------
# 5. removed_in is null or non-empty string
# ---------------------------------------------------------------------------
@test "deprecation-schema: removed_in is null or non-empty string" {
  local failures=()
  for module in "${EXPECTED_MODULES[@]}"; do
    local dep_file="$MODULES_DIR/$module/known-deprecations.json"
    [[ ! -f "$dep_file" ]] && continue
    local result
    result="$(python3 - "$dep_file" <<'PYEOF'
import json, sys
dep_file = sys.argv[1]
with open(dep_file) as f:
    data = json.load(f)
issues = []
for i, entry in enumerate(data.get('deprecations', [])):
    if 'removed_in' not in entry:
        issues.append(f"entry[{i}] missing 'removed_in' key (must be null or version string)")
        continue
    removed_in = entry['removed_in']
    if removed_in is not None and (not isinstance(removed_in, str) or removed_in.strip() == ''):
        issues.append(f"entry[{i}] removed_in must be null or non-empty string, got: {repr(removed_in)}")
if issues:
    print('\n'.join(issues))
PYEOF
)"
    if [[ -n "$result" ]]; then
      failures+=("$module: $result")
    fi
  done
  if (( ${#failures[@]} > 0 )); then
    fail "Deprecation entries with invalid removed_in: ${failures[*]}"
  fi
}

# ---------------------------------------------------------------------------
# 6. No duplicate patterns per module
# ---------------------------------------------------------------------------
@test "deprecation-schema: no duplicate patterns within a module" {
  local failures=()
  for module in "${EXPECTED_MODULES[@]}"; do
    local dep_file="$MODULES_DIR/$module/known-deprecations.json"
    [[ ! -f "$dep_file" ]] && continue
    local result
    result="$(python3 - "$dep_file" <<'PYEOF'
import json, sys
dep_file = sys.argv[1]
with open(dep_file) as f:
    data = json.load(f)
seen = {}
duplicates = []
for i, entry in enumerate(data.get('deprecations', [])):
    pattern = entry.get('pattern', '')
    if pattern in seen:
        duplicates.append(f"pattern '{pattern}' duplicated at entry[{seen[pattern]}] and entry[{i}]")
    else:
        seen[pattern] = i
if duplicates:
    print('\n'.join(duplicates))
PYEOF
)"
    if [[ -n "$result" ]]; then
      failures+=("$module: $result")
    fi
  done
  if (( ${#failures[@]} > 0 )); then
    fail "Duplicate patterns found in modules: ${failures[*]}"
  fi
}
