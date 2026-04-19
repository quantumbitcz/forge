#!/usr/bin/env bats
# Behavioral tests for hooks/post_tool_use_agent.py — Python compact-check hook.
#
# Semantic change from the old bash hook: instead of incrementing a dispatch
# counter (.compact-dispatches/.token-estimate) and writing .compact-suggestion
# every 5th call, the Python port reads state.json.tokens.total and emits a
# stderr warning when prompt+completion >= SUGGEST_THRESHOLD_TOKENS (180 000).

setup() {
  load '../helpers/test-helpers'
  HOOK_SCRIPT="$BATS_TEST_DIRNAME/../../hooks/post_tool_use_agent.py"
  TEST_TEMP="$(mktemp -d "${TMPDIR:-/tmp}/bats-compact-behavior.XXXXXX")"
  mkdir -p "$TEST_TEMP/project"
}

teardown() {
  if [[ -n "${TEST_TEMP:-}" && -d "${TEST_TEMP}" ]]; then
    rm -rf "$TEST_TEMP"
  fi
}

@test "compact-check: emits stderr warning when token usage exceeds threshold" {
  local forge_dir="${TEST_TEMP}/project/.forge"
  mkdir -p "$forge_dir"
  cat > "$forge_dir/state.json" <<'EOF'
{
  "tokens": { "total": { "prompt": 150000, "completion": 50000 } }
}
EOF

  cd "${TEST_TEMP}/project"
  run python3 "$HOOK_SCRIPT" </dev/null
  assert_success
  [[ "$output" == *"/compact"* ]] || fail "expected /compact hint on stderr, got: $output"
}

@test "compact-check: no warning when token usage is below threshold" {
  local forge_dir="${TEST_TEMP}/project/.forge"
  mkdir -p "$forge_dir"
  cat > "$forge_dir/state.json" <<'EOF'
{
  "tokens": { "total": { "prompt": 1000, "completion": 500 } }
}
EOF

  cd "${TEST_TEMP}/project"
  run python3 "$HOOK_SCRIPT" </dev/null
  assert_success
  [[ -z "$output" ]] || fail "expected no output below threshold, got: $output"
}

@test "compact-check: exits 0 when state.json is missing" {
  local forge_dir="${TEST_TEMP}/project/.forge"
  mkdir -p "$forge_dir"
  # No state.json — hook must still exit 0.

  cd "${TEST_TEMP}/project"
  run python3 "$HOOK_SCRIPT" </dev/null
  assert_success
}

@test "compact-check: exits 0 when state.json is malformed" {
  local forge_dir="${TEST_TEMP}/project/.forge"
  mkdir -p "$forge_dir"
  echo 'not valid json' > "$forge_dir/state.json"

  cd "${TEST_TEMP}/project"
  run python3 "$HOOK_SCRIPT" </dev/null
  assert_success
}
