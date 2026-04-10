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
