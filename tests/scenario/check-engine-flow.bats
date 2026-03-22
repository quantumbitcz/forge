#!/usr/bin/env bats
# Scenario tests: end-to-end check-engine flows

load '../helpers/test-helpers'

ENGINE="$PLUGIN_ROOT/shared/checks/engine.sh"
FIXTURE_DIR="$PLUGIN_ROOT/tests/fixtures/patterns"

setup() {
  TEST_TEMP="$(mktemp -d "${TMPDIR:-/tmp}/bats-ce-flow.XXXXXX")"
  MOCK_BIN="$TEST_TEMP/mock-bin"
  mkdir -p "$MOCK_BIN"
  export PATH="$MOCK_BIN:$PATH"
  git init -q "$TEST_TEMP/project"
  git -C "$TEST_TEMP/project" config user.email "t@t.com"
  git -C "$TEST_TEMP/project" config user.name "T"
}

teardown() { rm -rf "$TEST_TEMP"; }

# ---------------------------------------------------------------------------
# 1. Kotlin antipatterns → hook mode → multiple findings
# ---------------------------------------------------------------------------
@test "check-engine flow: kotlin-bad.kt in hook mode emits QUAL-NULL, PERF-BLOCK, CONV-LOG, SEC-CRED findings" {
  local proj="$TEST_TEMP/project"
  mkdir -p "$proj/src/main/kotlin"
  cp "$FIXTURE_DIR/kotlin-bad.kt" "$proj/src/main/kotlin/bad.kt"
  touch "$proj/build.gradle.kts"
  mkdir -p "$proj/src/main/kotlin" # ensure module detection
  git -C "$proj" add . && git -C "$proj" commit -q -m "init"

  run env \
    TOOL_INPUT="{\"file_path\": \"$proj/src/main/kotlin/bad.kt\"}" \
    CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" \
    bash "$ENGINE" --hook

  assert_success
  assert_output --partial "QUAL-NULL"
  assert_output --partial "PERF-BLOCK"
  assert_output --partial "CONV-LOG"
  assert_output --partial "SEC-CRED"
}

# ---------------------------------------------------------------------------
# 2. Clean Kotlin → no security/null/blocking findings
# ---------------------------------------------------------------------------
@test "check-engine flow: kotlin-clean.kt in hook mode emits no security or null findings" {
  local proj="$TEST_TEMP/project"
  mkdir -p "$proj/src/main/kotlin"
  cp "$FIXTURE_DIR/kotlin-clean.kt" "$proj/src/main/kotlin/clean.kt"
  touch "$proj/build.gradle.kts"
  git -C "$proj" add . && git -C "$proj" commit -q -m "init"

  run env \
    TOOL_INPUT="{\"file_path\": \"$proj/src/main/kotlin/clean.kt\"}" \
    CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" \
    bash "$ENGINE" --hook

  assert_success
  refute_output --partial "SEC-CRED"
  refute_output --partial "QUAL-NULL"
  refute_output --partial "PERF-BLOCK"
  refute_output --partial "CONV-LOG"
}

# ---------------------------------------------------------------------------
# 3. TypeScript bad → SEC-CRED or QUAL-TYPE findings
# ---------------------------------------------------------------------------
@test "check-engine flow: typescript-bad.tsx in hook mode emits QUAL-TYPE or CONV-LOG finding" {
  local proj="$TEST_TEMP/project"
  mkdir -p "$proj/src/main"
  cp "$FIXTURE_DIR/typescript-bad.tsx" "$proj/src/main/Bad.tsx"
  echo '{"name":"app"}' > "$proj/package.json"
  touch "$proj/vite.config.ts"
  git -C "$proj" add . && git -C "$proj" commit -q -m "init"

  run env \
    TOOL_INPUT="{\"file_path\": \"$proj/src/main/Bad.tsx\"}" \
    CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" \
    bash "$ENGINE" --hook

  assert_success
  # typescript-bad.tsx has `any` type (QUAL-TYPE) and console.log (CONV-LOG)
  [[ "$output" == *"QUAL-TYPE"* || "$output" == *"CONV-LOG"* || "$output" == *"SEC-CRED"* ]]
}

# ---------------------------------------------------------------------------
# 4. Non-code file (.json) → silent
# ---------------------------------------------------------------------------
@test "check-engine flow: non-code file produces no findings" {
  local proj="$TEST_TEMP/project"
  local json_file="$proj/config.json"
  echo '{"key":"value"}' > "$json_file"
  git -C "$proj" add . && git -C "$proj" commit -q -m "init"

  run env \
    TOOL_INPUT="{\"file_path\": \"$json_file\"}" \
    CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" \
    bash "$ENGINE" --hook

  assert_success
  assert_output ""
}

# ---------------------------------------------------------------------------
# 5. Verify mode: multiple files → findings from all
# ---------------------------------------------------------------------------
@test "check-engine flow: verify mode processes multiple files and emits findings from each" {
  local proj="$TEST_TEMP/project"
  mkdir -p "$proj/src/main/kotlin"
  touch "$proj/build.gradle.kts"
  git -C "$proj" add . && git -C "$proj" commit -q -m "init"

  local file1="$proj/src/main/kotlin/FileA.kt"
  local file2="$proj/src/main/kotlin/FileB.kt"
  printf 'package com.example\nval a = foo!!\n' > "$file1"
  printf 'package com.example\nval b = bar!!\n' > "$file2"

  run bash -c "env CLAUDE_PLUGIN_ROOT='$PLUGIN_ROOT' \
    bash '$ENGINE' --verify \
      --project-root '$proj' \
      --files-changed '$file1' '$file2' 2>/dev/null"

  assert_success
  assert_output --partial "FileA.kt"
  assert_output --partial "FileB.kt"
  assert_output --partial "QUAL-NULL"
}

# ---------------------------------------------------------------------------
# 6. Generated source path → silent
# ---------------------------------------------------------------------------
@test "check-engine flow: file under build/generated-sources is silently skipped" {
  local proj="$TEST_TEMP/project"
  mkdir -p "$proj/build/generated-sources/kotlin/com/example"
  touch "$proj/build.gradle.kts"
  mkdir -p "$proj/src/main/kotlin"
  local gen_file="$proj/build/generated-sources/kotlin/com/example/Gen.kt"
  printf 'package com.example\nval x = bad!!\n' > "$gen_file"
  git -C "$proj" add . && git -C "$proj" commit -q -m "init"

  run env \
    TOOL_INPUT="{\"file_path\": \"$gen_file\"}" \
    CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" \
    bash "$ENGINE" --hook

  assert_success
  assert_output ""
}

# ---------------------------------------------------------------------------
# 7. Clean TypeScript → no findings
# ---------------------------------------------------------------------------
@test "check-engine flow: clean TypeScript file produces no findings" {
  local proj="$TEST_TEMP/project"
  mkdir -p "$proj/src/main"
  echo '{"name":"app"}' > "$proj/package.json"
  touch "$proj/vite.config.ts"
  local ts_file="$proj/src/main/Clean.ts"
  printf 'const greeting: string = "hello";\nexport { greeting };\n' > "$ts_file"
  git -C "$proj" add . && git -C "$proj" commit -q -m "init"

  run env \
    TOOL_INPUT="{\"file_path\": \"$ts_file\"}" \
    CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" \
    bash "$ENGINE" --hook

  assert_success
  assert_output ""
}
