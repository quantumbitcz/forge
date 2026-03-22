#!/usr/bin/env bats
# Contract tests: shared/recovery/recovery-engine.md — validates the recovery engine document.

load '../helpers/test-helpers'

RECOVERY_ENGINE="$PLUGIN_ROOT/shared/recovery/recovery-engine.md"
CLAUDE_MD="$PLUGIN_ROOT/CLAUDE.md"

# ---------------------------------------------------------------------------
# 1. Document exists
# ---------------------------------------------------------------------------
@test "recovery-engine: document exists" {
  [[ -f "$RECOVERY_ENGINE" ]]
}

# ---------------------------------------------------------------------------
# 2. All 7 recovery strategies defined
# ---------------------------------------------------------------------------
@test "recovery-engine: all 7 strategy names defined" {
  local strategies=(
    transient-retry
    tool-diagnosis
    state-reconstruction
    agent-reset
    dependency-health
    resource-cleanup
    graceful-stop
  )
  for strategy in "${strategies[@]}"; do
    grep -q "$strategy" "$RECOVERY_ENGINE" \
      || fail "Recovery strategy $strategy not found in recovery-engine.md"
  done
}

# ---------------------------------------------------------------------------
# 3. Strategy weights documented (check recovery-engine.md or CLAUDE.md)
# ---------------------------------------------------------------------------
@test "recovery-engine: strategy weights documented" {
  # Weights: transient-retry=0.5, tool-diagnosis=1.0, state-reconstruction=1.5,
  #          agent-reset=1.0, dependency-health=1.0, resource-cleanup=0.5, graceful-stop=0.0
  local combined
  combined="$(cat "$RECOVERY_ENGINE" "$CLAUDE_MD")"

  printf '%s' "$combined" | grep -q "transient-retry.*0\.5\|0\.5.*transient-retry" \
    || fail "transient-retry weight 0.5 not documented"
  printf '%s' "$combined" | grep -q "tool-diagnosis.*1\.0\|1\.0.*tool-diagnosis" \
    || fail "tool-diagnosis weight 1.0 not documented"
  printf '%s' "$combined" | grep -q "state-reconstruction.*1\.5\|1\.5.*state-reconstruction" \
    || fail "state-reconstruction weight 1.5 not documented"
  printf '%s' "$combined" | grep -q "graceful-stop.*0\.0\|0\.0.*graceful-stop" \
    || fail "graceful-stop weight 0.0 not documented"
}

# ---------------------------------------------------------------------------
# 4. Budget ceiling max_weight=5.0 documented
# ---------------------------------------------------------------------------
@test "recovery-engine: budget ceiling max_weight 5.0 documented" {
  grep -q "max_weight.*5\.0\|5\.0.*max_weight\|max_weight: 5\.0" "$RECOVERY_ENGINE" \
    || fail "Budget ceiling max_weight=5.0 not found in recovery-engine.md"
}

# ---------------------------------------------------------------------------
# 5. Warning at 80% (4.0) documented
# ---------------------------------------------------------------------------
@test "recovery-engine: budget warning at 80 percent (4.0) documented" {
  grep -q "4\.0\|80%" "$RECOVERY_ENGINE" \
    || fail "Budget warning at 80% (4.0) not documented"
  grep -q "warning\|Warning" "$RECOVERY_ENGINE" \
    || fail "Budget warning not mentioned"
}

# ---------------------------------------------------------------------------
# 6. Pre-classified errors section exists (references error-taxonomy.md)
# ---------------------------------------------------------------------------
@test "recovery-engine: pre-classified errors section references error-taxonomy.md" {
  grep -q "Pre-Classified\|Pre-classified\|pre-classified" "$RECOVERY_ENGINE" \
    || fail "Pre-classified errors section not found"
  grep -q "error-taxonomy" "$RECOVERY_ENGINE" \
    || fail "error-taxonomy.md not referenced in recovery-engine.md"
}

# ---------------------------------------------------------------------------
# 7. TRANSIENT heuristics include ETIMEDOUT and ECONNRESET
# ---------------------------------------------------------------------------
@test "recovery-engine: TRANSIENT heuristics include ETIMEDOUT and ECONNRESET" {
  grep -q "ETIMEDOUT" "$RECOVERY_ENGINE" \
    || fail "ETIMEDOUT not listed in TRANSIENT heuristics"
  grep -q "ECONNRESET" "$RECOVERY_ENGINE" \
    || fail "ECONNRESET not listed in TRANSIENT heuristics"
}

# ---------------------------------------------------------------------------
# 8. TOOL_FAILURE heuristics include exit codes 137, 139, 127
# ---------------------------------------------------------------------------
@test "recovery-engine: TOOL_FAILURE heuristics include exit codes 137 139 127" {
  grep -q "137" "$RECOVERY_ENGINE" || fail "Exit code 137 (OOM) not in TOOL_FAILURE heuristics"
  grep -q "139" "$RECOVERY_ENGINE" || fail "Exit code 139 (segfault) not in TOOL_FAILURE heuristics"
  grep -q "127" "$RECOVERY_ENGINE" || fail "Exit code 127 (not found) not in TOOL_FAILURE heuristics"
}

# ---------------------------------------------------------------------------
# 9. Network permanence detection: 3 consecutive failures (documented in error-taxonomy.md
#    and referenced/implied in recovery-engine.md via TRANSIENT strategy)
# ---------------------------------------------------------------------------
@test "recovery-engine: network permanence detection referenced in error-taxonomy" {
  local ERROR_TAXONOMY="$PLUGIN_ROOT/shared/error-taxonomy.md"
  grep -q "3 consecutive\|consecutive.*3\|3.*consecutive" "$ERROR_TAXONOMY" \
    || fail "3 consecutive failures for network permanence not documented in error-taxonomy.md"
  # recovery-engine.md should reference transient-retry strategy for network failures
  grep -q "transient-retry" "$RECOVERY_ENGINE" \
    || fail "transient-retry strategy not mentioned in recovery-engine.md"
}

# ---------------------------------------------------------------------------
# 10. Result codes documented: RECOVERED, DEGRADED, ESCALATE
# ---------------------------------------------------------------------------
@test "recovery-engine: result codes RECOVERED DEGRADED ESCALATE documented" {
  local results=(RECOVERED DEGRADED ESCALATE)
  for result in "${results[@]}"; do
    grep -q "$result" "$RECOVERY_ENGINE" \
      || fail "Result code $result not found in recovery-engine.md"
  done
}
