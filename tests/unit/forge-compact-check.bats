#!/usr/bin/env bats
# Unit tests: forge-compact-check.sh — compaction suggestion after Agent dispatches.

load '../helpers/test-helpers'

SCRIPT="$PLUGIN_ROOT/shared/forge-compact-check.sh"

# ---------------------------------------------------------------------------
# 1. Script existence and structure
# ---------------------------------------------------------------------------

@test "forge-compact-check: script exists and is executable" {
  assert [ -f "$SCRIPT" ]
  assert [ -x "$SCRIPT" ]
}

@test "forge-compact-check: has bash shebang" {
  local first_line
  first_line=$(head -1 "$SCRIPT")
  assert_equal "$first_line" "#!/usr/bin/env bash"
}

# ---------------------------------------------------------------------------
# 2. Counter increments
# ---------------------------------------------------------------------------

@test "forge-compact-check: increments dispatch counter" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"

  FORGE_DIR="$forge_dir" run bash "$SCRIPT"
  assert_success
  assert [ -f "$forge_dir/.token-estimate" ]

  local count
  count=$(cat "$forge_dir/.token-estimate")
  assert_equal "$count" "1"

  FORGE_DIR="$forge_dir" run bash "$SCRIPT"
  assert_success
  count=$(cat "$forge_dir/.token-estimate")
  assert_equal "$count" "2"
}

# ---------------------------------------------------------------------------
# 3. Suggestion written every 5 dispatches
# ---------------------------------------------------------------------------

@test "forge-compact-check: writes suggestion every 5 dispatches" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"

  # Run 4 times — no suggestion yet
  for i in 1 2 3 4; do
    FORGE_DIR="$forge_dir" run bash "$SCRIPT"
    assert_success
  done
  assert [ ! -f "$forge_dir/.compact-suggestion" ]

  # 5th dispatch triggers suggestion
  FORGE_DIR="$forge_dir" run bash "$SCRIPT"
  assert_success
  assert [ -f "$forge_dir/.compact-suggestion" ]

  local suggestion
  suggestion=$(cat "$forge_dir/.compact-suggestion")
  assert_equal "$suggestion" "Consider running /compact to free context space (5 agent dispatches since last compact)"
}

# ---------------------------------------------------------------------------
# 4. Exits 0 when .forge dir does not exist
# ---------------------------------------------------------------------------

@test "forge-compact-check: exits 0 when forge dir missing" {
  FORGE_DIR="$TEST_TEMP/nonexistent/.forge" run bash "$SCRIPT"
  assert_success
}
