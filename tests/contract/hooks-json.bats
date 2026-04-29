#!/usr/bin/env bats
# Contract tests: hooks/hooks.json structure compliance.

load '../helpers/test-helpers'

HOOKS_JSON="$PLUGIN_ROOT/hooks/hooks.json"

# ---------------------------------------------------------------------------
# 1. Valid JSON
# ---------------------------------------------------------------------------
@test "hooks-json: file is valid JSON" {
  run python3 - "$HOOKS_JSON" <<'PYEOF'
import json, sys; json.load(open(sys.argv[1]))
PYEOF
  assert_success
}

# ---------------------------------------------------------------------------
# 2. Contains PostToolUse and Stop top-level hook types
# ---------------------------------------------------------------------------
@test "hooks-json: contains PostToolUse and Stop hook types" {
  run python3 - "$HOOKS_JSON" <<'PYEOF'
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
hooks = data.get('hooks', {})
missing = []
if 'PostToolUse' not in hooks:
    missing.append('PostToolUse')
if 'Stop' not in hooks:
    missing.append('Stop')
if missing:
    print(f"Missing hook types: {', '.join(missing)}")
    sys.exit(1)
PYEOF
  assert_success
}

# ---------------------------------------------------------------------------
# 3. Each top-level entry has a hooks array
# ---------------------------------------------------------------------------
@test "hooks-json: each PostToolUse and Stop entry has a hooks array" {
  run python3 - "$HOOKS_JSON" <<'PYEOF'
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
hooks = data.get('hooks', {})
issues = []
for hook_type in ('PostToolUse', 'Stop'):
    entries = hooks.get(hook_type, [])
    if not isinstance(entries, list):
        issues.append(f"{hook_type} is not a list")
        continue
    for i, entry in enumerate(entries):
        if 'hooks' not in entry:
            issues.append(f"{hook_type}[{i}] missing 'hooks' array")
        elif not isinstance(entry['hooks'], list):
            issues.append(f"{hook_type}[{i}].hooks is not a list")
if issues:
    print('\n'.join(issues))
    sys.exit(1)
PYEOF
  assert_success
}

# ---------------------------------------------------------------------------
# 4. Nested hooks have type, command, timeout fields
# ---------------------------------------------------------------------------
@test "hooks-json: nested hook entries have type, command, and timeout" {
  run python3 - "$HOOKS_JSON" <<'PYEOF'
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
hooks = data.get('hooks', {})
issues = []
required_fields = ('type', 'command', 'timeout')
for hook_type in ('PostToolUse', 'Stop'):
    for i, entry in enumerate(hooks.get(hook_type, [])):
        for j, nested in enumerate(entry.get('hooks', [])):
            for field in required_fields:
                if field not in nested:
                    issues.append(f"{hook_type}[{i}].hooks[{j}] missing '{field}'")
if issues:
    print('\n'.join(issues))
    sys.exit(1)
PYEOF
  assert_success
}

# ---------------------------------------------------------------------------
# 5. PostToolUse entries have matcher field
# ---------------------------------------------------------------------------
@test "hooks-json: PostToolUse entries have matcher field" {
  run python3 - "$HOOKS_JSON" <<'PYEOF'
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
hooks = data.get('hooks', {})
issues = []
for i, entry in enumerate(hooks.get('PostToolUse', [])):
    if 'matcher' not in entry:
        issues.append(f"PostToolUse[{i}] missing 'matcher' field")
    elif not isinstance(entry['matcher'], str) or not entry['matcher'].strip():
        issues.append(f"PostToolUse[{i}] 'matcher' must be a non-empty string")
if issues:
    print('\n'.join(issues))
    sys.exit(1)
PYEOF
  assert_success
}

# ---------------------------------------------------------------------------
# 6. Timeout values are positive integers
# ---------------------------------------------------------------------------
@test "hooks-json: all timeout values are positive integers" {
  run python3 - "$HOOKS_JSON" <<'PYEOF'
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
hooks = data.get('hooks', {})
issues = []
for hook_type in ('PostToolUse', 'Stop'):
    for i, entry in enumerate(hooks.get(hook_type, [])):
        for j, nested in enumerate(entry.get('hooks', [])):
            timeout = nested.get('timeout')
            if timeout is None:
                continue  # missing field caught by earlier test
            if not isinstance(timeout, int) or timeout <= 0:
                issues.append(
                    f"{hook_type}[{i}].hooks[{j}] timeout must be a positive integer, got: {repr(timeout)}"
                )
if issues:
    print('\n'.join(issues))
    sys.exit(1)
PYEOF
  assert_success
}
