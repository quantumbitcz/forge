#!/usr/bin/env bats
# Unit tests: atomic_increment and atomic_json_update from shared/platform.sh

load '../helpers/test-helpers'

PLATFORM_SH="$PLUGIN_ROOT/shared/platform.sh"

# ---------------------------------------------------------------------------
# atomic_increment
# ---------------------------------------------------------------------------

@test "atomic_increment: increments from 0 when file does not exist" {
  source "$PLATFORM_SH"
  local counter_file="$TEST_TEMP/counter"

  run atomic_increment "$counter_file"
  assert_success
  assert_output "1"
  assert_equal "$(cat "$counter_file")" "1"
}

@test "atomic_increment: increments existing value" {
  source "$PLATFORM_SH"
  local counter_file="$TEST_TEMP/counter"
  echo "5" > "$counter_file"

  run atomic_increment "$counter_file"
  assert_success
  assert_output "6"
  assert_equal "$(cat "$counter_file")" "6"
}

@test "atomic_increment: handles corrupted file (non-numeric content)" {
  source "$PLATFORM_SH"
  local counter_file="$TEST_TEMP/counter"
  echo "not-a-number" > "$counter_file"

  run atomic_increment "$counter_file"
  assert_success
  assert_output "1"
}

@test "atomic_increment: sequential calls produce monotonic values" {
  source "$PLATFORM_SH"
  local counter_file="$TEST_TEMP/counter"

  atomic_increment "$counter_file" >/dev/null
  atomic_increment "$counter_file" >/dev/null
  run atomic_increment "$counter_file"
  assert_success
  assert_output "3"
}

# ---------------------------------------------------------------------------
# atomic_json_update
# ---------------------------------------------------------------------------

@test "atomic_json_update: updates a field in JSON file" {
  source "$PLATFORM_SH"
  local json_file="$TEST_TEMP/test.json"
  echo '{"name": "old", "count": 0}' > "$json_file"

  run atomic_json_update "$json_file" "data['name'] = 'new'"
  assert_success

  local value
  value=$(python3 -c "import json; print(json.load(open('$json_file'))['name'])")
  assert_equal "$value" "new"
}

@test "atomic_json_update: preserves other fields" {
  source "$PLATFORM_SH"
  local json_file="$TEST_TEMP/test.json"
  echo '{"name": "keep", "count": 42}' > "$json_file"

  run atomic_json_update "$json_file" "data['name'] = 'changed'"
  assert_success

  local count
  count=$(python3 -c "import json; print(json.load(open('$json_file'))['count'])")
  assert_equal "$count" "42"
}

@test "atomic_json_update: fails gracefully on invalid JSON" {
  source "$PLATFORM_SH"
  local json_file="$TEST_TEMP/test.json"
  echo 'not json {{{' > "$json_file"

  run atomic_json_update "$json_file" "data['x'] = 1"
  assert_failure
}

@test "atomic_json_update: fails gracefully when file missing" {
  source "$PLATFORM_SH"
  local json_file="$TEST_TEMP/nonexistent.json"

  run atomic_json_update "$json_file" "data['x'] = 1"
  assert_failure
}
