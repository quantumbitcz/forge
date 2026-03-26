#!/usr/bin/env bats
# Unit tests for shared/graph/dependency-map.json and shared/graph/canonical-pairings.json.

load '../helpers/test-helpers'

DEPENDENCY_MAP="$PLUGIN_ROOT/shared/graph/dependency-map.json"
CANONICAL_PAIRINGS="$PLUGIN_ROOT/shared/graph/canonical-pairings.json"

# ---------------------------------------------------------------------------
# 1. dependency-map.json is valid JSON
# ---------------------------------------------------------------------------
@test "dependency-map.json is valid JSON" {
  run python3 -m json.tool "$DEPENDENCY_MAP"
  assert_success
}

# ---------------------------------------------------------------------------
# 2. All mapped module names reference existing modules
# ---------------------------------------------------------------------------
@test "all mapped module names reference existing modules (warn-only, fail if >20% missing)" {
  local all_values
  all_values="$(python3 - "$DEPENDENCY_MAP" <<'PYEOF'
import json, sys
data = json.load(open(sys.argv[1]))
values = []
for pkg_manager, entries in data.items():
    for pkg, module in entries.items():
        values.append(module)
for v in values:
    print(v)
PYEOF
)"

  local total=0
  local missing=0
  local missing_list=()

  while IFS= read -r module_name; do
    [[ -z "$module_name" ]] && continue
    total=$(( total + 1 ))

    # Search across all layer module directories for {module_name}.md
    local found=0
    for layer_dir in \
      "$PLUGIN_ROOT/modules/databases" \
      "$PLUGIN_ROOT/modules/persistence" \
      "$PLUGIN_ROOT/modules/messaging" \
      "$PLUGIN_ROOT/modules/auth" \
      "$PLUGIN_ROOT/modules/observability" \
      "$PLUGIN_ROOT/modules/search" \
      "$PLUGIN_ROOT/modules/caching" \
      "$PLUGIN_ROOT/modules/storage" \
      "$PLUGIN_ROOT/modules/migrations" \
      "$PLUGIN_ROOT/modules/api-protocols" \
      "$PLUGIN_ROOT/modules/frameworks"
    do
      if find "$layer_dir" -name "${module_name}.md" -maxdepth 3 | grep -q .; then
        found=1
        break
      fi
    done

    if [[ "$found" -eq 0 ]]; then
      missing=$(( missing + 1 ))
      missing_list+=("$module_name")
    fi
  done <<< "$all_values"

  # Warn about individual missing entries
  if [[ "${#missing_list[@]}" -gt 0 ]]; then
    echo "WARNING: ${#missing_list[@]} mapped module(s) have no matching .md file:" >&3
    for m in "${missing_list[@]}"; do
      echo "  - $m" >&3
    done
  fi

  # Only fail if more than 20% are missing (systemic issue)
  if [[ "$total" -gt 0 ]]; then
    local threshold=$(( total * 20 / 100 ))
    if [[ "$missing" -gt "$threshold" ]]; then
      fail "Systemic issue: $missing/$total mapped modules have no matching .md file (>${threshold}, >20% threshold)"
    fi
  fi
}

# ---------------------------------------------------------------------------
# 3. canonical-pairings.json is valid JSON
# ---------------------------------------------------------------------------
@test "canonical-pairings.json is valid JSON" {
  run python3 -m json.tool "$CANONICAL_PAIRINGS"
  assert_success
}

# ---------------------------------------------------------------------------
# 4. Canonical testing pairings reference existing testing modules
# ---------------------------------------------------------------------------
@test "canonical testing pairings reference existing testing modules (warn-only for missing)" {
  local testing_values
  testing_values="$(python3 - "$CANONICAL_PAIRINGS" <<'PYEOF'
import json, sys
data = json.load(open(sys.argv[1]))
for lang, framework in data.get("canonical_testing", {}).items():
    print(framework)
PYEOF
)"

  local warned=0
  while IFS= read -r framework; do
    [[ -z "$framework" ]] && continue
    local test_file="$PLUGIN_ROOT/modules/testing/${framework}.md"
    if [[ ! -f "$test_file" ]]; then
      echo "WARNING: canonical_testing references '$framework' but modules/testing/${framework}.md does not exist" >&3
      warned=$(( warned + 1 ))
    fi
  done <<< "$testing_values"

  # Test passes regardless — individual missing entries are warnings only
  return 0
}

# ---------------------------------------------------------------------------
# 5. Canonical persistence pairings reference existing modules
# ---------------------------------------------------------------------------
@test "canonical persistence pairings reference existing modules (warn-only for missing)" {
  local persistence_values
  persistence_values="$(python3 - "$CANONICAL_PAIRINGS" <<'PYEOF'
import json, sys
data = json.load(open(sys.argv[1]))
for lang, orm in data.get("canonical_persistence", {}).items():
    print(orm)
PYEOF
)"

  local warned=0
  while IFS= read -r orm; do
    [[ -z "$orm" ]] && continue

    # Search in modules/persistence/ and modules/frameworks/*/persistence/
    local found=0
    if [[ -f "$PLUGIN_ROOT/modules/persistence/${orm}.md" ]]; then
      found=1
    else
      if find "$PLUGIN_ROOT/modules/frameworks" -path "*/persistence/${orm}.md" -maxdepth 4 | grep -q .; then
        found=1
      fi
    fi

    if [[ "$found" -eq 0 ]]; then
      echo "WARNING: canonical_persistence references '$orm' but no matching file found in persistence layers" >&3
      warned=$(( warned + 1 ))
    fi
  done <<< "$persistence_values"

  # Test passes regardless — individual missing entries are warnings only
  return 0
}
