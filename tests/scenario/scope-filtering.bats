#!/usr/bin/env bats
# Scenario tests: scope filtering (main, test, all, regex, scope_exclude)

load '../helpers/test-helpers'

RUN_PATTERNS="$PLUGIN_ROOT/shared/checks/layer-1-fast/run-patterns.sh"
KOTLIN_RULES="$PLUGIN_ROOT/shared/checks/layer-1-fast/patterns/kotlin.json"
OVERRIDE_ADD="$PLUGIN_ROOT/tests/fixtures/overrides/add-rules.json"

setup() {
  TEST_TEMP="$(mktemp -d "${TMPDIR:-/tmp}/bats-scope.XXXXXX")"
  MOCK_BIN="$TEST_TEMP/mock-bin"
  mkdir -p "$MOCK_BIN"
  export PATH="$MOCK_BIN:$PATH"
  git init -q "$TEST_TEMP/project"
  git -C "$TEST_TEMP/project" config user.email "t@t.com"
  git -C "$TEST_TEMP/project" config user.name "T"
}

teardown() { rm -rf "$TEST_TEMP"; }

# ---------------------------------------------------------------------------
# 1. main scope fires for src/main/ (println → CONV-LOG)
# ---------------------------------------------------------------------------
@test "scope-filtering: main scope fires for src/main/ path" {
  local kt_file="$TEST_TEMP/project/src/main/kotlin/Service.kt"
  mkdir -p "$(dirname "$kt_file")"
  printf 'package com.example\nfun run() { println("hello") }\n' > "$kt_file"

  run bash "$RUN_PATTERNS" "$kt_file" "$KOTLIN_RULES"

  assert_success
  assert_output --partial "CONV-LOG"
}

# ---------------------------------------------------------------------------
# 2. main scope silent for src/test/ (println not detected)
# ---------------------------------------------------------------------------
@test "scope-filtering: main scope is silent for src/test/ path" {
  local kt_file="$TEST_TEMP/project/src/test/kotlin/ServiceTest.kt"
  mkdir -p "$(dirname "$kt_file")"
  printf 'package com.example\nfun testIt() { println("debug") }\n' > "$kt_file"

  run bash "$RUN_PATTERNS" "$kt_file" "$KOTLIN_RULES"

  assert_success
  refute_output --partial "CONV-LOG"
}

# ---------------------------------------------------------------------------
# 3. all scope fires everywhere (!! → QUAL-NULL in test dir)
# ---------------------------------------------------------------------------
@test "scope-filtering: all scope fires QUAL-NULL even in src/test/ directory" {
  local kt_file="$TEST_TEMP/project/src/test/kotlin/SomeTest.kt"
  mkdir -p "$(dirname "$kt_file")"
  printf 'package com.example\nval x = value!!\n' > "$kt_file"

  run bash "$RUN_PATTERNS" "$kt_file" "$KOTLIN_RULES"

  assert_success
  assert_output --partial "QUAL-NULL"
}

# ---------------------------------------------------------------------------
# 4. Regex scope /adapter/ fires for adapter path
# ---------------------------------------------------------------------------
@test "scope-filtering: regex scope_pattern /adapter/ fires only for adapter path" {
  # KS-ARCH-001 (from kotlin-spring override) uses scope_pattern "/adapter/"
  local ks_override="$PLUGIN_ROOT/modules/kotlin-spring/rules-override.json"

  local adapter_file="$TEST_TEMP/project/src/main/kotlin/adapter/UserAdapter.kt"
  mkdir -p "$(dirname "$adapter_file")"
  printf 'package com.example.adapter\n@Transactional\nclass UserAdapter\n' > "$adapter_file"

  run bash "$RUN_PATTERNS" "$adapter_file" "$KOTLIN_RULES" "$ks_override"

  assert_success
  assert_output --partial "ARCH-BOUNDARY"
}

# ---------------------------------------------------------------------------
# 5. scope_exclude skips excluded paths
# ---------------------------------------------------------------------------
@test "scope-filtering: scope_exclude skips matching file paths" {
  # Create an override with scope_exclude to suppress findings on generated/ paths
  local override_file="$TEST_TEMP/scope-exclude-override.json"
  cat > "$override_file" <<'EOF'
{
  "additional_rules": [
    {
      "id": "TEST-SCOPE-001",
      "pattern": "println",
      "severity": "WARNING",
      "category": "TEST-CAT",
      "message": "Test scope exclusion",
      "fix_hint": "Fix it",
      "scope": "all",
      "scope_exclude": "generated/"
    }
  ],
  "disabled_rules": [],
  "severity_overrides": {}
}
EOF

  local excluded_file="$TEST_TEMP/project/generated/Service.kt"
  mkdir -p "$(dirname "$excluded_file")"
  printf 'package gen\nfun run() { println("x") }\n' > "$excluded_file"

  run bash "$RUN_PATTERNS" "$excluded_file" "$KOTLIN_RULES" "$override_file"

  assert_success
  refute_output --partial "TEST-CAT"
}

# ---------------------------------------------------------------------------
# 6. Combined scope + scope_exclude: fires for main, not excluded sub-paths
# ---------------------------------------------------------------------------
@test "scope-filtering: combined scope=main and scope_exclude excludes specific subdirectory" {
  local override_file="$TEST_TEMP/combined-override.json"
  cat > "$override_file" <<'EOF'
{
  "additional_rules": [
    {
      "id": "COMBINED-001",
      "pattern": "println",
      "severity": "INFO",
      "category": "COMBINED-CAT",
      "message": "Combined scope test",
      "fix_hint": "Fix it",
      "scope": "main",
      "scope_exclude": "src/main/kotlin/ignored/"
    }
  ],
  "disabled_rules": [],
  "severity_overrides": {}
}
EOF

  # This file is in main scope but NOT excluded → should fire
  local main_file="$TEST_TEMP/project/src/main/kotlin/active/Service.kt"
  mkdir -p "$(dirname "$main_file")"
  printf 'package active\nfun run() { println("active") }\n' > "$main_file"

  run bash "$RUN_PATTERNS" "$main_file" "$KOTLIN_RULES" "$override_file"

  assert_success
  assert_output --partial "COMBINED-CAT"

  # This file is in main scope AND matches scope_exclude → should not fire
  local ignored_file="$TEST_TEMP/project/src/main/kotlin/ignored/Service.kt"
  mkdir -p "$(dirname "$ignored_file")"
  printf 'package ignored\nfun run() { println("ignored") }\n' > "$ignored_file"

  run bash "$RUN_PATTERNS" "$ignored_file" "$KOTLIN_RULES" "$override_file"

  assert_success
  refute_output --partial "COMBINED-CAT"
}
