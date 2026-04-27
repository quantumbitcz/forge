#!/usr/bin/env bats
# Scenario tests: state machine end-to-end transition flows.
# Tests multi-step paths through forge-state.sh to verify the complete pipeline.

# Covers: T-01, T-02, T-05, T-09, T-10, T-19, T-26, T-27, T-30, T-38, T-40, T-41, T-42, T-43, T-44, T-45, T-49, T-50, T-52, D-01, E-01

load '../helpers/test-helpers'

SCRIPT="$PLUGIN_ROOT/shared/forge-state.sh"

# ---------------------------------------------------------------------------
# 1. Happy path: PREFLIGHT → COMPLETE
# ---------------------------------------------------------------------------

@test "scenario: happy path transitions PREFLIGHT through COMPLETE" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"

  bash "$SCRIPT" init "feat-test" "Test" --mode standard --forge-dir "$forge_dir"
  bash "$SCRIPT" transition preflight_complete --guard "dry_run=false" --forge-dir "$forge_dir" > /dev/null
  bash "$SCRIPT" transition explore_complete --guard "scope=1" --guard "decomposition_threshold=3" --forge-dir "$forge_dir" > /dev/null
  bash "$SCRIPT" transition plan_complete --forge-dir "$forge_dir" > /dev/null
  bash "$SCRIPT" transition verdict_GO --guard "risk=LOW" --guard "auto_proceed_risk=MEDIUM" --forge-dir "$forge_dir" > /dev/null
  bash "$SCRIPT" transition implement_complete --guard "at_least_one_task_passed=true" --forge-dir "$forge_dir" > /dev/null
  bash "$SCRIPT" transition verify_pass --guard "convergence.phase=correctness" --forge-dir "$forge_dir" > /dev/null
  bash "$SCRIPT" transition score_target_reached --forge-dir "$forge_dir" > /dev/null
  bash "$SCRIPT" transition verify_pass --guard "convergence.phase=safety_gate" --forge-dir "$forge_dir" > /dev/null
  bash "$SCRIPT" transition docs_complete --forge-dir "$forge_dir" > /dev/null
  bash "$SCRIPT" transition evidence_SHIP --guard "evidence_fresh=true" --forge-dir "$forge_dir" > /dev/null
  bash "$SCRIPT" transition pr_created --forge-dir "$forge_dir" > /dev/null
  bash "$SCRIPT" transition user_approve_pr --forge-dir "$forge_dir" > /dev/null

  run bash "$SCRIPT" transition retrospective_complete --forge-dir "$forge_dir"
  assert_success
  echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['new_state']=='COMPLETE'"

  # Verify all counters are 0 (no retries in happy path)
  run bash "$SCRIPT" query --forge-dir "$forge_dir"
  echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d['total_retries'] == 0
assert d['quality_cycles'] == 0
assert d['test_cycles'] == 0
assert d['verify_fix_count'] == 0
"
}

# ---------------------------------------------------------------------------
# 2. Convergence: correctness → perfection → safety_gate → DOCUMENTING
# ---------------------------------------------------------------------------

@test "scenario: convergence phases transition correctly" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  bash "$SCRIPT" init "feat-test" "Test" --mode standard --forge-dir "$forge_dir"

  # Fast-forward state directly (bypasses forge-state-write.sh WAL/_seq validation;
  # this is acceptable for test setup since forge-state.sh reads _seq from the file as-is)
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

  # correctness → perfection
  bash "$SCRIPT" transition verify_pass --guard "convergence.phase=correctness" --forge-dir "$forge_dir" > /dev/null
  run bash "$SCRIPT" query --forge-dir "$forge_dir"
  echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['convergence']['phase']=='perfection'"

  # perfection → safety_gate (via score_target_reached)
  bash "$SCRIPT" transition score_target_reached --forge-dir "$forge_dir" > /dev/null
  run bash "$SCRIPT" query --forge-dir "$forge_dir"
  echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['convergence']['phase']=='safety_gate'"

  # safety_gate → DOCUMENTING (via verify_pass)
  bash "$SCRIPT" transition verify_pass --guard "convergence.phase=safety_gate" --forge-dir "$forge_dir" > /dev/null
  run bash "$SCRIPT" query --forge-dir "$forge_dir"
  echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d['story_state'] == 'DOCUMENTING'
assert d['convergence']['safety_gate_passed'] == True
"
}

# ---------------------------------------------------------------------------
# 3. Budget exhaustion stops the pipeline
# ---------------------------------------------------------------------------

@test "scenario: total_retries budget prevents infinite loops" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  bash "$SCRIPT" init "feat-test" "Test" --mode standard --forge-dir "$forge_dir"
  # Fast-forward state directly (bypasses forge-state-write.sh WAL/_seq validation;
  # this is acceptable for test setup since forge-state.sh reads _seq from the file as-is)
  python3 -c "
import json
with open('$forge_dir/state.json') as f:
    d = json.load(f)
d['story_state'] = 'VERIFYING'
d['total_retries'] = 10
d['total_retries_max'] = 10
d['convergence']['phase'] = 'correctness'
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
# 4. Dry-run stops at VALIDATING
# ---------------------------------------------------------------------------

@test "scenario: dry-run stops at VALIDATING" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  bash "$SCRIPT" init "feat-test" "Test" --mode standard --dry-run --forge-dir "$forge_dir"
  bash "$SCRIPT" transition preflight_complete --guard "dry_run=true" --forge-dir "$forge_dir" > /dev/null
  bash "$SCRIPT" transition explore_complete --guard "scope=1" --guard "decomposition_threshold=3" --forge-dir "$forge_dir" > /dev/null
  bash "$SCRIPT" transition plan_complete --forge-dir "$forge_dir" > /dev/null

  run bash "$SCRIPT" transition validate_complete --guard "dry_run=true" --forge-dir "$forge_dir"
  assert_success
  echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['new_state']=='COMPLETE'"
}

# ---------------------------------------------------------------------------
# 5. Diminishing returns stops early
# ---------------------------------------------------------------------------

@test "scenario: diminishing returns stops after 2 low-gain iterations" {
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
  echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['convergence']['phase']=='safety_gate'"
}

# ---------------------------------------------------------------------------
# 6. Row 50: score_diminishing triggers safety_gate
# ---------------------------------------------------------------------------

@test "scenario: score_diminishing routes to safety_gate (Row 50)" {
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
  echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['convergence']['phase']=='safety_gate'"
}

# ---------------------------------------------------------------------------
# 7. Row 42: evidence_BLOCK routes to IMPLEMENTING (correctness phase)
# ---------------------------------------------------------------------------

@test "scenario: evidence_BLOCK routes to IMPLEMENTING via Phase 1 (Row 42)" {
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

  run bash "$SCRIPT" transition evidence_BLOCK \
    --guard "block_reason=tests" \
    --forge-dir "$forge_dir"
  assert_success
  echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['new_state']=='IMPLEMENTING'"

  run bash "$SCRIPT" query --forge-dir "$forge_dir"
  echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['convergence']['phase']=='correctness'"
}

# ---------------------------------------------------------------------------
# 8. Row 43: evidence_BLOCK routes to IMPLEMENTING (perfection phase)
# ---------------------------------------------------------------------------

@test "scenario: evidence_BLOCK routes to IMPLEMENTING via Phase 2 (Row 43)" {
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

  run bash "$SCRIPT" transition evidence_BLOCK \
    --guard "block_reason=review" \
    --forge-dir "$forge_dir"
  assert_success
  echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['new_state']=='IMPLEMENTING'"

  run bash "$SCRIPT" query --forge-dir "$forge_dir"
  echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['convergence']['phase']=='perfection'"
}

# ---------------------------------------------------------------------------
# 9. Row 41: stale evidence re-verifies (stays in SHIPPING)
# ---------------------------------------------------------------------------

@test "scenario: stale evidence re-verifies (Row 41)" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  bash "$SCRIPT" init "feat-test" "Test" --mode standard --forge-dir "$forge_dir"

  python3 -c "
import json
with open('$forge_dir/state.json') as f:
    d = json.load(f)
d['story_state'] = 'SHIPPING'
d['evidence_refresh_count'] = 0
d['_seq'] = d.get('_seq', 0)
with open('$forge_dir/state.json', 'w') as f:
    json.dump(d, f, indent=2)
"

  run bash "$SCRIPT" transition evidence_SHIP \
    --guard "evidence_fresh=false" \
    --forge-dir "$forge_dir"
  assert_success
  echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['new_state']=='SHIPPING', f'Expected SHIPPING but got {d[\"new_state\"]}'"
  echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['row_id']=='41', f'Expected row 41 but got {d[\"row_id\"]}'"
}

# ---------------------------------------------------------------------------
# 10. Row 52: evidence refresh loop cap escalates
# ---------------------------------------------------------------------------

@test "scenario: evidence refresh loop cap escalates (Row 52)" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  bash "$SCRIPT" init "feat-test" "Test" --mode standard --forge-dir "$forge_dir"

  python3 -c "
import json
with open('$forge_dir/state.json') as f:
    d = json.load(f)
d['story_state'] = 'SHIPPING'
d['evidence_refresh_count'] = 3
d['_seq'] = d.get('_seq', 0)
with open('$forge_dir/state.json', 'w') as f:
    json.dump(d, f, indent=2)
"

  run bash "$SCRIPT" transition evidence_SHIP \
    --guard "evidence_fresh=false" \
    --forge-dir "$forge_dir"
  assert_success
  echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['new_state']=='ESCALATED', f'Expected ESCALATED but got {d[\"new_state\"]}'"
  echo "$output" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['row_id']=='52', f'Expected row 52 but got {d[\"row_id\"]}'"
}
