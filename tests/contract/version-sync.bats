#!/usr/bin/env bats
# Contract test: plugin.json and marketplace.json versions must match.

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
