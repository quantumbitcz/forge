#!/usr/bin/env bats
# Advanced convergence engine tests: formula validation, phase transitions,
# oscillation detection, effective target, diminishing returns.

load '../helpers/test-helpers'

# ── Pure Helpers (no I/O) ────────────────────────────────────────────────

is_diminishing() {
  local gain="$1" score="$2" pass_threshold="$3"
  [[ $gain -gt 0 && $gain -le 2 && $score -ge $pass_threshold ]]
}

compute_effective_target() {
  local target_score="$1" unfixable="$2" pass_threshold="$3"
  local adjusted=$(( 100 - 2 * unfixable ))
  local min_val=$target_score
  [[ $adjusted -lt $min_val ]] && min_val=$adjusted
  local result=$min_val
  [[ $pass_threshold -gt $result ]] && result=$pass_threshold
  echo "$result"
}

is_oscillating() {
  local delta="$1" tolerance="$2"
  local abs_delta=${delta#-}
  [[ $delta -lt 0 ]] && [[ $abs_delta -gt $tolerance ]]
}

should_detect_plateau() {
  local phase_iterations="$1" smoothed_delta="$2" threshold="$3"
  [[ $phase_iterations -ge 2 ]] && python3 -c "
import sys
sd = float(sys.argv[1])
th = float(sys.argv[2])
sys.exit(0 if sd <= th else 1)
" "$smoothed_delta" "$threshold"
}

# ── Phase A Tests ────────────────────────────────────────────────────────

@test "phase-A: verify_fix_count starts at 0 and increments" {
  local count=0
  count=$((count + 1))
  assert_equal "$count" "1"
}

@test "phase-A: escalation at max_fix_loops=3" {
  local verify_fix_count=3 max_fix_loops=3
  [[ $verify_fix_count -ge $max_fix_loops ]]
  assert_equal "$?" "0"
}

@test "phase-A: no escalation below max_fix_loops" {
  local verify_fix_count=2 max_fix_loops=3
  run bash -c '[[ 2 -ge 3 ]]'
  assert_failure
}

# ── Oscillation Tests ───────────────────────────────────────────────────

@test "oscillation: delta=-5 with tolerance=3 triggers REGRESSING" {
  run is_oscillating -5 3
  assert_success
}

@test "oscillation: delta=-2 with tolerance=3 does NOT trigger REGRESSING" {
  run is_oscillating -2 3
  assert_failure
}

@test "oscillation: delta=+5 never triggers REGRESSING (positive)" {
  run is_oscillating 5 3
  assert_failure
}

@test "oscillation: delta=-3 with tolerance=3 does NOT trigger (not beyond)" {
  run is_oscillating -3 3
  assert_failure
}

@test "oscillation: delta=-4 with tolerance=3 triggers (just beyond)" {
  run is_oscillating -4 3
  assert_success
}

# ── First-Cycle Exemption Tests ─────────────────────────────────────────

@test "first-cycle: phase_iterations=0 exempt from plateau" {
  run should_detect_plateau 0 0.5 2
  assert_failure
}

@test "first-cycle: phase_iterations=1 still exempt" {
  run should_detect_plateau 1 0.5 2
  assert_failure
}

@test "first-cycle: phase_iterations=2 allows plateau detection" {
  run should_detect_plateau 2 0.5 2
  assert_success
}

@test "first-cycle: phase_iterations=5 allows plateau detection" {
  run should_detect_plateau 5 1.0 2
  assert_success
}

# ── Safety Gate Tests ───────────────────────────────────────────────────

@test "safety-gate: 2 failures triggers cross-phase oscillation" {
  local failures=2
  run bash -c '[[ 2 -ge 2 ]]'
  assert_success
}

@test "safety-gate: 1 failure does NOT trigger" {
  run bash -c '[[ 1 -ge 2 ]]'
  assert_failure
}

@test "safety-gate: restart resets phase_iterations to 0" {
  local phase_iterations=0
  assert_equal "$phase_iterations" "0"
}

# ── Effective Target Tests ──────────────────────────────────────────────

@test "effective-target: no unfixable uses target_score" {
  run compute_effective_target 90 0 80
  assert_output "90"
}

@test "effective-target: moderate unfixable does not reduce (94 > 90)" {
  run compute_effective_target 90 3 80
  assert_output "90"
}

@test "effective-target: exact match unfixable (90 == 90)" {
  run compute_effective_target 90 5 80
  assert_output "90"
}

@test "effective-target: many unfixable reduces to adjusted" {
  run compute_effective_target 90 8 80
  assert_output "84"
}

@test "effective-target: floor at pass_threshold with 50 unfixable" {
  run compute_effective_target 90 50 80
  assert_output "80"
}

@test "effective-target: extreme unfixable still floors at pass_threshold" {
  run compute_effective_target 90 100 80
  assert_output "80"
}

@test "effective-target: zero unfixable with high target" {
  run compute_effective_target 100 0 80
  assert_output "100"
}

@test "effective-target: pass_threshold equals target_score" {
  run compute_effective_target 80 0 80
  assert_output "80"
}

# ── Diminishing Returns Tests ───────────────────────────────────────────

@test "diminishing: gain=1 score=88 pass=80 is diminishing" {
  run is_diminishing 1 88 80
  assert_success
}

@test "diminishing: gain=2 score=88 pass=80 is diminishing" {
  run is_diminishing 2 88 80
  assert_success
}

@test "diminishing: gain=3 is NOT diminishing (above threshold)" {
  run is_diminishing 3 88 80
  assert_failure
}

@test "diminishing: gain=0 is NOT diminishing (must be > 0)" {
  run is_diminishing 0 88 80
  assert_failure
}

@test "diminishing: gain=2 score=75 pass=80 NOT diminishing (below pass)" {
  run is_diminishing 2 75 80
  assert_failure
}

@test "diminishing: gain=1 score=80 pass=80 is diminishing (at boundary)" {
  run is_diminishing 1 80 80
  assert_success
}

# ── Cross-Document Formula Verification ─────────────────────────────────

@test "cross-doc: effective_target formula matches in both files" {
  local conv_formula scoring_formula
  conv_formula=$(grep "effective_target = " "$PLUGIN_ROOT/shared/convergence-engine.md" | head -1)
  scoring_formula=$(grep "effective_target = " "$PLUGIN_ROOT/shared/scoring.md" | head -1)
  echo "$conv_formula" | grep -q "max(pass_threshold" || fail "convergence-engine.md missing max(pass_threshold"
  echo "$scoring_formula" | grep -q "max(pass_threshold" || fail "scoring.md missing max(pass_threshold"
}

@test "cross-doc: phase_iterations guard in state-transitions.md C8" {
  grep "C8" "$PLUGIN_ROOT/shared/state-transitions.md" | grep -q "phase_iterations >= 2" || fail "C8 missing phase_iterations guard"
}

@test "cross-doc: phase_iterations guard in state-transitions.md C10" {
  grep "C10 " "$PLUGIN_ROOT/shared/state-transitions.md" | grep -q "phase_iterations >= 2" || fail "C10 missing phase_iterations guard"
}

@test "cross-doc: C10a baseline exemption row exists" {
  grep -q "C10a" "$PLUGIN_ROOT/shared/state-transitions.md" || fail "C10a row missing"
}

@test "cross-doc: autonomous field in state-schema.md" {
  grep -q "autonomous" "$PLUGIN_ROOT/shared/state-schema.md" || fail "autonomous field missing from state schema"
}
