#!/usr/bin/env bats
# Behavioral tests for the deprecation refresh agent (fg-140-deprecation-refresh)

load '../../helpers/test-helpers'

DEPR_AGENT="$PLUGIN_ROOT/agents/fg-140-deprecation-refresh.md"

@test "deprecation refresh agent frontmatter is valid" {
  assert [ -f "$DEPR_AGENT" ]
  local fm
  fm=$(get_frontmatter "$DEPR_AGENT")
  echo "$fm" | grep -q "^name:"
  echo "$fm" | grep -q "^description"
}

@test "all framework known-deprecations.json files are valid schema v2" {
  local violations=0
  for f in "$PLUGIN_ROOT"/modules/frameworks/*/known-deprecations.json; do
    # Valid JSON
    jq empty "$f" 2>/dev/null || { echo "Invalid JSON: $f"; violations=$((violations + 1)); continue; }
    # Version 2
    local ver
    ver=$(jq -r '.version' "$f")
    [[ "$ver" == "2" ]] || { echo "Wrong version in $f: $ver"; violations=$((violations + 1)); continue; }
    # Required v2 fields
    for field in pattern replacement package since applies_from; do
      local missing
      missing=$(jq --arg field "$field" '[.deprecations[] | select(has($field) | not)] | length' "$f")
      [[ "$missing" -eq 0 ]] || { echo "$f missing field $field in $missing entries"; violations=$((violations + 1)); }
    done
  done
  [[ "$violations" -eq 0 ]]
}

@test "deprecation entries have non-empty replacement guidance" {
  local violations=0
  for f in "$PLUGIN_ROOT"/modules/frameworks/*/known-deprecations.json; do
    local empty_replacements
    empty_replacements=$(jq '[.deprecations[] | select(.replacement == "" or .replacement == null)] | length' "$f")
    [[ "$empty_replacements" -eq 0 ]] || { echo "$f has $empty_replacements empty replacements"; violations=$((violations + 1)); }
  done
  [[ "$violations" -eq 0 ]]
}

@test "removed_in entries are valid version when present" {
  local violations=0
  for f in "$PLUGIN_ROOT"/modules/frameworks/*/known-deprecations.json; do
    local bad
    # Accept 2+ component numeric versions (e.g., 0.7, 1.22, 1.0.0) and
    # non-numeric platform versions (e.g., C11, C99). Reject empty strings.
    bad=$(jq '[.deprecations[] | select(.removed_in != null and (.removed_in | length > 0) and (.removed_in | test("^[0-9]+\\.[0-9]") | not) and (.removed_in | test("^[A-Za-z]") | not))] | length' "$f" 2>/dev/null || echo "0")
    [[ "$bad" -eq 0 ]] || { echo "$f has $bad invalid removed_in values"; violations=$((violations + 1)); }
  done
  [[ "$violations" -eq 0 ]]
}

@test "no duplicate patterns within a single framework" {
  local violations=0
  for f in "$PLUGIN_ROOT"/modules/frameworks/*/known-deprecations.json; do
    local total unique
    total=$(jq '.deprecations | length' "$f")
    unique=$(jq '[.deprecations[].pattern] | unique | length' "$f")
    [[ "$total" -eq "$unique" ]] || { echo "$f has duplicate patterns ($total total, $unique unique)"; violations=$((violations + 1)); }
  done
  [[ "$violations" -eq 0 ]]
}

@test "since field is valid version for all entries" {
  local violations=0
  for f in "$PLUGIN_ROOT"/modules/frameworks/*/known-deprecations.json; do
    local bad
    # Accept: multi-component numeric (0.6, 1.16, 3.10), single-component
    # numeric (4, 16 — Node.js majors), and non-numeric platform versions
    # (C99, C11, C89). Reject empty strings only.
    bad=$(jq '[.deprecations[] | select((.since | length > 0) and (.since | test("^[0-9]") | not) and (.since | test("^[A-Za-z]") | not))] | length' "$f" 2>/dev/null || echo "0")
    [[ "$bad" -eq 0 ]] || { echo "$f has $bad invalid since values"; violations=$((violations + 1)); }
  done
  [[ "$violations" -eq 0 ]]
}

@test "removed_in is greater than or equal to since when both present" {
  local violations=0
  for f in "$PLUGIN_ROOT"/modules/frameworks/*/known-deprecations.json; do
    # Use python for version comparison — skip non-numeric versions (e.g. C99)
    # and pre-release versions (e.g. 3.0.0-rc.1). Allow removed_in == since
    # (deprecated and removed in same major release).
    local bad
    bad=$(python3 -c "
import json, re
with open('$f') as fh:
    data = json.load(fh)
count = 0
for d in data.get('deprecations', []):
    r_str = d.get('removed_in', '')
    s_str = d.get('since', '')
    if not r_str or not s_str:
        continue
    # Skip non-numeric versions (C99, C11, etc.) and pre-release tags
    if not re.match(r'^[0-9]+\.', r_str) or not re.match(r'^[0-9]+\.', s_str):
        continue
    if '-' in r_str or '-' in s_str:
        continue
    try:
        r = tuple(int(x) for x in r_str.split('.')[:3])
        s = tuple(int(x) for x in s_str.split('.')[:3])
        if r < s:
            count += 1
    except ValueError:
        continue
print(count)
" 2>/dev/null || echo "0")
    [[ "$bad" -eq 0 ]] || { echo "$f has $bad entries where removed_in < since"; violations=$((violations + 1)); }
  done
  [[ "$violations" -eq 0 ]]
}
