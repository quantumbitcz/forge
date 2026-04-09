#!/usr/bin/env bats
# Unit tests: forge-state.sh — executable state machine for pipeline transitions.

load '../helpers/test-helpers'

SCRIPT="$PLUGIN_ROOT/shared/forge-state.sh"

# ---------------------------------------------------------------------------
# 1. Script existence and structure
# ---------------------------------------------------------------------------

@test "forge-state: script exists and is executable" {
  assert [ -f "$SCRIPT" ]
  assert [ -x "$SCRIPT" ]
}

@test "forge-state: has bash shebang" {
  local first_line
  first_line=$(head -1 "$SCRIPT")
  assert_equal "$first_line" "#!/usr/bin/env bash"
}

# ---------------------------------------------------------------------------
# 2. Init command
# ---------------------------------------------------------------------------

@test "forge-state: init creates valid state.json with all required fields" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"

  run bash "$SCRIPT" init "feat-test" "Add test feature" --mode standard --forge-dir "$forge_dir"
  assert_success
  assert [ -f "$forge_dir/state.json" ]

  python3 -c "
import json, sys
with open('$forge_dir/state.json') as f:
    d = json.load(f)
assert d['version'] == '1.5.0', f'version: {d[\"version\"]}'
assert d['complete'] == False
assert d['story_id'] == 'feat-test'
assert d['story_state'] == 'PREFLIGHT'
assert d['mode'] == 'standard'
assert d['total_retries'] == 0
assert d['total_retries_max'] == 10
assert d['_seq'] >= 1
assert 'convergence' in d
assert d['convergence']['phase'] == 'correctness'
assert d['convergence']['convergence_state'] == 'IMPROVING'
assert d['convergence']['diminishing_count'] == 0
"
}

@test "forge-state: init with --dry-run sets dry_run flag" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"

  run bash "$SCRIPT" init "feat-test" "Test" --mode standard --dry-run --forge-dir "$forge_dir"
  assert_success

  local dry_run
  dry_run=$(python3 -c "import json; print(json.load(open('$forge_dir/state.json'))['dry_run'])")
  assert_equal "$dry_run" "True"
}

@test "forge-state: init with --mode bugfix sets mode" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"

  run bash "$SCRIPT" init "fix-bug" "Fix bug" --mode bugfix --forge-dir "$forge_dir"
  assert_success

  local mode
  mode=$(python3 -c "import json; print(json.load(open('$forge_dir/state.json'))['mode'])")
  assert_equal "$mode" "bugfix"
}

# ---------------------------------------------------------------------------
# 3. Query command
# ---------------------------------------------------------------------------

@test "forge-state: query returns current state as JSON" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  bash "$SCRIPT" init "feat-test" "Test" --mode standard --forge-dir "$forge_dir"

  run bash "$SCRIPT" query --forge-dir "$forge_dir"
  assert_success
  echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['story_state']=='PREFLIGHT'"
}

# ---------------------------------------------------------------------------
# 4. Normal flow transitions
# ---------------------------------------------------------------------------

@test "forge-state: PREFLIGHT + preflight_complete (dry_run=false) → EXPLORING" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  bash "$SCRIPT" init "feat-test" "Test" --mode standard --forge-dir "$forge_dir"

  run bash "$SCRIPT" transition preflight_complete --guard "dry_run=false" --forge-dir "$forge_dir"
  assert_success
  echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['new_state']=='EXPLORING'"
}

@test "forge-state: EXPLORING + explore_complete (scope < threshold) → PLANNING" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  bash "$SCRIPT" init "feat-test" "Test" --mode standard --forge-dir "$forge_dir"
  bash "$SCRIPT" transition preflight_complete --guard "dry_run=false" --forge-dir "$forge_dir" > /dev/null

  run bash "$SCRIPT" transition explore_complete --guard "scope=1" --guard "decomposition_threshold=3" --forge-dir "$forge_dir"
  assert_success
  echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['new_state']=='PLANNING'"
}

@test "forge-state: EXPLORING + explore_complete (scope >= threshold) → DECOMPOSED" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  bash "$SCRIPT" init "feat-test" "Test" --mode standard --forge-dir "$forge_dir"
  bash "$SCRIPT" transition preflight_complete --guard "dry_run=false" --forge-dir "$forge_dir" > /dev/null

  run bash "$SCRIPT" transition explore_complete --guard "scope=5" --guard "decomposition_threshold=3" --forge-dir "$forge_dir"
  assert_success
  echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['new_state']=='DECOMPOSED'"
}

@test "forge-state: PLANNING + plan_complete → VALIDATING" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  bash "$SCRIPT" init "feat-test" "Test" --mode standard --forge-dir "$forge_dir"
  bash "$SCRIPT" transition preflight_complete --guard "dry_run=false" --forge-dir "$forge_dir" > /dev/null
  bash "$SCRIPT" transition explore_complete --guard "scope=1" --guard "decomposition_threshold=3" --forge-dir "$forge_dir" > /dev/null

  run bash "$SCRIPT" transition plan_complete --forge-dir "$forge_dir"
  assert_success
  echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['new_state']=='VALIDATING'"
}

@test "forge-state: VALIDATING + verdict_GO (risk <= auto_proceed) → IMPLEMENTING" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  bash "$SCRIPT" init "feat-test" "Test" --mode standard --forge-dir "$forge_dir"
  bash "$SCRIPT" transition preflight_complete --guard "dry_run=false" --forge-dir "$forge_dir" > /dev/null
  bash "$SCRIPT" transition explore_complete --guard "scope=1" --guard "decomposition_threshold=3" --forge-dir "$forge_dir" > /dev/null
  bash "$SCRIPT" transition plan_complete --forge-dir "$forge_dir" > /dev/null

  run bash "$SCRIPT" transition verdict_GO --guard "risk=LOW" --guard "auto_proceed_risk=MEDIUM" --forge-dir "$forge_dir"
  assert_success
  echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['new_state']=='IMPLEMENTING'"
}

@test "forge-state: VALIDATING + verdict_REVISE (retries < max) → PLANNING" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  bash "$SCRIPT" init "feat-test" "Test" --mode standard --forge-dir "$forge_dir"
  bash "$SCRIPT" transition preflight_complete --guard "dry_run=false" --forge-dir "$forge_dir" > /dev/null
  bash "$SCRIPT" transition explore_complete --guard "scope=1" --guard "decomposition_threshold=3" --forge-dir "$forge_dir" > /dev/null
  bash "$SCRIPT" transition plan_complete --forge-dir "$forge_dir" > /dev/null

  run bash "$SCRIPT" transition verdict_REVISE --forge-dir "$forge_dir"
  assert_success
  echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d['new_state'] == 'PLANNING', d['new_state']
assert d['counters_changed']['validation_retries'] == 1
assert d['counters_changed']['total_retries'] == 1
"
}

@test "forge-state: IMPLEMENTING + implement_complete (at_least_one_passed) → VERIFYING" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  bash "$SCRIPT" init "feat-test" "Test" --mode standard --forge-dir "$forge_dir"
  bash "$SCRIPT" transition preflight_complete --guard "dry_run=false" --forge-dir "$forge_dir" > /dev/null
  bash "$SCRIPT" transition explore_complete --guard "scope=1" --guard "decomposition_threshold=3" --forge-dir "$forge_dir" > /dev/null
  bash "$SCRIPT" transition plan_complete --forge-dir "$forge_dir" > /dev/null
  bash "$SCRIPT" transition verdict_GO --guard "risk=LOW" --guard "auto_proceed_risk=MEDIUM" --forge-dir "$forge_dir" > /dev/null

  run bash "$SCRIPT" transition implement_complete --guard "at_least_one_task_passed=true" --forge-dir "$forge_dir"
  assert_success
  echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['new_state']=='VERIFYING'"
}

@test "forge-state: VERIFYING + verify_pass (phase=correctness) → REVIEWING" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  bash "$SCRIPT" init "feat-test" "Test" --mode standard --forge-dir "$forge_dir"
  bash "$SCRIPT" transition preflight_complete --guard "dry_run=false" --forge-dir "$forge_dir" > /dev/null
  bash "$SCRIPT" transition explore_complete --guard "scope=1" --guard "decomposition_threshold=3" --forge-dir "$forge_dir" > /dev/null
  bash "$SCRIPT" transition plan_complete --forge-dir "$forge_dir" > /dev/null
  bash "$SCRIPT" transition verdict_GO --guard "risk=LOW" --guard "auto_proceed_risk=MEDIUM" --forge-dir "$forge_dir" > /dev/null
  bash "$SCRIPT" transition implement_complete --guard "at_least_one_task_passed=true" --forge-dir "$forge_dir" > /dev/null

  run bash "$SCRIPT" transition verify_pass --guard "convergence.phase=correctness" --forge-dir "$forge_dir"
  assert_success
  echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d['new_state'] == 'REVIEWING', d['new_state']
"

  # Verify convergence phase transitioned
  run bash "$SCRIPT" query --forge-dir "$forge_dir"
  echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d['convergence']['phase'] == 'perfection', d['convergence']['phase']
assert d['convergence']['phase_iterations'] == 0
"
}

@test "forge-state: REVIEWING + score_target_reached → VERIFYING (safety_gate)" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  bash "$SCRIPT" init "feat-test" "Test" --mode standard --forge-dir "$forge_dir"
  # Fast-forward state directly (bypasses forge-state-write.sh WAL/_seq validation;
  # this is acceptable for test setup since forge-state.sh reads _seq from the file as-is)
  python3 -c "
import json
with open('$forge_dir/state.json') as f:
    d = json.load(f)
d['story_state'] = 'REVIEWING'
d['convergence']['phase'] = 'perfection'
d['_seq'] = d.get('_seq', 0)
with open('$forge_dir/state.json', 'w') as f:
    json.dump(d, f, indent=2)
"

  run bash "$SCRIPT" transition score_target_reached --forge-dir "$forge_dir"
  assert_success
  echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['new_state']=='VERIFYING'"

  run bash "$SCRIPT" query --forge-dir "$forge_dir"
  echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d['convergence']['phase'] == 'safety_gate', d['convergence']['phase']
"
}

@test "forge-state: VERIFYING + verify_pass (phase=safety_gate) → DOCUMENTING" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  bash "$SCRIPT" init "feat-test" "Test" --mode standard --forge-dir "$forge_dir"
  python3 -c "
import json
with open('$forge_dir/state.json') as f:
    d = json.load(f)
d['story_state'] = 'VERIFYING'
d['convergence']['phase'] = 'safety_gate'
d['_seq'] = d.get('_seq', 0)
with open('$forge_dir/state.json', 'w') as f:
    json.dump(d, f, indent=2)
"

  run bash "$SCRIPT" transition verify_pass --guard "convergence.phase=safety_gate" --forge-dir "$forge_dir"
  assert_success
  echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['new_state']=='DOCUMENTING'"
}

@test "forge-state: DOCUMENTING + docs_complete → SHIPPING" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  bash "$SCRIPT" init "feat-test" "Test" --mode standard --forge-dir "$forge_dir"
  python3 -c "
import json
with open('$forge_dir/state.json') as f:
    d = json.load(f)
d['story_state'] = 'DOCUMENTING'
d['_seq'] = d.get('_seq', 0)
with open('$forge_dir/state.json', 'w') as f:
    json.dump(d, f, indent=2)
"

  run bash "$SCRIPT" transition docs_complete --forge-dir "$forge_dir"
  assert_success
  echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['new_state']=='SHIPPING'"
}

@test "forge-state: SHIPPING + user_approve_pr → LEARNING" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  bash "$SCRIPT" init "feat-test" "Test" --mode standard --forge-dir "$forge_dir"
  python3 -c "
import json
with open('$forge_dir/state.json') as f:
    d = json.load(f)
d['story_state'] = 'SHIPPING'
d['_seq'] = d.get('_seq', 0)
with open('$forge_dir/state.json', 'w') as f:
    json.dump(d, f, indent=2)
"

  run bash "$SCRIPT" transition user_approve_pr --forge-dir "$forge_dir"
  assert_success
  echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['new_state']=='LEARNING'"
}

@test "forge-state: LEARNING + retrospective_complete → COMPLETE" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  bash "$SCRIPT" init "feat-test" "Test" --mode standard --forge-dir "$forge_dir"
  python3 -c "
import json
with open('$forge_dir/state.json') as f:
    d = json.load(f)
d['story_state'] = 'LEARNING'
d['_seq'] = d.get('_seq', 0)
with open('$forge_dir/state.json', 'w') as f:
    json.dump(d, f, indent=2)
"

  run bash "$SCRIPT" transition retrospective_complete --forge-dir "$forge_dir"
  assert_success
  echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d['new_state'] == 'COMPLETE', d['new_state']
"
}

# ---------------------------------------------------------------------------
# 5. Counter management
# ---------------------------------------------------------------------------

@test "forge-state: phase_a_failure increments verify_fix_count + total_iterations + total_retries" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  bash "$SCRIPT" init "feat-test" "Test" --mode standard --forge-dir "$forge_dir"
  python3 -c "
import json
with open('$forge_dir/state.json') as f:
    d = json.load(f)
d['story_state'] = 'VERIFYING'
d['convergence']['phase'] = 'correctness'
d['_seq'] = d.get('_seq', 0)
with open('$forge_dir/state.json', 'w') as f:
    json.dump(d, f, indent=2)
"

  run bash "$SCRIPT" transition phase_a_failure \
    --guard "verify_fix_count=0" --guard "max_fix_loops=3" \
    --guard "total_iterations=0" --guard "max_iterations=8" \
    --forge-dir "$forge_dir"
  assert_success

  echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
c = d['counters_changed']
assert c['verify_fix_count'] == 1, f'verify_fix_count: {c[\"verify_fix_count\"]}'
assert c['total_iterations'] == 1
assert c['total_retries'] == 1
"
}

@test "forge-state: score_improving resets plateau_count to 0" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  bash "$SCRIPT" init "feat-test" "Test" --mode standard --forge-dir "$forge_dir"
  python3 -c "
import json
with open('$forge_dir/state.json') as f:
    d = json.load(f)
d['story_state'] = 'REVIEWING'
d['convergence']['phase'] = 'perfection'
d['convergence']['plateau_count'] = 1
d['_seq'] = d.get('_seq', 0)
with open('$forge_dir/state.json', 'w') as f:
    json.dump(d, f, indent=2)
"

  run bash "$SCRIPT" transition score_improving \
    --guard "total_iterations=2" --guard "max_iterations=8" \
    --forge-dir "$forge_dir"
  assert_success

  run bash "$SCRIPT" query --forge-dir "$forge_dir"
  echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d['convergence']['plateau_count'] == 0
"
}

@test "forge-state: pr_rejected (implementation) resets quality_cycles + test_cycles" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  bash "$SCRIPT" init "feat-test" "Test" --mode standard --forge-dir "$forge_dir"
  python3 -c "
import json
with open('$forge_dir/state.json') as f:
    d = json.load(f)
d['story_state'] = 'SHIPPING'
d['quality_cycles'] = 3
d['test_cycles'] = 2
d['total_retries'] = 5
d['_seq'] = d.get('_seq', 0)
with open('$forge_dir/state.json', 'w') as f:
    json.dump(d, f, indent=2)
"

  run bash "$SCRIPT" transition pr_rejected --guard "feedback_classification=implementation" --forge-dir "$forge_dir"
  assert_success

  run bash "$SCRIPT" query --forge-dir "$forge_dir"
  echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d['quality_cycles'] == 0
assert d['test_cycles'] == 0
assert d['total_retries'] == 6
assert d['story_state'] == 'IMPLEMENTING'
"
}

# ---------------------------------------------------------------------------
# 6. Error transitions
# ---------------------------------------------------------------------------

@test "forge-state: ANY + budget_exhausted → ESCALATED" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  bash "$SCRIPT" init "feat-test" "Test" --mode standard --forge-dir "$forge_dir"
  python3 -c "
import json
with open('$forge_dir/state.json') as f:
    d = json.load(f)
d['story_state'] = 'REVIEWING'
d['total_retries'] = 10
d['total_retries_max'] = 10
d['_seq'] = d.get('_seq', 0)
with open('$forge_dir/state.json', 'w') as f:
    json.dump(d, f, indent=2)
"

  run bash "$SCRIPT" transition budget_exhausted \
    --guard "total_retries=10" --guard "total_retries_max=10" \
    --forge-dir "$forge_dir"
  assert_success
  echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['new_state']=='ESCALATED'"
}

# ---------------------------------------------------------------------------
# 7. Invalid transitions
# ---------------------------------------------------------------------------

@test "forge-state: rejects PREFLIGHT + verify_pass (invalid event for state)" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  bash "$SCRIPT" init "feat-test" "Test" --mode standard --forge-dir "$forge_dir"

  run bash "$SCRIPT" transition verify_pass --guard "convergence.phase=correctness" --forge-dir "$forge_dir"
  assert_failure
  echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); assert 'error' in d"
}

# ---------------------------------------------------------------------------
# 8. Reset command
# ---------------------------------------------------------------------------

@test "forge-state: reset implementation clears quality_cycles + test_cycles" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  bash "$SCRIPT" init "feat-test" "Test" --mode standard --forge-dir "$forge_dir"
  python3 -c "
import json
with open('$forge_dir/state.json') as f:
    d = json.load(f)
d['quality_cycles'] = 3
d['test_cycles'] = 2
d['_seq'] = d.get('_seq', 0)
with open('$forge_dir/state.json', 'w') as f:
    json.dump(d, f, indent=2)
"

  run bash "$SCRIPT" reset implementation --forge-dir "$forge_dir"
  assert_success

  run bash "$SCRIPT" query --forge-dir "$forge_dir"
  echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d['quality_cycles'] == 0
assert d['test_cycles'] == 0
"
}

# ---------------------------------------------------------------------------
# 9. Decision logging
# ---------------------------------------------------------------------------

@test "forge-state: transitions append to decisions.jsonl" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  bash "$SCRIPT" init "feat-test" "Test" --mode standard --forge-dir "$forge_dir"

  bash "$SCRIPT" transition preflight_complete --guard "dry_run=false" --forge-dir "$forge_dir" > /dev/null

  assert [ -f "$forge_dir/decisions.jsonl" ]
  local line_count
  line_count=$(wc -l < "$forge_dir/decisions.jsonl" | tr -d ' ')
  assert [ "$line_count" -ge 1 ]

  # Validate JSON format
  python3 -c "
import json
with open('$forge_dir/decisions.jsonl') as f:
    for line in f:
        line = line.strip()
        if line:
            d = json.loads(line)
            assert 'ts' in d, 'missing ts'
            assert 'decision' in d, 'missing decision'
            assert d['decision'] == 'state_transition', d['decision']
"
}

# ---------------------------------------------------------------------------
# 10. Diminishing returns (row 50)
# ---------------------------------------------------------------------------

@test "forge-state: score_diminishing (count >= 2) → VERIFYING (safety_gate)" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  bash "$SCRIPT" init "feat-test" "Test" --mode standard --forge-dir "$forge_dir"
  python3 -c "
import json
with open('$forge_dir/state.json') as f:
    d = json.load(f)
d['story_state'] = 'REVIEWING'
d['convergence']['phase'] = 'perfection'
d['convergence']['diminishing_count'] = 2
d['score_history'] = [85, 86, 87]
d['_seq'] = d.get('_seq', 0)
with open('$forge_dir/state.json', 'w') as f:
    json.dump(d, f, indent=2)
"

  run bash "$SCRIPT" transition score_diminishing \
    --guard "diminishing_count=2" --guard "score=87" --guard "pass_threshold=80" \
    --forge-dir "$forge_dir"
  assert_success
  echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['new_state']=='VERIFYING'"

  run bash "$SCRIPT" query --forge-dir "$forge_dir"
  echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d['convergence']['phase'] == 'safety_gate'
"
}

# ---------------------------------------------------------------------------
# 11. C1: user_continue returns to previous state
# ---------------------------------------------------------------------------

@test "forge-state: ESCALATED + user_continue returns to previous state" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  bash "$SCRIPT" init "feat-test" "Test" --mode standard --forge-dir "$forge_dir"
  # Fast-forward to REVIEWING then ESCALATED
  python3 -c "
import json
with open('$forge_dir/state.json') as f:
    d = json.load(f)
d['story_state'] = 'ESCALATED'
d['previous_state'] = 'REVIEWING'
d['_seq'] = d.get('_seq', 0)
with open('$forge_dir/state.json', 'w') as f:
    json.dump(d, f, indent=2)
"
  run bash "$SCRIPT" transition user_continue --forge-dir "$forge_dir"
  assert_success
  echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['new_state']=='REVIEWING', d['new_state']"
}

# ---------------------------------------------------------------------------
# 12. S1: pr_rejected (design) resets all inner-loop counters
# ---------------------------------------------------------------------------

@test "forge-state: pr_rejected (design) resets all inner-loop counters" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  bash "$SCRIPT" init "feat-test" "Test" --mode standard --forge-dir "$forge_dir"
  python3 -c "
import json
with open('$forge_dir/state.json') as f:
    d = json.load(f)
d['story_state'] = 'SHIPPING'
d['quality_cycles'] = 3
d['test_cycles'] = 2
d['verify_fix_count'] = 2
d['validation_retries'] = 1
d['total_retries'] = 8
d['_seq'] = d.get('_seq', 0)
with open('$forge_dir/state.json', 'w') as f:
    json.dump(d, f, indent=2)
"
  run bash "$SCRIPT" transition pr_rejected --guard "feedback_classification=design" --forge-dir "$forge_dir"
  assert_success
  run bash "$SCRIPT" query --forge-dir "$forge_dir"
  echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d['quality_cycles'] == 0
assert d['test_cycles'] == 0
assert d['verify_fix_count'] == 0
assert d['validation_retries'] == 0
assert d['total_retries'] == 9
assert d['story_state'] == 'PLANNING'
"
}

# ---------------------------------------------------------------------------
# 13. S1: score_regressing → ESCALATED
# ---------------------------------------------------------------------------

@test "forge-state: score_regressing → ESCALATED" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  bash "$SCRIPT" init "feat-test" "Test" --mode standard --forge-dir "$forge_dir"
  python3 -c "
import json
with open('$forge_dir/state.json') as f:
    d = json.load(f)
d['story_state'] = 'REVIEWING'
d['convergence']['phase'] = 'perfection'
d['_seq'] = d.get('_seq', 0)
with open('$forge_dir/state.json', 'w') as f:
    json.dump(d, f, indent=2)
"
  run bash "$SCRIPT" transition score_regressing \
    --guard "delta=-8" --guard "oscillation_tolerance=5" \
    --forge-dir "$forge_dir"
  assert_success
  echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['new_state']=='ESCALATED'"
}

# ---------------------------------------------------------------------------
# 14. S1: dry-run validate_complete → COMPLETE
# ---------------------------------------------------------------------------

@test "forge-state: dry-run validate_complete → COMPLETE" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  bash "$SCRIPT" init "feat-test" "Test" --mode standard --dry-run --forge-dir "$forge_dir"
  python3 -c "
import json
with open('$forge_dir/state.json') as f:
    d = json.load(f)
d['story_state'] = 'VALIDATING'
d['_seq'] = d.get('_seq', 0)
with open('$forge_dir/state.json', 'w') as f:
    json.dump(d, f, indent=2)
"
  run bash "$SCRIPT" transition validate_complete --guard "dry_run=true" --forge-dir "$forge_dir"
  assert_success
  echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['new_state']=='COMPLETE'"
}

# ---------------------------------------------------------------------------
# 15. S1: reset design clears all inner-loop counters
# ---------------------------------------------------------------------------

@test "forge-state: reset design clears all inner-loop counters" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  bash "$SCRIPT" init "feat-test" "Test" --mode standard --forge-dir "$forge_dir"
  python3 -c "
import json
with open('$forge_dir/state.json') as f:
    d = json.load(f)
d['quality_cycles'] = 3
d['test_cycles'] = 2
d['verify_fix_count'] = 2
d['validation_retries'] = 1
d['_seq'] = d.get('_seq', 0)
with open('$forge_dir/state.json', 'w') as f:
    json.dump(d, f, indent=2)
"
  run bash "$SCRIPT" reset design --forge-dir "$forge_dir"
  assert_success
  run bash "$SCRIPT" query --forge-dir "$forge_dir"
  echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d['quality_cycles'] == 0
assert d['test_cycles'] == 0
assert d['verify_fix_count'] == 0
assert d['validation_retries'] == 0
"
}
