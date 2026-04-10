#!/usr/bin/env bats
# Unit tests: validate-conventions.sh — convention composition validation.

load '../helpers/test-helpers'

SCRIPT="$PLUGIN_ROOT/shared/validate-conventions.sh"

# ---------------------------------------------------------------------------
# Helper: create a forge.local.md with given YAML frontmatter
# ---------------------------------------------------------------------------
create_forge_local() {
  local content="$1"
  local file_path="${TEST_TEMP}/project/.claude/forge.local.md"
  mkdir -p "$(dirname "$file_path")"
  printf '%s' "$content" > "$file_path"
  printf '%s' "$file_path"
}

# ---------------------------------------------------------------------------
# 1. Script exists and is executable
# ---------------------------------------------------------------------------
@test "validate-conventions: script exists and is executable" {
  assert [ -f "$SCRIPT" ]
  assert [ -x "$SCRIPT" ]
}

@test "validate-conventions: has bash shebang" {
  local first_line
  first_line=$(head -1 "$SCRIPT")
  assert_equal "$first_line" "#!/usr/bin/env bash"
}

# ---------------------------------------------------------------------------
# 2. spring + kotlin + kotest resolves (all exist)
# ---------------------------------------------------------------------------
@test "validate-conventions: spring + kotlin + kotest resolves" {
  local forge_local
  forge_local=$(create_forge_local "---
components:
  backend:
    framework: spring
    language: kotlin
    testing: kotest
---
# Project Config
")
  run bash "$SCRIPT" "$forge_local" "$PLUGIN_ROOT"
  assert_success
}

# ---------------------------------------------------------------------------
# 3. spring + nonexistent variant fails
# ---------------------------------------------------------------------------
@test "validate-conventions: spring + nonexistent-variant fails" {
  local forge_local
  forge_local=$(create_forge_local "---
components:
  backend:
    framework: spring
    variant: unicorn-magic
    language: kotlin
    testing: kotest
---
# Project Config
")
  run bash "$SCRIPT" "$forge_local" "$PLUGIN_ROOT"
  assert_failure
  assert_output --partial "unicorn-magic"
}

# ---------------------------------------------------------------------------
# 4. react + vitest resolves
# ---------------------------------------------------------------------------
@test "validate-conventions: react + vitest resolves" {
  local forge_local
  forge_local=$(create_forge_local "---
components:
  frontend:
    framework: react
    language: typescript
    testing: vitest
---
# Project Config
")
  run bash "$SCRIPT" "$forge_local" "$PLUGIN_ROOT"
  assert_success
}

# ---------------------------------------------------------------------------
# 5. unknown framework fails
# ---------------------------------------------------------------------------
@test "validate-conventions: unknown framework fails" {
  local forge_local
  forge_local=$(create_forge_local "---
components:
  backend:
    framework: unicorn
    language: kotlin
    testing: kotest
---
# Project Config
")
  run bash "$SCRIPT" "$forge_local" "$PLUGIN_ROOT"
  assert_failure
  assert_output --partial "unicorn"
}

# ---------------------------------------------------------------------------
# 6. Multiple errors reported at once
# ---------------------------------------------------------------------------
@test "validate-conventions: multiple errors reported at once" {
  local forge_local
  forge_local=$(create_forge_local "---
components:
  backend:
    framework: nonexistent-fw
    language: nonexistent-lang
    testing: nonexistent-test
---
# Project Config
")
  run bash "$SCRIPT" "$forge_local" "$PLUGIN_ROOT"
  assert_failure
  assert_output --partial "nonexistent-fw"
  assert_output --partial "nonexistent-lang"
  assert_output --partial "nonexistent-test"
}

# ---------------------------------------------------------------------------
# 7. Crosscutting layer with framework binding resolves
# ---------------------------------------------------------------------------
@test "validate-conventions: crosscutting persistence with framework binding resolves" {
  local forge_local
  forge_local=$(create_forge_local "---
components:
  backend:
    framework: spring
    language: kotlin
    testing: kotest
    persistence: hibernate
---
# Project Config
")
  run bash "$SCRIPT" "$forge_local" "$PLUGIN_ROOT"
  assert_success
}

# ---------------------------------------------------------------------------
# 8. Crosscutting layer with generic module resolves
# ---------------------------------------------------------------------------
@test "validate-conventions: crosscutting database with generic module resolves" {
  local forge_local
  forge_local=$(create_forge_local "---
components:
  backend:
    framework: spring
    language: kotlin
    testing: kotest
    database: postgresql
---
# Project Config
")
  run bash "$SCRIPT" "$forge_local" "$PLUGIN_ROOT"
  assert_success
}

# ---------------------------------------------------------------------------
# 9. Empty components block = valid
# ---------------------------------------------------------------------------
@test "validate-conventions: empty components block = valid" {
  local forge_local
  forge_local=$(create_forge_local "---
project_type: backend
framework: spring
module: spring-kotlin
---
# Project Config
")
  run bash "$SCRIPT" "$forge_local" "$PLUGIN_ROOT"
  assert_success
}

# ---------------------------------------------------------------------------
# 10. Flat config (no components: block) with framework resolves
# ---------------------------------------------------------------------------
@test "validate-conventions: flat config with framework resolves" {
  local forge_local
  forge_local=$(create_forge_local "---
project_type: backend
framework: spring
language: kotlin
testing: kotest
module: spring-kotlin
---
# Project Config
")
  run bash "$SCRIPT" "$forge_local" "$PLUGIN_ROOT"
  assert_success
}

# ---------------------------------------------------------------------------
# 11. Missing forge.local.md file fails
# ---------------------------------------------------------------------------
@test "validate-conventions: missing file fails with usage error" {
  run bash "$SCRIPT" "/nonexistent/path/forge.local.md" "$PLUGIN_ROOT"
  assert_failure
}
