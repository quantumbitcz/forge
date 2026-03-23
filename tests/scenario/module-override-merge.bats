#!/usr/bin/env bats
# Scenario tests: module-level override merging in the check engine

load '../helpers/test-helpers'

RUN_PATTERNS="$PLUGIN_ROOT/shared/checks/layer-1-fast/run-patterns.sh"
KOTLIN_RULES="$PLUGIN_ROOT/shared/checks/layer-1-fast/patterns/kotlin.json"
KS_OVERRIDE="$PLUGIN_ROOT/modules/frameworks/spring/rules-override.json"
OVERRIDE_ADD="$PLUGIN_ROOT/tests/fixtures/overrides/add-rules.json"
OVERRIDE_DISABLE="$PLUGIN_ROOT/tests/fixtures/overrides/disable-rules.json"
OVERRIDE_EMPTY="$PLUGIN_ROOT/tests/fixtures/overrides/empty.json"

setup() {
  TEST_TEMP="$(mktemp -d "${TMPDIR:-/tmp}/bats-override-merge.XXXXXX")"
  MOCK_BIN="$TEST_TEMP/mock-bin"
  mkdir -p "$MOCK_BIN"
  export PATH="$MOCK_BIN:$PATH"
  git init -q "$TEST_TEMP/project"
  git -C "$TEST_TEMP/project" config user.email "t@t.com"
  git -C "$TEST_TEMP/project" config user.name "T"
}

teardown() { rm -rf "$TEST_TEMP"; }

# ---------------------------------------------------------------------------
# 1. spring adds ARCH-BOUNDARY rule (core/ importing from adapter)
# ---------------------------------------------------------------------------
@test "module-override: spring additional_boundaries detects core->adapter import" {
  # core/src/main matches the scope_pattern "core/src/main"
  local kt_file="$TEST_TEMP/project/core/src/main/Service.kt"
  mkdir -p "$(dirname "$kt_file")"
  printf 'package com.example.core\nimport com.example.app.adapter.UserAdapter\n' > "$kt_file"

  run bash "$RUN_PATTERNS" "$kt_file" "$KOTLIN_RULES" "$KS_OVERRIDE"

  assert_success
  assert_output --partial "ARCH-BOUNDARY"
}

# ---------------------------------------------------------------------------
# 2. disabled_rules suppresses KT-NULL-001 (!! not detected)
# ---------------------------------------------------------------------------
@test "module-override: disabled_rules suppresses KT-NULL-001 (!! not flagged)" {
  local kt_file="$TEST_TEMP/project/src/main/kotlin/HasBang.kt"
  mkdir -p "$(dirname "$kt_file")"
  printf 'package com.example\nval x = value!!\n' > "$kt_file"

  run bash "$RUN_PATTERNS" "$kt_file" "$KOTLIN_RULES" "$OVERRIDE_DISABLE"

  assert_success
  refute_output --partial "QUAL-NULL"
}

# ---------------------------------------------------------------------------
# 3. severity_overrides changes KT-BLOCK-001 to CRITICAL
# ---------------------------------------------------------------------------
@test "module-override: severity_overrides escalates KT-BLOCK-001 to CRITICAL" {
  local kt_file="$TEST_TEMP/project/src/main/kotlin/Blocking.kt"
  mkdir -p "$(dirname "$kt_file")"
  printf 'package com.example\nfun work() { Thread.sleep(500) }\n' > "$kt_file"

  run bash "$RUN_PATTERNS" "$kt_file" "$KOTLIN_RULES" "$OVERRIDE_DISABLE"

  assert_success
  assert_output --partial "CRITICAL"
  assert_output --partial "PERF-BLOCK"
}

# ---------------------------------------------------------------------------
# 4. Empty override → base rules apply unchanged
# ---------------------------------------------------------------------------
@test "module-override: empty override leaves base rules intact" {
  local kt_file="$TEST_TEMP/project/src/main/kotlin/WithBang.kt"
  mkdir -p "$(dirname "$kt_file")"
  printf 'package com.example\nval x = someValue!!\n' > "$kt_file"

  run bash "$RUN_PATTERNS" "$kt_file" "$KOTLIN_RULES" "$OVERRIDE_EMPTY"

  assert_success
  assert_output --partial "QUAL-NULL"
}

# ---------------------------------------------------------------------------
# 5. additional_rules adds CUSTOM-001 (TODO detection)
# ---------------------------------------------------------------------------
@test "module-override: additional_rules from add-rules.json detects TODO -> CONV-TODO" {
  local kt_file="$TEST_TEMP/project/src/main/kotlin/HasTodo.kt"
  mkdir -p "$(dirname "$kt_file")"
  printf 'package com.example\n// TODO fix this later\nval x = 1\n' > "$kt_file"

  run bash "$RUN_PATTERNS" "$kt_file" "$KOTLIN_RULES" "$OVERRIDE_ADD"

  assert_success
  assert_output --partial "CONV-TODO"
}

# ---------------------------------------------------------------------------
# 6. threshold_overrides: port/ files get lower file_size threshold (100)
# ---------------------------------------------------------------------------
@test "module-override: spring threshold_overrides lowers port/ file size to 100" {
  local kt_file="$TEST_TEMP/project/src/main/kotlin/port/BigPort.kt"
  mkdir -p "$(dirname "$kt_file")"
  # 105 comment lines so no pattern rules fire, but exceeds 100-line port threshold
  python3 -c "
for i in range(105):
    print('// line %d' % i)
" > "$kt_file"

  run bash "$RUN_PATTERNS" "$kt_file" "$KOTLIN_RULES" "$KS_OVERRIDE"

  assert_success
  assert_output --partial "QUAL-READ"
  assert_output --partial "WARNING"
}
