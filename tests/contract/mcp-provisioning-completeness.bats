#!/usr/bin/env bats
# Contract test: every MCP listed in CLAUDE.md must have a section in mcp-provisioning.md.

load '../helpers/test-helpers'

# extract_mcp_list() provided by test-helpers.bash

@test "mcp-completeness: every detected MCP has section in mcp-provisioning.md" {
  local failures=()
  local prov_file="$PLUGIN_ROOT/shared/mcp-provisioning.md"
  [[ -f "$prov_file" ]] || fail "shared/mcp-provisioning.md not found"

  while IFS= read -r mcp_name; do
    [[ -z "$mcp_name" ]] && continue
    # Check for section header containing the MCP name (case-insensitive)
    if ! grep -qi "${mcp_name}" "$prov_file"; then
      failures+=("${mcp_name}: no section found in mcp-provisioning.md")
    fi
  done < <(extract_mcp_list)

  if (( ${#failures[@]} > 0 )); then
    printf '%s\n' "${failures[@]}"
    fail "Missing MCP documentation: ${#failures[@]} MCPs"
  fi
}

@test "mcp-completeness: at least 7 MCPs detected from CLAUDE.md" {
  local count=0
  while IFS= read -r mcp_name; do
    [[ -n "$mcp_name" ]] && ((count++)) || true
  done < <(extract_mcp_list)
  (( count >= 7 )) || fail "Expected >= 7 MCPs, found $count"
}
