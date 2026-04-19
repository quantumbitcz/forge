#!/usr/bin/env bats
# Unit tests for hooks/post_tool_use_agent.py — compaction suggestion hook.
#
# Old bash hook counted agent dispatches via .compact-dispatches/.token-estimate
# and wrote .compact-suggestion every 5. The Python port reads
# state.json.tokens.total and emits a stderr warning once usage passes
# SUGGEST_THRESHOLD_TOKENS (180 000).

load '../helpers/test-helpers'

SCRIPT="$PLUGIN_ROOT/hooks/post_tool_use_agent.py"

# ---------------------------------------------------------------------------
# 1. Script existence and structure
# ---------------------------------------------------------------------------

@test "forge-compact-check: script exists and is executable" {
  assert [ -f "$SCRIPT" ]
  assert [ -x "$SCRIPT" ]
}

@test "forge-compact-check: has python shebang" {
  local first_line
  first_line=$(head -1 "$SCRIPT")
  assert_equal "$first_line" "#!/usr/bin/env python3"
}

# ---------------------------------------------------------------------------
# 2. Token-threshold behavior
# ---------------------------------------------------------------------------

@test "forge-compact-check: exits 0 when forge dir missing" {
  local proj="$TEST_TEMP/no-forge"
  mkdir -p "$proj"
  run bash -c "cd '$proj' && python3 '$SCRIPT' </dev/null"
  assert_success
}

@test "forge-compact-check: silent when token usage is below threshold" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  cat > "$forge_dir/state.json" <<'EOF'
{ "tokens": { "total": { "prompt": 10000, "completion": 2000 } } }
EOF

  run bash -c "cd '$TEST_TEMP/project' && python3 '$SCRIPT' </dev/null 2>&1"
  assert_success
  [[ -z "$output" ]] || fail "expected no output below threshold, got: $output"
}

@test "forge-compact-check: emits /compact hint when above threshold" {
  local forge_dir="$TEST_TEMP/project/.forge"
  mkdir -p "$forge_dir"
  cat > "$forge_dir/state.json" <<'EOF'
{ "tokens": { "total": { "prompt": 170000, "completion": 20000 } } }
EOF

  run bash -c "cd '$TEST_TEMP/project' && python3 '$SCRIPT' </dev/null 2>&1"
  assert_success
  [[ "$output" == *"/compact"* ]] || fail "expected /compact hint, got: $output"
}
