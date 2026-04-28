#!/usr/bin/env bats
# Skill-consolidation structural guards.
# Locks in the consolidated skill set (28 skills), forbids the old
# per-cluster names, and asserts each consolidated cluster carries the
# documented dispatch + subcommand sections.

load ../lib/module-lists.bash

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}

@test "skill count is exactly MIN_SKILLS (28)" {
  actual=$(ls -d "$PLUGIN_ROOT"/skills/*/ 2>/dev/null | wc -l | tr -d ' ')
  [ "$actual" -eq 28 ]
}

@test "every expected skill directory exists with SKILL.md" {
  for name in "${EXPECTED_SKILL_NAMES[@]}"; do
    [ -f "$PLUGIN_ROOT/skills/$name/SKILL.md" ] || \
      { echo "MISSING: skills/$name/SKILL.md"; return 1; }
  done
}

@test "no removed Phase-05 skill directories exist" {
  removed=(
    forge-codebase-health
    forge-deep-health
    forge-config-validate
    forge-graph-init
    forge-graph-status
    forge-graph-query
    forge-graph-rebuild
    forge-graph-debug
  )
  for name in "${removed[@]}"; do
    [ ! -e "$PLUGIN_ROOT/skills/$name" ] || \
      { echo "STILL PRESENT: skills/$name"; return 1; }
  done
}

@test "forge-review has exactly one '## Subcommand dispatch' section" {
  count=$(grep -c '^## Subcommand dispatch' "$PLUGIN_ROOT/skills/forge review/SKILL.md")
  [ "$count" -eq 1 ]
}

@test "forge-graph has exactly one '## Subcommand dispatch' section" {
  count=$(grep -c '^## Subcommand dispatch' "$PLUGIN_ROOT/skills/forge-admin graph/SKILL.md")
  [ "$count" -eq 1 ]
}

@test "forge-verify has exactly one '## Subcommand dispatch' section" {
  count=$(grep -c '^## Subcommand dispatch' "$PLUGIN_ROOT/skills/forge verify/SKILL.md")
  [ "$count" -eq 1 ]
}

@test "forge-review has 'changed' and 'all' and 'all --fix' subcommand sections" {
  file="$PLUGIN_ROOT/skills/forge review/SKILL.md"
  grep -q '^### Subcommand: changed' "$file"
  grep -q '^### Subcommand: all' "$file"
  grep -q '^### Subcommand: all --fix' "$file"
}

@test "forge-graph has all 5 positional subcommand sections" {
  file="$PLUGIN_ROOT/skills/forge-admin graph/SKILL.md"
  for sub in init status query rebuild debug; do
    grep -q "^### Subcommand: $sub" "$file" || \
      { echo "MISSING: ### Subcommand: $sub"; return 1; }
  done
}

@test "forge-verify has build and all subcommand sections (no config)" {
  file="$PLUGIN_ROOT/skills/forge verify/SKILL.md"
  grep -q '^### Subcommand: build' "$file"
  grep -q '^### Subcommand: all' "$file"
  ! grep -q '^### Subcommand: config' "$file" || { echo "--config must be removed per Phase 2"; return 1; }
}

@test "forge-review --scope=all --fix documents AskUserQuestion safety gate" {
  file="$PLUGIN_ROOT/skills/forge review/SKILL.md"
  # The gate MUST be documented under the all --fix subcommand.
  grep -q 'AskUserQuestion' "$file"
  grep -qiE 'safety.*gate|safety-confirm|confirm.*gate' "$file"
  grep -q '\-\-yes' "$file"
}

@test "CLAUDE.md Skills header reads '(28 total)'" {
  grep -q '^## Skills (28 total)' "$PLUGIN_ROOT/CLAUDE.md"
}

@test "shared/skill-subcommand-pattern.md exists" {
  [ -f "$PLUGIN_ROOT/shared/skill-subcommand-pattern.md" ]
}

@test "validate-config.sh is read-only (I1 regression guard)" {
  # No touch, mkdir, tee, or stdout redirection to filesystem paths.
  # Allowed: echo >&2 (stderr), case-statement redirections.
  forbidden=$(grep -nE '(\b(touch|mkdir|tee)\b|>\s*[./a-zA-Z]|>>\s*[./a-zA-Z])' \
                   "$PLUGIN_ROOT/shared/validate-config.sh" \
                | grep -vE '>\s*&\s*[12]|2>\s*>?[&/]|^[^:]*:[[:space:]]*#' \
                || true)
  [ -z "$forbidden" ] || { echo "FORBIDDEN WRITES in validate-config.sh:"; echo "$forbidden"; return 1; }
}
