# MCP Auto-Provisioning

Defines how auto-bootstrap (the `/forge` first-run trigger) automatically provisions MCP servers that the pipeline depends on. Covers the decision flow, configuration schema, version resolution, and graceful degradation on failure.

---

## Provisioning Flow

For each MCP listed in `forge.local.md` under `mcps:` where `auto_install: true`, execute the following 6-step decision tree:

1. **Check if configured** — Search the project root for `.mcp.json`. If the MCP entry already exists inside `mcpServers`, skip to verification (step 5). Do not re-install.

2. **Check prerequisites** — Inspect the MCP's `prerequisites` list. For each prerequisite:
   - `docker` → run `docker info` to verify Docker is running
   - If a prerequisite is missing, do NOT proceed to install. Jump to the missing-prerequisites handling in Graceful Degradation.

3. **Search internet for latest version** — Use WebSearch or WebFetch to resolve the current stable version of the MCP package. NEVER hardcode versions — always resolve at install time. See [Version Resolution](#version-resolution) below.

4. **Install** — Run the appropriate package manager command to install the resolved package version (e.g., `npm install -g @neo4j/mcp@<resolved-version>`).

5. **Write .mcp.json** — Merge the new `mcpServers` entry into the project root's `.mcp.json`. Create the file if it does not exist. See [.mcp.json Format](#mcpjson-format) below.

6. **Verify connectivity** — Execute the MCP's `verify` Cypher/command. For Neo4j: `RETURN 1`. If verification passes, mark the MCP as provisioned. If it fails, see Graceful Degradation.

---

## Configuration

`forge.local.md` `mcps:` section:

```yaml
mcps:
  neo4j:
    required: false
    auto_install: true
    package: "@neo4j/mcp"
    prerequisites:
      - docker
    verify: "RETURN 1"

  playwright:
    required: false
    auto_install: true
    package: "@playwright/mcp"
    prerequisites: []
    verify: ""

  linear:
    required: false
    auto_install: false
    package: "@linear/mcp"
    prerequisites: []
    verify: ""
    # Note: auto_install is false because Linear requires a user-supplied API key.
    # Set auto_install: true only after configuring linear.api_key in forge.local.md.
```

Field reference:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `required` | bool | yes | If `true`, pipeline aborts when MCP is unavailable after provisioning attempts. If `false`, degrades gracefully. |
| `auto_install` | bool | yes | Whether auto-bootstrap (the `/forge` first-run trigger) should attempt automatic installation. |
| `package` | string | yes | npm package name. Version is resolved at runtime — never hardcoded here. |
| `prerequisites` | list | yes | System dependencies that must be available before install. Supported values: `docker`. Empty list means no prerequisites. |
| `verify` | string | no | Command or Cypher query to confirm the MCP is reachable after install. Empty string skips verification. |

---

## .mcp.json Format

The provisioned `.mcp.json` at the project root uses the standard MCP server format:

```json
{
  "mcpServers": {
    "neo4j": {
      "command": "npx",
      "args": ["-y", "@neo4j/mcp@<resolved-version>"],
      "env": {
        "NEO4J_URI": "bolt://localhost:7687",
        "NEO4J_USERNAME": "neo4j",
        "NEO4J_PASSWORD": "forge-local"
      }
    }
  }
}
```

Rules:
- Always write the resolved version tag into `args` — prevents silent drift on re-runs.
- Merge into existing `mcpServers` object; do NOT overwrite unrelated entries.
- Environment variables for credentials must be pulled from project config or `.env` — never hardcoded in this document.

---

## Version Resolution

NEVER hardcode versions in configuration files or in this document. Always resolve at install time:

1. Use WebSearch to query `{package} latest version npm` or fetch `https://registry.npmjs.org/{package}/latest`.
2. Extract the `version` field from the registry response.
3. Use the resolved version for both the install command and the `.mcp.json` args entry.

For the detailed resolution algorithm and fallback strategy, see `shared/version-resolution.md`.

---

## Graceful Degradation

MCP provisioning failures must never block the initialization flow. Apply the following rules:

| Failure scenario | Response |
|-----------------|----------|
| Installation failure | Log a WARNING. Skip this MCP. Continue with remaining MCPs and auto-bootstrap (the `/forge` first-run trigger) phases. Recovery engine is NOT invoked. |
| Verification failure | Retry verification once (no re-install). If still failing, log a WARNING and skip. Mark the MCP as `degraded` in `integrations` state. |
| Missing prerequisites | Ask user via `AskUserQuestion`: install the prerequisite now, or skip this MCP. If user skips, continue without it. |
| No internet access | Skip all MCPs with `auto_install: true`. Log a single INFO note: "No internet — MCP auto-provisioning skipped." |
| MCP with `required: false` unavailable | Pipeline continues. Feature that depends on the MCP degrades silently (same as normal MCP degradation behaviour). |

The recovery engine is NOT invoked for MCP provisioning failures. Handle all failures inline per this table.

---

## User-Supplied Credentials

MCPs with `auto_install: false` (e.g., Linear) require user-supplied credentials before the pipeline can use them. Credential configuration flow:

1. **During `/forge`:** If a non-auto-install MCP is listed in the `mcps:` config, auto-bootstrap (the `/forge` first-run trigger) prompts the user via `AskUserQuestion`:
   - Header: "MCP Configuration Required"
   - Question: "{MCP name} requires credentials. How would you like to configure?"
   - Options:
     - "Environment variable" — set `{MCP_NAME}_API_KEY` in shell environment or `.env` file
     - "Skip for now" — proceed without this MCP (it will be marked unavailable)

2. **Credential sources** (checked in order at PREFLIGHT):
   - Environment variable: `{MCP_NAME}_API_KEY` (e.g., `LINEAR_API_KEY`)
   - `.env` file in project root
   - `forge.local.md` under `mcps.{name}.api_key` (last resort — prefer env vars to avoid committing secrets)

3. **Validation:** If a credential source is found, test connectivity during the MCP probe at PREFLIGHT step 15. If the credential is invalid (auth failure), log WARNING and mark MCP as unavailable — do not retry or prompt again during this run.

---

## MCP Entries

### Figma

**Detection:** Check for tool `mcp__plugin_figma_figma__get_design_context`

**Used by:** fg-200-planner (design context extraction), fg-320-frontend-polisher (design reference), fg-413-frontend-reviewer (design fidelity audit)

**Degradation:** Skip design-grounded planning and visual comparison. Frontend reviewer falls back to convention-only checks. Log INFO: "Figma MCP not available — design fidelity checks skipped."

**First failure:** Set `integrations.figma.available = false` for the remainder of the run.

### Excalidraw

**Detection:** Check for tool `mcp__claude_ai_Excalidraw__create_view`

**Used by:** fg-200-planner (architecture diagrams), fg-400-quality-gate (findings heatmap), fg-700-retrospective (convergence charts), fg-090-sprint-orchestrator (dependency graphs), forge-status skill (pipeline visualization)

**Degradation:** Skip diagram generation. Text-only output. Log INFO: "Excalidraw MCP not available — visual diagrams skipped."

**First failure:** Set `integrations.excalidraw.available = false` for the remainder of the run.

### Slack

**Detection:** Check for tool `mcp__claude_ai_Slack__slack_send_message`

**Used by:** fg-100-orchestrator (pipeline notifications), fg-710-post-run (completion summaries)

**Degradation:** Skip Slack notifications. Use console output and file-based tracking only. Log INFO: "Slack MCP not available — notifications skipped."

**First failure:** Set `integrations.slack.available = false` for the remainder of the run.

### Context7

**Detection:** Check for tool `mcp__plugin_context7_context7__resolve-library-id`

**Used by:** fg-410-code-reviewer through fg-417-dependency-reviewer (live API validation), fg-140-deprecation-refresh (current deprecation data), fg-300-implementer (version-aware patterns)

**Degradation:** Fall back to training data knowledge and WebSearch. Version-specific guidance may be stale. Log INFO: "Context7 MCP not available — using training data fallback."

**First failure:** Set `integrations.context7.available = false` for the remainder of the run.
