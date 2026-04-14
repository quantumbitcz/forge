#!/usr/bin/env bats
# Tests for shared/caveman-benchmark.sh

load '../helpers/test-helpers'

SCRIPT="$PLUGIN_ROOT/shared/caveman-benchmark.sh"

@test "caveman-benchmark: script exists and is executable" {
  assert [ -f "$SCRIPT" ]
  assert [ -x "$SCRIPT" ]
}

@test "caveman-benchmark: exits 0 with valid input file" {
  run bash "$SCRIPT" "$PLUGIN_ROOT/CLAUDE.md"
  assert_success
}

@test "caveman-benchmark: outputs benchmark table" {
  run bash "$SCRIPT" "$PLUGIN_ROOT/CLAUDE.md"
  assert_success
  assert_output --partial "Caveman Benchmark"
  assert_output --partial "original"
  assert_output --partial "lite"
  assert_output --partial "full"
  assert_output --partial "ultra"
}

@test "caveman-benchmark: outputs JSON line" {
  run bash "$SCRIPT" "$PLUGIN_ROOT/CLAUDE.md"
  assert_success
  assert_output --partial "JSON:"
  local json_line
  json_line=$(echo "$output" | grep "^JSON:" | sed 's/^JSON: //')
  echo "$json_line" | python3 -c "import json,sys; d=json.load(sys.stdin); assert 'original_tokens' in d"
}

@test "caveman-benchmark: exits 1 with nonexistent file" {
  run bash "$SCRIPT" "/tmp/nonexistent-file-12345.md"
  assert_failure
  assert_output --partial "ERROR"
}
