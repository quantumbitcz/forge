#!/usr/bin/env bats
# Contract tests: shared/error-taxonomy.md — validates the error taxonomy document.

load '../helpers/test-helpers'

ERROR_TAXONOMY="$PLUGIN_ROOT/shared/error-taxonomy.md"

# ---------------------------------------------------------------------------
# 1. Document exists
# ---------------------------------------------------------------------------
@test "error-taxonomy: document exists" {
  [[ -f "$ERROR_TAXONOMY" ]]
}

# ---------------------------------------------------------------------------
# 2. All 15 error types are defined
# ---------------------------------------------------------------------------
@test "error-taxonomy: all 15 error types are defined" {
  local types=(
    TOOL_FAILURE
    BUILD_FAILURE
    TEST_FAILURE
    LINT_FAILURE
    AGENT_TIMEOUT
    AGENT_ERROR
    STATE_CORRUPTION
    DEPENDENCY_MISSING
    CONFIG_INVALID
    GIT_CONFLICT
    DISK_FULL
    NETWORK_UNAVAILABLE
    PERMISSION_DENIED
    MCP_UNAVAILABLE
    PATTERN_MISSING
  )
  for t in "${types[@]}"; do
    grep -q "$t" "$ERROR_TAXONOMY" || fail "Error type $t not found in error-taxonomy.md"
  done
}

# ---------------------------------------------------------------------------
# 3. Each error type has a recovery strategy (or "none") in the table
# ---------------------------------------------------------------------------
@test "error-taxonomy: error table rows contain recovery strategy or none" {
  # Every type listed in the table should have either a named strategy or "none"
  # Check that the error types appear in table rows that include | (table cells)
  local found_table_rows
  found_table_rows=$(grep -c '|.*\(tool-diagnosis\|agent-reset\|state-reconstruction\|dependency-health\|transient-retry\|resource-cleanup\|graceful\|none\)' "$ERROR_TAXONOMY" || true)
  [[ "$found_table_rows" -ge 10 ]] || fail "Expected at least 10 table rows with recovery strategies, got $found_table_rows"
}

# ---------------------------------------------------------------------------
# 4. Error severity ordering has 12 levels (numbered list 1-12)
# ---------------------------------------------------------------------------
@test "error-taxonomy: severity ordering has 12 levels" {
  local count
  count=$(grep -cE '^[0-9]+\. `' "$ERROR_TAXONOMY" || true)
  assert_equal "$count" "12"
}

# ---------------------------------------------------------------------------
# 5. CONFIG_INVALID is highest severity (position 1)
# ---------------------------------------------------------------------------
@test "error-taxonomy: CONFIG_INVALID is severity level 1 (highest)" {
  # The first numbered item should reference CONFIG_INVALID
  local first_item
  first_item=$(grep -E '^1\. ' "$ERROR_TAXONOMY")
  printf '%s' "$first_item" | grep -q "CONFIG_INVALID" \
    || fail "Severity level 1 does not reference CONFIG_INVALID: $first_item"
}

# ---------------------------------------------------------------------------
# 6. PATTERN_MISSING is lowest severity (position 12)
# ---------------------------------------------------------------------------
@test "error-taxonomy: PATTERN_MISSING is severity level 12 (lowest)" {
  local last_item
  last_item=$(grep -E '^12\. ' "$ERROR_TAXONOMY")
  printf '%s' "$last_item" | grep -q "PATTERN_MISSING" \
    || fail "Severity level 12 does not reference PATTERN_MISSING: $last_item"
}

# ---------------------------------------------------------------------------
# 7. MCP_UNAVAILABLE handling section exists (inline, not recovery engine)
# ---------------------------------------------------------------------------
@test "error-taxonomy: MCP_UNAVAILABLE handled inline not via recovery engine" {
  # Section heading must exist
  grep -q "MCP_UNAVAILABLE Handling" "$ERROR_TAXONOMY" \
    || fail "MCP_UNAVAILABLE Handling section not found"
  # Must state NOT recovery engine domain
  grep -q "NOT recovery engine" "$ERROR_TAXONOMY" \
    || fail "Document does not state MCP_UNAVAILABLE is NOT recovery engine domain"
}

# ---------------------------------------------------------------------------
# 8. Network permanence detection section exists (3 consecutive failures, 60 seconds)
# ---------------------------------------------------------------------------
@test "error-taxonomy: network permanence detection documented with 3 failures and 60 seconds" {
  grep -q "Network Permanence Detection" "$ERROR_TAXONOMY" \
    || fail "Network Permanence Detection section not found"
  grep -q "3 consecutive" "$ERROR_TAXONOMY" \
    || fail "3 consecutive failures not mentioned"
  grep -q "60 second" "$ERROR_TAXONOMY" \
    || fail "60 second window not mentioned"
}

# ---------------------------------------------------------------------------
# 9. Error format fields documented: ERROR_TYPE, ERROR_DETAIL, RECOVERABLE,
#    SUGGESTED_STRATEGY, CONTEXT
# ---------------------------------------------------------------------------
@test "error-taxonomy: error format fields all documented" {
  local fields=(ERROR_TYPE ERROR_DETAIL RECOVERABLE SUGGESTED_STRATEGY CONTEXT)
  for field in "${fields[@]}"; do
    grep -q "$field" "$ERROR_TAXONOMY" || fail "Error format field $field not found"
  done
}

# ---------------------------------------------------------------------------
# 10. Error aggregation rules documented (group by ERROR_TYPE)
# ---------------------------------------------------------------------------
@test "error-taxonomy: error aggregation rules document group by ERROR_TYPE" {
  grep -q "Error Aggregation" "$ERROR_TAXONOMY" \
    || fail "Error Aggregation section not found"
  grep -q "Group by ERROR_TYPE\|Group by\|group by ERROR_TYPE\|group by" "$ERROR_TAXONOMY" \
    || fail "Group-by ERROR_TYPE aggregation rule not mentioned"
}
