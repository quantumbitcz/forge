#!/usr/bin/env bats
# Contract test: plugin.json, marketplace.json, and CLAUDE.md versions must match.

load '../helpers/test-helpers'

@test "version-sync: plugin.json version equals marketplace.json version" {
  local plugin_version marketplace_version
  plugin_version="$(jq -r '.version' "$PLUGIN_ROOT/.claude-plugin/plugin.json")"
  marketplace_version="$(jq -r '.metadata.version' "$PLUGIN_ROOT/.claude-plugin/marketplace.json")"

  [[ -n "$plugin_version" ]] || fail "Could not extract plugin.json version"
  [[ -n "$marketplace_version" ]] || fail "Could not extract marketplace.json version"

  [[ "$plugin_version" == "$marketplace_version" ]] || \
    fail "Version mismatch: plugin.json=$plugin_version, marketplace.json=$marketplace_version"
}

@test "version-sync: CLAUDE.md version matches plugin.json version" {
  local plugin_version claude_version
  plugin_version="$(jq -r '.version' "$PLUGIN_ROOT/.claude-plugin/plugin.json")"
  claude_version="$(grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' "$PLUGIN_ROOT/CLAUDE.md" | head -1 | sed 's/^v//')"

  [[ -n "$claude_version" ]] || fail "Could not extract version from CLAUDE.md"

  [[ "$plugin_version" == "$claude_version" ]] || \
    fail "Version mismatch: plugin.json=$plugin_version, CLAUDE.md=v$claude_version"
}
