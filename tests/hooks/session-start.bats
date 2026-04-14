#!/usr/bin/env bats
# Hook integration tests for hooks/session-start.sh — SessionStart event hook.
# Tests: registration in hooks.json, timeout configuration, subshell guard, shebang.

load '../helpers/test-helpers'

HOOK_SCRIPT="$PLUGIN_ROOT/hooks/session-start.sh"
HOOKS_JSON="$PLUGIN_ROOT/hooks/hooks.json"

# ---------------------------------------------------------------------------
# 1. SessionStart event registered in hooks.json
# ---------------------------------------------------------------------------
@test "session-start-hook: SessionStart event registered in hooks.json" {
  run python3 -c "
import json
with open('$HOOKS_JSON') as f:
    data = json.load(f)
assert 'SessionStart' in data.get('hooks', {}), 'SessionStart not in hooks.json'
print('ok')
"
  assert_success
  assert_output "ok"
}

# ---------------------------------------------------------------------------
# 2. hooks.json SessionStart entry references session-start.sh
# ---------------------------------------------------------------------------
@test "session-start-hook: hooks.json entry references session-start.sh" {
  run python3 -c "
import json
with open('$HOOKS_JSON') as f:
    data = json.load(f)
hooks = data['hooks']['SessionStart']
found = False
for entry in hooks:
    for h in entry.get('hooks', []):
        if 'session-start.sh' in h.get('command', ''):
            found = True
assert found, 'session-start.sh not found in SessionStart hooks'
print('ok')
"
  assert_success
  assert_output "ok"
}

# ---------------------------------------------------------------------------
# 3. Hook has correct shebang and self-enforcing timeout
# ---------------------------------------------------------------------------
@test "session-start-hook: has correct shebang and timeout wrapper" {
  run head -1 "$HOOK_SCRIPT"
  assert_output "#!/usr/bin/env bash"

  run grep -c '_HOOK_TIMEOUT' "$HOOK_SCRIPT"
  # Should have multiple references to timeout (declaration + usage)
  [[ "${output}" -ge 2 ]] || fail "Expected at least 2 _HOOK_TIMEOUT references, got: $output"
}

# ---------------------------------------------------------------------------
# 4. Hook body is wrapped in ( ... ) || true subshell
# ---------------------------------------------------------------------------
@test "session-start-hook: body wrapped in subshell with || true guard" {
  # Verify the pattern: line starting with ( and a line with ) || true
  run grep -c '^(' "$HOOK_SCRIPT"
  [[ "${output}" -ge 1 ]] || fail "Expected subshell open '(' at start of line"

  run grep -c ') || true' "$HOOK_SCRIPT"
  [[ "${output}" -ge 1 ]] || fail "Expected ') || true' subshell guard"
}
