#!/usr/bin/env bats
# Unit tests for hook scripts:
#   hooks/forge-checkpoint.sh — PostToolUse hook that updates lastCheckpoint in state.json
#   hooks/feedback-capture.sh   — Stop hook that appends timestamped line to auto-captured.md

load '../helpers/test-helpers'

CHECKPOINT_HOOK="$PLUGIN_ROOT/hooks/forge-checkpoint.sh"
FEEDBACK_HOOK="$PLUGIN_ROOT/hooks/feedback-capture.sh"

# Helper: run a hook with CWD set to the given project dir
run_hook_in() {
  local hook="$1"
  local project_dir="$2"
  run bash -c "cd '$project_dir' && bash '$hook'"
}

# ---------------------------------------------------------------------------
# checkpoint hook
# ---------------------------------------------------------------------------

# 1. Updates lastCheckpoint in state.json
@test "checkpoint: updates lastCheckpoint in state.json" {
  local state_file
  state_file="$(create_state_json '{"lastCheckpoint": "2000-01-01T00:00:00Z"}')"
  local project_dir
  project_dir="$(dirname "$(dirname "$state_file")")"

  run_hook_in "$CHECKPOINT_HOOK" "$project_dir"
  assert_success

  local new_value
  new_value="$(python3 -c "import json; d=json.load(open('$state_file')); print(d['lastCheckpoint'])")"
  [[ "$new_value" != "2000-01-01T00:00:00Z" ]]
}

# 2. Timestamp written is ISO 8601 UTC format
@test "checkpoint: timestamp is ISO 8601 UTC (YYYY-MM-DDThh:mm:ssZ)" {
  local state_file
  state_file="$(create_state_json '{}')"
  local project_dir
  project_dir="$(dirname "$(dirname "$state_file")")"

  run_hook_in "$CHECKPOINT_HOOK" "$project_dir"
  assert_success

  local ts
  ts="$(python3 -c "import json; d=json.load(open('$state_file')); print(d.get('lastCheckpoint',''))")"
  [[ "$ts" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]
}

# 3. Handles missing state.json — exits 0, no error
@test "checkpoint: exits 0 when state.json is missing" {
  local project_dir="${TEST_TEMP}/empty-project"
  mkdir -p "$project_dir"

  run_hook_in "$CHECKPOINT_HOOK" "$project_dir"
  assert_success
}

# 4. Malformed state.json — no crash (exit 0), original file content unchanged
@test "checkpoint: no crash and original content unchanged on malformed state.json" {
  local project_dir="${TEST_TEMP}/malformed-project"
  mkdir -p "$project_dir/.forge"
  local state_file="$project_dir/.forge/state.json"
  printf 'this is not valid json {{{' > "$state_file"

  run_hook_in "$CHECKPOINT_HOOK" "$project_dir"
  assert_success

  local content
  content="$(cat "$state_file")"
  [[ "$content" == "this is not valid json {{{" ]]
}

# 5. Overwrites existing lastCheckpoint value
@test "checkpoint: overwrites existing lastCheckpoint value" {
  local state_file
  state_file="$(create_state_json '{"lastCheckpoint": "1999-12-31T23:59:59Z"}')"
  local project_dir
  project_dir="$(dirname "$(dirname "$state_file")")"

  run_hook_in "$CHECKPOINT_HOOK" "$project_dir"
  assert_success

  local ts
  ts="$(python3 -c "import json; d=json.load(open('$state_file')); print(d['lastCheckpoint'])")"
  [[ "$ts" != "1999-12-31T23:59:59Z" ]]
  [[ "$ts" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]
}

# ---------------------------------------------------------------------------
# feedback hook
# ---------------------------------------------------------------------------

# 6. Appends timestamped line to auto-captured.md
@test "feedback: appends timestamped line to auto-captured.md" {
  local project_dir="${TEST_TEMP}/feedback-project"
  mkdir -p "$project_dir/.forge"

  run_hook_in "$FEEDBACK_HOOK" "$project_dir"
  assert_success

  local feedback_file="$project_dir/.forge/feedback/auto-captured.md"
  [ -f "$feedback_file" ]
  local content
  content="$(cat "$feedback_file")"
  [[ "$content" =~ \[.*\].*Session\ ended ]]
}

# 7. Creates feedback directory if it does not exist
@test "feedback: creates feedback/ directory if missing" {
  local project_dir="${TEST_TEMP}/feedback-mkdir-project"
  mkdir -p "$project_dir/.forge"
  # Intentionally do NOT create feedback/ subdirectory

  run_hook_in "$FEEDBACK_HOOK" "$project_dir"
  assert_success

  [ -d "$project_dir/.forge/feedback" ]
  [ -f "$project_dir/.forge/feedback/auto-captured.md" ]
}

# 8. Exits 0 when .forge/ directory is missing
@test "feedback: exits 0 when .forge/ directory is missing" {
  local project_dir="${TEST_TEMP}/no-pipeline-dir"
  mkdir -p "$project_dir"
  # Do NOT create .forge/

  run_hook_in "$FEEDBACK_HOOK" "$project_dir"
  assert_success
}

# 9. All hooks exit 0 on error conditions (no .forge at all)
@test "all hooks exit 0 when project has no .forge directory" {
  local project_dir="${TEST_TEMP}/bare-project"
  mkdir -p "$project_dir"

  run bash -c "cd '$project_dir' && bash '$CHECKPOINT_HOOK'"
  assert_success

  run bash -c "cd '$project_dir' && bash '$FEEDBACK_HOOK'"
  assert_success
}

# 10. Feedback hook appends (does not overwrite) on multiple runs
@test "feedback: appends on successive runs (does not overwrite)" {
  local project_dir="${TEST_TEMP}/feedback-append-project"
  mkdir -p "$project_dir/.forge/feedback"
  printf '[2000-01-01 00:00] Previous entry.\n' \
    > "$project_dir/.forge/feedback/auto-captured.md"

  run_hook_in "$FEEDBACK_HOOK" "$project_dir"
  assert_success

  local line_count
  line_count="$(wc -l < "$project_dir/.forge/feedback/auto-captured.md")"
  [ "$line_count" -ge 2 ]
}
