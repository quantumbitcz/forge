#!/usr/bin/env bats
# Per-row state transition tests: one test per transition table row.
# Tests individual rows from state-transitions.md against forge-state.sh.

# Covers: T-01, T-02, T-05, T-06, T-07, T-08, T-09, T-10, T-14, T-15, T-16, T-17, T-18, T-19, T-21, T-22, T-23, T-26, T-27, T-28, T-29, T-30, T-31, T-32, T-33, T-34, T-35, T-36, T-37, T-38, T-39, T-42, T-43, T-46, T-47, T-49, T-50, T-51

load '../helpers/test-helpers'

SCRIPT="$PLUGIN_ROOT/shared/forge-state.sh"

# ── Helpers ──────────────────────────────────────────────────────────────

init_state() {
  local forge_dir="$TEST_TEMP/project/.forge"
  local mode="${1:-standard}"
  local extra_json="$2"
  mkdir -p "$forge_dir"
  bash "$SCRIPT" init "test-row" "Test" --mode "$mode" --forge-dir "$forge_dir" > /dev/null
  if [[ -n "$extra_json" && "$extra_json" != "{}" ]]; then
    python3 -c '
import json, sys
state_path = sys.argv[1]
extra_str = sys.argv[2]
with open(state_path) as f: state = json.load(f)
extra = json.loads(extra_str)
def deep_merge(base, override):
    for k, v in override.items():
        if k in base and isinstance(base[k], dict) and isinstance(v, dict):
            deep_merge(base[k], v)
        else:
            base[k] = v
deep_merge(state, extra)
with open(state_path, "w") as f: json.dump(state, f, indent=2)
' "$forge_dir/state.json" "$extra_json"
  fi
  echo "$forge_dir"
}

do_transition() {
  local forge_dir="$1"
  local event="$2"
  shift 2
  local guard_args=()
  for g in "$@"; do
    guard_args+=(--guard "$g")
  done
  bash "$SCRIPT" transition "$event" "${guard_args[@]}" --forge-dir "$forge_dir"
}

assert_state() {
  local output="$1"
  local expected_state="$2"
  echo "$output" | python3 -c '
import json, sys
d = json.load(sys.stdin)
actual = d.get("new_state", d.get("story_state", "UNKNOWN"))
expected = sys.argv[1]
assert actual == expected, f"Expected {expected}, got {actual}"
' "$expected_state"
}

assert_conv_phase() {
  local output="$1"
  local expected_phase="$2"
  echo "$output" | python3 -c '
import json, sys
d = json.load(sys.stdin)
actual = d.get("convergence", {}).get("phase", "UNKNOWN")
expected = sys.argv[1]
assert actual == expected, f"Expected phase {expected}, got {actual}"
' "$expected_phase"
}

# ── Normal Flow: PREFLIGHT ───────────────────────────────────────────────

@test "row-01: PREFLIGHT + preflight_complete + dry_run=false → EXPLORING" {
  local fd=$(init_state)
  run do_transition "$fd" preflight_complete "dry_run=false"
  assert_success
  assert_state "$output" "EXPLORING"
}

@test "row-02: PREFLIGHT + preflight_complete + dry_run=true → EXPLORING" {
  local fd=$(init_state standard '{"dry_run":true}')
  run do_transition "$fd" preflight_complete "dry_run=true"
  assert_success
  assert_state "$output" "EXPLORING"
}

# ── Normal Flow: EXPLORING ───────────────────────────────────────────────

@test "row-05: EXPLORING + explore_complete + scope<threshold → PLANNING" {
  local fd=$(init_state standard '{"story_state":"EXPLORING"}')
  run do_transition "$fd" explore_complete "scope=1" "decomposition_threshold=3"
  assert_success
  assert_state "$output" "PLANNING"
}

@test "row-06: EXPLORING + explore_complete + scope>=threshold → DECOMPOSED" {
  local fd=$(init_state standard '{"story_state":"EXPLORING"}')
  run do_transition "$fd" explore_complete "scope=5" "decomposition_threshold=3"
  assert_success
  assert_state "$output" "DECOMPOSED"
}

@test "row-07: EXPLORING + explore_timeout → PLANNING" {
  local fd=$(init_state standard '{"story_state":"EXPLORING"}')
  run do_transition "$fd" explore_timeout
  assert_success
  assert_state "$output" "PLANNING"
}

@test "row-08: EXPLORING + explore_failure → PLANNING" {
  local fd=$(init_state standard '{"story_state":"EXPLORING"}')
  run do_transition "$fd" explore_failure
  assert_success
  assert_state "$output" "PLANNING"
}

# ── Normal Flow: PLANNING ────────────────────────────────────────────────

@test "row-09: PLANNING + plan_complete → VALIDATING" {
  local fd=$(init_state standard '{"story_state":"PLANNING"}')
  run do_transition "$fd" plan_complete
  assert_success
  assert_state "$output" "VALIDATING"
}

# ── Normal Flow: VALIDATING ──────────────────────────────────────────────

@test "row-10: VALIDATING + verdict_GO + risk<=auto_proceed → IMPLEMENTING" {
  local fd=$(init_state standard '{"story_state":"VALIDATING"}')
  run do_transition "$fd" verdict_GO "risk=LOW" "auto_proceed_risk=MEDIUM"
  assert_success
  assert_state "$output" "IMPLEMENTING"
}

@test "row-14: VALIDATING + verdict_REVISE + retries<max → PLANNING" {
  local fd=$(init_state standard '{"story_state":"VALIDATING","validation_retries":0}')
  run do_transition "$fd" verdict_REVISE "validation_retries=0" "max_validation_retries=3"
  assert_success
  assert_state "$output" "PLANNING"
}

@test "row-15: VALIDATING + verdict_REVISE + retries>=max → ESCALATED" {
  local fd=$(init_state standard '{"story_state":"VALIDATING","validation_retries":3}')
  run do_transition "$fd" verdict_REVISE "validation_retries=3" "max_validation_retries=3"
  assert_success
  assert_state "$output" "ESCALATED"
}

@test "row-16: VALIDATING + verdict_NOGO → ESCALATED" {
  local fd=$(init_state standard '{"story_state":"VALIDATING"}')
  run do_transition "$fd" verdict_NOGO
  assert_success
  assert_state "$output" "ESCALATED"
}

@test "row-17: VALIDATING + contract_breaking + consumer_tasks → IMPLEMENTING" {
  local fd=$(init_state standard '{"story_state":"VALIDATING"}')
  run do_transition "$fd" contract_breaking "consumer_tasks_in_plan=true"
  assert_success
  assert_state "$output" "IMPLEMENTING"
}

@test "row-18: VALIDATING + contract_breaking + no_consumer_tasks → PLANNING" {
  local fd=$(init_state standard '{"story_state":"VALIDATING"}')
  run do_transition "$fd" contract_breaking "consumer_tasks_in_plan=false"
  assert_success
  assert_state "$output" "PLANNING"
}

# ── Dry-run ──────────────────────────────────────────────────────────────

@test "row-D1: VALIDATING + validate_complete + dry_run=true → COMPLETE" {
  local fd=$(init_state standard '{"story_state":"VALIDATING","dry_run":true}')
  run do_transition "$fd" validate_complete "dry_run=true"
  assert_success
  assert_state "$output" "COMPLETE"
}

# ── Normal Flow: IMPLEMENTING ────────────────────────────────────────────

@test "row-19: IMPLEMENTING + implement_complete + tasks_passed → VERIFYING" {
  local fd=$(init_state standard '{"story_state":"IMPLEMENTING"}')
  run do_transition "$fd" implement_complete "at_least_one_task_passed=true"
  assert_success
  assert_state "$output" "VERIFYING"
}

@test "row-21: IMPLEMENTING + implement_complete + all_failed → ESCALATED" {
  local fd=$(init_state standard '{"story_state":"IMPLEMENTING"}')
  run do_transition "$fd" implement_complete "all_tasks_failed=true"
  assert_success
  assert_state "$output" "ESCALATED"
}

# ── Normal Flow: VERIFYING ───────────────────────────────────────────────

@test "row-22: VERIFYING + phase_a_failure + under cap → IMPLEMENTING" {
  local fd=$(init_state standard '{"story_state":"VERIFYING","convergence":{"phase":"correctness","verify_fix_count":0}}')
  run do_transition "$fd" phase_a_failure "verify_fix_count=0" "max_fix_loops=3" "total_iterations=0" "max_iterations=8"
  assert_success
  assert_state "$output" "IMPLEMENTING"
}

@test "row-23: VERIFYING + phase_a_failure + cap reached → ESCALATED" {
  local fd=$(init_state standard '{"story_state":"VERIFYING","convergence":{"phase":"correctness","verify_fix_count":3}}')
  run do_transition "$fd" phase_a_failure "verify_fix_count=3" "max_fix_loops=3"
  assert_success
  assert_state "$output" "ESCALATED"
}

@test "row-26: VERIFYING + verify_pass + phase=correctness → REVIEWING" {
  local fd=$(init_state standard '{"story_state":"VERIFYING","convergence":{"phase":"correctness","phase_iterations":2}}')
  run do_transition "$fd" verify_pass "convergence.phase=correctness"
  assert_success
  assert_state "$output" "REVIEWING"
}

@test "row-27: VERIFYING + verify_pass + phase=safety_gate → DOCUMENTING" {
  local fd=$(init_state standard '{"story_state":"VERIFYING","convergence":{"phase":"safety_gate"}}')
  run do_transition "$fd" verify_pass "convergence.phase=safety_gate"
  assert_success
  assert_state "$output" "DOCUMENTING"
}

@test "row-28: VERIFYING + safety_gate_fail + failures<2 → IMPLEMENTING" {
  local fd=$(init_state standard '{"story_state":"VERIFYING","convergence":{"phase":"safety_gate","safety_gate_failures":0}}')
  run do_transition "$fd" safety_gate_fail "safety_gate_failures=0"
  assert_success
  assert_state "$output" "IMPLEMENTING"
}

@test "row-29: VERIFYING + safety_gate_fail + failures>=2 → ESCALATED" {
  local fd=$(init_state standard '{"story_state":"VERIFYING","convergence":{"phase":"safety_gate","safety_gate_failures":2}}')
  run do_transition "$fd" safety_gate_fail "safety_gate_failures=2"
  assert_success
  assert_state "$output" "ESCALATED"
}

# ── Normal Flow: REVIEWING ───────────────────────────────────────────────

@test "row-30: REVIEWING + score_target_reached → VERIFYING (safety_gate)" {
  local fd=$(init_state standard '{"story_state":"REVIEWING","convergence":{"phase":"perfection"}}')
  run do_transition "$fd" score_target_reached
  assert_success
  assert_state "$output" "VERIFYING"
}

@test "row-31: REVIEWING + score_improving + within cap → IMPLEMENTING" {
  local fd=$(init_state standard '{"story_state":"REVIEWING","convergence":{"phase":"perfection","total_iterations":2}}')
  run do_transition "$fd" score_improving "total_iterations=2" "max_iterations=8"
  assert_success
  assert_state "$output" "IMPLEMENTING"
}

@test "row-32: REVIEWING + score_improving + cap reached → ESCALATED" {
  local fd=$(init_state standard '{"story_state":"REVIEWING","convergence":{"phase":"perfection","total_iterations":8}}')
  run do_transition "$fd" score_improving "total_iterations=8" "max_iterations=8"
  assert_success
  assert_state "$output" "ESCALATED"
}

@test "row-33: REVIEWING + score_plateau + patience reached + score>=pass → VERIFYING" {
  local fd=$(init_state standard '{"story_state":"REVIEWING","convergence":{"phase":"perfection","plateau_count":3,"phase_iterations":3},"score_history":[85]}')
  run do_transition "$fd" score_plateau "plateau_count=3" "plateau_patience=3" "score=85" "pass_threshold=80" "phase_iterations=3"
  assert_success
  assert_state "$output" "VERIFYING"
}

@test "row-34: REVIEWING + score_plateau + patience reached + concerns range → ESCALATED" {
  local fd=$(init_state standard '{"story_state":"REVIEWING","convergence":{"phase":"perfection","plateau_count":3,"phase_iterations":3},"score_history":[70]}')
  run do_transition "$fd" score_plateau "plateau_count=3" "plateau_patience=3" "score=70" "pass_threshold=80" "concerns_threshold=60" "phase_iterations=3"
  assert_success
  assert_state "$output" "ESCALATED"
}

@test "row-35: REVIEWING + score_plateau + patience reached + score<concerns → ESCALATED" {
  local fd=$(init_state standard '{"story_state":"REVIEWING","convergence":{"phase":"perfection","plateau_count":3,"phase_iterations":3},"score_history":[50]}')
  run do_transition "$fd" score_plateau "plateau_count=3" "plateau_patience=3" "score=50" "pass_threshold=80" "concerns_threshold=60" "phase_iterations=3"
  assert_success
  assert_state "$output" "ESCALATED"
}

@test "row-36: REVIEWING + score_plateau + within patience + within iterations → IMPLEMENTING" {
  local fd=$(init_state standard '{"story_state":"REVIEWING","convergence":{"phase":"perfection","plateau_count":1,"phase_iterations":3,"total_iterations":3}}')
  run do_transition "$fd" score_plateau "plateau_count=1" "plateau_patience=3" "total_iterations=3" "max_iterations=8" "phase_iterations=3"
  assert_success
  assert_state "$output" "IMPLEMENTING"
}

@test "row-37: REVIEWING + score_regressing + beyond tolerance → ESCALATED" {
  local fd=$(init_state standard '{"story_state":"REVIEWING","convergence":{"phase":"perfection","phase_iterations":3}}')
  run do_transition "$fd" score_regressing "delta=-6" "oscillation_tolerance=3"
  assert_success
  assert_state "$output" "ESCALATED"
}

# ── Normal Flow: DOCUMENTING ─────────────────────────────────────────────

@test "row-38: DOCUMENTING + docs_complete → SHIPPING" {
  local fd=$(init_state standard '{"story_state":"DOCUMENTING"}')
  run do_transition "$fd" docs_complete
  assert_success
  assert_state "$output" "SHIPPING"
}

@test "row-39: DOCUMENTING + docs_failure → SHIPPING" {
  local fd=$(init_state standard '{"story_state":"DOCUMENTING"}')
  run do_transition "$fd" docs_failure
  assert_success
  assert_state "$output" "SHIPPING"
}

# ── Normal Flow: SHIPPING ────────────────────────────────────────────────

@test "row-42: SHIPPING + evidence_BLOCK + build/lint/tests → IMPLEMENTING (Phase 1)" {
  local fd=$(init_state standard '{"story_state":"SHIPPING"}')
  run do_transition "$fd" evidence_BLOCK "block_reason=build"
  assert_success
  assert_state "$output" "IMPLEMENTING"
}

@test "row-43: SHIPPING + evidence_BLOCK + review/score → IMPLEMENTING (Phase 2)" {
  local fd=$(init_state standard '{"story_state":"SHIPPING"}')
  run do_transition "$fd" evidence_BLOCK "block_reason=review"
  assert_success
  assert_state "$output" "IMPLEMENTING"
}

@test "row-46: SHIPPING + pr_rejected + implementation → IMPLEMENTING" {
  local fd=$(init_state standard '{"story_state":"SHIPPING"}')
  run do_transition "$fd" pr_rejected "feedback_classification=implementation"
  assert_success
  assert_state "$output" "IMPLEMENTING"
}

@test "row-47: SHIPPING + pr_rejected + design → PLANNING" {
  local fd=$(init_state standard '{"story_state":"SHIPPING"}')
  run do_transition "$fd" pr_rejected "feedback_classification=design"
  assert_success
  assert_state "$output" "PLANNING"
}

# ── Normal Flow: LEARNING ────────────────────────────────────────────────

@test "row-49: LEARNING + retrospective_complete → COMPLETE" {
  local fd=$(init_state standard '{"story_state":"LEARNING"}')
  run do_transition "$fd" retrospective_complete
  assert_success
  assert_state "$output" "COMPLETE"
}

# ── Diminishing Returns ──────────────────────────────────────────────────

@test "row-50: REVIEWING + score_diminishing + count>=2 + score>=pass → VERIFYING" {
  local fd=$(init_state standard '{"story_state":"REVIEWING","convergence":{"phase":"perfection","diminishing_count":2}}')
  run do_transition "$fd" score_diminishing "diminishing_count=2" "score=85" "pass_threshold=80"
  assert_success
  assert_state "$output" "VERIFYING"
}

@test "row-51: REVIEWING + score_plateau + within patience + iterations>=max → ESCALATED" {
  local fd=$(init_state standard '{"story_state":"REVIEWING","convergence":{"phase":"perfection","plateau_count":1,"phase_iterations":3,"total_iterations":8}}')
  run do_transition "$fd" score_plateau "plateau_count=1" "plateau_patience=3" "total_iterations=8" "max_iterations=8" "phase_iterations=3"
  assert_success
  assert_state "$output" "ESCALATED"
}

# ── Convergence: C10a (first-cycle exemption) ────────────────────────────

@test "row-C10a: score_plateau + phase_iterations<2 → IMPLEMENTING (baseline exempt)" {
  local fd=$(init_state standard '{"story_state":"REVIEWING","convergence":{"phase":"perfection","phase_iterations":1}}')
  run do_transition "$fd" score_plateau "phase_iterations=1"
  assert_success
  assert_state "$output" "IMPLEMENTING"
}

# ── Error Transitions ────────────────────────────────────────────────────

@test "row-E1: budget_exhausted → ESCALATED" {
  local fd=$(init_state standard '{"story_state":"IMPLEMENTING","total_retries":10}')
  run do_transition "$fd" budget_exhausted "total_retries=10" "total_retries_max=10"
  assert_success
  assert_state "$output" "ESCALATED"
}

@test "row-E4: unrecoverable_error → ESCALATED" {
  local fd=$(init_state standard '{"story_state":"IMPLEMENTING"}')
  run do_transition "$fd" unrecoverable_error
  assert_success
  assert_state "$output" "ESCALATED"
}

@test "row-E6: user_abort from ESCALATED → ABORTED" {
  local fd=$(init_state standard '{"story_state":"ESCALATED","previous_state":"IMPLEMENTING"}')
  run do_transition "$fd" user_abort
  assert_success
  assert_state "$output" "ABORTED"
}

# ── Counter Verification Tests ───────────────────────────────────────────

@test "row-22 counter: phase_a_failure increments verify_fix_count" {
  local fd=$(init_state standard '{"story_state":"VERIFYING","convergence":{"phase":"correctness","verify_fix_count":1},"verify_fix_count":1}')
  run do_transition "$fd" phase_a_failure "verify_fix_count=1" "max_fix_loops=3" "total_iterations=0" "max_iterations=8"
  assert_success
  # Verify counter in state file
  python3 -c '
import json, sys
with open(sys.argv[1]) as f: d = json.load(f)
vfc = d["verify_fix_count"]
assert vfc >= 2, "verify_fix_count should be >=2, got %d" % vfc
' "$fd/state.json"
}

@test "row-31 counter: score_improving increments total_retries" {
  local fd=$(init_state standard '{"story_state":"REVIEWING","convergence":{"phase":"perfection","total_iterations":2},"total_retries":1}')
  run do_transition "$fd" score_improving "total_iterations=2" "max_iterations=8"
  assert_success
  python3 -c '
import json, sys
with open(sys.argv[1]) as f: d = json.load(f)
tr = d["total_retries"]
assert tr >= 2, "total_retries should be >=2, got %d" % tr
' "$fd/state.json"
}

@test "row-28 counter: safety_gate_fail resets phase_iterations" {
  local fd=$(init_state standard '{"story_state":"VERIFYING","convergence":{"phase":"safety_gate","safety_gate_failures":0,"phase_iterations":5,"plateau_count":3}}')
  run do_transition "$fd" safety_gate_fail "safety_gate_failures=0"
  assert_success
  python3 -c '
import json, sys
with open(sys.argv[1]) as f: d = json.load(f)
conv = d.get("convergence", {})
assert conv.get("phase") == "correctness", "Expected correctness, got %s" % conv.get("phase")
assert conv.get("phase_iterations", -1) == 0, "phase_iterations should be 0, got %d" % conv.get("phase_iterations", -1)
assert conv.get("plateau_count", -1) == 0, "plateau_count should be 0, got %d" % conv.get("plateau_count", -1)
' "$fd/state.json"
}
