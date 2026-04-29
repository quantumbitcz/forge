#!/usr/bin/env bats

# Runtime --dry-run behavior for /forge-admin recover subcommands

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

# Extract the `### Subcommand: recover` block from skills/forge-admin/SKILL.md.
_recover_subcommand_block() {
  awk '
    /^### Subcommand: recover$/ { in_block=1; print; next }
    in_block && /^### Subcommand: / { exit }
    in_block && /^## / { exit }
    in_block { print }
  ' "$PLUGIN_ROOT/skills/forge-admin/SKILL.md"
}

@test "forge-admin SKILL.md exists" {
  [ -f "$PLUGIN_ROOT/skills/forge-admin/SKILL.md" ]
}

@test "forge-admin recover subcommand advertises all 5 verbs" {
  # Post-Mega-B: verbs are documented as `#### Action: <verb>` subsections
  # within the consolidated recover subcommand. The pipe-separated list at
  # the top of the block ("Actions: `diagnose | repair | reset | ...`") wraps
  # the whole list in a single backtick-pair, so a per-verb backtick grep
  # would only match the leading verb. Check both forms.
  local body
  body="$(_recover_subcommand_block)"
  for sc in diagnose repair reset resume rollback; do
    echo "$body" | grep -qE "(#### Action: $sc|\\| $sc \\||\` $sc \\||$sc \\||\\| $sc \`|\`$sc\`)" \
      || { echo "Missing subcommand doc: $sc"; return 1; }
  done
}

@test "forge-admin recover subcommand advertises --dry-run on mutating verbs" {
  _recover_subcommand_block | grep -q "\-\-dry-run"
}

@test "forge-admin recover subcommand advertises --json on diagnose" {
  _recover_subcommand_block | grep -q "\-\-json"
}
