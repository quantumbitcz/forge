#!/usr/bin/env bats
# Reflection eval scenario fixtures structural guard.
# Asserts every YAML under tests/evals/scenarios/reflection/ carries the schema
# fields the future fg-301-implementer-critic eval harness will consume.

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  SCENARIOS_DIR="$PLUGIN_ROOT/tests/evals/scenarios/reflection"
}

@test "reflection scenarios directory exists" {
  [ -d "$SCENARIOS_DIR" ]
}

@test "exactly 5 reflection scenarios are defined" {
  count=$(find "$SCENARIOS_DIR" -maxdepth 1 -name '*.yaml' | wc -l | tr -d ' ')
  [ "$count" -eq 5 ]
}

@test "every reflection scenario has the required top-level keys" {
  for f in "$SCENARIOS_DIR"/*.yaml; do
    for key in id phase kind agent_under_test description task test_code implementation_diff expected; do
      grep -qE "^${key}:" "$f" || { echo "MISSING key '${key}' in $f"; return 1; }
    done
  done
}

@test "every reflection scenario targets fg-301-implementer-critic" {
  for f in "$SCENARIOS_DIR"/*.yaml; do
    grep -qE '^agent_under_test:[[:space:]]*fg-301-implementer-critic' "$f" || \
      { echo "WRONG agent_under_test in $f"; return 1; }
  done
}

@test "every reflection scenario uses kind planted-defect or false-positive-guard" {
  for f in "$SCENARIOS_DIR"/*.yaml; do
    grep -qE '^kind:[[:space:]]*(planted-defect|false-positive-guard)$' "$f" || \
      { echo "WRONG kind in $f"; return 1; }
  done
}

@test "every reflection scenario declares phase 04" {
  for f in "$SCENARIOS_DIR"/*.yaml; do
    grep -qE '^phase:[[:space:]]*0?4$' "$f" || \
      { echo "WRONG phase in $f"; return 1; }
  done
}

@test "scenarios cover the 3 REFLECT-* defect categories + 2 false-positive guards" {
  required_categories=(REFLECT-HARDCODED-RETURN REFLECT-OVER-NARROW REFLECT-MISSING-BRANCH)
  for cat in "${required_categories[@]}"; do
    grep -lqE "finding_category:[[:space:]]*${cat}" "$SCENARIOS_DIR"/*.yaml || \
      { echo "MISSING coverage for category $cat"; return 1; }
  done
  guard_count=$(grep -l '^kind:[[:space:]]*false-positive-guard' "$SCENARIOS_DIR"/*.yaml | wc -l | tr -d ' ')
  [ "$guard_count" -eq 2 ]
}

@test "planted-defect scenarios expect REVISE verdict; guards expect PASS" {
  for f in "$SCENARIOS_DIR"/*.yaml; do
    kind=$(grep -E '^kind:' "$f" | head -1 | awk '{print $2}')
    verdict=$(grep -A 3 '^expected:' "$f" | grep -E '^[[:space:]]+verdict:' | awk '{print $2}')
    case "$kind" in
      planted-defect)
        [ "$verdict" = "REVISE" ] || { echo "Defect $f has verdict $verdict (expected REVISE)"; return 1; }
        ;;
      false-positive-guard)
        [ "$verdict" = "PASS" ] || { echo "Guard $f has verdict $verdict (expected PASS)"; return 1; }
        ;;
    esac
  done
}
