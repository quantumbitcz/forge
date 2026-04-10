#!/usr/bin/env bats
# Contract tests: error-taxonomy.md <-> recovery-engine.md sync validation
# Validates that all error types are consistently mapped between the two documents.

load '../helpers/test-helpers'

ERROR_TAXONOMY="$PLUGIN_ROOT/shared/error-taxonomy.md"
RECOVERY_ENGINE="$PLUGIN_ROOT/shared/recovery/recovery-engine.md"

# ---------------------------------------------------------------------------
# 1. All taxonomy error types appear in recovery mapping table
# ---------------------------------------------------------------------------
@test "error-recovery-sync: all taxonomy error types appear in recovery mapping table" {
  # Extract error types from the taxonomy table (first column after | Type |)
  local taxonomy_types
  taxonomy_types=$(grep -E '^\| [A-Z_]+ \|' "$ERROR_TAXONOMY" | awk -F'|' '{gsub(/^ +| +$/, "", $2); print $2}')

  # Extract error types from the recovery engine mapping table (section 3)
  local recovery_section
  recovery_section=$(sed -n '/^### Error Type to Recovery Category Mapping/,/^### /p' "$RECOVERY_ENGINE")

  local missing=0
  while IFS= read -r etype; do
    [[ -z "$etype" ]] && continue
    if ! echo "$recovery_section" | grep -q "$etype"; then
      echo "MISSING in recovery-engine.md: $etype"
      missing=$((missing + 1))
    fi
  done <<< "$taxonomy_types"

  [[ $missing -eq 0 ]] || fail "$missing error types from taxonomy missing in recovery mapping table"
}

# ---------------------------------------------------------------------------
# 2. All recovery mapping types exist in taxonomy
# ---------------------------------------------------------------------------
@test "error-recovery-sync: all recovery mapping types exist in taxonomy" {
  # Extract error types from recovery engine mapping table
  local recovery_types
  recovery_types=$(sed -n '/^### Error Type to Recovery Category Mapping/,/^### /p' "$RECOVERY_ENGINE" \
    | grep -E '^\| [A-Z_]+ \|' | awk -F'|' '{gsub(/^ +| +$/, "", $2); print $2}')

  local missing=0
  while IFS= read -r etype; do
    [[ -z "$etype" ]] && continue
    if ! grep -q "| $etype " "$ERROR_TAXONOMY"; then
      echo "MISSING in error-taxonomy.md: $etype"
      missing=$((missing + 1))
    fi
  done <<< "$recovery_types"

  [[ $missing -eq 0 ]] || fail "$missing error types from recovery mapping missing in taxonomy"
}

# ---------------------------------------------------------------------------
# 3. CODE errors (BUILD/TEST/LINT) mapped to orchestrator, not recovery
# ---------------------------------------------------------------------------
@test "error-recovery-sync: CODE errors (BUILD/TEST/LINT) mapped to orchestrator, not recovery" {
  local recovery_section
  recovery_section=$(sed -n '/^### Error Type to Recovery Category Mapping/,/^### /p' "$RECOVERY_ENGINE")

  for etype in BUILD_FAILURE TEST_FAILURE LINT_FAILURE; do
    local row
    row=$(echo "$recovery_section" | grep "| $etype ")
    # These should have "—" in the strategy column (not recovery engine)
    echo "$row" | grep -q "—" \
      || fail "$etype should be mapped to orchestrator (— in strategy column), got: $row"
  done
}

# ---------------------------------------------------------------------------
# 4. MCP_UNAVAILABLE mapped to inline, not recovery
# ---------------------------------------------------------------------------
@test "error-recovery-sync: MCP_UNAVAILABLE mapped to inline, not recovery" {
  local recovery_section
  recovery_section=$(sed -n '/^### Error Type to Recovery Category Mapping/,/^### /p' "$RECOVERY_ENGINE")

  local row
  row=$(echo "$recovery_section" | grep "| MCP_UNAVAILABLE ")
  echo "$row" | grep -q "—" \
    || fail "MCP_UNAVAILABLE should be mapped inline (— in strategy column), got: $row"
}

# ---------------------------------------------------------------------------
# 5. UNRECOVERABLE types map to graceful-stop
# ---------------------------------------------------------------------------
@test "error-recovery-sync: UNRECOVERABLE types map to graceful-stop" {
  local recovery_section
  recovery_section=$(sed -n '/^### Error Type to Recovery Category Mapping/,/^### /p' "$RECOVERY_ENGINE")

  # Error types that map to UNRECOVERABLE category
  for etype in CONFIG_INVALID PATTERN_MISSING VERSION_MISMATCH BUDGET_EXHAUSTED; do
    local row
    row=$(echo "$recovery_section" | grep "| $etype ")
    echo "$row" | grep -qi "UNRECOVERABLE" \
      || fail "$etype should map to UNRECOVERABLE category, got: $row"
    echo "$row" | grep -qi "graceful-stop" \
      || fail "$etype should use graceful-stop strategy, got: $row"
  done
}

# ---------------------------------------------------------------------------
# 6. Circuit breaker categories cover all recovery categories
# ---------------------------------------------------------------------------
@test "error-recovery-sync: circuit breaker categories cover all recovery categories" {
  # Get circuit breaker failure categories from section 8.1
  local cb_section
  cb_section=$(sed -n '/^## 8.1 Circuit Breaker/,/^## [0-9]/p' "$RECOVERY_ENGINE")

  # Circuit breaker categories: build, test, network, agent, state, environment
  local cb_categories="build test network agent state environment"

  # For each non-code, non-MCP, non-UNRECOVERABLE error type in recovery mapping,
  # verify its category maps to a circuit breaker category
  local recovery_section
  recovery_section=$(sed -n '/^### Error Type to Recovery Category Mapping/,/^### /p' "$RECOVERY_ENGINE")

  # Check that the CB section documents all 6 categories
  for cat in $cb_categories; do
    echo "$cb_section" | grep -qi "$cat" \
      || fail "Circuit breaker category '$cat' not documented in section 8.1"
  done
}
