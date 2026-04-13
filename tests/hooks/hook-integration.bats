#!/usr/bin/env bats

setup() {
  load '../../helpers/test-helpers'
  HOOKS_JSON="$BATS_TEST_DIRNAME/../../hooks/hooks.json"
  PLUGIN_ROOT="$BATS_TEST_DIRNAME/../.."
}

@test "hook-integration: hooks.json is valid JSON" {
  run python3 -c "import json; json.load(open('$HOOKS_JSON'))"
  assert_success
}

@test "hook-integration: all hook command scripts exist" {
  # Extract command paths from hooks.json, resolve CLAUDE_PLUGIN_ROOT
  local commands
  commands=$(python3 -c "
import json
with open('$HOOKS_JSON') as f:
    data = json.load(f)
for event_hooks in data.get('hooks', {}).values():
    for entry in event_hooks:
        for hook in entry.get('hooks', []):
            cmd = hook.get('command', '').split()[0]
            cmd = cmd.replace('\${CLAUDE_PLUGIN_ROOT}', '$PLUGIN_ROOT')
            print(cmd)
")
  while IFS= read -r cmd; do
    [[ -z "$cmd" ]] && continue
    assert [ -f "$cmd" ] "Hook command not found: $cmd"
  done <<< "$commands"
}

@test "hook-integration: all hook scripts are executable" {
  local commands
  commands=$(python3 -c "
import json
with open('$HOOKS_JSON') as f:
    data = json.load(f)
for event_hooks in data.get('hooks', {}).values():
    for entry in event_hooks:
        for hook in entry.get('hooks', []):
            cmd = hook.get('command', '').split()[0]
            cmd = cmd.replace('\${CLAUDE_PLUGIN_ROOT}', '$PLUGIN_ROOT')
            print(cmd)
")
  while IFS= read -r cmd; do
    [[ -z "$cmd" ]] && continue
    assert [ -x "$cmd" ] "Hook script not executable: $cmd"
  done <<< "$commands"
}

@test "hook-integration: all timeouts are positive integers" {
  run python3 -c "
import json
with open('$HOOKS_JSON') as f:
    data = json.load(f)
for event_hooks in data.get('hooks', {}).values():
    for entry in event_hooks:
        for hook in entry.get('hooks', []):
            t = hook.get('timeout', 0)
            assert isinstance(t, int) and t > 0, f'Invalid timeout: {t}'
print('OK')
"
  assert_success
  assert_output --partial "OK"
}
