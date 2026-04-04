#!/usr/bin/env bats
# Contract tests: shared/mcp-provisioning.md and forge-init MCP provisioning phase.

load '../helpers/test-helpers'

MCP_DOC="$PLUGIN_ROOT/shared/mcp-provisioning.md"
FORGE_INIT="$PLUGIN_ROOT/skills/forge-init/SKILL.md"

# ---------------------------------------------------------------------------
# 1. Document exists
# ---------------------------------------------------------------------------
@test "mcp-provisioning: document exists" {
  [[ -f "$MCP_DOC" ]]
}

# ---------------------------------------------------------------------------
# 2. Provisioning flow documented (6-step decision tree)
# ---------------------------------------------------------------------------
@test "mcp-provisioning: provisioning flow documented" {
  grep -qi "Provisioning Flow\|provisioning flow" "$MCP_DOC" \
    || fail "Provisioning Flow section not found in mcp-provisioning.md"
}

# ---------------------------------------------------------------------------
# 3. .mcp.json format documented
# ---------------------------------------------------------------------------
@test "mcp-provisioning: .mcp.json format documented" {
  grep -q "\.mcp\.json" "$MCP_DOC" \
    || fail ".mcp.json not mentioned in mcp-provisioning.md"
  grep -q "mcpServers" "$MCP_DOC" \
    || fail "mcpServers JSON structure not documented"
}

# ---------------------------------------------------------------------------
# 4. Version resolution references shared doc
# ---------------------------------------------------------------------------
@test "mcp-provisioning: version resolution references shared/version-resolution.md" {
  grep -q "version-resolution\.md" "$MCP_DOC" \
    || fail "version-resolution.md not referenced in mcp-provisioning.md"
}

# ---------------------------------------------------------------------------
# 5. Graceful degradation documented
# ---------------------------------------------------------------------------
@test "mcp-provisioning: graceful degradation documented" {
  grep -qi "Graceful Degradation\|graceful degradation" "$MCP_DOC" \
    || fail "Graceful Degradation section not found in mcp-provisioning.md"
}

# ---------------------------------------------------------------------------
# 6. forge-init has MCP provisioning phase
# ---------------------------------------------------------------------------
@test "mcp-provisioning: forge-init has MCP provisioning phase" {
  grep -qi "MCP Provisioning\|Phase 6c" "$FORGE_INIT" \
    || fail "MCP Provisioning phase (Phase 6c) not found in forge-init SKILL.md"
}

# ---------------------------------------------------------------------------
# 7. Neo4j configured with Docker prerequisite
# ---------------------------------------------------------------------------
@test "mcp-provisioning: neo4j configured with docker prerequisite" {
  grep -q "neo4j" "$MCP_DOC" \
    || fail "neo4j MCP not documented"
  grep -q "docker" "$MCP_DOC" \
    || fail "docker prerequisite for neo4j not documented"
  grep -q "@neo4j/mcp" "$MCP_DOC" \
    || fail "@neo4j/mcp package not documented"
}

# ---------------------------------------------------------------------------
# 8. Never hardcode versions rule documented
# ---------------------------------------------------------------------------
@test "mcp-provisioning: never hardcode versions rule documented" {
  grep -qi "NEVER hardcode\|never hardcode" "$MCP_DOC" \
    || fail "NEVER hardcode versions rule not found in mcp-provisioning.md"
}
