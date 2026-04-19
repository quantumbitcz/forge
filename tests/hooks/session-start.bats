#!/usr/bin/env bats
# Hook integration tests for hooks/session_start.py — SessionStart event hook.
# Tests: registration in hooks.json, shebang. Bash-specific timeout/subshell
# guards removed with the Python port.

load '../helpers/test-helpers'

HOOK_SCRIPT="$PLUGIN_ROOT/hooks/session_start.py"
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
# 2. hooks.json SessionStart entry references session_start.py
# ---------------------------------------------------------------------------
@test "session-start-hook: hooks.json entry references session_start.py" {
  run python3 -c "
import json
with open('$HOOKS_JSON') as f:
    data = json.load(f)
hooks = data['hooks']['SessionStart']
found = False
for entry in hooks:
    for h in entry.get('hooks', []):
        if 'session_start.py' in h.get('command', ''):
            found = True
assert found, 'session_start.py not found in SessionStart hooks'
print('ok')
"
  assert_success
  assert_output "ok"
}

# ---------------------------------------------------------------------------
# 3. Hook has correct Python shebang
# ---------------------------------------------------------------------------
@test "session-start-hook: has python3 shebang" {
  run head -1 "$HOOK_SCRIPT"
  assert_output "#!/usr/bin/env python3"
}
