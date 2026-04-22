#!/usr/bin/env bats
# Scenario tests: domain detection consistency across documentation.

load '../helpers/test-helpers'

DOMAIN_DETECTION="$PLUGIN_ROOT/shared/domain-detection.md"
ORCHESTRATOR="$PLUGIN_ROOT/agents/fg-100-orchestrator.md"
ORCHESTRATOR_ALL=("$PLUGIN_ROOT/agents/fg-100-orchestrator.md")
STATE_SCHEMA="$PLUGIN_ROOT/shared/state-schema.md"
STATE_SCHEMA_FIELDS="$PLUGIN_ROOT/shared/state-schema-fields.md"

# ---------------------------------------------------------------------------
# 1. Orchestrator validates domain_area after planner
# ---------------------------------------------------------------------------
@test "domain-detection scenario: orchestrator validates domain_area after planner" {
  # The orchestrator must mention verifying/validating domain_area post-planner
  grep -q "domain_area" "${ORCHESTRATOR_ALL[@]}" \
    || fail "Orchestrator does not mention domain_area"
  grep -iq "verify\|validate\|check\|default" "${ORCHESTRATOR_ALL[@]}" \
    || fail "Orchestrator has no validation language for domain_area"
  # Specifically, it should default to "general" with WARNING
  grep -q 'general.*WARNING\|WARNING.*general' "${ORCHESTRATOR_ALL[@]}" \
    || fail "Orchestrator does not default to 'general' with WARNING"
}

# ---------------------------------------------------------------------------
# 2. State-schema references domain-detection.md
# ---------------------------------------------------------------------------
@test "domain-detection scenario: state-schema references domain-detection.md" {
  grep -qh "domain-detection.md" "$STATE_SCHEMA" "$STATE_SCHEMA_FIELDS" \
    || fail "state-schema(-fields).md does not reference domain-detection.md"
}

# ---------------------------------------------------------------------------
# 3. Known domains consistent between docs (auth and billing in both)
# ---------------------------------------------------------------------------
@test "domain-detection scenario: known domains consistent between docs" {
  for domain in auth billing; do
    grep -q "${domain}" "$DOMAIN_DETECTION" \
      || fail "Domain '${domain}' missing from domain-detection.md"
    grep -qh "${domain}" "$STATE_SCHEMA" "$STATE_SCHEMA_FIELDS" \
      || fail "Domain '${domain}' missing from state-schema(-fields).md"
  done
}

# ---------------------------------------------------------------------------
# 4. Fallback value is "general" in both docs
# ---------------------------------------------------------------------------
@test "domain-detection scenario: fallback value is general in both docs" {
  grep -q "general" "$DOMAIN_DETECTION" \
    || fail "'general' not found in domain-detection.md"
  grep -qh "general" "$STATE_SCHEMA" "$STATE_SCHEMA_FIELDS" \
    || fail "'general' not found in state-schema(-fields).md"
}
