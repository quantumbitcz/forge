# MCP Governance

MCP server allowlist system for controlling which Model Context Protocol servers the pipeline trusts. Implements OWASP ASI04 (Supply Chain Compromise) mitigation for external tool integrations.

## Governance Modes

| Mode | Behavior |
|---|---|
| `allowlist` (default) | Only servers in the allowlist are permitted. Unknown servers produce a CRITICAL finding and are blocked. |
| `audit` | All servers are permitted but every connection and tool invocation is logged. Non-listed servers produce an INFO finding. |
| `disabled` | No governance checks. MCP detection proceeds as before (not recommended). |

## Default Allowlist

The built-in allowlist covers the 7 MCP servers recognized by `shared/mcp-detection.md`:

| Name | Tool Name Prefix | Risk Level |
|---|---|---|
| context7 | `mcp__plugin_context7_context7__` | LOW |
| playwright | `mcp__plugin_playwright_playwright__` | LOW |
| neo4j | `neo4j-mcp` | LOW |
| linear | `mcp__claude_ai_Linear__` | MEDIUM |
| slack | `mcp__claude_ai_Slack__` | MEDIUM |
| figma | `mcp__claude_ai_Figma__` | LOW |
| excalidraw | `mcp__claude_ai_Excalidraw__` | LOW |

Risk levels affect audit verbosity. MEDIUM and HIGH servers have all invocations logged even when `audit_all_calls` is `false`.

## Governance Flow

At PREFLIGHT, after MCP detection (per `shared/mcp-detection.md`):

1. For each detected MCP server (tool prefix found in available tools):
   a. Look up the prefix in `security.mcp_governance.allowlist`
   b. **If found:** mark as allowed, set `state.json.integrations.{name}.available = true`
   c. **If not found and `block_unknown: true`:**
      - Set `state.json.integrations.{name}.available = false`
      - Set `state.json.integrations.{name}.blocked_reason = "not in mcp_governance.allowlist"`
      - Emit finding: `SEC-MCP-UNAUTHORIZED | CRITICAL | MCP server '{name}' (prefix: {prefix}) is not in the security allowlist | Add to security.mcp_governance.allowlist in forge-config.md or set block_unknown: false`
   d. **If not found and `block_unknown: false`:**
      - Allow with WARNING: `SEC-MCP-UNAUTHORIZED | WARNING | MCP server '{name}' is not in the allowlist | Consider adding to allowlist for explicit approval`
2. When `mode: audit`: all MCPs are allowed. Non-listed servers emit INFO findings instead of blocking.
3. All governance decisions are logged to `.forge/security-audit.jsonl` (see `shared/security-audit-trail.md`).

## Blocked Server Behavior

When an MCP server is blocked:
- Its tools remain technically available but the pipeline treats the MCP as unavailable
- The same degradation behavior from `shared/mcp-detection.md` applies (e.g., Linear blocked = file-based kanban only)
- The block is logged as a CRITICAL finding, which impacts the pipeline score per `shared/scoring.md`
- The block persists for the entire pipeline run; re-detection does not bypass governance

## Audit Trail

When `audit_all_calls: true`, every MCP tool invocation is logged to `.forge/security-audit.jsonl`:

```json
{
  "timestamp": "2026-04-13T10:15:00Z",
  "event": "MCP_TOOL_INVOCATION",
  "mcp_name": "linear",
  "tool_name": "mcp__claude_ai_Linear__save_issue",
  "agent": "fg-200-planner",
  "stage": "PLANNING",
  "risk_level": "MEDIUM"
}
```

When `audit_all_calls: false`, only connection events and governance decisions are logged (not individual tool calls), except for MEDIUM and HIGH risk servers which always log invocations.

## Configuration

```yaml
security:
  mcp_governance:
    enabled: true
    mode: allowlist              # allowlist | audit | disabled
    allowlist:
      - name: context7
        prefix: "mcp__plugin_context7_context7__"
        risk_level: LOW
      - name: playwright
        prefix: "mcp__plugin_playwright_playwright__"
        risk_level: LOW
      - name: neo4j
        prefix: "neo4j-mcp"
        risk_level: LOW
      - name: linear
        prefix: "mcp__claude_ai_Linear__"
        risk_level: MEDIUM
      - name: slack
        prefix: "mcp__claude_ai_Slack__"
        risk_level: MEDIUM
      - name: figma
        prefix: "mcp__claude_ai_Figma__"
        risk_level: LOW
      - name: excalidraw
        prefix: "mcp__claude_ai_Excalidraw__"
        risk_level: LOW
    block_unknown: true
    audit_all_calls: false
```

| Parameter | Type | Default | Description |
|---|---|---|---|
| `enabled` | boolean | `true` | Master toggle for MCP governance |
| `mode` | string | `allowlist` | `allowlist`: block non-listed MCPs. `audit`: allow all but log. `disabled`: no checks. |
| `allowlist` | array | (7 known MCPs) | List of approved MCP servers with name, prefix, and risk level |
| `allowlist[].name` | string | -- | Human-readable MCP name |
| `allowlist[].prefix` | string | -- | Tool name prefix (from `shared/mcp-detection.md` Detection Table) |
| `allowlist[].risk_level` | string | `LOW` | `LOW`, `MEDIUM`, `HIGH` -- affects audit verbosity |
| `block_unknown` | boolean | `true` | Block MCP servers not in the allowlist |
| `audit_all_calls` | boolean | `false` | Log every MCP tool invocation (verbose, for compliance) |

## Error Handling

| Failure Mode | Behavior |
|---|---|
| Allowlist missing from config | Default to built-in allowlist (7 known MCPs). Log INFO. |
| Invalid `mode` value | Fall back to `allowlist` mode. Log WARNING. |
| Allowlist entry missing `prefix` | Skip that entry. Log WARNING: "Allowlist entry '{name}' missing prefix -- skipped." |
| Audit log write failure | Continue pipeline. Log WARNING to console. Security audit is best-effort. |
