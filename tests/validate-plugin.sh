#!/usr/bin/env bash
# Structural validation for the dev-pipeline plugin.
# Zero dependencies beyond bash + jq.
# Prints PASS/FAIL for each of 28 checks. Exits 1 if any check fails.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PASS=0
FAIL=0

check() {
  local name="$1" result="$2"
  if [ "$result" = "0" ]; then
    echo "  PASS: $name"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $name"
    FAIL=$((FAIL + 1))
  fi
}

echo ""
echo "=== dev-pipeline structural validation ==="
echo ""
echo "--- AGENTS ---"

# Check 1: All agents have valid YAML frontmatter (name + description between --- delimiters)
check1_fail=0
for f in "$ROOT/agents/"*.md; do
  # Frontmatter must start on line 1 with ---, end with a second ---
  # name: must appear in the frontmatter, description: must appear too
  has_open=$(awk 'NR==1{print ($0=="---")?1:0}' "$f")
  if [ "$has_open" != "1" ]; then
    check1_fail=1; break
  fi
  in_fm=$(awk '/^---/{c++; next} c==1{print}' "$f")
  has_name=$(echo "$in_fm" | grep -c '^name:' || true)
  has_desc=$(echo "$in_fm" | grep -c '^description' || true)
  if [ "$has_name" -lt 1 ] || [ "$has_desc" -lt 1 ]; then
    check1_fail=1; break
  fi
done
check "All agents have valid YAML frontmatter (name, description)" "$check1_fail"

# Check 2: Agent name in frontmatter matches filename without .md
check2_fail=0
for f in "$ROOT/agents/"*.md; do
  expected=$(basename "$f" .md)
  # Extract name from frontmatter (first --- block)
  actual=$(awk '/^---/{c++; next} c==1 && /^name:/{sub(/^name:[[:space:]]*/,""); print; exit} c==2{exit}' "$f")
  if [ "$actual" != "$expected" ]; then
    check2_fail=1; break
  fi
done
check "Agent name matches filename without .md" "$check2_fail"

# Check 3: Pipeline agents (pl-* files) follow pl-{NNN}-{role} naming
check3_fail=0
for f in "$ROOT/agents/pl-"*.md; do
  name=$(basename "$f" .md)
  if ! echo "$name" | grep -qE '^pl-[0-9]{3}-.+$'; then
    check3_fail=1; break
  fi
done
check "Pipeline agents follow pl-{NNN}-{role} naming" "$check3_fail"

# Check 4: Cross-cutting review agents (non-pl-* agents) have tools list in frontmatter
check4_fail=0
for f in "$ROOT/agents/"*.md; do
  name=$(basename "$f" .md)
  if echo "$name" | grep -qE '^pl-[0-9]{3}-'; then
    continue
  fi
  has_tools=$(awk '/^---/{c++; next} c==1 && /^tools:/{found=1} c==2{exit} END{print found+0}' "$f")
  if [ "$has_tools" != "1" ]; then
    check4_fail=1; break
  fi
done
check "Cross-cutting review agents have tools list in frontmatter" "$check4_fail"

# Check 5: All agents have "Forbidden Actions" section
check5_fail=0
for f in "$ROOT/agents/"*.md; do
  if ! grep -q "Forbidden Actions" "$f"; then
    check5_fail=1; break
  fi
done
check "All agents have Forbidden Actions section" "$check5_fail"

echo ""
echo "--- MODULES ---"

FRAMEWORKS=(spring react fastapi axum swiftui vapor express sveltekit k8s embedded go-stdlib aspnet django nextjs gin jetpack-compose kotlin-multiplatform angular nestjs vue svelte)
LANGUAGES=(kotlin java typescript python go rust swift c csharp ruby php dart elixir scala cpp)
TESTING_FILES=(kotest.md junit5.md vitest.md jest.md pytest.md go-testing.md xctest.md rust-test.md xunit-nunit.md testcontainers.md playwright.md cypress.md cucumber.md k6.md detox.md)
REQUIRED_FILES=(conventions.md local-template.md pipeline-config-template.md rules-override.json known-deprecations.json)

# Check 6: All 21 framework directories have 5 required files
check6_fail=0
for fw in "${FRAMEWORKS[@]}"; do
  for req in "${REQUIRED_FILES[@]}"; do
    if [ ! -f "$ROOT/modules/frameworks/$fw/$req" ]; then
      check6_fail=1; break 2
    fi
  done
done
check "All 21 framework directories have required 5 files" "$check6_fail"

# Check 7: All frameworks/*/conventions.md have Dos/Don'ts section (case-insensitive for don't / donts / Don'ts)
check7_fail=0
for fw in "${FRAMEWORKS[@]}"; do
  f="$ROOT/modules/frameworks/$fw/conventions.md"
  if [ ! -f "$f" ]; then
    check7_fail=1; break
  fi
  if ! grep -qiE "don'?ts?" "$f"; then
    check7_fail=1; break
  fi
done
check "All conventions.md have Dos/Don'ts section" "$check7_fail"

# Check 8: All pipeline-config-template.md have total_retries_max
check8_fail=0
for fw in "${FRAMEWORKS[@]}"; do
  f="$ROOT/modules/frameworks/$fw/pipeline-config-template.md"
  if ! grep -q "total_retries_max" "$f"; then
    check8_fail=1; break
  fi
done
check "All pipeline-config-template.md have total_retries_max" "$check8_fail"

# Check 9: All pipeline-config-template.md have oscillation_tolerance
check9_fail=0
for fw in "${FRAMEWORKS[@]}"; do
  f="$ROOT/modules/frameworks/$fw/pipeline-config-template.md"
  if ! grep -q "oscillation_tolerance" "$f"; then
    check9_fail=1; break
  fi
done
check "All pipeline-config-template.md have oscillation_tolerance" "$check9_fail"

# Check 10: All local-template.md have linear: section
check10_fail=0
for fw in "${FRAMEWORKS[@]}"; do
  f="$ROOT/modules/frameworks/$fw/local-template.md"
  if ! grep -q "linear:" "$f"; then
    check10_fail=1; break
  fi
done
check "All local-template.md have linear: section" "$check10_fail"

# Check 10a: All 9 language files exist in modules/languages/
check10a_fail=0
for lang in "${LANGUAGES[@]}"; do
  if [ ! -f "$ROOT/modules/languages/$lang.md" ]; then
    check10a_fail=1; break
  fi
done
check "All 15 language files exist in modules/languages/" "$check10a_fail"

# Check 10b: All 11 testing files exist in modules/testing/
check10b_fail=0
for tf in "${TESTING_FILES[@]}"; do
  if [ ! -f "$ROOT/modules/testing/$tf" ]; then
    check10b_fail=1; break
  fi
done
check "All 15 testing files exist in modules/testing/" "$check10b_fail"

echo ""
echo "--- JSON ---"

# Check 11: All rules-override.json valid JSON
check11_fail=0
for fw in "${FRAMEWORKS[@]}"; do
  f="$ROOT/modules/frameworks/$fw/rules-override.json"
  if ! jq empty "$f" 2>/dev/null; then
    check11_fail=1; break
  fi
done
check "All rules-override.json are valid JSON" "$check11_fail"

# Check 12: All known-deprecations.json valid JSON
check12_fail=0
for fw in "${FRAMEWORKS[@]}"; do
  f="$ROOT/modules/frameworks/$fw/known-deprecations.json"
  if ! jq empty "$f" 2>/dev/null; then
    check12_fail=1; break
  fi
done
check "All known-deprecations.json are valid JSON" "$check12_fail"

# Check 13: All known-deprecations.json have "version": 2
check13_fail=0
for fw in "${FRAMEWORKS[@]}"; do
  f="$ROOT/modules/frameworks/$fw/known-deprecations.json"
  ver=$(jq -r '.version // empty' "$f" 2>/dev/null)
  if [ "$ver" != "2" ]; then
    check13_fail=1; break
  fi
done
check 'All known-deprecations.json have "version": 2' "$check13_fail"

# Check 14: All deprecation entries have required v2 fields
check14_fail=0
REQUIRED_DEP_FIELDS=(pattern replacement package since applies_from applies_to)
for fw in "${FRAMEWORKS[@]}"; do
  f="$ROOT/modules/frameworks/$fw/known-deprecations.json"
  for field in "${REQUIRED_DEP_FIELDS[@]}"; do
    missing=$(jq --arg field "$field" '[.deprecations[] | select(has($field) | not)] | length' "$f" 2>/dev/null)
    if [ "$missing" -gt 0 ]; then
      check14_fail=1; break 2
    fi
  done
done
check "All deprecation entries have required v2 fields" "$check14_fail"

echo ""
echo "--- SCRIPTS ---"

# Check 15: All .sh files in shared/ and hooks/ have shebang (#!)
check15_fail=0
while IFS= read -r -d '' f; do
  first=$(head -1 "$f")
  if [[ "$first" != \#!* ]]; then
    check15_fail=1; break
  fi
done < <(find "$ROOT/shared" "$ROOT/hooks" "$ROOT/modules" -name "*.sh" -print0)
check "All .sh files in shared/, hooks/, and modules/ have shebang" "$check15_fail"

# Check 16: All .sh files in shared/, hooks/, and modules/ are executable
check16_fail=0
while IFS= read -r -d '' f; do
  if [ ! -x "$f" ]; then
    check16_fail=1; break
  fi
done < <(find "$ROOT/shared" "$ROOT/hooks" "$ROOT/modules" -name "*.sh" -print0)
check "All .sh files in shared/, hooks/, and modules/ are executable" "$check16_fail"

echo ""
echo "--- HOOKS ---"

HOOKS_JSON="$ROOT/hooks/hooks.json"

# Check 17: hooks/hooks.json is valid JSON
check17_fail=0
if ! jq empty "$HOOKS_JSON" 2>/dev/null; then
  check17_fail=1
fi
check "hooks/hooks.json is valid JSON" "$check17_fail"

# Check 18: hooks/hooks.json has PostToolUse and Stop event types
check18_fail=0
has_post=$(jq 'has("PostToolUse")' "$HOOKS_JSON" 2>/dev/null)
has_stop=$(jq 'has("Stop")' "$HOOKS_JSON" 2>/dev/null)
# hooks.json has a top-level "hooks" object wrapping the events
has_post_nested=$(jq '.hooks | has("PostToolUse")' "$HOOKS_JSON" 2>/dev/null || echo "false")
has_stop_nested=$(jq '.hooks | has("Stop")' "$HOOKS_JSON" 2>/dev/null || echo "false")
if [ "$has_post" != "true" ] && [ "$has_post_nested" != "true" ]; then
  check18_fail=1
fi
if [ "$has_stop" != "true" ] && [ "$has_stop_nested" != "true" ]; then
  check18_fail=1
fi
check "hooks/hooks.json has PostToolUse and Stop event types" "$check18_fail"

echo ""
echo "--- SKILLS ---"

# Check 19: All skills/*/SKILL.md have name: and description: frontmatter
check19_fail=0
for skill_dir in "$ROOT/skills/"/*/; do
  f="$skill_dir/SKILL.md"
  if [ ! -f "$f" ]; then
    check19_fail=1; break
  fi
  has_open=$(awk 'NR==1{print ($0=="---")?1:0}' "$f")
  in_fm=$(awk '/^---/{c++; next} c==1{print} c==2{exit}' "$f")
  has_name=$(echo "$in_fm" | grep -c '^name:' || true)
  has_desc=$(echo "$in_fm" | grep -c '^description:' || true)
  if [ "$has_open" != "1" ] || [ "$has_name" -lt 1 ] || [ "$has_desc" -lt 1 ]; then
    check19_fail=1; break
  fi
done
check "All skills/*/SKILL.md have name: and description: frontmatter" "$check19_fail"

echo ""
echo "--- PATTERNS ---"

SEVERITY_MAP="$ROOT/shared/checks/layer-2-linter/config/severity-map.json"
PATTERNS_DIR="$ROOT/shared/checks/layer-1-fast/patterns"

# Check 20: shared/checks/layer-2-linter/config/severity-map.json is valid JSON
check20_fail=0
if ! jq empty "$SEVERITY_MAP" 2>/dev/null; then
  check20_fail=1
fi
check "layer-2-linter/config/severity-map.json is valid JSON" "$check20_fail"

# Check 21: All layer-1 pattern files are valid JSON
check21_fail=0
for f in "$PATTERNS_DIR/"*.json; do
  if ! jq empty "$f" 2>/dev/null; then
    check21_fail=1; break
  fi
done
check "All layer-1 pattern files are valid JSON" "$check21_fail"

# Check 22: All pattern rules have required fields (id, pattern, severity, category, message)
check22_fail=0
REQUIRED_RULE_FIELDS=(id pattern severity category message)
for f in "$PATTERNS_DIR/"*.json; do
  for field in "${REQUIRED_RULE_FIELDS[@]}"; do
    missing=$(jq --arg field "$field" '[.rules[] | select(has($field) | not)] | length' "$f" 2>/dev/null)
    if [ "$missing" -gt 0 ]; then
      check22_fail=1; break 2
    fi
  done
done
check "All pattern rules have required fields (id, pattern, severity, category, message)" "$check22_fail"

# Check 23: Pattern rule IDs are unique within each language file
check23_fail=0
for f in "$PATTERNS_DIR/"*.json; do
  total=$(jq '.rules | length' "$f" 2>/dev/null)
  unique=$(jq '[.rules[].id] | unique | length' "$f" 2>/dev/null)
  if [ "$total" != "$unique" ]; then
    check23_fail=1; break
  fi
done
check "Pattern rule IDs are unique within each language file" "$check23_fail"

echo ""
echo "--- LEARNINGS ---"

# Check 24: shared/learnings/{framework}.md exists for each framework
check24_fail=0
for fw in "${FRAMEWORKS[@]}"; do
  if [ ! -f "$ROOT/shared/learnings/$fw.md" ]; then
    check24_fail=1; break
  fi
done
check "shared/learnings/{framework}.md exists for each framework" "$check24_fail"

echo ""
echo "--- VERSION ---"

# Check 25: plugin.json version matches CLAUDE.md version
check25_fail=0
plugin_ver=$(jq -r '.version' "$ROOT/.claude-plugin/plugin.json" 2>/dev/null)
# CLAUDE.md refers to version as "v1.0.0" — strip leading v for comparison
claude_ver=$(grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' "$ROOT/CLAUDE.md" | head -1 | sed 's/^v//')
if [ -z "$plugin_ver" ] || [ -z "$claude_ver" ] || [ "$plugin_ver" != "$claude_ver" ]; then
  check25_fail=1
fi
check "plugin.json version matches CLAUDE.md version ($plugin_ver == $claude_ver)" "$check25_fail"

# --- CROSSCUTTING LAYERS ---
echo ""
echo "--- CROSSCUTTING LAYERS ---"

LAYERS=(databases persistence migrations api-protocols messaging caching search storage auth observability)

check26_fail=0
for layer in "${LAYERS[@]}"; do
  if [[ ! -d "$ROOT/modules/$layer" ]]; then
    echo "    Missing layer directory: modules/$layer"
    check26_fail=1
  fi
done
check "All crosscutting layer directories exist" "$check26_fail"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
echo ""

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi

exit 0
