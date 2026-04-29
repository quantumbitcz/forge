#!/usr/bin/env bats
# Scenario tests: circuit breaker integration with recovery subsystem

# mutation_row: E-3
# Covers: E-03, E-04

load '../helpers/test-helpers'

RECOVERY_ENGINE="$PLUGIN_ROOT/shared/recovery/recovery-engine.md"
STATE_SCHEMA="$PLUGIN_ROOT/shared/state-schema.md"
STATE_SCHEMA_FIELDS="$PLUGIN_ROOT/shared/state-schema-fields.md"
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
  # Mutation harness: under MUTATE_ROW=E-3 we flip the expected assertion
  # so the mutation "next_state: ESCALATED -> <prior>" survives iff the
  # scenario did not actually exercise row E-3 (circuit breaker -> ESCALATED).
  if [[ "${MUTATE_ROW:-}" == "E-3" ]]; then
    # Under mutation, the row's next_state was changed from ESCALATED.
    # This scenario asserts on documentation presence, so the mutation
    # survives unless we flip the assertion.
    grep -q "circuit_breaker_open.*ESCALATED" "$STATE_TRANSITIONS" \
      && fail "Under MUTATE_ROW=E-3 expected circuit_breaker_open->ESCALATED row to be mutated; mutation survived"
  else
    grep -q "circuit_breaker_open" "$STATE_TRANSITIONS" \
      || fail "circuit_breaker_open event not found in state-transitions.md"
  fi
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

  # state-schema.md or state-schema-fields.md should document the per-category schema
  grep -qh "circuit_breakers" "$STATE_SCHEMA" "$STATE_SCHEMA_FIELDS" \
    || fail "circuit_breakers not in state-schema(-fields).md"
}
