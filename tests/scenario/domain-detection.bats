#!/usr/bin/env bats
# Scenario tests: domain detection consistency across documentation.

load '../helpers/test-helpers'

DOMAIN_DETECTION="$PLUGIN_ROOT/shared/domain-detection.md"
ORCHESTRATOR="$PLUGIN_ROOT/agents/fg-100-orchestrator.md"
STATE_SCHEMA="$PLUGIN_ROOT/shared/state-schema.md"

# ---------------------------------------------------------------------------
# 1. Orchestrator validates domain_area after planner
# ---------------------------------------------------------------------------
@test "domain-detection scenario: orchestrator validates domain_area after planner" {
  # The orchestrator must mention verifying/validating domain_area post-planner
  grep -q "domain_area" "$ORCHESTRATOR" \
    || fail "Orchestrator does not mention domain_area"
  grep -iq "verify\|validate\|check\|default" "$ORCHESTRATOR" \
    || fail "Orchestrator has no validation language for domain_area"
  # Specifically, it should default to "general" with WARNING
  grep -q 'general.*WARNING\|WARNING.*general' "$ORCHESTRATOR" \
    || fail "Orchestrator does not default to 'general' with WARNING"
}

# ---------------------------------------------------------------------------
# 2. State-schema references domain-detection.md
# ---------------------------------------------------------------------------
@test "domain-detection scenario: state-schema references domain-detection.md" {
  grep -q "domain-detection.md" "$STATE_SCHEMA" \
    || fail "state-schema.md does not reference domain-detection.md"
}

# ---------------------------------------------------------------------------
# 3. Known domains consistent between docs (auth and billing in both)
# ---------------------------------------------------------------------------
@test "domain-detection scenario: known domains consistent between docs" {
  for domain in auth billing; do
    grep -q "${domain}" "$DOMAIN_DETECTION" \
      || fail "Domain '${domain}' missing from domain-detection.md"
    grep -q "${domain}" "$STATE_SCHEMA" \
      || fail "Domain '${domain}' missing from state-schema.md"
  done
}

# ---------------------------------------------------------------------------
# 4. Fallback value is "general" in both docs
# ---------------------------------------------------------------------------
@test "domain-detection scenario: fallback value is general in both docs" {
  grep -q "general" "$DOMAIN_DETECTION" \
    || fail "'general' not found in domain-detection.md"
  grep -q "general" "$STATE_SCHEMA" \
    || fail "'general' not found in state-schema.md"
}
