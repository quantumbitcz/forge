# MCP Detection Reference

Canonical tool name prefixes and degradation behavior for each detected MCP.
Skills MUST reference this document instead of inline detection logic.

## Detection Table

| MCP | Tool Name Prefix | Detection Probe Tool | Available Capability | Degradation When Unavailable |
|---|---|---|---|---|
| Linear | `mcp__claude_ai_Linear__` | `mcp__claude_ai_Linear__list_teams` | Epic/story tracking, status sync | File-based kanban only; skip Linear sync |
| Playwright | `mcp__plugin_playwright_playwright__` | `mcp__plugin_playwright_playwright__browser_navigate` | Browser automation, E2E testing, screenshots | Skip preview validation; manual testing |
| Slack | `mcp__claude_ai_Slack__` | `mcp__claude_ai_Slack__slack_send_message` | Channel messaging, search, canvas | Skip notifications; console output only |
| Context7 | `mcp__plugin_context7_context7__` | `mcp__plugin_context7_context7__resolve-library-id` | Live documentation lookup, version-aware API refs | Fall back to training data + WebSearch |
| Figma | `mcp__claude_ai_Figma__` | `mcp__claude_ai_Figma__get_design_context` | Design-to-code, screenshots, component mapping | Skip design system validation |
| Excalidraw | `mcp__claude_ai_Excalidraw__` | `mcp__claude_ai_Excalidraw__create_view` | Architecture diagrams, visual documentation | Text-based diagrams only |
| Neo4j | `neo4j-mcp` | `neo4j-mcp` (tool name) | Knowledge graph queries, codebase graph | Skip graph enrichment; file-based analysis |

## Detection Protocol

1. At PREFLIGHT, probe each MCP by checking if its detection probe tool is available
2. First failure per MCP marks it as `degraded` for the remainder of the run
3. Log an INFO finding: `MCP-UNAVAILABLE: {mcp_name} — {degradation behavior}`
4. Do NOT invoke the recovery engine for MCP failures (per `error-taxonomy.md`)

## Referencing This Document

Skills should reference this table rather than hardcoding detection logic:
- Use: "Detect MCPs per `shared/mcp-detection.md` detection table"
- Do NOT duplicate tool name prefixes in skill files
