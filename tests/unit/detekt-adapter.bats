#!/usr/bin/env bats
# Unit tests for shared/checks/layer-2-linter/adapters/detekt.sh
# The Python parsing logic is extracted and called directly with fixture data,
# so tests run without detekt being installed.

load '../helpers/test-helpers'

ADAPTER="$PLUGIN_ROOT/shared/checks/layer-2-linter/adapters/detekt.sh"
SEV_MAP="$PLUGIN_ROOT/shared/checks/layer-2-linter/config/severity-map.json"
DETEKT_FIXTURE="$PLUGIN_ROOT/tests/fixtures/linter-output/detekt-sample.txt"

# ---------------------------------------------------------------------------
# Python snippet extracted from detekt.sh — used by parsing tests.
# Accepts: $1=sev_map_path  $2=raw_path
# ---------------------------------------------------------------------------
run_parser() {
  local sev_map="$1"
  local raw="$2"
  python3 -c "
import json, re, sys

sev_map_path = sys.argv[1]
raw_path = sys.argv[2]

with open(sev_map_path) as f:
    full_map = json.load(f)
detekt_map = full_map.get('detekt', {})

def lookup_severity(rule_id):
    if rule_id in detekt_map:
        return detekt_map[rule_id]
    best = ('', 'INFO')
    for pattern, sev in detekt_map.items():
        if pattern.endswith('.*'):
            prefix = pattern[:-2]
            if rule_id.startswith(prefix) and len(prefix) > len(best[0]):
                best = (prefix, sev)
        elif pattern.endswith('*'):
            prefix = pattern[:-1]
            if rule_id.startswith(prefix) and len(prefix) > len(best[0]):
                best = (prefix, sev)
    return best[1]

def map_category(rule_id):
    rule_lower = rule_id.lower()
    if any(k in rule_lower for k in ('security', 'injection', 'eval')):
        return 'SEC-DETEKT'
    if any(k in rule_lower for k in ('performance', 'perf')):
        return 'PERF-DETEKT'
    if any(k in rule_lower for k in ('exception', 'error', 'swallow')):
        return 'QUAL-ERR'
    if any(k in rule_lower for k in ('complexity', 'long', 'large')):
        return 'QUAL-COMPLEX'
    return 'QUAL-DETEKT'

pat = re.compile(r'^(.+?):(\d+):\d+:\s+(.+?)\s+\[([\w.]+)]')

with open(raw_path) as f:
    for line in f:
        m = pat.match(line.strip())
        if not m:
            continue
        filepath, lineno, message, rule_id = m.group(1), m.group(2), m.group(3), m.group(4)
        severity = lookup_severity(rule_id)
        category = map_category(rule_id)
        hint = f'detekt rule {rule_id}'
        print(f'{filepath}:{lineno} | {category} | {severity} | {message} | {hint}')
" "$sev_map" "$raw"
}

# ---------------------------------------------------------------------------
# 1. Exits 1 when detekt not available (no detekt on PATH, no gradlew)
# ---------------------------------------------------------------------------
@test "detekt adapter: exits 1 when detekt not installed and no gradlew" {
  local fake_project="${TEST_TEMP}/empty-project"
  mkdir -p "$fake_project"

  # Ensure detekt is NOT on PATH (mock-bin has no detekt, and real detekt unlikely installed)
  # Pass a project dir with no gradlew
  run bash "$ADAPTER" "$fake_project" "$fake_project" "$SEV_MAP"
  assert_failure
  assert [ "$status" -eq 1 ]
}

# ---------------------------------------------------------------------------
# 2. Parses detekt output format correctly — all 4 fixture lines produce output
# ---------------------------------------------------------------------------
@test "detekt parser: parses all 4 fixture lines" {
  run run_parser "$SEV_MAP" "$DETEKT_FIXTURE"
  assert_success
  # 4 valid lines in fixture → 4 output lines
  local line_count
  line_count=$(printf '%s\n' "$output" | grep -c '|' || true)
  assert [ "$line_count" -eq 4 ]
}

# ---------------------------------------------------------------------------
# 3. Exact severity match: SwallowedException → CRITICAL
# ---------------------------------------------------------------------------
@test "detekt parser: SwallowedException maps to CRITICAL (exact match)" {
  local raw="${TEST_TEMP}/single.txt"
  printf 'src/main/kotlin/Foo.kt:15:5: A swallowed exception [SwallowedException]\n' > "$raw"

  run run_parser "$SEV_MAP" "$raw"
  assert_success
  assert_output --partial "CRITICAL"
}

# ---------------------------------------------------------------------------
# 4. Glob prefix match: complexity.TooLongFunction → WARNING (via complexity.*)
# ---------------------------------------------------------------------------
@test "detekt parser: complexity.TooLongFunction maps to WARNING (glob prefix match)" {
  local raw="${TEST_TEMP}/complexity.txt"
  printf 'src/main/kotlin/Foo.kt:23:1: The function is too long (45 lines) [complexity.TooLongFunction]\n' > "$raw"

  run run_parser "$SEV_MAP" "$raw"
  assert_success
  assert_output --partial "WARNING"
}

# ---------------------------------------------------------------------------
# 5. Longest glob prefix wins
#    Set up a severity map where both "foo.*" → INFO and "foo.bar.*" → CRITICAL exist.
#    Rule "foo.bar.Baz" should resolve to CRITICAL (longer prefix wins).
# ---------------------------------------------------------------------------
@test "detekt parser: longest glob prefix wins" {
  local custom_map="${TEST_TEMP}/custom-sev-map.json"
  cat > "$custom_map" << 'JSON'
{
  "detekt": {
    "foo.*": "INFO",
    "foo.bar.*": "CRITICAL"
  }
}
JSON

  local raw="${TEST_TEMP}/prefix.txt"
  printf 'src/main/kotlin/Foo.kt:10:1: Some message [foo.bar.Baz]\n' > "$raw"

  run run_parser "$custom_map" "$raw"
  assert_success
  assert_output --partial "CRITICAL"
}

# ---------------------------------------------------------------------------
# 6. Default severity INFO for unknown rules (SomeNewRule)
# ---------------------------------------------------------------------------
@test "detekt parser: unknown rule defaults to INFO" {
  local raw="${TEST_TEMP}/unknown.txt"
  printf 'src/main/kotlin/Foo.kt:8:3: Unknown rule [SomeNewRule]\n' > "$raw"

  run run_parser "$SEV_MAP" "$raw"
  assert_success
  assert_output --partial "INFO"
}

# ---------------------------------------------------------------------------
# 7. Category mapping: exception/swallow keywords → QUAL-ERR
# ---------------------------------------------------------------------------
@test "detekt parser: SwallowedException maps to category QUAL-ERR" {
  local raw="${TEST_TEMP}/exception.txt"
  printf 'src/main/kotlin/Foo.kt:15:5: A swallowed exception [SwallowedException]\n' > "$raw"

  run run_parser "$SEV_MAP" "$raw"
  assert_success
  assert_output --partial "QUAL-ERR"
}

# ---------------------------------------------------------------------------
# 8. Category mapping: complexity keywords → QUAL-COMPLEX
# ---------------------------------------------------------------------------
@test "detekt parser: complexity.TooLongFunction maps to category QUAL-COMPLEX" {
  local raw="${TEST_TEMP}/complex.txt"
  printf 'src/main/kotlin/Foo.kt:23:1: The function is too long (45 lines) [complexity.TooLongFunction]\n' > "$raw"

  run run_parser "$SEV_MAP" "$raw"
  assert_success
  assert_output --partial "QUAL-COMPLEX"
}
