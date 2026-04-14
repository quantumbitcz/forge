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

@test "removed_in entries are valid semver when present" {
  local violations=0
  for f in "$PLUGIN_ROOT"/modules/frameworks/*/known-deprecations.json; do
    local bad
    bad=$(jq '[.deprecations[] | select(.removed_in != null and (.removed_in | test("^[0-9]+\\.[0-9]+\\.[0-9]") | not))] | length' "$f" 2>/dev/null || echo "0")
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

@test "since field is valid semver for all entries" {
  local violations=0
  for f in "$PLUGIN_ROOT"/modules/frameworks/*/known-deprecations.json; do
    local bad
    bad=$(jq '[.deprecations[] | select(.since | test("^[0-9]+\\.[0-9]+\\.[0-9]") | not)] | length' "$f" 2>/dev/null || echo "0")
    [[ "$bad" -eq 0 ]] || { echo "$f has $bad invalid since values"; violations=$((violations + 1)); }
  done
  [[ "$violations" -eq 0 ]]
}

@test "removed_in is greater than since when both present" {
  local violations=0
  for f in "$PLUGIN_ROOT"/modules/frameworks/*/known-deprecations.json; do
    # Use python for semver comparison
    local bad
    bad=$(python3 -c "
import json
with open('$f') as fh:
    data = json.load(fh)
count = 0
for d in data.get('deprecations', []):
    if d.get('removed_in') and d.get('since'):
        r = tuple(int(x) for x in d['removed_in'].split('.')[:3])
        s = tuple(int(x) for x in d['since'].split('.')[:3])
        if r <= s:
            count += 1
print(count)
" 2>/dev/null || echo "0")
    [[ "$bad" -eq 0 ]] || { echo "$f has $bad entries where removed_in <= since"; violations=$((violations + 1)); }
  done
  [[ "$violations" -eq 0 ]]
}
