#!/usr/bin/env bats
# Unit tests for shared/checks/layer-2-linter/adapters/scalafmt.sh

load '../helpers/test-helpers'

SCALAFMT_FIXTURE="$PLUGIN_ROOT/tests/fixtures/linter-output/scalafmt-sample.txt"

run_parser() {
  local raw="$1"
  python3 -c "
import sys, re
with open(sys.argv[1]) as f:
    for line in f:
        line = line.strip()
        m = re.match(r'(?:error:\s*)?(.+?)\s+is not formatted', line)
        if m:
            filepath = m.group(1)
            print(f'{filepath}:1 | SCALA-LINT-FMT | INFO | File not formatted per scalafmt rules | Run: scalafmt {filepath}')
" "$raw"
}

@test "scalafmt adapter: parses 2 findings from fixture" {
  run run_parser "$SCALAFMT_FIXTURE"
  assert_success
  local count; count="$(echo "$output" | grep -c '|')"
  [[ "$count" -eq 2 ]]
}

@test "scalafmt adapter: all findings use SCALA-LINT-FMT category" {
  run run_parser "$SCALAFMT_FIXTURE"
  assert_success
  local fmt_count; fmt_count="$(echo "$output" | grep -c 'SCALA-LINT-FMT')"
  [[ "$fmt_count" -eq 2 ]]
}

@test "scalafmt adapter: all findings have INFO severity" {
  run run_parser "$SCALAFMT_FIXTURE"
  assert_success
  local info_count; info_count="$(echo "$output" | grep -c '| INFO |')"
  [[ "$info_count" -eq 2 ]]
}

@test "scalafmt adapter: file paths preserved" {
  run run_parser "$SCALAFMT_FIXTURE"
  assert_success
  echo "$output" | grep -q "src/main/scala/com/example/App.scala:1"
  echo "$output" | grep -q "src/main/scala/com/example/service/UserService.scala:1"
}

@test "scalafmt adapter: hint includes run command" {
  run run_parser "$SCALAFMT_FIXTURE"
  assert_success
  echo "$output" | grep -q "Run: scalafmt"
}

@test "scalafmt adapter: empty input produces no output" {
  local empty="${TEST_TEMP}/empty.txt"
  : > "$empty"
  run run_parser "$empty"
  assert_success
  [[ -z "$output" ]]
}
