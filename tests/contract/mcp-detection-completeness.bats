#!/usr/bin/env bats
# Contract test: shared/mcp-detection.md must document all MCPs from CLAUDE.md.

load '../helpers/test-helpers'

@test "mcp-detection: shared/mcp-detection.md exists" {
  [[ -f "$PLUGIN_ROOT/shared/mcp-detection.md" ]]
}

@test "mcp-detection: contains Detection Table section" {
  grep -q "Detection Table\|Detection Protocol" "$PLUGIN_ROOT/shared/mcp-detection.md"
}

@test "mcp-detection: documents all MCPs listed in CLAUDE.md" {
  local failures=()
  local detect_file="$PLUGIN_ROOT/shared/mcp-detection.md"
  local mcp_line
  mcp_line="$(grep -i "Detects.*Linear" "$PLUGIN_ROOT/CLAUDE.md" | head -1)"
  local mcps
  mcps="$(echo "$mcp_line" | sed 's/.*Detects //' | sed 's/\..*//' | tr ',' '\n' | sed 's/^ *//' | sed 's/ *$//')"

  while IFS= read -r mcp_name; do
    [[ -z "$mcp_name" ]] && continue
    grep -qi "$mcp_name" "$detect_file" || failures+=("$mcp_name")
  done <<< "$mcps"

  if (( ${#failures[@]} > 0 )); then
    printf 'Missing: %s\n' "${failures[@]}"
    fail "MCPs not in mcp-detection.md: ${#failures[@]}"
  fi
}
