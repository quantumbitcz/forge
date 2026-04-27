#!/usr/bin/env bash

# Covers:

setup() {
  load '../lib/bats-support/load'
  load '../lib/bats-assert/load'
  PLUGIN_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  source "$PLUGIN_ROOT/shared/tracking/tracking-ops.sh"
  TEST_TEMP="$(mktemp -d)"
  export FORGE_DIR="$TEST_TEMP/.forge"
  mkdir -p "$FORGE_DIR/tracking/backlog" "$FORGE_DIR/tracking/in-progress" "$FORGE_DIR/tracking/review" "$FORGE_DIR/tracking/done"
  init_counter "$FORGE_DIR/tracking"
}

teardown() {
  rm -rf "$TEST_TEMP"
}

# --- Full lifecycle ---

@test "lifecycle: create -> in-progress -> review -> done" {
  create_ticket "$FORGE_DIR/tracking" "Feature A" "feature" "medium"
  [ -f "$FORGE_DIR/tracking/backlog/FG-001-feature-a.md" ]

  move_ticket "$FORGE_DIR/tracking" "FG-001" "in-progress"
  [ -f "$FORGE_DIR/tracking/in-progress/FG-001-feature-a.md" ]
  [ ! -f "$FORGE_DIR/tracking/backlog/FG-001-feature-a.md" ]

  move_ticket "$FORGE_DIR/tracking" "FG-001" "review"
  [ -f "$FORGE_DIR/tracking/review/FG-001-feature-a.md" ]
  [ ! -f "$FORGE_DIR/tracking/in-progress/FG-001-feature-a.md" ]

  move_ticket "$FORGE_DIR/tracking" "FG-001" "done"
  [ -f "$FORGE_DIR/tracking/done/FG-001-feature-a.md" ]
  [ ! -f "$FORGE_DIR/tracking/review/FG-001-feature-a.md" ]
}

@test "lifecycle: PR rejection moves review -> in-progress" {
  create_ticket "$FORGE_DIR/tracking" "Feature B" "feature" "high"
  move_ticket "$FORGE_DIR/tracking" "FG-001" "in-progress"
  move_ticket "$FORGE_DIR/tracking" "FG-001" "review"
  move_ticket "$FORGE_DIR/tracking" "FG-001" "in-progress"
  [ -f "$FORGE_DIR/tracking/in-progress/FG-001-feature-b.md" ]
  # Activity log should have entries for all moves
  local count
  count=$(grep -c "Moved to\|Created\|moved to\|created" "$FORGE_DIR/tracking/in-progress/FG-001-feature-b.md")
  [ "$count" -ge 4 ]
}

@test "lifecycle: abort moves in-progress -> backlog" {
  create_ticket "$FORGE_DIR/tracking" "Feature C" "feature" "low"
  move_ticket "$FORGE_DIR/tracking" "FG-001" "in-progress"
  move_ticket "$FORGE_DIR/tracking" "FG-001" "backlog"
  [ -f "$FORGE_DIR/tracking/backlog/FG-001-feature-c.md" ]
}

@test "lifecycle: multiple tickets tracked independently" {
  create_ticket "$FORGE_DIR/tracking" "Feature A" "feature" "medium"
  create_ticket "$FORGE_DIR/tracking" "Bug B" "bugfix" "critical"
  move_ticket "$FORGE_DIR/tracking" "FG-001" "in-progress"
  [ -f "$FORGE_DIR/tracking/in-progress/FG-001-feature-a.md" ]
  [ -f "$FORGE_DIR/tracking/backlog/FG-002-bug-b.md" ]
}

@test "lifecycle: board reflects current state after moves" {
  create_ticket "$FORGE_DIR/tracking" "Feature A" "feature" "medium"
  create_ticket "$FORGE_DIR/tracking" "Bug B" "bugfix" "high"
  move_ticket "$FORGE_DIR/tracking" "FG-001" "in-progress"
  generate_board "$FORGE_DIR/tracking"
  grep -q "in-progress\|In Progress\|FG-001" "$FORGE_DIR/tracking/board.md"
  grep -q "backlog\|Backlog\|FG-002" "$FORGE_DIR/tracking/board.md"
}

@test "lifecycle: update_ticket_field sets PR URL" {
  create_ticket "$FORGE_DIR/tracking" "Feature A" "feature" "medium"
  update_ticket_field "$FORGE_DIR/tracking" "FG-001" "pr" "https://github.com/org/repo/pull/1"
  grep -q "^pr: \"https://github.com/org/repo/pull/1\"$" "$FORGE_DIR/tracking/backlog/FG-001-feature-a.md"
}

@test "lifecycle: create with custom prefix" {
  echo '{"next": 1, "prefix": "WP"}' > "$FORGE_DIR/tracking/counter.json"
  run create_ticket "$FORGE_DIR/tracking" "Custom prefix" "feature" "low"
  assert_output "WP-001"
  [ -f "$FORGE_DIR/tracking/backlog/WP-001-custom-prefix.md" ]
}

@test "lifecycle: create ticket directly in in-progress" {
  run create_ticket "$FORGE_DIR/tracking" "Urgent fix" "bugfix" "critical" "in-progress"
  assert_success
  assert_output "FG-001"
  [ -f "$FORGE_DIR/tracking/in-progress/FG-001-urgent-fix.md" ]
  [ ! -f "$FORGE_DIR/tracking/backlog/FG-001-urgent-fix.md" ]
}

@test "lifecycle: final status in frontmatter matches directory" {
  create_ticket "$FORGE_DIR/tracking" "Track status" "feature" "medium"
  move_ticket "$FORGE_DIR/tracking" "FG-001" "in-progress"
  move_ticket "$FORGE_DIR/tracking" "FG-001" "review"
  grep -q "^status: review$" "$FORGE_DIR/tracking/review/FG-001-track-status.md"
}

@test "lifecycle: updated timestamp changes on move" {
  create_ticket "$FORGE_DIR/tracking" "Timestamp test" "feature" "low"
  local created
  created=$(grep "^created:" "$FORGE_DIR/tracking/backlog/FG-001-timestamp-test.md" | sed 's/^created: *//')
  sleep 1
  move_ticket "$FORGE_DIR/tracking" "FG-001" "in-progress"
  local updated
  updated=$(grep "^updated:" "$FORGE_DIR/tracking/in-progress/FG-001-timestamp-test.md" | sed 's/^updated: *//')
  [ "$created" != "$updated" ]
}
