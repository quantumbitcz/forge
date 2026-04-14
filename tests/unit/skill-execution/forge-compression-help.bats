#!/usr/bin/env bats

load '../../helpers/test-helpers'

SKILLS_DIR="$PLUGIN_ROOT/skills"
SKILL_FILE="$SKILLS_DIR/forge-compression-help/SKILL.md"

@test "forge-compression-help: SKILL.md exists" {
  assert [ -f "$SKILL_FILE" ]
}

@test "forge-compression-help: has disable-model-invocation true" {
  run grep -q 'disable-model-invocation: true' "$SKILL_FILE"
  assert_success
}

@test "forge-compression-help: documents all output compression modes" {
  # Must reference lite, full, ultra, and off
  run grep -c 'lite\|full\|ultra\|off' "$SKILL_FILE"
  assert_success
  assert [ "$output" -ge 4 ]
}

@test "forge-compression-help: documents input compression commands" {
  run grep -qi 'forge-compress\|--dry-run\|--restore\|--scope\|--level' "$SKILL_FILE"
  assert_success
}
