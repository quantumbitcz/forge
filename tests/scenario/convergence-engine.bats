#!/usr/bin/env bats
# Scenario tests: convergence engine behavior in the orchestrator

load '../helpers/test-helpers'

ORCHESTRATOR="$PLUGIN_ROOT/agents/fg-100-orchestrator.md"
ENGINE="$PLUGIN_ROOT/shared/convergence-engine.md"
QUALITY_GATE="$PLUGIN_ROOT/agents/fg-400-quality-gate.md"
TEST_GATE="$PLUGIN_ROOT/agents/fg-500-test-gate.md"
STAGE_CONTRACT="$PLUGIN_ROOT/shared/stage-contract.md"

# ---------------------------------------------------------------------------
# 1. Orchestrator references convergence engine
# ---------------------------------------------------------------------------
@test "convergence-scenario: orchestrator references convergence-engine.md" {
  grep -q "convergence-engine.md" "$ORCHESTRATOR" \
    || fail "Orchestrator does not reference convergence-engine.md"
}

# ---------------------------------------------------------------------------
# 2. Orchestrator initializes convergence state
# ---------------------------------------------------------------------------
@test "convergence-scenario: orchestrator initializes convergence object in state" {
  grep -q '"convergence"' "$ORCHESTRATOR" \
    || fail "Orchestrator does not initialize convergence object"
  grep -q '"phase".*"correctness"' "$ORCHESTRATOR" \
    || fail "Orchestrator does not set initial phase to correctness"
}

# ---------------------------------------------------------------------------
# 3. Quality gate delegates iteration to convergence engine
# ---------------------------------------------------------------------------
@test "convergence-scenario: quality gate delegates fix cycles to convergence engine" {
  grep -q "convergence engine" "$QUALITY_GATE" \
    || fail "Quality gate does not reference convergence engine"
  # Quality gate should NOT manage cycles itself anymore
  ! grep -q "The fix-and-rescore cycle continues until" "$QUALITY_GATE" \
    || fail "Quality gate still contains old fix-cycle management language"
}

# ---------------------------------------------------------------------------
# 4. Test gate documents convergence context
# ---------------------------------------------------------------------------
@test "convergence-scenario: test gate documents Phase 1 convergence role" {
  grep -qi "phase 1\|convergence" "$TEST_GATE" \
    || fail "Test gate does not document its Phase 1 convergence role"
}

# ---------------------------------------------------------------------------
# 5. Stage contract references convergence for both VERIFY and REVIEW
# ---------------------------------------------------------------------------
@test "convergence-scenario: stage contract references convergence in VERIFY and REVIEW" {
  # Check Stage 5 section
  local stage5
  stage5=$(sed -n '/### Stage 5: VERIFY/,/### Stage 6/p' "$STAGE_CONTRACT")
  echo "$stage5" | grep -qi "convergence" \
    || fail "Stage 5 does not reference convergence"

  # Check Stage 6 section
  local stage6
  stage6=$(sed -n '/### Stage 6: REVIEW/,/### Stage 7/p' "$STAGE_CONTRACT")
  echo "$stage6" | grep -qi "convergence" \
    || fail "Stage 6 does not reference convergence"
}

# ---------------------------------------------------------------------------
# 6. Safety gate is documented as re-invoking VERIFY
# ---------------------------------------------------------------------------
@test "convergence-scenario: safety gate re-invokes VERIFY" {
  grep -qi "safety.*gate.*verify\|safety_gate.*verify" "$ENGINE" \
    || fail "Safety gate re-invoking VERIFY not documented"
  grep -qi "safety.*gate.*fail.*correctness\|back to.*correctness\|routes to Phase 1" "$ENGINE" \
    || fail "Safety gate failure routing to correctness not documented"
}

# ---------------------------------------------------------------------------
# 7. All 21 pipeline config templates have convergence section
# ---------------------------------------------------------------------------
@test "convergence-scenario: all 21 pipeline config templates have convergence section" {
  local count=0
  local missing=()
  for f in "$PLUGIN_ROOT"/modules/frameworks/*/forge-config-template.md; do
    if grep -q "convergence:" "$f"; then
      count=$((count + 1))
    else
      missing+=("$(basename "$(dirname "$f")")")
    fi
  done
  [[ ${#missing[@]} -eq 0 ]] \
    || fail "Missing convergence section in: ${missing[*]}"
  [[ $count -ge 21 ]] \
    || fail "Expected >= 21 templates with convergence, got $count"
}

# ---------------------------------------------------------------------------
# 8. Convergence config has all 5 parameters in templates
# ---------------------------------------------------------------------------
@test "convergence-scenario: config templates document all convergence parameters" {
  local params=(max_iterations plateau_threshold plateau_patience target_score safety_gate)
  # Check just one template — Task 8 ensures all 21 are identical
  local template="$PLUGIN_ROOT/modules/frameworks/spring/forge-config-template.md"
  for param in "${params[@]}"; do
    grep -q "$param" "$template" \
      || fail "Parameter $param missing from spring forge-config-template.md"
  done
}
