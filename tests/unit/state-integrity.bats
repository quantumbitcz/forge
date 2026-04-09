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
