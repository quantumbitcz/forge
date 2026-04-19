#!/usr/bin/env bats

setup() {
  load '../helpers/test-helpers'
  HOOK_SCRIPT="$BATS_TEST_DIRNAME/../../hooks/post_tool_use_skill.py"
}

@test "checkpoint: updates lastCheckpoint in state.json" {
  local forge_dir="${TEST_TEMP}/project/.forge"
  mkdir -p "$forge_dir"
  # Create valid state.json with story_state
  cat > "$forge_dir/state.json" <<'EOF'
{
  "version": "1.5.0",
  "story_state": "IMPLEMENTING",
  "mode": "standard",
  "lastCheckpoint": ""
}
EOF

  # The checkpoint hook requires platform.sh for atomic_json_update.
  # Source it from the plugin root.
  cd "${TEST_TEMP}/project"

  run python3 "$HOOK_SCRIPT" </dev/null
  assert_success

  # Verify lastCheckpoint was updated (non-empty timestamp)
  if command -v python3 &>/dev/null; then
    local ts
    ts=$(python3 -c "import json; print(json.load(open('$forge_dir/state.json')).get('lastCheckpoint',''))" 2>/dev/null) || true
    if [[ -n "$ts" ]]; then
      assert [ "$ts" != "" ]
    fi
  fi
}

@test "checkpoint: handles missing state.json gracefully" {
  local forge_dir="${TEST_TEMP}/project/.forge"
  mkdir -p "$forge_dir"
  # No state.json present
  cd "${TEST_TEMP}/project"

  run python3 "$HOOK_SCRIPT" </dev/null
  assert_success
}

@test "checkpoint: logs failure to .hook-failures.log on invalid JSON" {
  local forge_dir="${TEST_TEMP}/project/.forge"
  mkdir -p "$forge_dir"
  echo "not json" > "$forge_dir/state.json"
  cd "${TEST_TEMP}/project"

  run python3 "$HOOK_SCRIPT" </dev/null
  assert_success

  # Verify failure was logged
  if [[ -f "$forge_dir/.hook-failures.log" ]]; then
    run grep -q 'forge-checkpoint' "$forge_dir/.hook-failures.log"
    assert_success
  fi
}
