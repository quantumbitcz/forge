#!/usr/bin/env bats
# Scenario tests: circuit breaker integration with recovery subsystem

load '../helpers/test-helpers'

RECOVERY_ENGINE="$PLUGIN_ROOT/shared/recovery/recovery-engine.md"
STATE_SCHEMA="$PLUGIN_ROOT/shared/state-schema.md"
STATE_TRANSITIONS="$PLUGIN_ROOT/shared/state-transitions.md"
ERROR_TAXONOMY="$PLUGIN_ROOT/shared/error-taxonomy.md"

# ---------------------------------------------------------------------------
# 1. Recovery engine checks circuit before budget (decision order)
# ---------------------------------------------------------------------------
@test "circuit-breaker-scenario: recovery engine checks circuit before budget" {
  local section
  section=$(sed -n '/## 8.1 Circuit Breaker/,/^## [0-9]/p' "$RECOVERY_ENGINE")
  echo "$section" | grep -qi "circuit breaker check.*budget\|before.*budget\|circuit.*then.*budget" \
    || fail "Decision order (circuit before budget) not documented"
}

# ---------------------------------------------------------------------------
# 2. state-transitions.md has circuit_breaker_open event
# ---------------------------------------------------------------------------
@test "circuit-breaker-scenario: state-transitions.md has circuit_breaker_open event" {
  [[ -f "$STATE_TRANSITIONS" ]] \
    || fail "state-transitions.md does not exist"
  grep -q "circuit_breaker_open" "$STATE_TRANSITIONS" \
    || fail "circuit_breaker_open event not found in state-transitions.md"
}

# ---------------------------------------------------------------------------
# 3. Error taxonomy categories map to circuit breaker categories
# ---------------------------------------------------------------------------
@test "circuit-breaker-scenario: error taxonomy types map to circuit breaker categories" {
  local cb_section
  cb_section=$(sed -n '/## 8.1 Circuit Breaker/,/^## [0-9]/p' "$RECOVERY_ENGINE")

  # Key error types from taxonomy should appear in circuit breaker category mappings
  local mapped=0
  for error_type in BUILD_FAILURE TEST_FAILURE NETWORK_UNAVAILABLE AGENT_TIMEOUT STATE_CORRUPTION DEPENDENCY_MISSING; do
    if echo "$cb_section" | grep -q "$error_type"; then
      mapped=$((mapped + 1))
    fi
  done
  [[ $mapped -ge 4 ]] \
    || fail "Expected at least 4 error taxonomy types mapped in circuit breaker, found $mapped"
}

# ---------------------------------------------------------------------------
# 4. Schema matches between recovery-engine and state-schema
# ---------------------------------------------------------------------------
@test "circuit-breaker-scenario: circuit breaker schema consistent between recovery-engine and state-schema" {
  # Both documents should reference the same key schema fields
  local engine_section
  engine_section=$(sed -n '/## 8.1 Circuit Breaker/,/^## [0-9]/p' "$RECOVERY_ENGINE")

  # Check that key schema fields appear in both documents
  for field in state failures_count last_failure_timestamp cooldown_seconds; do
    echo "$engine_section" | grep -q "$field" \
      || fail "Schema field '$field' missing from recovery-engine.md circuit breaker section"
  done

  # state-schema.md should document the per-category schema
  grep -q "circuit_breakers" "$STATE_SCHEMA" \
    || fail "circuit_breakers not in state-schema.md"
}
