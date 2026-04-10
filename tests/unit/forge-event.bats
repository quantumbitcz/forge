#!/usr/bin/env bats
# Unit tests: forge-event.sh — structured pipeline event emitter.

load '../helpers/test-helpers'

SCRIPT="$PLUGIN_ROOT/shared/forge-event.sh"

# ---------------------------------------------------------------------------
# 1. Script exists and is executable
# ---------------------------------------------------------------------------
@test "forge-event: script exists and is executable" {
  assert [ -f "$SCRIPT" ]
  assert [ -x "$SCRIPT" ]
}

@test "forge-event: has bash shebang" {
  local first_line
  first_line=$(head -1 "$SCRIPT")
  assert_equal "$first_line" "#!/usr/bin/env bash"
}

# ---------------------------------------------------------------------------
# 2. Emits valid JSON line
# ---------------------------------------------------------------------------
@test "forge-event: emits valid JSON line" {
  local forge_dir="${TEST_TEMP}/project/.forge"
  mkdir -p "$forge_dir"

  run bash "$SCRIPT" state_transition --field from=PREFLIGHT --field to=EXPLORING --forge-dir "$forge_dir"
  assert_success

  # Verify the events file has exactly one line of valid JSON
  assert [ -f "$forge_dir/events.jsonl" ]
  local line_count
  line_count=$(wc -l < "$forge_dir/events.jsonl" | tr -d ' ')
  [[ "$line_count" -eq 1 ]] || fail "Expected 1 line, got $line_count"

  # Validate JSON
  run python3 -c "
import json
with open('$forge_dir/events.jsonl') as f:
    for line in f:
        json.loads(line)
"
  assert_success
}

# ---------------------------------------------------------------------------
# 3. Timestamp in ISO 8601
# ---------------------------------------------------------------------------
@test "forge-event: timestamp in ISO 8601 format" {
  local forge_dir="${TEST_TEMP}/project/.forge"
  mkdir -p "$forge_dir"

  bash "$SCRIPT" test_event --forge-dir "$forge_dir"

  python3 -c "
import json, re
with open('$forge_dir/events.jsonl') as f:
    event = json.loads(f.readline())
ts = event['ts']
# ISO 8601 pattern: YYYY-MM-DDTHH:MM:SS or with timezone
assert re.match(r'\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}', ts), f'Bad timestamp: {ts}'
" || fail "Timestamp is not ISO 8601"
}

# ---------------------------------------------------------------------------
# 4. Seq increments monotonically
# ---------------------------------------------------------------------------
@test "forge-event: seq increments monotonically" {
  local forge_dir="${TEST_TEMP}/project/.forge"
  mkdir -p "$forge_dir"

  bash "$SCRIPT" event_a --forge-dir "$forge_dir"
  bash "$SCRIPT" event_b --forge-dir "$forge_dir"

  python3 -c "
import json
with open('$forge_dir/events.jsonl') as f:
    lines = [json.loads(line) for line in f]
assert len(lines) == 2, f'Expected 2 events, got {len(lines)}'
assert lines[0]['seq'] == 1, f'First seq: {lines[0][\"seq\"]}'
assert lines[1]['seq'] == 2, f'Second seq: {lines[1][\"seq\"]}'
" || fail "Seq does not increment monotonically"
}

# ---------------------------------------------------------------------------
# 5. Event type stored correctly
# ---------------------------------------------------------------------------
@test "forge-event: event type stored correctly" {
  local forge_dir="${TEST_TEMP}/project/.forge"
  mkdir -p "$forge_dir"

  bash "$SCRIPT" state_transition --forge-dir "$forge_dir"

  python3 -c "
import json
with open('$forge_dir/events.jsonl') as f:
    event = json.loads(f.readline())
assert event['event'] == 'state_transition', f'Event type: {event[\"event\"]}'
" || fail "Event type not stored correctly"
}

# ---------------------------------------------------------------------------
# 6. Fields stored as key-value pairs
# ---------------------------------------------------------------------------
@test "forge-event: fields stored as key-value pairs" {
  local forge_dir="${TEST_TEMP}/project/.forge"
  mkdir -p "$forge_dir"

  bash "$SCRIPT" state_transition --field from=IMPLEMENTING --field to=VERIFYING --forge-dir "$forge_dir"

  python3 -c "
import json
with open('$forge_dir/events.jsonl') as f:
    event = json.loads(f.readline())
assert event['fields']['from'] == 'IMPLEMENTING', f'from: {event[\"fields\"][\"from\"]}'
assert event['fields']['to'] == 'VERIFYING', f'to: {event[\"fields\"][\"to\"]}'
" || fail "Fields not stored correctly"
}

# ---------------------------------------------------------------------------
# 7. Appends to existing file (does not overwrite)
# ---------------------------------------------------------------------------
@test "forge-event: appends to existing file" {
  local forge_dir="${TEST_TEMP}/project/.forge"
  mkdir -p "$forge_dir"

  bash "$SCRIPT" first_event --forge-dir "$forge_dir"
  bash "$SCRIPT" second_event --forge-dir "$forge_dir"

  local line_count
  line_count=$(wc -l < "$forge_dir/events.jsonl" | tr -d ' ')
  [[ "$line_count" -eq 2 ]] || fail "Expected 2 lines (append), got $line_count"

  # Verify both events are valid and have correct types
  python3 -c "
import json
with open('$forge_dir/events.jsonl') as f:
    lines = [json.loads(line) for line in f]
assert lines[0]['event'] == 'first_event'
assert lines[1]['event'] == 'second_event'
" || fail "Appended events not valid"
}

# ---------------------------------------------------------------------------
# 8. Run ID from state.json if available
# ---------------------------------------------------------------------------
@test "forge-event: reads run_id from state.json if available" {
  local forge_dir="${TEST_TEMP}/project/.forge"
  mkdir -p "$forge_dir"

  # Create a minimal state.json with story_id (the run identifier)
  echo '{"story_id": "feat-test-123", "_seq": 1}' > "$forge_dir/state.json"

  bash "$SCRIPT" test_event --forge-dir "$forge_dir"

  python3 -c "
import json
with open('$forge_dir/events.jsonl') as f:
    event = json.loads(f.readline())
assert event.get('run_id') == 'feat-test-123', f'run_id: {event.get(\"run_id\")}'
" || fail "run_id not read from state.json"
}

# ---------------------------------------------------------------------------
# 9. Missing forge-dir creates file
# ---------------------------------------------------------------------------
@test "forge-event: creates events.jsonl if it does not exist" {
  local forge_dir="${TEST_TEMP}/project/.forge"
  mkdir -p "$forge_dir"
  # Ensure events.jsonl does not exist
  rm -f "$forge_dir/events.jsonl"

  bash "$SCRIPT" test_event --forge-dir "$forge_dir"

  assert [ -f "$forge_dir/events.jsonl" ]
}

# ---------------------------------------------------------------------------
# 10. No event type = error
# ---------------------------------------------------------------------------
@test "forge-event: missing event type exits with error" {
  local forge_dir="${TEST_TEMP}/project/.forge"
  mkdir -p "$forge_dir"

  run bash "$SCRIPT" --forge-dir "$forge_dir"
  assert_failure
}
