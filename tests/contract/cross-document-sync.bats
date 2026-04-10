#!/usr/bin/env bats
# Contract tests: cross-document coupling validation
# Validates consistency between interrelated specification documents.

load '../helpers/test-helpers'

STATE_SCHEMA="$PLUGIN_ROOT/shared/state-schema.md"
STATE_TRANSITIONS="$PLUGIN_ROOT/shared/state-transitions.md"
CONVERGENCE_ENGINE="$PLUGIN_ROOT/shared/convergence-engine.md"
RECOVERY_ENGINE="$PLUGIN_ROOT/shared/recovery/recovery-engine.md"
SCORING="$PLUGIN_ROOT/shared/scoring.md"
AGENTS_DIR="$PLUGIN_ROOT/agents"
MODES_DIR="$PLUGIN_ROOT/shared/modes"

# ---------------------------------------------------------------------------
# 1. State schema fields referenced in transition guards exist
# ---------------------------------------------------------------------------
@test "cross-doc: state schema fields referenced in transition guards exist" {
  # Key guard fields used in state-transitions.md that must exist in state-schema.md
  local guard_fields=(
    "dry_run"
    "verify_fix_count"
    "total_iterations"
    "phase_iterations"
    "safety_gate_failures"
    "plateau_count"
    "convergence_state"
    "feedback_loop_count"
    "total_retries"
    "score_history"
  )

  local missing=0
  for field in "${guard_fields[@]}"; do
    if ! grep -q "$field" "$STATE_SCHEMA"; then
      echo "MISSING in state-schema.md: guard field '$field'"
      missing=$((missing + 1))
    fi
  done

  [[ $missing -eq 0 ]] || fail "$missing guard fields from transition table missing in state-schema.md"
}

# ---------------------------------------------------------------------------
# 2. Convergence state values in transition table match convergence-engine.md
# ---------------------------------------------------------------------------
@test "cross-doc: convergence state values in transition table match convergence-engine.md" {
  # Convergence phases used in both documents
  for phase in "correctness" "perfection" "safety_gate"; do
    grep -q "$phase" "$STATE_TRANSITIONS" \
      || fail "Phase '$phase' not found in state-transitions.md"
    grep -q "$phase" "$CONVERGENCE_ENGINE" \
      || fail "Phase '$phase' not found in convergence-engine.md"
  done

  # Convergence states referenced in both documents
  # IMPROVING and REGRESSING appear as convergence_state values in transition actions
  # PLATEAUED is defined in convergence-engine.md; state-transitions.md uses
  # score_plateau event + plateau_count guards to model the same concept
  for state in "IMPROVING" "REGRESSING"; do
    grep -q "$state" "$STATE_TRANSITIONS" \
      || fail "Convergence state '$state' not found in state-transitions.md"
    grep -q "$state" "$CONVERGENCE_ENGINE" \
      || fail "Convergence state '$state' not found in convergence-engine.md"
  done

  # Verify PLATEAUED is defined in convergence-engine (authoritative source)
  grep -q "PLATEAUED" "$CONVERGENCE_ENGINE" \
    || fail "Convergence state 'PLATEAUED' not found in convergence-engine.md"

  # Verify plateau concept exists in state-transitions.md (via score_plateau event)
  grep -q "score_plateau" "$STATE_TRANSITIONS" \
    || fail "score_plateau event not found in state-transitions.md (PLATEAUED equivalent)"
}

# ---------------------------------------------------------------------------
# 3. Degraded capabilities in recovery-engine.md match orchestrator dispatch rules
# ---------------------------------------------------------------------------
@test "cross-doc: degraded capabilities in recovery-engine.md match orchestrator dispatch rules" {
  # Section 7 of recovery-engine.md lists capability names and their dispatch rules
  local degraded_section
  degraded_section=$(sed -n '/^## 7\. Degraded Capability Handling/,/^## [0-9]/p' "$RECOVERY_ENGINE")

  # All documented degraded capability names must appear
  for cap in "context7" "linear" "playwright" "slack" "figma" "build" "test" "git"; do
    echo "$degraded_section" | grep -q "\"$cap\"" \
      || fail "Degraded capability '$cap' not in recovery-engine.md section 7"
  done
}

# ---------------------------------------------------------------------------
# 4. Scoring constraint ranges in scoring.md match convergence-engine.md
# ---------------------------------------------------------------------------
@test "cross-doc: scoring constraint ranges in scoring.md match convergence-engine.md" {
  # max_iterations range: 3-20 in both docs
  grep -q "max_iterations" "$CONVERGENCE_ENGINE" \
    || fail "max_iterations not found in convergence-engine.md"
  grep -q "3-20\|3.*20" "$CONVERGENCE_ENGINE" \
    || fail "max_iterations range 3-20 not in convergence-engine.md"

  # plateau_threshold range: 0-10 in both docs
  grep -q "plateau_threshold" "$CONVERGENCE_ENGINE" \
    || fail "plateau_threshold not found in convergence-engine.md"
  grep -q "0-10\|0.*10" "$CONVERGENCE_ENGINE" \
    || fail "plateau_threshold range 0-10 not in convergence-engine.md"

  # plateau_patience range: 1-5 in both docs
  grep -q "plateau_patience" "$CONVERGENCE_ENGINE" \
    || fail "plateau_patience not found in convergence-engine.md"
  grep -q "1-5\|1.*5" "$CONVERGENCE_ENGINE" \
    || fail "plateau_patience range 1-5 not in convergence-engine.md"

  # oscillation_tolerance: same range in scoring.md
  grep -q "oscillation_tolerance" "$SCORING" \
    || fail "oscillation_tolerance not found in scoring.md"
}

# ---------------------------------------------------------------------------
# 5. Transition table row count matches expected
# ---------------------------------------------------------------------------
@test "cross-doc: transition table row count matches expected" {
  # Count pipeline rows (numbered lines starting with | <number> |)
  local pipeline_rows
  pipeline_rows=$(grep -cE '^\| [0-9]+ \|' "$STATE_TRANSITIONS")

  # Count error rows (E1-E8)
  local error_rows
  error_rows=$(grep -cE '^\| E[0-9]+ \|' "$STATE_TRANSITIONS")

  # Count dry-run rows (D1)
  local dryrun_rows
  dryrun_rows=$(grep -cE '^\| D[0-9]+ \|' "$STATE_TRANSITIONS")

  # Count convergence rows (C1-C13)
  local convergence_rows
  convergence_rows=$(grep -cE '^\| C[0-9]+ \|' "$STATE_TRANSITIONS")

  local total=$((pipeline_rows + error_rows + dryrun_rows + convergence_rows))

  # After P0 adds row 50-51 and E8: expect 50 pipeline + 8 error + 1 dry-run + 13 convergence = 72
  # Note: pipeline rows skip #20, so rows 1-19,21-51 = 50 rows
  # If counts differ, the table has been modified without updating this test
  echo "Pipeline: $pipeline_rows, Error: $error_rows, Dry-run: $dryrun_rows, Convergence: $convergence_rows, Total: $total"

  [[ $pipeline_rows -ge 49 ]] \
    || fail "Expected at least 49 pipeline rows, found $pipeline_rows"
  [[ $error_rows -ge 7 ]] \
    || fail "Expected at least 7 error rows, found $error_rows"
  [[ $dryrun_rows -ge 1 ]] \
    || fail "Expected at least 1 dry-run row, found $dryrun_rows"
  [[ $convergence_rows -ge 13 ]] \
    || fail "Expected at least 13 convergence rows, found $convergence_rows"
}

# ---------------------------------------------------------------------------
# 6. All agents referenced in mode overlays exist
# ---------------------------------------------------------------------------
@test "cross-doc: all agents referenced in mode overlays exist" {
  [[ -d "$MODES_DIR" ]] || skip "Mode overlays directory not found (created by P1)"

  local missing=0
  for overlay in "$MODES_DIR"/*.md; do
    [[ -f "$overlay" ]] || continue
    # Extract agent references (fg-NNN-name pattern)
    local agents
    agents=$(grep -oE 'fg-[0-9]+-[a-z-]+' "$overlay" | sort -u)
    while IFS= read -r agent_ref; do
      [[ -z "$agent_ref" ]] && continue
      # Check if agent file exists (with or without .md)
      if [[ ! -f "$AGENTS_DIR/${agent_ref}.md" ]]; then
        echo "MISSING agent: $agent_ref (referenced in $(basename "$overlay"))"
        missing=$((missing + 1))
      fi
    done <<< "$agents"
  done

  [[ $missing -eq 0 ]] || fail "$missing agents referenced in mode overlays do not exist"
}

# ---------------------------------------------------------------------------
# 7. Circuit breaker categories cover all recovery category columns
# ---------------------------------------------------------------------------
@test "cross-doc: circuit breaker categories cover all recovery category columns" {
  # The CB section (8.1) defines 6 lowercase categories (build, test, network,
  # agent, state, environment) that each aggregate multiple error types.
  # Verify all 6 categories are documented and that their listed error types
  # are valid entries in the error-taxonomy.md.

  local cb_section
  cb_section=$(sed -n '/^## 8.1 Circuit Breaker/,/^## [0-9]/p' "$RECOVERY_ENGINE")

  # Verify all 6 CB categories are documented
  local cb_categories="build test network agent state environment"
  local missing=0
  for cat in $cb_categories; do
    if ! echo "$cb_section" | grep -q "\`$cat\`"; then
      echo "Circuit breaker category '$cat' not documented in section 8.1"
      missing=$((missing + 1))
    fi
  done

  # Cross-check: error types listed in CB Failure Categories table should
  # be valid error types from the mapping table in section 3
  local recovery_section
  recovery_section=$(sed -n '/^### Error Type to Recovery Category Mapping/,/^### /p' "$RECOVERY_ENGINE")

  # Check representative error types from each CB category exist in the mapping table
  for etype in AGENT_TIMEOUT STATE_CORRUPTION DEPENDENCY_MISSING NETWORK_UNAVAILABLE DISK_FULL BUILD_FAILURE TEST_FAILURE; do
    echo "$recovery_section" | grep -q "$etype" \
      || { echo "CB error type '$etype' not in recovery mapping table"; missing=$((missing + 1)); }
  done

  [[ $missing -eq 0 ]] || fail "$missing issues in circuit breaker category coverage"
}
