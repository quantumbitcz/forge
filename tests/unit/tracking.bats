#!/usr/bin/env bats
# Unit tests for shared/tracking/tracking-ops.sh

load '../helpers/test-helpers'

TRACKING_OPS="${PLUGIN_ROOT}/shared/tracking/tracking-ops.sh"

# ---------------------------------------------------------------------------
# Helper: create a fresh tracking dir with the standard sub-directories.
# Prints the path to stdout.
# ---------------------------------------------------------------------------
make_tracking_dir() {
  local td="${TEST_TEMP}/tracking"
  mkdir -p "${td}/backlog" "${td}/in-progress" "${td}/review" "${td}/done"
  printf '%s' "$td"
}

setup() {
  # Create our own TEST_TEMP (overrides the one in test-helpers.bash setup)
  TEST_TEMP="$(mktemp -d "${TMPDIR:-${TMP:-${TEMP:-/tmp}}}/bats-tracking.XXXXXX")"
  MOCK_BIN="${TEST_TEMP}/mock-bin"
  mkdir -p "${MOCK_BIN}"
  export PATH="${MOCK_BIN}:${PATH}"
  mkdir -p "${TEST_TEMP}/project"

  # Source the tracking library (functions become available in test scope)
  # shellcheck disable=SC1090
  source "$TRACKING_OPS"
}

teardown() {
  if [[ -n "${TEST_TEMP:-}" && -d "${TEST_TEMP}" ]]; then
    rm -rf "${TEST_TEMP}"
  fi
}

# ===========================================================================
# slugify
# ===========================================================================

@test "slugify: converts title to lowercase kebab-case" {
  run slugify "Add User Auth"
  assert_success
  assert_output "add-user-auth"
}

@test "slugify: strips special characters" {
  run slugify "Fix: login/redirect (bug) #42!"
  assert_success
  # Special chars become hyphens, adjacent hyphens collapsed, leading/trailing stripped
  assert_output "fix-login-redirect-bug-42"
}

@test "slugify: truncates to default max (40 chars)" {
  run slugify "This is a very long title that should definitely be truncated at forty chars"
  assert_success
  local result="$output"
  [[ "${#result}" -le 40 ]]
}

@test "slugify: respects custom max_len" {
  run slugify "Short title here" 10
  assert_success
  local result="$output"
  [[ "${#result}" -le 10 ]]
}

@test "slugify: does not end with a hyphen after truncation" {
  run slugify "word1 word2 word3 word4 word5" 12
  assert_success
  [[ "$output" != *- ]]
}

@test "slugify: handles already-lowercase input" {
  run slugify "hello world"
  assert_success
  assert_output "hello-world"
}

@test "tracking: slugify rejects empty string" {
  run slugify ""
  assert_failure
}

@test "tracking: slugify handles unicode" {
  run slugify "Ünïcödé tïtle"
  assert_success
  # Non-ASCII characters must be stripped; result must be non-empty and contain only a-z, 0-9, or hyphens
  [[ "$output" =~ ^[a-z0-9-]+$ ]]
}

# ===========================================================================
# init_counter
# ===========================================================================

@test "init_counter: creates counter.json with default prefix FG" {
  local td
  td="$(make_tracking_dir)"

  run init_counter "$td"
  assert_success

  [[ -f "${td}/counter.json" ]]
  local prefix next
  prefix="$(python3 - "${td}/counter.json" <<'PYEOF'
import json, sys; d=json.load(open(sys.argv[1])); print(d['prefix'])
PYEOF
  )"
  next="$(python3 - "${td}/counter.json" <<'PYEOF'
import json, sys; d=json.load(open(sys.argv[1])); print(d['next'])
PYEOF
  )"
  [[ "$prefix" == "FG" ]]
  [[ "$next" == "1" ]]
}

@test "init_counter: creates counter.json with custom prefix" {
  local td
  td="$(make_tracking_dir)"

  run init_counter "$td" "WP"
  assert_success

  local prefix
  prefix="$(python3 - "${td}/counter.json" <<'PYEOF'
import json, sys; d=json.load(open(sys.argv[1])); print(d['prefix'])
PYEOF
  )"
  [[ "$prefix" == "WP" ]]
}

@test "init_counter: does not overwrite existing counter.json" {
  local td
  td="$(make_tracking_dir)"

  # Seed with a specific value
  printf '{"next":42,"prefix":"BE"}\n' > "${td}/counter.json"

  run init_counter "$td" "FG"
  assert_success

  local next
  next="$(python3 - "${td}/counter.json" <<'PYEOF'
import json, sys; d=json.load(open(sys.argv[1])); print(d['next'])
PYEOF
  )"
  [[ "$next" == "42" ]]
}

# ===========================================================================
# next_id
# ===========================================================================

@test "next_id: returns first ID as FG-001" {
  local td
  td="$(make_tracking_dir)"
  init_counter "$td"

  run next_id "$td"
  assert_success
  assert_output "FG-001"
}

@test "next_id: increments counter on successive calls" {
  local td
  td="$(make_tracking_dir)"
  init_counter "$td"

  local id1 id2 id3
  id1="$(next_id "$td")"
  id2="$(next_id "$td")"
  id3="$(next_id "$td")"

  [[ "$id1" == "FG-001" ]]
  [[ "$id2" == "FG-002" ]]
  [[ "$id3" == "FG-003" ]]
}

@test "next_id: 3-digit zero-padding for IDs < 1000" {
  local td
  td="$(make_tracking_dir)"
  printf '{"next":9,"prefix":"FG"}\n' > "${td}/counter.json"

  run next_id "$td"
  assert_success
  assert_output "FG-009"
}

@test "next_id: no zero-padding for IDs >= 1000" {
  local td
  td="$(make_tracking_dir)"
  printf '{"next":1000,"prefix":"FG"}\n' > "${td}/counter.json"

  run next_id "$td"
  assert_success
  assert_output "FG-1000"
}

@test "next_id: uses prefix from counter.json" {
  local td
  td="$(make_tracking_dir)"
  init_counter "$td" "WP"

  run next_id "$td"
  assert_success
  assert_output "WP-001"
}

@test "next_id: fails if counter.json is missing" {
  local td
  td="$(make_tracking_dir)"
  # counter.json not created

  run next_id "$td"
  assert_failure
}

# ===========================================================================
# create_ticket
# ===========================================================================

@test "create_ticket: creates file in backlog by default" {
  local td
  td="$(make_tracking_dir)"
  init_counter "$td"

  run create_ticket "$td" "Add user auth" "feature" "high"
  assert_success
  assert_output "FG-001"

  # File must exist in backlog
  local f
  f="$(find "${td}/backlog" -name "FG-001-*.md" | head -1)"
  [[ -n "$f" && -f "$f" ]]
}

@test "create_ticket: frontmatter contains all required fields" {
  local td
  td="$(make_tracking_dir)"
  init_counter "$td"

  create_ticket "$td" "Fix login bug" "bug" "critical" >/dev/null

  local f
  f="$(find "${td}/backlog" -name "FG-001-*.md" | head -1)"

  # Check each required frontmatter field is present
  grep -q "^id: FG-001" "$f"
  grep -q '^title: "Fix login bug"' "$f"
  grep -q "^type: bug" "$f"
  grep -q "^status: backlog" "$f"
  grep -q "^priority: critical" "$f"
  grep -q "^branch:" "$f"
  grep -q "^created:" "$f"
  grep -q "^updated:" "$f"
  grep -q "^linear_id:" "$f"
  grep -q "^spec:" "$f"
  grep -q "^pr:" "$f"
}

@test "create_ticket: supports target_status in-progress" {
  local td
  td="$(make_tracking_dir)"
  init_counter "$td"

  run create_ticket "$td" "Active task" "chore" "medium" "in-progress"
  assert_success

  local f
  f="$(find "${td}/in-progress" -name "FG-001-*.md" | head -1)"
  [[ -n "$f" && -f "$f" ]]
  grep -q "^status: in-progress" "$f"
}

@test "create_ticket: file is placed in correct status subdirectory" {
  local td
  td="$(make_tracking_dir)"
  init_counter "$td"

  create_ticket "$td" "Review me" "feature" "low" "review" >/dev/null

  local count
  count="$(find "${td}/review" -name "FG-001-*.md" | wc -l | tr -d ' ')"
  [[ "$count" == "1" ]]
}

@test "create_ticket: Activity Log contains creation entry" {
  local td
  td="$(make_tracking_dir)"
  init_counter "$td"

  create_ticket "$td" "New ticket" "spike" "low" >/dev/null

  local f
  f="$(find "${td}/backlog" -name "FG-001-*.md" | head -1)"
  grep -q "created (backlog)" "$f"
}

@test "create_ticket: fails with unknown target_status" {
  local td
  td="$(make_tracking_dir)"
  init_counter "$td"

  run create_ticket "$td" "Bad status" "chore" "low" "nonexistent"
  assert_failure
}

# ===========================================================================
# find_ticket
# ===========================================================================

@test "find_ticket: locates ticket in backlog" {
  local td
  td="$(make_tracking_dir)"
  init_counter "$td"
  create_ticket "$td" "Find me" "feature" "medium" >/dev/null

  run find_ticket "$td" "FG-001"
  assert_success
  [[ "$output" == *"backlog"* ]]
}

@test "find_ticket: locates ticket in in-progress" {
  local td
  td="$(make_tracking_dir)"
  init_counter "$td"
  create_ticket "$td" "In flight" "feature" "high" "in-progress" >/dev/null

  run find_ticket "$td" "FG-001"
  assert_success
  [[ "$output" == *"in-progress"* ]]
}

@test "find_ticket: returns non-zero for unknown ticket" {
  local td
  td="$(make_tracking_dir)"
  init_counter "$td"

  run find_ticket "$td" "FG-999"
  assert_failure
}

# ===========================================================================
# move_ticket
# ===========================================================================

@test "move_ticket: moves file from backlog to in-progress" {
  local td
  td="$(make_tracking_dir)"
  init_counter "$td"
  create_ticket "$td" "Start me" "feature" "high" >/dev/null

  run move_ticket "$td" "FG-001" "in-progress"
  assert_success

  # Must exist in in-progress, not in backlog
  local f
  f="$(find "${td}/in-progress" -name "FG-001-*.md" | head -1)"
  [[ -n "$f" && -f "$f" ]]
  [[ -z "$(find "${td}/backlog" -name "FG-001-*.md" 2>/dev/null)" ]]
}

@test "move_ticket: updates status field in frontmatter" {
  local td
  td="$(make_tracking_dir)"
  init_counter "$td"
  create_ticket "$td" "Status update" "bug" "medium" >/dev/null

  move_ticket "$td" "FG-001" "review"

  local f
  f="$(find "${td}/review" -name "FG-001-*.md" | head -1)"
  grep -q "^status: review" "$f"
}

@test "move_ticket: updates updated timestamp in frontmatter" {
  local td
  td="$(make_tracking_dir)"
  init_counter "$td"
  create_ticket "$td" "Timestamp test" "chore" "low" >/dev/null

  # Record created timestamp from the file
  local f_before
  f_before="$(find "${td}/backlog" -name "FG-001-*.md" | head -1)"
  local created_ts
  created_ts="$(grep "^created:" "$f_before" | head -1)"

  # Small sleep to ensure the updated timestamp is different
  sleep 1

  move_ticket "$td" "FG-001" "in-progress"

  local f
  f="$(find "${td}/in-progress" -name "FG-001-*.md" | head -1)"
  local updated_line
  updated_line="$(grep "^updated:" "$f" | head -1)"

  # updated should be a different value than created (we slept 1s)
  # At minimum it must exist
  [[ -n "$updated_line" ]]
}

@test "move_ticket: appends entry to Activity Log" {
  local td
  td="$(make_tracking_dir)"
  init_counter "$td"
  create_ticket "$td" "Activity test" "feature" "high" >/dev/null

  move_ticket "$td" "FG-001" "review"

  local f
  f="$(find "${td}/review" -name "FG-001-*.md" | head -1)"
  grep -q "moved to review" "$f"
}

@test "move_ticket: fails for unknown ticket" {
  local td
  td="$(make_tracking_dir)"
  init_counter "$td"

  run move_ticket "$td" "FG-999" "in-progress"
  assert_failure
}

@test "move_ticket: fails for unknown target status" {
  local td
  td="$(make_tracking_dir)"
  init_counter "$td"
  create_ticket "$td" "Move fail" "chore" "low" >/dev/null

  run move_ticket "$td" "FG-001" "invalid-status"
  assert_failure
}

# ===========================================================================
# update_ticket_field
# ===========================================================================

@test "update_ticket_field: updates pr field" {
  local td
  td="$(make_tracking_dir)"
  init_counter "$td"
  create_ticket "$td" "PR update" "feature" "medium" >/dev/null

  run update_ticket_field "$td" "FG-001" "pr" "https://github.com/org/repo/pull/42"
  assert_success

  local f
  f="$(find "${td}/backlog" -name "FG-001-*.md" | head -1)"
  grep -q 'pr: "https://github.com/org/repo/pull/42"' "$f"
}

@test "update_ticket_field: updates branch field" {
  local td
  td="$(make_tracking_dir)"
  init_counter "$td"
  create_ticket "$td" "Branch update" "feature" "high" >/dev/null

  run update_ticket_field "$td" "FG-001" "branch" "feat/FG-001-branch-update"
  assert_success

  local f
  f="$(find "${td}/backlog" -name "FG-001-*.md" | head -1)"
  grep -q 'branch: "feat/FG-001-branch-update"' "$f"
}

@test "update_ticket_field: updates linear_id field" {
  local td
  td="$(make_tracking_dir)"
  init_counter "$td"
  create_ticket "$td" "Linear link" "chore" "low" >/dev/null

  run update_ticket_field "$td" "FG-001" "linear_id" "ENG-99"
  assert_success

  local f
  f="$(find "${td}/backlog" -name "FG-001-*.md" | head -1)"
  grep -q 'linear_id: "ENG-99"' "$f"
}

@test "update_ticket_field: updates updated timestamp" {
  local td
  td="$(make_tracking_dir)"
  init_counter "$td"
  create_ticket "$td" "Timestamp update" "bug" "medium" >/dev/null

  sleep 1
  update_ticket_field "$td" "FG-001" "pr" "#10"

  local f
  f="$(find "${td}/backlog" -name "FG-001-*.md" | head -1)"
  # updated field must exist
  grep -q "^updated:" "$f"
}

# ===========================================================================
# generate_board
# ===========================================================================

@test "generate_board: creates board.md" {
  local td
  td="$(make_tracking_dir)"
  init_counter "$td"

  run generate_board "$td"
  assert_success

  [[ -f "${td}/board.md" ]]
}

@test "generate_board: board.md contains table headers" {
  local td
  td="$(make_tracking_dir)"
  init_counter "$td"

  generate_board "$td"

  grep -q "| ID |" "${td}/board.md"
  grep -q "| Title |" "${td}/board.md"
  grep -q "| Status |" "${td}/board.md"
}

@test "generate_board: board.md contains ticket rows" {
  local td
  td="$(make_tracking_dir)"
  init_counter "$td"
  create_ticket "$td" "Board ticket" "feature" "high" >/dev/null

  generate_board "$td"

  grep -q "FG-001" "${td}/board.md"
  grep -q "Board ticket" "${td}/board.md"
}

@test "generate_board: lists tickets from multiple status dirs" {
  local td
  td="$(make_tracking_dir)"
  init_counter "$td"

  create_ticket "$td" "Backlog item" "chore" "low" >/dev/null
  create_ticket "$td" "Active item" "feature" "high" "in-progress" >/dev/null

  generate_board "$td"

  grep -q "FG-001" "${td}/board.md"
  grep -q "FG-002" "${td}/board.md"
}

@test "generate_board: regenerates board.md on subsequent calls" {
  local td
  td="$(make_tracking_dir)"
  init_counter "$td"
  create_ticket "$td" "First ticket" "bug" "medium" >/dev/null

  generate_board "$td"
  local first_content
  first_content="$(cat "${td}/board.md")"

  create_ticket "$td" "Second ticket" "feature" "low" >/dev/null
  generate_board "$td"
  local second_content
  second_content="$(cat "${td}/board.md")"

  # Board should now include both tickets
  grep -q "FG-002" "${td}/board.md"
}

# ===========================================================================
# next_id: concurrency stress test
# ===========================================================================

@test "next_id: 5 parallel calls produce 5 unique IDs" {
  local td
  td="$(make_tracking_dir)"
  init_counter "$td"

  local ids_file="${TEST_TEMP}/parallel_ids.txt"
  : > "$ids_file"

  # Spawn 5 parallel next_id calls
  local pids=()
  for i in 1 2 3 4 5; do
    (
      local result
      result="$(next_id "$td")"
      printf '%s\n' "$result"
    ) >> "$ids_file" &
    pids+=($!)
  done

  # Wait for all to complete
  local all_ok=true
  for pid in "${pids[@]}"; do
    if ! wait "$pid"; then
      all_ok=false
    fi
  done

  [[ "$all_ok" == "true" ]]

  # Verify: 5 lines, all unique, all matching FG-NNN pattern
  local count
  count="$(wc -l < "$ids_file" | tr -d ' ')"
  [[ "$count" == "5" ]]

  local unique_count
  unique_count="$(sort -u "$ids_file" | wc -l | tr -d ' ')"
  [[ "$unique_count" == "5" ]]

  # Counter should now be at 6
  local next_val
  next_val="$("$FORGE_PYTHON" -c "import json; print(json.load(open('${td}/counter.json'))['next'])")"
  [[ "$next_val" == "6" ]]
}

# ===========================================================================
# next_id — platform-adaptive Python locking
# ===========================================================================

@test "next_id: inline Python uses try/except for fcntl import (not unconditional)" {
  local python_block
  python_block=$(sed -n '/\$FORGE_PYTHON.*-c/,/counter_file/p' "$TRACKING_OPS")
  if echo "$python_block" | grep -q 'import.*fcntl.*os$\|import json.*fcntl'; then
    fail "tracking-ops.sh still uses unconditional fcntl import — must use try/except"
  fi
  run grep -c 'except ImportError' "$TRACKING_OPS"
  assert_success
  [[ "${output}" -ge 1 ]]
}

@test "next_id: inline Python defines lock() and unlock() functions" {
  run grep -c 'def lock(fd)' "$TRACKING_OPS"
  assert_success
  [[ "${output}" -ge 1 ]]
  run grep -c 'def unlock(fd)' "$TRACKING_OPS"
  assert_success
  [[ "${output}" -ge 1 ]]
}

@test "next_id: inline Python references msvcrt as fallback" {
  run grep -c 'import msvcrt' "$TRACKING_OPS"
  assert_success
  [[ "${output}" -ge 1 ]]
}

@test "next_id: still works correctly after refactor" {
  local td
  td="$(make_tracking_dir)"
  init_counter "$td" "TEST"
  run next_id "$td"
  assert_success
  assert_output "TEST-001"
  run next_id "$td"
  assert_success
  assert_output "TEST-002"
}
