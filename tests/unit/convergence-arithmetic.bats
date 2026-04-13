#!/usr/bin/env bats
# Unit tests: convergence engine arithmetic — validates diminishing returns
# detection and effective_target calculation from convergence-engine.md.

load '../helpers/test-helpers'

ENGINE="$PLUGIN_ROOT/shared/convergence-engine.md"

is_diminishing() {
  local gain="${1:?}" score="${2:?}" pass_threshold="${3:?}"
  [[ $gain -gt 0 && $gain -le 2 && $score -ge $pass_threshold ]]
}

compute_effective_target() {
  local target_score="${1:?}" unfixable_info_count="${2:?}" pass_threshold="${3:?}"
  local adjusted=$(( 100 - 2 * unfixable_info_count ))
  local min_val
  if [[ $target_score -le $adjusted ]]; then min_val=$target_score; else min_val=$adjusted; fi
  if [[ $pass_threshold -ge $min_val ]]; then echo "$pass_threshold"; else echo "$min_val"; fi
}

@test "convergence-arith: gain <= 2 with score >= pass_threshold increments diminishing_count" {
  run is_diminishing 1 89 80
  assert_success
}

@test "convergence-arith: gain > 2 resets diminishing_count to 0" {
  run is_diminishing 5 90 80
  assert_failure
}

@test "convergence-arith: diminishing_count >= 2 triggers PLATEAUED" {
  local diminishing_count=0
  if is_diminishing 1 88 80; then diminishing_count=$(( diminishing_count + 1 )); fi
  [[ $diminishing_count -eq 1 ]] || fail "Expected count 1, got $diminishing_count"
  if is_diminishing 2 90 80; then diminishing_count=$(( diminishing_count + 1 )); fi
  [[ $diminishing_count -eq 2 ]] || fail "Expected count 2, got $diminishing_count"
  [[ $diminishing_count -ge 2 ]] || fail "Should trigger PLATEAUED"
}

@test "convergence-arith: gain <= 2 with score < pass_threshold does NOT trigger diminishing" {
  run is_diminishing 2 57 80
  assert_failure
}

@test "convergence-arith: effective_target with 0 unfixable INFOs = target_score" {
  local result
  result=$(compute_effective_target 90 0 80)
  assert_equal "$result" "90"
}

@test "convergence-arith: effective_target with 3 unfixable INFOs stays at 90" {
  local result
  result=$(compute_effective_target 90 3 80)
  assert_equal "$result" "90"
}

@test "convergence-arith: effective_target with 6 unfixable INFOs = 88" {
  local result
  result=$(compute_effective_target 90 6 80)
  assert_equal "$result" "88"
}

@test "convergence-arith: effective_target never below pass_threshold" {
  local result
  result=$(compute_effective_target 90 25 80)
  assert_equal "$result" "80"
}

@test "convergence-arith: effective_target floor at pass_threshold" {
  local result
  result=$(compute_effective_target 90 30 80)
  assert_equal "$result" "80"
}

@test "convergence-arith: unfixable INFO identified after 2 cycles of persistence" {
  local finding="src/User.kt:42 | QUAL-COMPLEX | INFO | method too complex | extract"
  local cycle_1_findings="$finding"
  local cycle_2_findings="$finding"
  run python3 -c "
import sys
f1 = set(sys.argv[1].strip().split('\n'))
f2 = set(sys.argv[2].strip().split('\n'))
persistent = f1 & f2
unfixable = [f for f in persistent if '| INFO |' in f]
print(len(unfixable))
" "$cycle_1_findings" "$cycle_2_findings"
  assert_success
  assert_equal "$output" "1"
}

@test "convergence-arith: first-cycle exempt from plateau via phase_iterations > 0" {
  # Note: P2 changed the guard to phase_iterations >= 2 (smoothed delta needs 2 cycles).
  # This test still validates that phase_iterations=0 is exempt (which remains true).
  local phase_iterations=0 delta=0 plateau_threshold=2
  if [[ $delta -le $plateau_threshold && $phase_iterations -gt 0 ]]; then
    fail "First cycle (phase_iterations=0) should be exempt from plateau detection"
  fi
}

@test "convergence-arith: effective_target floor documented in convergence-engine.md" {
  grep -q "max(pass_threshold" "$ENGINE" \
    || fail "effective_target floor (max(pass_threshold, ...)) not documented"
}

@test "convergence-arith: diminishing returns detection documented" {
  grep -qi "diminishing.*return\|diminishing_count" "$ENGINE" \
    || fail "Diminishing returns not documented in convergence-engine.md"
}

# ---------------------------------------------------------------------------
# P2: Smoothed delta (moving average) tests
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Helper: compute smoothed_delta from a space-separated score history
# Implements the 4-case smoothed_delta function from convergence-engine.md
# ---------------------------------------------------------------------------
compute_smoothed_delta() {
  local -a scores=($@)
  local len=${#scores[@]}

  if [[ $len -lt 2 ]]; then
    echo "0"
    return
  fi

  if [[ $len -eq 2 ]]; then
    # Raw delta
    echo "${scores[1]} - ${scores[0]}" | bc
    return
  fi

  if [[ $len -eq 3 ]]; then
    # 2-point weighted: d1*0.6 + d2*0.4
    local d1 d2
    d1=$(echo "${scores[2]} - ${scores[1]}" | bc)
    d2=$(echo "${scores[1]} - ${scores[0]}" | bc)
    echo "$d1 * 0.6 + $d2 * 0.4" | bc
    return
  fi

  # 4+ scores: 3-point weighted using last 4 scores
  local d1 d2 d3
  d1=$(echo "${scores[$((len-1))]} - ${scores[$((len-2))]}" | bc)
  d2=$(echo "${scores[$((len-2))]} - ${scores[$((len-3))]}" | bc)
  d3=$(echo "${scores[$((len-3))]} - ${scores[$((len-4))]}" | bc)
  echo "$d1 * 0.5 + $d2 * 0.3 + $d3 * 0.2" | bc
}

@test "convergence-arith: smoothed_delta with 2 scores uses raw delta" {
  local result
  result=$(compute_smoothed_delta 80 85)
  [[ "$result" == "5" ]] || fail "Expected 5, got $result"
}

@test "convergence-arith: smoothed_delta with 3 scores uses 2-point avg" {
  # history=[80, 85, 87] -> deltas=[2, 5], smoothed = 2*0.6 + 5*0.4 = 1.2 + 2.0 = 3.2
  local result
  result=$(compute_smoothed_delta 80 85 87)
  [[ "$result" == "3.2" ]] || fail "Expected 3.2, got $result"
}

@test "convergence-arith: smoothed_delta with 4+ scores uses last 3 deltas" {
  # history=[80, 85, 87, 88] -> deltas=[1, 2, 5], smoothed = 1*0.5 + 2*0.3 + 5*0.2 = 0.5 + 0.6 + 1.0 = 2.1
  local result
  result=$(compute_smoothed_delta 80 85 87 88)
  [[ "$result" == "2.1" ]] || fail "Expected 2.1, got $result"
}

@test "convergence-arith: noise cancellation — alternating +1/-1 smoothed to ~0" {
  # history=[85, 86, 85, 86] -> deltas=[1, -1, 1], smoothed = 1*0.5 + (-1)*0.3 + 1*0.2 = 0.5 - 0.3 + 0.2 = 0.4
  local result
  result=$(compute_smoothed_delta 85 86 85 86)
  [[ "$result" == ".4" || "$result" == "0.4" ]] || fail "Expected 0.4, got $result"
}

@test "convergence-arith: steady improvement smoothed correctly" {
  # history=[80, 84, 88, 92] -> deltas=[4, 4, 4], smoothed = 4*0.5 + 4*0.3 + 4*0.2 = 2.0 + 1.2 + 0.8 = 4.0
  local result
  result=$(compute_smoothed_delta 80 84 88 92)
  [[ "$result" == "4.0" ]] || fail "Expected 4.0, got $result"
}

@test "convergence-arith: plateau guard requires phase_iterations >= 2" {
  # phase_iterations=1, smoothed_delta=0 -> NOT counted as plateau
  # The convergence engine uses: IF smoothed_delta <= plateau_threshold AND phase_iterations >= 2
  local phase_iterations=1
  local smoothed_delta=0
  local plateau_threshold=2

  if [[ $phase_iterations -ge 2 ]] && [[ $(echo "$smoothed_delta <= $plateau_threshold" | bc) -eq 1 ]]; then
    fail "phase_iterations=1 should NOT trigger plateau counting"
  fi

  # phase_iterations=2 should trigger
  phase_iterations=2
  if [[ $phase_iterations -ge 2 ]] && [[ $(echo "$smoothed_delta <= $plateau_threshold" | bc) -eq 1 ]]; then
    # This is correct — plateau detected
    true
  else
    fail "phase_iterations=2 with smoothed_delta=0 should trigger plateau counting"
  fi
}

# --- Simulator-based tests (S14) ---

@test "convergence-sim: exists and is executable" {
  assert [ -x "$BATS_TEST_DIRNAME/../../shared/convergence-engine-sim.sh" ]
}

@test "convergence-sim: happy path PASS on first cycle" {
  run "$BATS_TEST_DIRNAME/../../shared/convergence-engine-sim.sh" --scores "95" --pass-threshold 80
  assert_success
  assert_output --partial "decision=PASS"
}

@test "convergence-sim: fix loop converges to PASS" {
  run "$BATS_TEST_DIRNAME/../../shared/convergence-engine-sim.sh" --scores "43,84" --pass-threshold 80
  assert_success
  assert_line --index 1 --partial "decision=PASS"
}

@test "convergence-sim: plateau detection below threshold escalates" {
  run "$BATS_TEST_DIRNAME/../../shared/convergence-engine-sim.sh" --scores "72,78,75,76" --pass-threshold 80 --plateau-patience 2
  assert_success
  assert_line --index 3 --partial "phase=PLATEAUED"
  assert_line --index 3 --partial "decision=ESCALATE"
}

@test "convergence-sim: budget exhaustion at max-iterations" {
  run "$BATS_TEST_DIRNAME/../../shared/convergence-engine-sim.sh" --scores "50,55,60,65,70" --max-iterations 5
  assert_success
  assert_line --index 4 --partial "phase=BUDGET_EXHAUSTED"
}

@test "convergence-sim: regressing beyond tolerance escalates" {
  run "$BATS_TEST_DIRNAME/../../shared/convergence-engine-sim.sh" --scores "80,70" --oscillation-tolerance 5
  assert_success
  assert_line --index 1 --partial "phase=REGRESSING"
}

@test "convergence-sim: --help shows usage" {
  run "$BATS_TEST_DIRNAME/../../shared/convergence-engine-sim.sh" --help
  assert_success
  assert_output --partial "Convergence Engine Simulator"
}
