#!/usr/bin/env bats

setup() {
  load '../helpers/test-helpers'
  load './helpers/mock-forge-state'
  HOOK_SCRIPT="$BATS_TEST_DIRNAME/../../hooks/stop.py"
}

teardown() {
  teardown_mock_forge
  if [[ -n "${TEST_TEMP:-}" && -d "${TEST_TEMP}" ]]; then
    rm -rf "${TEST_TEMP}"
  fi
}

@test "feedback-capture: writes session context to auto-captured.md" {
  setup_mock_forge
  # Ensure state.json has story_state (not pipeline_state)
  cat > "$FORGE_DIR/state.json" <<'EOF'
{
  "version": "1.5.0",
  "story_state": "REVIEWING",
  "mode": "standard",
  "score_history": [85],
  "convergence": {
    "phase": "perfection",
    "total_iterations": 3
  },
  "total_retries": 1,
  "cost": { "wall_time_seconds": 120 }
}
EOF

  run python3 "$HOOK_SCRIPT" </dev/null
  assert_success
  assert [ -f "$FORGE_DIR/feedback/auto-captured.md" ]
  run grep -q 'Session ended' "$FORGE_DIR/feedback/auto-captured.md"
  assert_success
}

@test "feedback-capture: rotates auto-captured.md at 100KB" {
  setup_mock_forge
  # Create auto-captured.md slightly over 100KB (102401 bytes)
  dd if=/dev/zero bs=1024 count=101 2>/dev/null | tr '\0' 'x' \
    > "$FORGE_DIR/feedback/auto-captured.md"

  run python3 "$HOOK_SCRIPT" </dev/null
  assert_success
  # After rotation, an archived copy should exist
  local archived
  archived=$(ls "$FORGE_DIR/feedback/auto-captured-"*.md 2>/dev/null | head -1)
  assert [ -n "$archived" ]
}

@test "feedback-capture: handles missing .forge directory" {
  cd "${TEST_TEMP}/project"
  # Ensure no .forge directory
  rm -rf .forge 2>/dev/null || true

  run python3 "$HOOK_SCRIPT" </dev/null
  assert_success
}

@test "feedback-capture: handles malformed state.json" {
  setup_mock_forge
  echo "this is not valid json" > "$FORGE_DIR/state.json"

  run python3 "$HOOK_SCRIPT" </dev/null
  assert_success
  # Should still write something to auto-captured.md (graceful degradation)
  assert [ -f "$FORGE_DIR/feedback/auto-captured.md" ]
}
