#!/usr/bin/env bats
# Unit tests for hooks/session_start.py — SessionStart event hook.
# Tests: forge detection, caveman auto-activation, pipeline status, alerts, exit behavior.

load '../helpers/test-helpers'

HOOK_SCRIPT="$PLUGIN_ROOT/hooks/session_start.py"

# Helper: run the hook with CWD set to the given project dir
run_hook_in() {
  local project_dir="$1"
  run bash -c "cd '$project_dir' && python3 '$HOOK_SCRIPT'"
}

# ---------------------------------------------------------------------------
# 1. Script exists and is executable
# ---------------------------------------------------------------------------
@test "session-start: script exists and is executable" {
  assert [ -f "$HOOK_SCRIPT" ]
  assert [ -x "$HOOK_SCRIPT" ]
}

# ---------------------------------------------------------------------------
# 2. Exits 0 when not a forge project (no .claude/forge.local.md)
# ---------------------------------------------------------------------------
@test "session-start: exits 0 when not a forge project" {
  local project_dir="${TEST_TEMP}/non-forge"
  mkdir -p "$project_dir"
  # No .claude/forge.local.md or .forge/

  run_hook_in "$project_dir"
  assert_success
  # Should produce no output
  assert_output ""
}

# ---------------------------------------------------------------------------
# 3. Exits 0 when .forge/ exists but .claude/forge.local.md is missing
# ---------------------------------------------------------------------------
@test "session-start: exits 0 when .forge exists but no forge.local.md" {
  local project_dir="${TEST_TEMP}/partial-forge"
  mkdir -p "$project_dir/.forge"
  # No .claude/forge.local.md

  run_hook_in "$project_dir"
  assert_success
  assert_output ""
}

# ---------------------------------------------------------------------------
# 4. Reads existing .forge/caveman-mode and emits compression instructions
# ---------------------------------------------------------------------------
@test "session-start: emits caveman instructions when caveman-mode file exists" {
  local project_dir="${TEST_TEMP}/caveman-project"
  mkdir -p "$project_dir/.claude" "$project_dir/.forge"
  printf '' > "$project_dir/.claude/forge.local.md"
  printf 'full' > "$project_dir/.forge/caveman-mode"

  run_hook_in "$project_dir"
  assert_success
  [[ "$output" == *"OUTPUT COMPRESSION"* ]] || fail "Expected OUTPUT COMPRESSION rules, got: $output"
  [[ "$output" == *"Drop:"* ]] || fail "Expected Drop: rules, got: $output"
}

# ---------------------------------------------------------------------------
# 5. Caveman lite mode emits correct message
# ---------------------------------------------------------------------------
@test "session-start: emits lite caveman message" {
  local project_dir="${TEST_TEMP}/caveman-lite"
  mkdir -p "$project_dir/.claude" "$project_dir/.forge"
  printf '' > "$project_dir/.claude/forge.local.md"
  printf 'lite' > "$project_dir/.forge/caveman-mode"

  run_hook_in "$project_dir"
  assert_success
  [[ "$output" == *"OUTPUT COMPRESSION -- LITE MODE"* ]] || fail "Expected LITE MODE rules, got: $output"
  [[ "$output" == *"Drop:"* ]] || fail "Expected Drop: rules, got: $output"
}

# ---------------------------------------------------------------------------
# 6. Caveman ultra mode emits correct message
# ---------------------------------------------------------------------------
@test "session-start: emits ultra caveman message" {
  local project_dir="${TEST_TEMP}/caveman-ultra"
  mkdir -p "$project_dir/.claude" "$project_dir/.forge"
  printf '' > "$project_dir/.claude/forge.local.md"
  printf 'ultra' > "$project_dir/.forge/caveman-mode"

  run_hook_in "$project_dir"
  assert_success
  [[ "$output" == *"OUTPUT COMPRESSION -- ULTRA"* ]] || fail "Expected ULTRA mode rules, got: $output"
  [[ "$output" == *"Abbreviate:"* ]] || fail "Expected Abbreviate: in rules, got: $output"
}

# ---------------------------------------------------------------------------
# 7. Caveman off mode produces no caveman output
# ---------------------------------------------------------------------------
@test "session-start: no caveman output when mode is off" {
  local project_dir="${TEST_TEMP}/caveman-off"
  mkdir -p "$project_dir/.claude" "$project_dir/.forge"
  printf '' > "$project_dir/.claude/forge.local.md"
  printf 'off' > "$project_dir/.forge/caveman-mode"

  run_hook_in "$project_dir"
  assert_success
  [[ "$output" != *"Caveman"* && "$output" != *"CAVEMAN"* ]] || fail "Expected no caveman output when off, got: $output"
}

# ---------------------------------------------------------------------------
# 8. Displays pipeline status from state.json
# ---------------------------------------------------------------------------
@test "session-start: displays pipeline status from state.json" {
  local project_dir="${TEST_TEMP}/status-project"
  mkdir -p "$project_dir/.claude" "$project_dir/.forge"
  printf '' > "$project_dir/.claude/forge.local.md"
  cat > "$project_dir/.forge/state.json" <<'EOF'
{
  "story_state": "REVIEWING",
  "mode": "standard",
  "score_history": [60, 75, 88]
}
EOF

  run_hook_in "$project_dir"
  assert_success
  [[ "$output" == *"state=REVIEWING"* ]] || fail "Expected state=REVIEWING in: $output"
  [[ "$output" == *"mode=standard"* ]] || fail "Expected mode=standard in: $output"
  [[ "$output" == *"score=88"* ]] || fail "Expected score=88 in: $output"
}

# ---------------------------------------------------------------------------
# 9. Displays unacknowledged alerts from alerts.json
# ---------------------------------------------------------------------------
@test "session-start: displays unacknowledged alerts" {
  local project_dir="${TEST_TEMP}/alert-project"
  mkdir -p "$project_dir/.claude" "$project_dir/.forge"
  printf '' > "$project_dir/.claude/forge.local.md"
  cat > "$project_dir/.forge/alerts.json" <<'EOF'
{
  "alerts": [
    {
      "id": "alert-001",
      "type": "REGRESSING",
      "severity": "CRITICAL",
      "message": "Score dropped from 85 to 62",
      "resolved": false
    },
    {
      "id": "alert-002",
      "type": "BUILD_FAILURE",
      "severity": "WARNING",
      "message": "Build failed after 3 attempts",
      "resolved": true
    }
  ]
}
EOF

  run_hook_in "$project_dir"
  assert_success
  [[ "$output" == *"1 unacknowledged alert"* ]] || fail "Expected 1 unacknowledged alert in: $output"
  [[ "$output" == *"REGRESSING"* ]] || fail "Expected REGRESSING alert type in: $output"
  # Resolved alert should NOT appear
  [[ "$output" != *"BUILD_FAILURE"* ]] || fail "Resolved alert should not appear in: $output"
}

# ---------------------------------------------------------------------------
# 10. Auto-creates caveman-mode file when caveman.enabled is true in config
# ---------------------------------------------------------------------------
@test "session-start: auto-creates caveman-mode when caveman.enabled is true" {
  local project_dir="${TEST_TEMP}/auto-caveman"
  mkdir -p "$project_dir/.claude" "$project_dir/.forge"
  printf '' > "$project_dir/.claude/forge.local.md"
  cat > "$project_dir/.claude/forge-config.md" <<'EOF'
---
caveman:
  enabled: true
  default_mode: ultra
---
EOF

  # Ensure no caveman-mode file exists
  [[ ! -f "$project_dir/.forge/caveman-mode" ]]

  run_hook_in "$project_dir"
  assert_success

  # File should now exist with the default_mode value
  [[ -f "$project_dir/.forge/caveman-mode" ]] || fail "caveman-mode file should have been created"
  local mode_content
  mode_content="$(cat "$project_dir/.forge/caveman-mode")"
  [[ "$mode_content" == "ultra" ]] || fail "Expected caveman-mode=ultra, got: $mode_content"
}

# ---------------------------------------------------------------------------
# 11. Statusline badge emitted for full caveman mode
# ---------------------------------------------------------------------------
@test "session-start: emits STATUS badge for full caveman" {
  local project_dir="${TEST_TEMP}/status-full"
  mkdir -p "$project_dir/.claude" "$project_dir/.forge"
  printf '' > "$project_dir/.claude/forge.local.md"
  printf 'full' > "$project_dir/.forge/caveman-mode"

  run_hook_in "$project_dir"
  assert_success
  [[ "$output" == *"[STATUS: CAVEMAN]"* ]] || fail "Expected STATUS badge, got: $output"
}

# ---------------------------------------------------------------------------
# 12. Statusline badge emitted for lite caveman mode
# ---------------------------------------------------------------------------
@test "session-start: emits STATUS badge for lite caveman" {
  local project_dir="${TEST_TEMP}/status-lite"
  mkdir -p "$project_dir/.claude" "$project_dir/.forge"
  printf '' > "$project_dir/.claude/forge.local.md"
  printf 'lite' > "$project_dir/.forge/caveman-mode"

  run_hook_in "$project_dir"
  assert_success
  [[ "$output" == *"[STATUS: CAVEMAN:LITE]"* ]] || fail "Expected CAVEMAN:LITE badge, got: $output"
}

# ---------------------------------------------------------------------------
# 13. Statusline badge emitted for ultra caveman mode
# ---------------------------------------------------------------------------
@test "session-start: emits STATUS badge for ultra caveman" {
  local project_dir="${TEST_TEMP}/status-ultra"
  mkdir -p "$project_dir/.claude" "$project_dir/.forge"
  printf '' > "$project_dir/.claude/forge.local.md"
  printf 'ultra' > "$project_dir/.forge/caveman-mode"

  run_hook_in "$project_dir"
  assert_success
  [[ "$output" == *"[STATUS: CAVEMAN:ULTRA]"* ]] || fail "Expected CAVEMAN:ULTRA badge, got: $output"
}

# ---------------------------------------------------------------------------
# 14. No STATUS badge when caveman is off
# ---------------------------------------------------------------------------
@test "session-start: no STATUS badge when caveman is off" {
  local project_dir="${TEST_TEMP}/status-off"
  mkdir -p "$project_dir/.claude" "$project_dir/.forge"
  printf '' > "$project_dir/.claude/forge.local.md"
  printf 'off' > "$project_dir/.forge/caveman-mode"

  run_hook_in "$project_dir"
  assert_success
  [[ "$output" != *"[STATUS:"* ]] || fail "Expected no STATUS badge when off, got: $output"
}

# ---------------------------------------------------------------------------
# 15. Full compression rules emitted for lite mode (multi-line)
# ---------------------------------------------------------------------------
@test "session-start: emits full compression rules for lite mode" {
  local project_dir="${TEST_TEMP}/rules-lite"
  mkdir -p "$project_dir/.claude" "$project_dir/.forge"
  printf '' > "$project_dir/.claude/forge.local.md"
  printf 'lite' > "$project_dir/.forge/caveman-mode"

  run_hook_in "$project_dir"
  assert_success
  [[ "$output" == *"OUTPUT COMPRESSION -- LITE MODE"* ]] || fail "Expected LITE MODE rules, got: $output"
  [[ "$output" == *"Drop:"* ]] || fail "Expected Drop: rules, got: $output"
  [[ "$output" == *"Keep:"* ]] || fail "Expected Keep: rules, got: $output"
  [[ "$output" == *"Exceptions:"* ]] || fail "Expected Exceptions rules, got: $output"
}

# ---------------------------------------------------------------------------
# 16. Full compression rules emitted for full mode (multi-line)
# ---------------------------------------------------------------------------
@test "session-start: emits full compression rules for full mode" {
  local project_dir="${TEST_TEMP}/rules-full"
  mkdir -p "$project_dir/.claude" "$project_dir/.forge"
  printf '' > "$project_dir/.claude/forge.local.md"
  printf 'full' > "$project_dir/.forge/caveman-mode"

  run_hook_in "$project_dir"
  assert_success
  [[ "$output" == *"OUTPUT COMPRESSION -- FULL"* ]] || fail "Expected FULL mode rules, got: $output"
  [[ "$output" == *"Pattern:"* ]] || fail "Expected Pattern: in rules, got: $output"
  [[ "$output" == *"Example:"* ]] || fail "Expected Example: in rules, got: $output"
}

# ---------------------------------------------------------------------------
# 17. Full compression rules emitted for ultra mode (multi-line)
# ---------------------------------------------------------------------------
@test "session-start: emits full compression rules for ultra mode" {
  local project_dir="${TEST_TEMP}/rules-ultra"
  mkdir -p "$project_dir/.claude" "$project_dir/.forge"
  printf '' > "$project_dir/.claude/forge.local.md"
  printf 'ultra' > "$project_dir/.forge/caveman-mode"

  run_hook_in "$project_dir"
  assert_success
  [[ "$output" == *"OUTPUT COMPRESSION -- ULTRA"* ]] || fail "Expected ULTRA mode rules, got: $output"
  [[ "$output" == *"Abbreviate:"* ]] || fail "Expected Abbreviate: in rules, got: $output"
}

# ---------------------------------------------------------------------------
# 18. Compression rules have more than 5 lines per mode
# ---------------------------------------------------------------------------
@test "session-start: compression rules are multi-line (not one-liner)" {
  local project_dir="${TEST_TEMP}/rules-multiline"
  mkdir -p "$project_dir/.claude" "$project_dir/.forge"
  printf '' > "$project_dir/.claude/forge.local.md"
  printf 'full' > "$project_dir/.forge/caveman-mode"

  run_hook_in "$project_dir"
  assert_success
  # Count lines containing forge compression content (filter out status/pipeline lines)
  local compression_lines
  compression_lines=$(echo "$output" | grep -c -E '(COMPRESSION|Drop:|Keep:|Pattern:|Example:|Exceptions:|BEFORE:|AFTER:)' || true)
  [[ "$compression_lines" -ge 5 ]] || fail "Expected >=5 compression rule lines, got $compression_lines"
}
