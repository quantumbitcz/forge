#!/usr/bin/env bats
# Contract tests: Forge MCP server structure and integration.

load '../helpers/test-helpers'

SERVER_FILE="$PLUGIN_ROOT/shared/mcp-server/forge-mcp-server.py"
REQUIREMENTS="$PLUGIN_ROOT/shared/mcp-server/requirements.txt"
# Post-Mega-B: /forge-init is retired. The MCP server is auto-provisioned by
# auto-bootstrap (per CLAUDE.md F30) and documented in shared/mcp-provisioning.md.
CLAUDE_MD="$PLUGIN_ROOT/CLAUDE.md"
MCP_PROVISIONING="$PLUGIN_ROOT/shared/mcp-provisioning.md"

# ---------------------------------------------------------------------------
# 1. Server file exists and has valid Python syntax
# ---------------------------------------------------------------------------
@test "mcp-server: forge-mcp-server.py exists" {
  [[ -f "$SERVER_FILE" ]]
}

@test "mcp-server: forge-mcp-server.py has valid Python syntax" {
  if ! command -v python3 &>/dev/null; then
    skip "python3 not available"
  fi
  python3 - "$SERVER_FILE" <<'PYEOF'
import sys
import ast; ast.parse(open(sys.argv[1]).read())
PYEOF
}

# ---------------------------------------------------------------------------
# 2. Requirements file
# ---------------------------------------------------------------------------
@test "mcp-server: requirements.txt exists" {
  [[ -f "$REQUIREMENTS" ]]
}

@test "mcp-server: requirements.txt contains mcp" {
  grep -q "mcp" "$REQUIREMENTS" \
    || fail "requirements.txt does not list mcp dependency"
}

# ---------------------------------------------------------------------------
# 3. All 13 tools defined (11 core + 2 handoff)
# ---------------------------------------------------------------------------
@test "mcp-server: defines 13 @server.tool() functions" {
  local count
  count=$(grep -c "@server.tool()" "$SERVER_FILE")
  [[ "$count" -eq 13 ]] || fail "Expected 13 tools, found $count"
}

# ---------------------------------------------------------------------------
# 4. Tool names present
# ---------------------------------------------------------------------------
@test "mcp-server: defines forge_pipeline_status tool" {
  grep -q "def forge_pipeline_status" "$SERVER_FILE"
}

@test "mcp-server: defines forge_pipeline_evidence tool" {
  grep -q "def forge_pipeline_evidence" "$SERVER_FILE"
}

@test "mcp-server: defines forge_agent_card tool" {
  grep -q "def forge_agent_card" "$SERVER_FILE"
}

@test "mcp-server: defines forge_runs_list tool" {
  grep -q "def forge_runs_list" "$SERVER_FILE"
}

@test "mcp-server: defines forge_runs_search tool" {
  grep -q "def forge_runs_search" "$SERVER_FILE"
}

@test "mcp-server: defines forge_run_detail tool" {
  grep -q "def forge_run_detail" "$SERVER_FILE"
}

@test "mcp-server: defines forge_findings_recurring tool" {
  grep -q "def forge_findings_recurring" "$SERVER_FILE"
}

@test "mcp-server: defines forge_learnings_active tool" {
  grep -q "def forge_learnings_active" "$SERVER_FILE"
}

@test "mcp-server: defines forge_log_search tool" {
  grep -q "def forge_log_search" "$SERVER_FILE"
}

@test "mcp-server: defines forge_playbooks_list tool" {
  grep -q "def forge_playbooks_list" "$SERVER_FILE"
}

@test "mcp-server: defines forge_playbook_effectiveness tool" {
  grep -q "def forge_playbook_effectiveness" "$SERVER_FILE"
}

# ---------------------------------------------------------------------------
# 5. Security: no write operations
# ---------------------------------------------------------------------------
@test "mcp-server: server is read-only (no file writes)" {
  ! grep -qE '\.write_text\(|\.write_bytes\(|open\(.*(\"w\"|\"a\"|'\''w'\''|'\''a'\'')' "$SERVER_FILE" \
    || fail "Server contains write operations — must be read-only"
}

# ---------------------------------------------------------------------------
# 6. Integration: auto-bootstrap surface references MCP server provisioning.
#    Mega B retired /forge-init; CLAUDE.md F30 documents auto-provisioning,
#    and shared/mcp-provisioning.md owns the flow contract.
# ---------------------------------------------------------------------------
@test "mcp-server: auto-bootstrap references MCP server provisioning" {
  grep -qiE "MCP server|mcp-server|mcp_server" "$CLAUDE_MD" \
    || fail "CLAUDE.md does not reference MCP server provisioning"
  [[ -f "$MCP_PROVISIONING" ]] \
    || fail "shared/mcp-provisioning.md missing — required by Mega-B-era auto-bootstrap"
}

# ---------------------------------------------------------------------------
# 7. Server reads plugin version
# ---------------------------------------------------------------------------
@test "mcp-server: reads plugin version from plugin.json" {
  grep -q "plugin.json" "$SERVER_FILE" \
    || fail "Server does not reference plugin.json for version"
}
