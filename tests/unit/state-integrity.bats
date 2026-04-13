#!/usr/bin/env bats
# Unit tests: state-integrity.sh — validates .forge/ state consistency checks.

load '../helpers/test-helpers'

SCRIPT="$PLUGIN_ROOT/shared/state-integrity.sh"

# ---------------------------------------------------------------------------
# 1. Script exists and is executable
# ---------------------------------------------------------------------------
@test "state-integrity: script exists and is executable" {
  assert [ -f "$SCRIPT" ]
  assert [ -x "$SCRIPT" ]
}

# ---------------------------------------------------------------------------
# 2. Has shebang
# ---------------------------------------------------------------------------
@test "state-integrity: has bash shebang" {
  local first_line
  first_line=$(head -1 "$SCRIPT")
  assert_equal "$first_line" "#!/usr/bin/env bash"
}

# ---------------------------------------------------------------------------
# 3. Reports issue when state.json is missing
# ---------------------------------------------------------------------------
@test "state-integrity: reports issue when state.json is missing" {
  local forge_dir="$TEST_TEMP/empty-forge"
  mkdir -p "$forge_dir"

  run bash "$SCRIPT" "$forge_dir"

  assert_failure
  assert_output --partial "state.json"
}

# ---------------------------------------------------------------------------
# 4. Reports invalid JSON
# ---------------------------------------------------------------------------
@test "state-integrity: reports invalid JSON" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  printf 'NOT VALID JSON { broken\n' > "$forge_dir/state.json"

  run bash "$SCRIPT" "$forge_dir"

  assert_failure
  assert_output --partial "invalid"
}

# ---------------------------------------------------------------------------
# 5. Passes on minimal valid state
# ---------------------------------------------------------------------------
@test "state-integrity: passes on minimal valid state" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  cat > "$forge_dir/state.json" << 'EOF'
{
  "version": "1.5.0",
  "complete": false,
  "story_id": "test-001",
  "story_state": "PREFLIGHT",
  "domain_area": "test",
  "total_retries": 0,
  "total_retries_max": 10
}
EOF

  run bash "$SCRIPT" "$forge_dir"

  assert_success
  assert_output --partial "OK"
}

# ---------------------------------------------------------------------------
# 6. Detects missing required fields
# ---------------------------------------------------------------------------
@test "state-integrity: detects missing required fields" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  cat > "$forge_dir/state.json" << 'EOF'
{
  "version": "1.5.0",
  "complete": false
}
EOF

  run bash "$SCRIPT" "$forge_dir"

  assert_failure
  assert_output --partial "missing"
}

# ---------------------------------------------------------------------------
# 7. Detects total_retries exceeding max
# ---------------------------------------------------------------------------
@test "state-integrity: detects total_retries exceeding max" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  cat > "$forge_dir/state.json" << 'EOF'
{
  "version": "1.5.0",
  "complete": false,
  "story_id": "test-001",
  "story_state": "IMPLEMENTING",
  "domain_area": "test",
  "total_retries": 15,
  "total_retries_max": 10
}
EOF

  run bash "$SCRIPT" "$forge_dir"

  assert_failure
  assert_output --partial "exceeds"
}

# ===========================================================================
# NEW TESTS: State integrity expansion (Q04)
# ===========================================================================

# ---------------------------------------------------------------------------
# 8. story_state in valid set (all pipeline states + ABORTED + COMPLETE)
# ---------------------------------------------------------------------------
@test "state-integrity: valid story_state IMPLEMENTING passes" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  cat > "$forge_dir/state.json" << 'EOF'
{
  "version": "1.5.0",
  "complete": false,
  "story_id": "test-001",
  "story_state": "IMPLEMENTING",
  "domain_area": "test",
  "total_retries": 0,
  "total_retries_max": 10
}
EOF

  run bash "$SCRIPT" "$forge_dir"
  assert_success
}

@test "state-integrity: invalid story_state FOOBAR rejected" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  cat > "$forge_dir/state.json" << 'EOF'
{
  "version": "1.5.0",
  "complete": false,
  "story_id": "test-001",
  "story_state": "FOOBAR",
  "domain_area": "test",
  "total_retries": 0,
  "total_retries_max": 10
}
EOF

  run bash "$SCRIPT" "$forge_dir"
  assert_failure
  assert_output --partial "invalid"
}

# ---------------------------------------------------------------------------
# 9. Migration states are valid
# ---------------------------------------------------------------------------
@test "state-integrity: migration states are valid story_state values" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  for state in MIGRATING MIGRATION_PAUSED MIGRATION_CLEANUP MIGRATION_VERIFY; do
    cat > "$forge_dir/state.json" << EOF
{
  "version": "1.5.0",
  "complete": false,
  "story_id": "test-001",
  "story_state": "$state",
  "domain_area": "test",
  "total_retries": 0,
  "total_retries_max": 10
}
EOF
    run bash "$SCRIPT" "$forge_dir"
    assert_success
  done
}

# ---------------------------------------------------------------------------
# 10. Empty state.json (0 bytes) detected
# ---------------------------------------------------------------------------
@test "state-integrity: empty state.json (0 bytes) detected" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  : > "$forge_dir/state.json"

  run bash "$SCRIPT" "$forge_dir"
  assert_failure
  assert_output --partial "invalid"
}

# ---------------------------------------------------------------------------
# 11. domain_area with invalid characters rejected
# ---------------------------------------------------------------------------
@test "state-integrity: domain_area with uppercase rejected" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  cat > "$forge_dir/state.json" << 'EOF'
{
  "version": "1.5.0",
  "complete": false,
  "story_id": "test-001",
  "story_state": "PREFLIGHT",
  "domain_area": "MyDomain",
  "total_retries": 0,
  "total_retries_max": 10
}
EOF

  run bash "$SCRIPT" "$forge_dir"
  assert_failure
  assert_output --partial "domain_area"
}

# ---------------------------------------------------------------------------
# 12. Valid state with all optional fields present passes
# ---------------------------------------------------------------------------
@test "state-integrity: valid state with all optional fields present passes" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  cat > "$forge_dir/state.json" << 'EOF'
{
  "version": "1.5.0",
  "complete": false,
  "story_id": "test-001",
  "story_state": "REVIEWING",
  "domain_area": "backend",
  "total_retries": 3,
  "total_retries_max": 10,
  "_seq": 42,
  "mode": "standard",
  "quality_cycles": 2,
  "test_cycles": 1,
  "verify_fix_count": 1,
  "score_history": [45, 62, 75, 82],
  "convergence": {
    "phase": "quality",
    "total_iterations": 5,
    "plateau_count": 0
  },
  "recovery_budget": {
    "total_weight": 2.5,
    "max_weight": 5.5
  }
}
EOF

  run bash "$SCRIPT" "$forge_dir"
  assert_success
  assert_output --partial "OK"
}

# ---------------------------------------------------------------------------
# 13. Orphaned checkpoint file detected
# ---------------------------------------------------------------------------
@test "state-integrity: orphaned checkpoint files detected as warning" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  cat > "$forge_dir/state.json" << 'EOF'
{
  "version": "1.5.0",
  "complete": false,
  "story_id": "test-001",
  "story_state": "PREFLIGHT",
  "domain_area": "test",
  "total_retries": 0,
  "total_retries_max": 10
}
EOF
  # Create an orphaned checkpoint (different story_id)
  echo '{}' > "$forge_dir/checkpoint-OLD-STORY.json"

  run bash "$SCRIPT" "$forge_dir"
  # Should still succeed (warnings don't cause failure) but mention orphaned
  assert_success
  assert_output --partial "orphaned"
}

@test "state-integrity: matching checkpoint file is not orphaned" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  cat > "$forge_dir/state.json" << 'EOF'
{
  "version": "1.5.0",
  "complete": false,
  "story_id": "test-001",
  "story_state": "PREFLIGHT",
  "domain_area": "test",
  "total_retries": 0,
  "total_retries_max": 10
}
EOF
  echo '{}' > "$forge_dir/checkpoint-test-001.json"

  run bash "$SCRIPT" "$forge_dir"
  assert_success
  refute_output --partial "orphaned"
}

# ---------------------------------------------------------------------------
# 14. Stale lock file detection
# ---------------------------------------------------------------------------
@test "state-integrity: fresh lock file does not trigger warning" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  cat > "$forge_dir/state.json" << 'EOF'
{
  "version": "1.5.0",
  "complete": false,
  "story_id": "test-001",
  "story_state": "PREFLIGHT",
  "domain_area": "test",
  "total_retries": 0,
  "total_retries_max": 10
}
EOF
  echo "$$" > "$forge_dir/.lock"

  run bash "$SCRIPT" "$forge_dir"
  assert_success
  refute_output --partial "stale"
}

# ---------------------------------------------------------------------------
# 15. Evidence freshness: SHIPPING without evidence.json
# ---------------------------------------------------------------------------
@test "state-integrity: shipping state without evidence.json reports error" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  cat > "$forge_dir/state.json" << 'EOF'
{
  "version": "1.5.0",
  "complete": false,
  "story_id": "test-001",
  "story_state": "SHIPPING",
  "domain_area": "test",
  "total_retries": 0,
  "total_retries_max": 10
}
EOF

  run bash "$SCRIPT" "$forge_dir"
  assert_failure
  assert_output --partial "evidence"
}

@test "state-integrity: shipping state with SHIP verdict passes" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  cat > "$forge_dir/state.json" << 'EOF'
{
  "version": "1.5.0",
  "complete": false,
  "story_id": "test-001",
  "story_state": "SHIPPING",
  "domain_area": "test",
  "total_retries": 0,
  "total_retries_max": 10
}
EOF
  echo '{"verdict":"SHIP","timestamp":"2026-01-01T00:00:00Z"}' > "$forge_dir/evidence.json"

  run bash "$SCRIPT" "$forge_dir"
  assert_success
}

@test "state-integrity: shipping state with non-SHIP verdict reports error" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  cat > "$forge_dir/state.json" << 'EOF'
{
  "version": "1.5.0",
  "complete": false,
  "story_id": "test-001",
  "story_state": "SHIPPING",
  "domain_area": "test",
  "total_retries": 0,
  "total_retries_max": 10
}
EOF
  echo '{"verdict":"FAIL","timestamp":"2026-01-01T00:00:00Z"}' > "$forge_dir/evidence.json"

  run bash "$SCRIPT" "$forge_dir"
  assert_failure
  assert_output --partial "verdict"
}

# ---------------------------------------------------------------------------
# 16. Decision log validation
# ---------------------------------------------------------------------------
@test "state-integrity: malformed decisions.jsonl triggers warning" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  cat > "$forge_dir/state.json" << 'EOF'
{
  "version": "1.5.0",
  "complete": false,
  "story_id": "test-001",
  "story_state": "PREFLIGHT",
  "domain_area": "test",
  "total_retries": 0,
  "total_retries_max": 10
}
EOF
  printf 'NOT VALID JSON\n{"ts":"2026-01-01","decision":"ok"}\n' > "$forge_dir/decisions.jsonl"

  run bash "$SCRIPT" "$forge_dir"
  assert_success
  assert_output --partial "malformed"
}

@test "state-integrity: valid decisions.jsonl passes without warning" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  cat > "$forge_dir/state.json" << 'EOF'
{
  "version": "1.5.0",
  "complete": false,
  "story_id": "test-001",
  "story_state": "PREFLIGHT",
  "domain_area": "test",
  "total_retries": 0,
  "total_retries_max": 10
}
EOF
  printf '{"ts":"2026-01-01T00:00:00Z","decision":"proceed","agent":"fg-100"}\n' > "$forge_dir/decisions.jsonl"

  run bash "$SCRIPT" "$forge_dir"
  assert_success
  refute_output --partial "malformed"
}

# ---------------------------------------------------------------------------
# 17. Multiple errors reported together
# ---------------------------------------------------------------------------
@test "state-integrity: multiple errors are all reported" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  cat > "$forge_dir/state.json" << 'EOF'
{
  "version": "1.5.0",
  "complete": false,
  "story_state": "INVALID_STATE",
  "domain_area": "BadDomain",
  "total_retries": 20,
  "total_retries_max": 10
}
EOF

  run bash "$SCRIPT" "$forge_dir"
  assert_failure
  # Should report at least 3 issues: missing story_id, invalid state, domain_area, and retries
  assert_output --partial "missing"
  assert_output --partial "invalid"
}

# ---------------------------------------------------------------------------
# 18. ABORTED is a valid terminal state
# ---------------------------------------------------------------------------
@test "state-integrity: ABORTED is a valid story_state" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  cat > "$forge_dir/state.json" << 'EOF'
{
  "version": "1.5.0",
  "complete": true,
  "story_id": "test-001",
  "story_state": "ABORTED",
  "domain_area": "test",
  "total_retries": 0,
  "total_retries_max": 10
}
EOF

  run bash "$SCRIPT" "$forge_dir"
  assert_success
}

# ---------------------------------------------------------------------------
# 19. COMPLETE is a valid terminal state
# ---------------------------------------------------------------------------
@test "state-integrity: COMPLETE is a valid story_state" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  cat > "$forge_dir/state.json" << 'EOF'
{
  "version": "1.5.0",
  "complete": true,
  "story_id": "test-001",
  "story_state": "COMPLETE",
  "domain_area": "test",
  "total_retries": 5,
  "total_retries_max": 10
}
EOF

  run bash "$SCRIPT" "$forge_dir"
  assert_success
}

# ---------------------------------------------------------------------------
# 20. Truncated JSON detected
# ---------------------------------------------------------------------------
@test "state-integrity: truncated JSON (missing closing brace) detected" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  printf '{"version":"1.5.0","story_state":"PREFLIGHT"' > "$forge_dir/state.json"

  run bash "$SCRIPT" "$forge_dir"
  assert_failure
  assert_output --partial "invalid"
}
