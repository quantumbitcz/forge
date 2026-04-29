#!/usr/bin/env bats
# Contract tests: all rules-override.json files must have _version and _updated.

load '../helpers/test-helpers'

FRAMEWORKS_DIR="$PLUGIN_ROOT/modules/frameworks"

# ---------------------------------------------------------------------------
# 1. Every rules-override.json has _version field
# ---------------------------------------------------------------------------

@test "rules-override: all files have _version field (integer >= 1)" {
  local failures=()
  while IFS= read -r -d '' file; do
    local version
    version=$(python3 - "$file" <<'PYEOF'
import json, sys
print(json.load(open(sys.argv[1])).get('_version', 'MISSING'))
PYEOF
)
    if [[ "$version" == "MISSING" ]]; then
      failures+=("$file: missing _version")
    elif ! [[ "$version" =~ ^[0-9]+$ ]] || [[ "$version" -lt 1 ]]; then
      failures+=("$file: _version=$version (must be integer >= 1)")
    fi
  done < <(find "$FRAMEWORKS_DIR" -name "rules-override.json" -print0)

  if [[ ${#failures[@]} -gt 0 ]]; then
    printf '%s\n' "${failures[@]}" >&2
    fail "${#failures[@]} file(s) missing or invalid _version"
  fi
}

# ---------------------------------------------------------------------------
# 2. Every rules-override.json has _updated field
# ---------------------------------------------------------------------------

@test "rules-override: all files have _updated field (ISO 8601)" {
  local failures=()
  while IFS= read -r -d '' file; do
    local updated
    updated=$(python3 - "$file" <<'PYEOF'
import json, sys
print(json.load(open(sys.argv[1])).get('_updated', 'MISSING'))
PYEOF
)
    if [[ "$updated" == "MISSING" ]]; then
      failures+=("$file: missing _updated")
    elif ! [[ "$updated" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; then
      failures+=("$file: _updated=$updated (must be ISO 8601 YYYY-MM-DDThh:mm:ssZ)")
    fi
  done < <(find "$FRAMEWORKS_DIR" -name "rules-override.json" -print0)

  if [[ ${#failures[@]} -gt 0 ]]; then
    printf '%s\n' "${failures[@]}" >&2
    fail "${#failures[@]} file(s) missing or invalid _updated"
  fi
}

# ---------------------------------------------------------------------------
# 3. Files remain valid JSON after versioning
# ---------------------------------------------------------------------------

@test "rules-override: all files are valid JSON" {
  local failures=()
  while IFS= read -r -d '' file; do
    local result
    result=$(python3 - "$file" <<'PYEOF'
import json, sys
try:
    json.load(open(sys.argv[1]))
    print("OK")
except Exception:
    print("FAIL")
PYEOF
)
    if [[ "$result" != "OK" ]]; then
      failures+=("$file")
    fi
  done < <(find "$FRAMEWORKS_DIR" -name "rules-override.json" -print0)

  if [[ ${#failures[@]} -gt 0 ]]; then
    printf '%s\n' "${failures[@]}" >&2
    fail "${#failures[@]} file(s) are not valid JSON"
  fi
}

# ---------------------------------------------------------------------------
# 4. Minimum file count (21 frameworks)
# ---------------------------------------------------------------------------

@test "rules-override: at least 21 rules-override.json files exist" {
  local count
  count=$(find "$FRAMEWORKS_DIR" -name "rules-override.json" | wc -l | tr -d ' ')
  [[ "$count" -ge 21 ]] || fail "Expected >= 21 files, found $count"
}
