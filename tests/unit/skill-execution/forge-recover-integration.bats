#!/usr/bin/env bats

# Runtime --dry-run behavior for /forge-recover subcommands

setup() {
  PLUGIN_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../.." && pwd)"
  TEST_FORGE_DIR="$(mktemp -d)"
  export PLUGIN_ROOT TEST_FORGE_DIR
  # Seed a fixture .forge/ directory
  mkdir -p "$TEST_FORGE_DIR/.forge"
  echo '{"status":"FAILED","stage":"IMPLEMENTING"}' > "$TEST_FORGE_DIR/.forge/state.json"
}

teardown() {
  rm -rf "$TEST_FORGE_DIR"
}

@test "forge-recover SKILL.md exists" {
  [ -f "$PLUGIN_ROOT/skills/forge-recover/SKILL.md" ]
}

@test "forge-recover SKILL.md advertises all 5 subcommands" {
  local body="$PLUGIN_ROOT/skills/forge-recover/SKILL.md"
  for sc in diagnose repair reset resume rollback; do
    grep -q "\`$sc\`" "$body" || { echo "Missing subcommand doc: $sc"; return 1; }
  done
}

@test "forge-recover SKILL.md advertises --dry-run on mutating subcommands" {
  grep -q "\-\-dry-run" "$PLUGIN_ROOT/skills/forge-recover/SKILL.md"
}

@test "forge-recover SKILL.md advertises --json on diagnose" {
  grep -q "\-\-json" "$PLUGIN_ROOT/skills/forge-recover/SKILL.md"
}
