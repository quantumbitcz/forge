#!/usr/bin/env bash
# Structural validation for the forge plugin.
# Zero dependencies beyond bash + jq.
# Prints PASS/FAIL for each check. Exits 1 if any check fails.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Use git rev-parse for ROOT — works correctly on Windows Git Bash where pwd returns
# POSIX-style /d/a/... paths that don't resolve with test -f or ls.
ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || (cd "$SCRIPT_DIR/.." && pwd))"

# Check for required dependency
if ! command -v jq &>/dev/null; then
  echo "ERROR: jq is required but not found. Install it:" >&2
  echo "  MacOS:   brew install jq" >&2
  echo "  Linux:   sudo apt install jq (or your package manager)" >&2
  echo "  Windows: choco install jq" >&2
  exit 1
fi

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
echo "=== forge structural validation ==="
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

# Check 3: Pipeline agents (fg-* files) follow fg-{NNN}-{role} naming
check3_fail=0
for f in "$ROOT/agents/fg-"*.md; do
  name=$(basename "$f" .md)
  if ! echo "$name" | grep -qE '^fg-[0-9]{3}-.+$'; then
    check3_fail=1; break
  fi
done
check "Pipeline agents follow fg-{NNN}-{role} naming" "$check3_fail"

# Check 4: Cross-cutting review agents (non-fg-* agents) have tools list in frontmatter
check4_fail=0
for f in "$ROOT/agents/"*.md; do
  name=$(basename "$f" .md)
  if echo "$name" | grep -qE '^fg-[0-9]{3}-'; then
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

# Module lists discovered from disk (single source of truth)
# shellcheck source=lib/module-lists.bash
PLUGIN_ROOT="$ROOT" source "$SCRIPT_DIR/lib/module-lists.bash"

FRAMEWORKS=("${DISCOVERED_FRAMEWORKS[@]}")
LANGUAGES=("${DISCOVERED_LANGUAGES[@]}")
TESTING_FILES=("${DISCOVERED_TESTING_FILES[@]}")
REQUIRED_FILES=("${REQUIRED_FRAMEWORK_FILES[@]}")

# Guard against accidental module deletions
guard_min_count "frameworks" "${#FRAMEWORKS[@]}" "$MIN_FRAMEWORKS" || { FAIL=$((FAIL + 1)); }
guard_min_count "languages" "${#LANGUAGES[@]}" "$MIN_LANGUAGES" || { FAIL=$((FAIL + 1)); }
guard_min_count "testing files" "${#TESTING_FILES[@]}" "$MIN_TESTING_FILES" || { FAIL=$((FAIL + 1)); }

# Check 6: All 21 framework directories have 5 required files
check6_fail=0
for fw in "${FRAMEWORKS[@]}"; do
  for req in "${REQUIRED_FILES[@]}"; do
    if [ ! -f "$ROOT/modules/frameworks/$fw/$req" ]; then
      check6_fail=1; break 2
    fi
  done
done
check "All ${#FRAMEWORKS[@]} framework directories have required 5 files" "$check6_fail"

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

# Check 8: All forge-config-template.md have total_retries_max
check8_fail=0
for fw in "${FRAMEWORKS[@]}"; do
  f="$ROOT/modules/frameworks/$fw/forge-config-template.md"
  if ! grep -q "total_retries_max" "$f"; then
    check8_fail=1; break
  fi
done
check "All forge-config-template.md have total_retries_max" "$check8_fail"

# Check 9: All forge-config-template.md have oscillation_tolerance
check9_fail=0
for fw in "${FRAMEWORKS[@]}"; do
  f="$ROOT/modules/frameworks/$fw/forge-config-template.md"
  if ! grep -q "oscillation_tolerance" "$f"; then
    check9_fail=1; break
  fi
done
check "All forge-config-template.md have oscillation_tolerance" "$check9_fail"

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
check "All ${#LANGUAGES[@]} language files exist in modules/languages/" "$check10a_fail"

# Check 10b: All 11 testing files exist in modules/testing/
check10b_fail=0
for tf in "${TESTING_FILES[@]}"; do
  if [ ! -f "$ROOT/modules/testing/$tf" ]; then
    check10b_fail=1; break
  fi
done
check "All ${#TESTING_FILES[@]} testing files exist in modules/testing/" "$check10b_fail"

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

# Check 18b: All hook command scripts exist, are executable, and have shebangs
check18b_fail=0
# On Windows Git Bash (MSYS/Cygwin), absolute and relative path resolution with
# test -f, ls, and find is unreliable due to /d/a/ vs D:/ path translation issues.
# Skip this check on Windows — hook scripts are already validated in the SCRIPTS
# section above (shebang, executable, exist checks on all .sh files).
if [[ "${OSTYPE:-}" == msys* || "${OSTYPE:-}" == cygwin* || "${OSTYPE:-}" == mingw* ]]; then
  echo "    NOTE: Skipping hook path resolution check on Windows Git Bash (validated in SCRIPTS section)" >&2
else
  while IFS= read -r cmd; do
    [[ -z "$cmd" ]] && continue
    # Commands can be either bare paths (legacy) or "python3 <path>".
    # Extract the last whitespace-separated token that mentions ${CLAUDE_PLUGIN_ROOT}
    # or a relative path ending in .sh/.py.
    script_path=""
    for tok in $cmd; do
      if [[ "$tok" == *'${CLAUDE_PLUGIN_ROOT}'* ]] || [[ "$tok" == *.sh ]] || [[ "$tok" == *.py ]]; then
        script_path="$tok"
      fi
    done
    [[ -z "$script_path" ]] && script_path="${cmd%% *}"
    script_path="${script_path/\$\{CLAUDE_PLUGIN_ROOT\}/$ROOT}"
    if [[ ! -f "$script_path" ]]; then
      echo "    DETAIL: Hook script not found: $script_path" >&2
      check18b_fail=1
    elif [[ ! -x "$script_path" ]]; then
      echo "    DETAIL: Hook script not executable: $script_path (run: chmod +x $script_path)" >&2
      check18b_fail=1
    elif ! head -n 1 "$script_path" | grep -q '^#!'; then
      echo "    DETAIL: Hook script missing shebang: $script_path (add: #!/usr/bin/env bash)" >&2
      check18b_fail=1
    fi
  done < <(jq -r '.. | objects | select(has("command")) | .command' "$HOOKS_JSON" 2>/dev/null)
fi
check "All hook command scripts exist, are executable, and have shebangs" "$check18b_fail"

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

# Check 19b: Every SKILL.md description has [read-only] or [writes] prefix (Phase 1 skill contract)
check19b_fail=0
for skill_md in "$ROOT"/skills/*/SKILL.md; do
  [ -f "$skill_md" ] || continue
  desc=$(awk '/^description:/{sub(/^description: *"?/, ""); sub(/"?$/, ""); print; exit}' "$skill_md")
  if [[ ! "$desc" =~ ^\[read-only\] ]] && [[ ! "$desc" =~ ^\[writes\] ]]; then
    echo "    DETAIL: $skill_md missing [read-only]/[writes] badge"
    check19b_fail=1
  fi
done
check "All SKILL.md descriptions have [read-only] or [writes] badge prefix" "$check19b_fail"

# Check 19c: No deleted-skill names remain referenced in sweep scope (DEPRECATIONS.md exempt)
check19c_fail=0
stray=$(grep -rn "forge-diagnose\|forge-repair-state\|forge-reset\|forge-resume\|forge-rollback\|forge-caveman\|forge-compression-help" \
  "$ROOT/README.md" "$ROOT/CLAUDE.md" "$ROOT/CHANGELOG.md" "$ROOT/shared/" "$ROOT/skills/" 2>/dev/null \
  | grep -v "forge-recover\|forge-compress" \
  | grep -v "DEPRECATIONS.md" || true)
if [[ -n "$stray" ]]; then
  check19c_fail=1
  echo "    DETAIL: found stray references to deleted skill names:"
  echo "$stray" | sed 's/^/      /'
fi
check "No deleted-skill names remain in README/CLAUDE/CHANGELOG/shared/skills (Phase 1 sweep)" "$check19c_fail"

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
# CLAUDE.md refers to version as "v1.1.0" — strip leading v for comparison
claude_ver=$(grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' "$ROOT/CLAUDE.md" | head -1 | sed 's/^v//')
if [ -z "$plugin_ver" ] || [ -z "$claude_ver" ] || [ "$plugin_ver" != "$claude_ver" ]; then
  check25_fail=1
fi
check "plugin.json version matches CLAUDE.md version ($plugin_ver == $claude_ver)" "$check25_fail"

# Check 25b: CHANGELOG.md has entry for current plugin version (advisory — does not fail)
if [[ -n "$plugin_ver" ]] && [[ -f "$ROOT/CHANGELOG.md" ]]; then
  if ! grep -q "\[${plugin_ver}\]" "$ROOT/CHANGELOG.md" && \
     ! grep -q "## ${plugin_ver}" "$ROOT/CHANGELOG.md"; then
    echo "    ADVISORY: CHANGELOG.md has no entry for current version ${plugin_ver}"
  fi
fi

echo ""
echo "--- PHASE 1 (A+ UPGRADE) ---"

# Graph versioning (SPEC-09)
check_graph_ver_fail=0
[[ -f "$ROOT/shared/graph/schema-versioning.md" ]] || { echo "    Missing: shared/graph/schema-versioning.md"; check_graph_ver_fail=1; }
[[ -d "$ROOT/shared/graph/migrations" ]] || { echo "    Missing: shared/graph/migrations/"; check_graph_ver_fail=1; }
check "Graph schema versioning exists" "$check_graph_ver_fail"

# Next.js App Router variant (SPEC-08) — conditional
check_app_router_fail=0
if [[ -d "$ROOT/modules/frameworks/nextjs/variants" ]]; then
  [[ -f "$ROOT/modules/frameworks/nextjs/variants/app-router.md" ]] || { echo "    Missing: nextjs/variants/app-router.md"; check_app_router_fail=1; }
  check "Next.js App Router variant exists" "$check_app_router_fail"
fi

# Compression benchmarks (SPEC-06) — conditional
if [[ -d "$ROOT/benchmarks" ]]; then
  check_bench_fail=0
  [[ -f "$ROOT/benchmarks/count-tokens.py" ]] || { echo "    Missing: benchmarks/count-tokens.py"; check_bench_fail=1; }
  check "Compression benchmark harness exists" "$check_bench_fail"
fi

# --- CROSSCUTTING LAYERS ---
echo ""
echo "--- CROSSCUTTING LAYERS ---"

LAYERS=("${DISCOVERED_LAYERS[@]}")
BUILD_SYSTEMS=("${DISCOVERED_BUILD_SYSTEMS[@]}")
CI_PLATFORMS=("${DISCOVERED_CI_PLATFORMS[@]}")
CONTAINER_ORCH=("${DISCOVERED_CONTAINER_ORCH[@]}")

# Guard against accidental deletions in new layers
guard_min_count "crosscutting layers" "${#LAYERS[@]}" "$MIN_LAYERS" || { FAIL=$((FAIL + 1)); }
guard_min_count "documentation bindings" "${#DISCOVERED_DOC_BINDINGS[@]}" "$MIN_DOCUMENTATION_BINDINGS" || { FAIL=$((FAIL + 1)); }
guard_min_count "build systems" "${#BUILD_SYSTEMS[@]}" "$MIN_BUILD_SYSTEMS" || { FAIL=$((FAIL + 1)); }
guard_min_count "CI/CD platforms" "${#CI_PLATFORMS[@]}" "$MIN_CI_PLATFORMS" || { FAIL=$((FAIL + 1)); }
guard_min_count "container orchestration" "${#CONTAINER_ORCH[@]}" "$MIN_CONTAINER_ORCH" || { FAIL=$((FAIL + 1)); }

check26_fail=0
for layer in "${LAYERS[@]}"; do
  if [[ ! -d "$ROOT/modules/$layer" ]]; then
    echo "    Missing layer directory: modules/$layer"
    check26_fail=1
  fi
done
check "All crosscutting layer directories exist" "$check26_fail"

echo ""
echo "--- BUILD SYSTEMS ---"

# Check 27: All build system generic modules exist
check27_fail=0
for bs in "${BUILD_SYSTEMS[@]}"; do
  if [ ! -f "$ROOT/modules/build-systems/$bs.md" ] && [ ! -f "$ROOT/modules/build-systems/$bs/conventions.md" ]; then
    echo "    Missing: modules/build-systems/$bs.md or modules/build-systems/$bs/conventions.md"
    check27_fail=1
  fi
done
check "All ${#BUILD_SYSTEMS[@]} build system generic modules exist" "$check27_fail"

# Check 28: All build system learnings files exist
check28_fail=0
for bs in "${BUILD_SYSTEMS[@]}"; do
  if [ ! -f "$ROOT/shared/learnings/$bs.md" ]; then
    echo "    Missing: shared/learnings/$bs.md"
    check28_fail=1
  fi
done
check "All build system learnings files exist" "$check28_fail"

echo ""
echo "--- CI/CD PLATFORMS ---"

# Check 29: All CI/CD platform generic modules exist
check29_fail=0
for ci in "${CI_PLATFORMS[@]}"; do
  if [ ! -f "$ROOT/modules/ci-cd/$ci.md" ]; then
    echo "    Missing: modules/ci-cd/$ci.md"
    check29_fail=1
  fi
done
check "All ${#CI_PLATFORMS[@]} CI/CD platform generic modules exist" "$check29_fail"

# Check 30: All CI/CD platform learnings files exist
check30_fail=0
for ci in "${CI_PLATFORMS[@]}"; do
  if [ ! -f "$ROOT/shared/learnings/$ci.md" ]; then
    echo "    Missing: shared/learnings/$ci.md"
    check30_fail=1
  fi
done
check "All CI/CD platform learnings files exist" "$check30_fail"

echo ""
echo "--- CONTAINER ORCHESTRATION ---"

# Check 31: All container orchestration generic modules exist
check31_fail=0
for co in "${CONTAINER_ORCH[@]}"; do
  if [ ! -f "$ROOT/modules/container-orchestration/$co.md" ]; then
    echo "    Missing: modules/container-orchestration/$co.md"
    check31_fail=1
  fi
done
check "All ${#CONTAINER_ORCH[@]} container orchestration generic modules exist" "$check31_fail"

# Check 32: All container orchestration learnings files exist
check32_fail=0
for co in "${CONTAINER_ORCH[@]}"; do
  if [ ! -f "$ROOT/shared/learnings/$co.md" ]; then
    echo "    Missing: shared/learnings/$co.md"
    check32_fail=1
  fi
done
check "All container orchestration learnings files exist" "$check32_fail"

echo ""
echo "--- CROSSCUTTING LAYER LEARNINGS ---"

# Check: All crosscutting layer learnings files exist
check_layer_learnings_fail=0
for layer in "${LAYERS[@]}"; do
  # Each layer directory may contain multiple .md files — check each has a learnings file
  for f in "$ROOT/modules/$layer"/*.md; do
    [ -f "$f" ] || continue
    name=$(basename "$f" .md)
    if [ ! -f "$ROOT/shared/learnings/$name.md" ]; then
      echo "    Missing: shared/learnings/$name.md (for modules/$layer/$name.md)"
      check_layer_learnings_fail=1
    fi
  done
done
check "All crosscutting layer module learnings files exist" "$check_layer_learnings_fail"

echo ""
echo "--- RECOVERY ENGINE ---"

# Check: Recovery engine exists with required sections
check_recovery_fail=0
if [[ ! -f "$ROOT/shared/recovery/recovery-engine.md" ]]; then
  echo "  FAIL: shared/recovery/recovery-engine.md does not exist"
  check_recovery_fail=1
else
  for section in "Boundary" "Failure Classification" "Recovery Execution" "Recovery Budget"; do
    if ! grep -q "$section" "$ROOT/shared/recovery/recovery-engine.md"; then
      echo "  FAIL: recovery-engine.md missing section: $section"
      check_recovery_fail=1
    fi
  done
fi
check "Recovery engine exists with required sections" "$check_recovery_fail"

echo ""
echo "--- CONVERGENCE ENGINE ---"

# ── CONVERGENCE ENGINE ──────────────────────────────────────────────────────
check33_fail=0
if [[ ! -f "$ROOT/shared/convergence-engine.md" ]]; then
  echo "  FAIL: shared/convergence-engine.md does not exist"
  check33_fail=1
else
  for section in "Convergence States" "Phase Model" "Algorithm" "Configuration" "PREFLIGHT Constraints"; do
    if ! grep -q "$section" "$ROOT/shared/convergence-engine.md"; then
      echo "  FAIL: convergence-engine.md missing section: $section"
      check33_fail=1
    fi
  done
fi
check "Convergence engine exists with required sections" "$check33_fail"

# Check 34: All forge-config-template.md have convergence: section
check34_fail=0
for f in "$ROOT"/modules/frameworks/*/forge-config-template.md; do
  if ! grep -q "convergence:" "$f"; then
    echo "  FAIL: $(basename "$(dirname "$f")")/forge-config-template.md missing convergence section"
    check34_fail=1
  fi
done
check "All forge config templates have convergence section" "$check34_fail"

echo ""
echo "--- TRACKING ---"

# Check: tracking-ops.sh exists and is executable
check_tracking_ops_fail=0
if [ ! -x "$ROOT/shared/tracking/tracking-ops.sh" ]; then
  check_tracking_ops_fail=1
fi
check "tracking-ops.sh exists and is executable" "$check_tracking_ops_fail"

# Check: tracking-schema.md exists
check_tracking_schema_fail=0
if [ ! -f "$ROOT/shared/tracking/tracking-schema.md" ]; then
  check_tracking_schema_fail=1
fi
check "tracking-schema.md exists" "$check_tracking_schema_fail"

# Check: git-conventions.md exists
check_git_conventions_fail=0
if [ ! -f "$ROOT/shared/git-conventions.md" ]; then
  check_git_conventions_fail=1
fi
check "git-conventions.md exists" "$check_git_conventions_fail"

# Check: All local-template.md have git: section
check_git_section_fail=0
git_count=0
git_total=0
for tmpl in "$ROOT"/modules/frameworks/*/local-template.md; do
  git_total=$((git_total + 1))
  grep -q "^git:" "$tmpl" 2>/dev/null && git_count=$((git_count + 1)) || true
done
if [ "$git_count" -ne "$git_total" ] || [ "$git_total" -eq 0 ]; then
  check_git_section_fail=1
  echo "    DETAIL: $git_count/$git_total local-template.md files have git: section"
fi
check "All local-template.md have git: section ($git_count/$git_total)" "$check_git_section_fail"

# Check: All local-template.md have tracking: section
check_tracking_section_fail=0
tracking_count=0
tracking_total=0
for tmpl in "$ROOT"/modules/frameworks/*/local-template.md; do
  tracking_total=$((tracking_total + 1))
  grep -q "^tracking:" "$tmpl" 2>/dev/null && tracking_count=$((tracking_count + 1)) || true
done
if [ "$tracking_count" -ne "$tracking_total" ] || [ "$tracking_total" -eq 0 ]; then
  check_tracking_section_fail=1
  echo "    DETAIL: $tracking_count/$tracking_total local-template.md files have tracking: section"
fi
check "All local-template.md have tracking: section ($tracking_count/$tracking_total)" "$check_tracking_section_fail"

echo ""
echo "--- BUGFIX WORKFLOW ---"

# Check: fg-020-bug-investigator agent exists
check_bugfix_agent_fail=0
if [ ! -f "$ROOT/agents/fg-020-bug-investigator.md" ]; then
  check_bugfix_agent_fail=1
fi
check "fg-020-bug-investigator agent exists" "$check_bugfix_agent_fail"

# Check: forge-fix skill exists
check_forgefix_skill_fail=0
if [ ! -f "$ROOT/skills/forge-fix/SKILL.md" ]; then
  check_forgefix_skill_fail=1
fi
check "forge-fix skill exists" "$check_forgefix_skill_fail"

# Check: forge-fix name matches directory
check_forgefix_name_fail=0
if ! grep -q "^name: forge-fix$" "$ROOT/skills/forge-fix/SKILL.md" 2>/dev/null; then
  check_forgefix_name_fail=1
fi
check "forge-fix name matches directory" "$check_forgefix_name_fail"

echo ""
echo "--- PHASE 4: GRAPH + INIT ---"

# Check: mcp-provisioning.md exists
check_mcp_prov_fail=0
if [ ! -f "$ROOT/shared/mcp-provisioning.md" ]; then
  check_mcp_prov_fail=1
fi
check "mcp-provisioning.md exists" "$check_mcp_prov_fail"

# Check: version-resolution.md exists
check_ver_res_fail=0
if [ ! -f "$ROOT/shared/version-resolution.md" ]; then
  check_ver_res_fail=1
fi
check "version-resolution.md exists" "$check_ver_res_fail"

# Check: All code-quality modules have frontmatter (line 1 is ---)
check_cq_frontmatter_fail=0
cq_total=0
cq_with_fm=0
for f in "$ROOT/modules/code-quality/"*.md; do
  [ -f "$f" ] || continue
  cq_total=$((cq_total + 1))
  has_open=$(awk 'NR==1{print ($0=="---")?1:0}' "$f")
  if [ "$has_open" = "1" ]; then
    cq_with_fm=$((cq_with_fm + 1))
  fi
done
if [ "$cq_total" -eq 0 ] || [ "$cq_with_fm" -ne "$cq_total" ]; then
  check_cq_frontmatter_fail=1
  echo "    DETAIL: $cq_with_fm/$cq_total code-quality modules have frontmatter"
fi
check "All code-quality modules have frontmatter ($cq_with_fm/$cq_total)" "$check_cq_frontmatter_fail"

# Check: query-patterns.md has at least 15 patterns (counts both ### N. and ## Pattern N formats)
check_qp_fail=0
qp_file="$ROOT/shared/graph/query-patterns.md"
if [ ! -f "$qp_file" ]; then
  check_qp_fail=1
  echo "    DETAIL: shared/graph/query-patterns.md not found"
else
  pattern_count=$(grep -cE "^(### [0-9]+\.|## Pattern)" "$qp_file" 2>/dev/null || echo 0)
  if [ "$pattern_count" -lt 15 ]; then
    check_qp_fail=1
    echo "    DETAIL: query-patterns.md has $pattern_count patterns (expected >= 15)"
  fi
fi
check "query-patterns.md has at least 15 patterns ($pattern_count)" "$check_qp_fail"

# --- Deterministic Pipeline Hardening ---
echo ""
echo "--- DETERMINISTIC PIPELINE HARDENING ---"

echo "Checking state-transitions.md..."
check_st_fail=0
[[ -f "$ROOT/shared/state-transitions.md" ]] || { echo "FAIL: shared/state-transitions.md missing"; check_st_fail=1; }
check "state-transitions.md exists" "$check_st_fail"

echo "Checking domain-detection.md..."
check_dd_fail=0
[[ -f "$ROOT/shared/domain-detection.md" ]] || { echo "FAIL: shared/domain-detection.md missing"; check_dd_fail=1; }
check "domain-detection.md exists" "$check_dd_fail"

echo "Checking decision-log.md..."
check_dl_fail=0
[[ -f "$ROOT/shared/decision-log.md" ]] || { echo "FAIL: shared/decision-log.md missing"; check_dl_fail=1; }
check "decision-log.md exists" "$check_dl_fail"

echo "Checking state-integrity.sh..."
check_si_fail=0
[[ -f "$ROOT/shared/state-integrity.sh" ]] || { echo "FAIL: shared/state-integrity.sh missing"; check_si_fail=1; }
[[ -x "$ROOT/shared/state-integrity.sh" ]] || { echo "FAIL: shared/state-integrity.sh not executable"; check_si_fail=1; }
check "state-integrity.sh exists and is executable" "$check_si_fail"

# --- P0: Orchestrator split files ---
echo ""
echo "P0: Orchestrator and scripts..."

orch_merged_check_fail=0
if [[ ! -f "$ROOT/agents/fg-100-orchestrator.md" ]]; then
  orch_merged_check_fail=1
fi
check "Orchestrator merged file exists" "$orch_merged_check_fail"

core_name_fail=0
if ! grep -q "^name: fg-100-orchestrator$" "$ROOT/agents/fg-100-orchestrator.md"; then
  core_name_fail=1
fi
check "Orchestrator has correct name in frontmatter" "$core_name_fail"

merged_orch_fail=0
if [[ ! -f "$ROOT/agents/fg-100-orchestrator.md" ]]; then
  merged_orch_fail=1
fi
check "Merged orchestrator exists" "$merged_orch_fail"

# Verify phase fragment files no longer exist
phase_fragment_fail=0
for frag in fg-100-orchestrator-core.md fg-100-orchestrator-boot.md fg-100-orchestrator-execute.md fg-100-orchestrator-ship.md; do
  if [[ -f "$ROOT/agents/$frag" ]]; then
    phase_fragment_fail=1
    break
  fi
done
check "Orchestrator phase fragment files removed" "$phase_fragment_fail"

for script in forge-state.sh forge-state-write.sh; do
  script_fail=0
  if [[ ! -f "$ROOT/shared/$script" ]] || [[ ! -x "$ROOT/shared/$script" ]]; then
    script_fail=1
  fi
  check "shared/$script exists and is executable" "$script_fail"
done

# Python-based prerequisite gate (replaces shared/check-prerequisites.sh)
py_script_fail=0
if [[ ! -f "$ROOT/shared/check_prerequisites.py" ]] || [[ ! -x "$ROOT/shared/check_prerequisites.py" ]]; then
  py_script_fail=1
fi
check "shared/check_prerequisites.py exists and is executable" "$py_script_fail"

# --- P1+P2: New scripts and files ---
echo ""
echo "P1+P2: New scripts and files..."

for script in forge-token-tracker.sh forge-linear-sync.sh forge-sim.sh forge-timeout.sh; do
  script_fail=0
  if [[ ! -f "$ROOT/shared/$script" ]] || [[ ! -x "$ROOT/shared/$script" ]]; then
    script_fail=1
  fi
  check "shared/$script exists and is executable" "$script_fail"
done

# fg-505-build-verifier exists
fg505_fail=0
if ! grep -q "^name: fg-505-build-verifier" "$ROOT/agents/fg-505-build-verifier.md" 2>/dev/null; then
  fg505_fail=1
fi
check "fg-505-build-verifier agent exists with correct frontmatter" "$fg505_fail"

# Mode overlay files
modes_fail=0
for mode in standard bugfix migration bootstrap testing refactor performance; do
  if [[ ! -f "$ROOT/shared/modes/${mode}.md" ]]; then
    modes_fail=1
    break
  fi
done
check "All 7 mode overlay files exist" "$modes_fail"

# fg-414 removed
fg414_fail=0
if [[ -f "$ROOT/agents/fg-414-frontend-quality-reviewer.md" ]]; then
  fg414_fail=1
fi
check "fg-414-frontend-quality-reviewer removed (merged into fg-413)" "$fg414_fail"

# fg-415 never existed
fg415_fail=0
if [[ -f "$ROOT/agents/fg-415-frontend-performance-reviewer.md" ]]; then
  fg415_fail=1
fi
check "fg-415-frontend-performance-reviewer does not exist" "$fg415_fail"

# Cross-repo contracts doc
xrepo_fail=0
if [[ ! -f "$ROOT/shared/cross-repo-contracts.md" ]]; then
  xrepo_fail=1
fi
check "shared/cross-repo-contracts.md exists" "$xrepo_fail"

# Simulation fixtures
sim_fail=0
sim_count=$(ls "$ROOT/tests/fixtures/sim/"*.yaml 2>/dev/null | wc -l | tr -d ' ')
if [[ "$sim_count" -lt 10 ]]; then
  sim_fail=1
fi
check "At least 10 simulation scenario files exist" "$sim_fail"

echo ""
echo "--- EVAL SUITE ---"

# Check: tests/evals/framework.bash exists
check_eval_framework_fail=0
if [[ ! -f "$ROOT/tests/evals/framework.bash" ]]; then
  echo "    Missing: tests/evals/framework.bash"
  check_eval_framework_fail=1
fi
check "Eval framework.bash exists" "$check_eval_framework_fail"

# Check: tests/evals/README.md exists
check_eval_readme_fail=0
if [[ ! -f "$ROOT/tests/evals/README.md" ]]; then
  echo "    Missing: tests/evals/README.md"
  check_eval_readme_fail=1
fi
check "Eval README.md exists" "$check_eval_readme_fail"

# Check: Each review agent (fg-410 through fg-419) has a matching eval directory
check_eval_agents_fail=0
eval_agent_count=0
for agent_file in "$ROOT"/agents/fg-41*.md; do
  [[ -f "$agent_file" ]] || continue
  agent_name=$(basename "$agent_file" .md)
  eval_dir="$ROOT/tests/evals/agents/$agent_name"
  if [[ ! -d "$eval_dir" ]]; then
    echo "    Missing eval directory for $agent_name"
    check_eval_agents_fail=1
  else
    eval_agent_count=$((eval_agent_count + 1))
    # Check each eval dir has inputs/, expected/, and eval.bats
    if [[ ! -d "$eval_dir/inputs" ]]; then
      echo "    Missing: $agent_name/inputs/"
      check_eval_agents_fail=1
    fi
    if [[ ! -d "$eval_dir/expected" ]]; then
      echo "    Missing: $agent_name/expected/"
      check_eval_agents_fail=1
    fi
    if [[ ! -f "$eval_dir/eval.bats" ]]; then
      echo "    Missing: $agent_name/eval.bats"
      check_eval_agents_fail=1
    fi
    # Check input/expected counts match
    if [[ -d "$eval_dir/inputs" && -d "$eval_dir/expected" ]]; then
      input_count=$(ls "$eval_dir"/inputs/*.md 2>/dev/null | wc -l | tr -d ' ')
      expected_count=$(ls "$eval_dir"/expected/*.expected 2>/dev/null | wc -l | tr -d ' ')
      if [[ "$input_count" != "$expected_count" ]]; then
        echo "    Mismatch in $agent_name: $input_count inputs vs $expected_count expected"
        check_eval_agents_fail=1
      fi
    fi
  fi
done
check "All review agents have eval directories with inputs/expected/eval.bats ($eval_agent_count agents)" "$check_eval_agents_fail"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
echo ""

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi

exit 0
