#!/usr/bin/env bats
# Unit tests: forge-timeout.sh — pipeline time budget enforcement.

load '../helpers/test-helpers'

SCRIPT="$PLUGIN_ROOT/shared/forge-timeout.sh"

# ---------------------------------------------------------------------------
# 1. Script existence and structure
# ---------------------------------------------------------------------------

@test "forge-timeout: script exists and is executable" {
  assert [ -f "$SCRIPT" ]
  assert [ -x "$SCRIPT" ]
}

@test "forge-timeout: has bash shebang" {
  local first_line
  first_line=$(head -1 "$SCRIPT")
  assert_equal "$first_line" "#!/usr/bin/env bash"
}

# ---------------------------------------------------------------------------
# 2. No state file — exits 0
# ---------------------------------------------------------------------------

@test "forge-timeout: exits 0 when no state.json exists" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"

  run bash "$SCRIPT" "$forge_dir" 7200
  assert_success
  assert_output ""
}

# ---------------------------------------------------------------------------
# 3. Within budget — exits 0
# ---------------------------------------------------------------------------

@test "forge-timeout: exits 0 when within budget" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"

  # Create state.json with a recent preflight timestamp
  local ts
  ts=$(python3 -c "from datetime import datetime, timezone; print(datetime.now(timezone.utc).isoformat())")

  cat > "$forge_dir/state.json" <<EOF
{
  "stage_timestamps": {
    "preflight": "$ts"
  }
}
EOF

  run bash "$SCRIPT" "$forge_dir" 7200
  assert_success
}

# ---------------------------------------------------------------------------
# 4. Exceeded budget — exits 1
# ---------------------------------------------------------------------------

@test "forge-timeout: exits 1 when time budget exceeded" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"

  # Create state.json with a preflight timestamp 3 hours ago
  local ts
  ts=$(python3 -c "
from datetime import datetime, timezone, timedelta
print((datetime.now(timezone.utc) - timedelta(hours=3)).isoformat())
")

  cat > "$forge_dir/state.json" <<EOF
{
  "stage_timestamps": {
    "preflight": "$ts"
  }
}
EOF

  run bash "$SCRIPT" "$forge_dir" 7200
  assert_failure
  assert_output --partial "TIMEOUT"
}
