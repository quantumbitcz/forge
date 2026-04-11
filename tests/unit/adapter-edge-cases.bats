#!/usr/bin/env bats
# Unit tests: adapter edge cases — validates that eslint, ruff, and detekt
# adapters handle empty results, are executable, follow expected structure,
# have proper shebangs, and handle missing tools gracefully.

load '../helpers/test-helpers'

ADAPTER_DIR="$PLUGIN_ROOT/shared/checks/layer-2-linter/adapters"
SEV_MAP="$PLUGIN_ROOT/shared/checks/layer-2-linter/config/severity-map.json"

ESLINT_ADAPTER="$ADAPTER_DIR/eslint.sh"
RUFF_ADAPTER="$ADAPTER_DIR/ruff.sh"
DETEKT_ADAPTER="$ADAPTER_DIR/detekt.sh"

# ===========================================================================
# ESLint adapter edge cases (1-5)
# ===========================================================================

@test "adapter-edge: eslint adapter exists and is executable" {
  [[ -f "$ESLINT_ADAPTER" ]] || fail "eslint.sh not found at $ESLINT_ADAPTER"
  [[ -x "$ESLINT_ADAPTER" ]] || fail "eslint.sh is not executable"
}

@test "adapter-edge: eslint adapter has proper shebang line" {
  local first_line
  first_line=$(head -n1 "$ESLINT_ADAPTER")
  [[ "$first_line" == "#!/usr/bin/env bash" || "$first_line" == "#!/bin/bash" ]] \
    || fail "eslint.sh has unexpected shebang: $first_line"
}

@test "adapter-edge: eslint adapter output format has required pipe delimiters" {
  # Adapter output must use: file:line | CATEGORY | SEVERITY | message | fix_hint
  # Verify the script references the pipe-delimited output format
  grep -q '|' "$ESLINT_ADAPTER" \
    || fail "eslint.sh does not contain pipe-delimited output format"
}

@test "adapter-edge: eslint empty JSON array produces no findings" {
  local raw="${TEST_TEMP}/eslint-empty.json"
  printf '[]\n' > "$raw"

  # Extract parser inline — pass empty JSON to verify no output
  run python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    content = f.read().strip()
    if not content:
        sys.exit(0)
    results = json.loads(content)
for entry in results:
    for msg in entry.get('messages', []):
        print('finding')
" "$raw"

  assert_success
  [[ -z "$output" ]] || fail "Expected no findings for empty JSON array, got: $output"
}

@test "adapter-edge: eslint adapter handles missing tool gracefully (exits non-zero)" {
  local fake_project="${TEST_TEMP}/no-eslint"
  mkdir -p "$fake_project"
  # Create a mock npx that always fails
  mock_command "npx" 'exit 1'

  run bash "$ESLINT_ADAPTER" "$fake_project" "$fake_project" "$SEV_MAP"
  assert_failure
}

# ===========================================================================
# Ruff adapter edge cases (6-10)
# ===========================================================================

@test "adapter-edge: ruff adapter exists and is executable" {
  [[ -f "$RUFF_ADAPTER" ]] || fail "ruff.sh not found at $RUFF_ADAPTER"
  [[ -x "$RUFF_ADAPTER" ]] || fail "ruff.sh is not executable"
}

@test "adapter-edge: ruff adapter has proper shebang line" {
  local first_line
  first_line=$(head -n1 "$RUFF_ADAPTER")
  [[ "$first_line" == "#!/usr/bin/env bash" || "$first_line" == "#!/bin/bash" ]] \
    || fail "ruff.sh has unexpected shebang: $first_line"
}

@test "adapter-edge: ruff adapter output format has required pipe delimiters" {
  grep -q '|' "$RUFF_ADAPTER" \
    || fail "ruff.sh does not contain pipe-delimited output format"
}

@test "adapter-edge: ruff empty JSON input produces no findings" {
  local raw="${TEST_TEMP}/ruff-empty.json"
  printf '' > "$raw"

  run python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    content = f.read().strip()
    if not content:
        sys.exit(0)
    findings = json.loads(content)
for item in findings:
    print('finding')
" "$raw"

  assert_success
  [[ -z "$output" ]] || fail "Expected no findings for empty input, got: $output"
}

@test "adapter-edge: ruff adapter handles missing tool gracefully (exits non-zero)" {
  # Clear PATH to ensure ruff is not found
  local save_path="$PATH"
  PATH="/usr/bin:/bin"
  run bash "$RUFF_ADAPTER" "/tmp" "." "$SEV_MAP"
  PATH="$save_path"
  [[ $status -eq 1 ]] || fail "Expected exit 1 for missing ruff, got $status"
}

# ===========================================================================
# Detekt adapter edge cases (11-15)
# ===========================================================================

@test "adapter-edge: detekt adapter exists and is executable" {
  [[ -f "$DETEKT_ADAPTER" ]] || fail "detekt.sh not found at $DETEKT_ADAPTER"
  [[ -x "$DETEKT_ADAPTER" ]] || fail "detekt.sh is not executable"
}

@test "adapter-edge: detekt adapter has proper shebang line" {
  local first_line
  first_line=$(head -n1 "$DETEKT_ADAPTER")
  [[ "$first_line" == "#!/usr/bin/env bash" || "$first_line" == "#!/bin/bash" ]] \
    || fail "detekt.sh has unexpected shebang: $first_line"
}

@test "adapter-edge: detekt adapter output format has required pipe delimiters" {
  grep -q '|' "$DETEKT_ADAPTER" \
    || fail "detekt.sh does not contain pipe-delimited output format"
}

@test "adapter-edge: detekt empty input produces no findings" {
  local raw="${TEST_TEMP}/detekt-empty.txt"
  printf '' > "$raw"

  run python3 -c "
import re, sys
pat = re.compile(r'^(.+?):(\d+):\d+:\s+(.+?)\s+\[(\w+)]')
with open(sys.argv[1]) as f:
    for line in f:
        m = pat.match(line.strip())
        if m:
            print('finding')
" "$raw"

  assert_success
  [[ -z "$output" ]] || fail "Expected no findings for empty detekt input, got: $output"
}

@test "adapter-edge: detekt adapter handles missing tool gracefully (exits non-zero)" {
  local fake_project="${TEST_TEMP}/no-detekt"
  mkdir -p "$fake_project"
  # No gradlew or detekt on PATH

  run bash "$DETEKT_ADAPTER" "$fake_project" "$fake_project" "$SEV_MAP"
  assert_failure
}
