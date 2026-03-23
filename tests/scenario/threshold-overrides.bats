#!/usr/bin/env bats
# Scenario tests: threshold overrides (file size and function size)

load '../helpers/test-helpers'

RUN_PATTERNS="$PLUGIN_ROOT/shared/checks/layer-1-fast/run-patterns.sh"
KOTLIN_RULES="$PLUGIN_ROOT/shared/checks/layer-1-fast/patterns/kotlin.json"
KS_OVERRIDE="$PLUGIN_ROOT/modules/frameworks/spring/rules-override.json"

setup() {
  TEST_TEMP="$(mktemp -d "${TMPDIR:-/tmp}/bats-thresholds.XXXXXX")"
  MOCK_BIN="$TEST_TEMP/mock-bin"
  mkdir -p "$MOCK_BIN"
  export PATH="$MOCK_BIN:$PATH"
  git init -q "$TEST_TEMP/project"
  git -C "$TEST_TEMP/project" config user.email "t@t.com"
  git -C "$TEST_TEMP/project" config user.name "T"
}

teardown() { rm -rf "$TEST_TEMP"; }

# ---------------------------------------------------------------------------
# 1. Default kotlin threshold 300 lines → QUAL-READ for 305-line file
# ---------------------------------------------------------------------------
@test "threshold: kotlin file over 300 lines triggers QUAL-READ WARNING (base rules)" {
  local kt_file="$TEST_TEMP/project/src/main/kotlin/BigFile.kt"
  mkdir -p "$(dirname "$kt_file")"
  python3 -c "
for i in range(305):
    print('// line %d' % i)
" > "$kt_file"

  run bash "$RUN_PATTERNS" "$kt_file" "$KOTLIN_RULES"

  assert_success
  assert_output --partial "QUAL-READ"
  assert_output --partial "WARNING"
}

# ---------------------------------------------------------------------------
# 2. Path-specific override: port/ gets threshold 100 (spring)
# ---------------------------------------------------------------------------
@test "threshold: spring override lowers port/ threshold to 100 lines" {
  local kt_file="$TEST_TEMP/project/src/main/kotlin/port/BigPort.kt"
  mkdir -p "$(dirname "$kt_file")"
  # 105 comment lines — under the 300 default but above the 100 port/ threshold
  python3 -c "
for i in range(105):
    print('// line %d' % i)
" > "$kt_file"

  run bash "$RUN_PATTERNS" "$kt_file" "$KOTLIN_RULES" "$KS_OVERRIDE"

  assert_success
  assert_output --partial "QUAL-READ"
  assert_output --partial "WARNING"
}

# ---------------------------------------------------------------------------
# 3. Path-specific override: adapter/ gets threshold 200 (spring)
# ---------------------------------------------------------------------------
@test "threshold: spring override sets adapter/ threshold to 200 lines" {
  local kt_file="$TEST_TEMP/project/src/main/kotlin/adapter/BigAdapter.kt"
  mkdir -p "$(dirname "$kt_file")"
  # 205 comment lines — above the 200 adapter/ threshold
  python3 -c "
for i in range(205):
    print('// line %d' % i)
" > "$kt_file"

  run bash "$RUN_PATTERNS" "$kt_file" "$KOTLIN_RULES" "$KS_OVERRIDE"

  assert_success
  assert_output --partial "QUAL-READ"
  assert_output --partial "WARNING"

  # And a file with 195 lines should be within the adapter/ threshold
  local small_adapter="$TEST_TEMP/project/src/main/kotlin/adapter/SmallAdapter.kt"
  python3 -c "
for i in range(195):
    print('// line %d' % i)
" > "$small_adapter"

  run bash "$RUN_PATTERNS" "$small_adapter" "$KOTLIN_RULES" "$KS_OVERRIDE"

  assert_success
  refute_output --partial "QUAL-READ"
}

# ---------------------------------------------------------------------------
# 4. Large Kotlin function (>30 lines) is detected
# ---------------------------------------------------------------------------
@test "threshold: kotlin function exceeding 30 lines emits function size QUAL-READ" {
  local kt_file="$TEST_TEMP/project/src/main/kotlin/LargeFunc.kt"
  mkdir -p "$(dirname "$kt_file")"
  {
    printf 'package com.example\n'
    printf 'fun bigFunction() {\n'
    for i in $(seq 1 35); do
      printf '    // step %d\n' "$i"
    done
    printf '}\n'
  } > "$kt_file"

  run bash "$RUN_PATTERNS" "$kt_file" "$KOTLIN_RULES"

  assert_success
  assert_output --partial "QUAL-READ"
  assert_output --partial "bigFunction"
}

# ---------------------------------------------------------------------------
# 5. Function within limit is silent
# ---------------------------------------------------------------------------
@test "threshold: kotlin function within 30 lines emits no function size warning" {
  local kt_file="$TEST_TEMP/project/src/main/kotlin/SmallFunc.kt"
  mkdir -p "$(dirname "$kt_file")"
  {
    printf 'package com.example\n'
    printf 'fun smallFunction() {\n'
    for i in $(seq 1 10); do
      printf '    // step %d\n' "$i"
    done
    printf '}\n'
  } > "$kt_file"

  run bash "$RUN_PATTERNS" "$kt_file" "$KOTLIN_RULES"

  assert_success
  assert_output ""
}
