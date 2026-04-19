#!/usr/bin/env bats
# Tests for hooks/pre_tool_use.py — Python L0 syntax validator.
#
# Semantic change from the old bash hook:
# - Reads JSON payload from stdin (no TOOL_INPUT env var).
# - Validates in-process via Python's ast / json stdlib — no tree-sitter.
# - Supported file extensions are .py and .json; unknown extensions pass.
# - On invalid content: exits 2 and prints "L0 blocked <path>: <reason>" to stderr.
# - On missing/invalid stdin payload: exits 0.

setup() {
  load '../helpers/test-helpers'
  HOOK_SCRIPT="$BATS_TEST_DIRNAME/../../hooks/pre_tool_use.py"
}

@test "l0-syntax: script exists and is executable" {
  assert [ -f "$HOOK_SCRIPT" ]
  assert [ -x "$HOOK_SCRIPT" ]
}

@test "l0-syntax: has python3 shebang" {
  run head -1 "$HOOK_SCRIPT"
  assert_output --partial "python3"
}

@test "l0-syntax: exits 0 on empty stdin" {
  run bash -c "echo '' | python3 '$HOOK_SCRIPT'"
  assert_success
}

@test "l0-syntax: exits 0 on malformed stdin JSON" {
  run bash -c "echo 'not valid json at all' | python3 '$HOOK_SCRIPT'"
  assert_success
}

# ---------------------------------------------------------------------------
# Python content validation (.py files)
# ---------------------------------------------------------------------------

@test "l0-syntax: blocks Write with invalid Python content" {
  local payload='{"tool_name":"Write","tool_input":{"file_path":"/tmp/bad.py","content":"def foo(:"}}'
  run bash -c "printf %s '$payload' | python3 '$HOOK_SCRIPT'"
  assert_failure
  [[ "$status" -eq 2 ]] || fail "expected exit 2, got $status"
  [[ "$output" == *"L0 blocked"* ]] || fail "expected L0 blocked message, got: $output"
}

@test "l0-syntax: allows Write with valid Python content" {
  local payload='{"tool_name":"Write","tool_input":{"file_path":"/tmp/good.py","content":"def foo():\n    return 1\n"}}'
  run bash -c "printf %s '$payload' | python3 '$HOOK_SCRIPT'"
  assert_success
}

@test "l0-syntax: allows Edit with valid Python content" {
  local payload='{"tool_name":"Edit","tool_input":{"file_path":"/tmp/ok.py","content":"x = 1\n"}}'
  run bash -c "printf %s '$payload' | python3 '$HOOK_SCRIPT'"
  assert_success
}

# ---------------------------------------------------------------------------
# JSON content validation (.json files)
# ---------------------------------------------------------------------------

@test "l0-syntax: blocks Write with invalid JSON content" {
  local payload='{"tool_name":"Write","tool_input":{"file_path":"/tmp/bad.json","content":"{not valid"}}'
  run bash -c "printf %s '$payload' | python3 '$HOOK_SCRIPT'"
  [[ "$status" -eq 2 ]] || fail "expected exit 2, got $status"
  [[ "$output" == *"L0 blocked"* ]] || fail "expected L0 blocked message, got: $output"
}

@test "l0-syntax: allows Write with valid JSON content" {
  local payload='{"tool_name":"Write","tool_input":{"file_path":"/tmp/good.json","content":"{\"a\":1}"}}'
  run bash -c "printf %s '$payload' | python3 '$HOOK_SCRIPT'"
  assert_success
}

# ---------------------------------------------------------------------------
# Unsupported / no-op cases
# ---------------------------------------------------------------------------

@test "l0-syntax: allows unsupported extensions (.md, .yaml, .ts)" {
  for ext in md yaml ts; do
    local payload
    payload=$(printf '{"tool_name":"Edit","tool_input":{"file_path":"/tmp/x.%s","content":"anything"}}' "$ext")
    run bash -c "printf %s '$payload' | python3 '$HOOK_SCRIPT'"
    assert_success
  done
}

@test "l0-syntax: skips when tool_name is not Edit/Write/MultiEdit" {
  local payload='{"tool_name":"Read","tool_input":{"file_path":"/tmp/x.py","content":"def foo(:"}}'
  run bash -c "printf %s '$payload' | python3 '$HOOK_SCRIPT'"
  assert_success
}

@test "l0-syntax: skips when file_path is empty" {
  local payload='{"tool_name":"Edit","tool_input":{"file_path":"","content":"def foo(:"}}'
  run bash -c "printf %s '$payload' | python3 '$HOOK_SCRIPT'"
  assert_success
}

@test "l0-syntax: skips when content is empty" {
  local payload='{"tool_name":"Edit","tool_input":{"file_path":"/tmp/x.py","content":""}}'
  run bash -c "printf %s '$payload' | python3 '$HOOK_SCRIPT'"
  assert_success
}
