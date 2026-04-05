---
name: forge-fix
description: Start a bugfix workflow. Accepts a kanban ticket ID, Linear issue, or plain bug description.
---

# /forge-fix — Bugfix Workflow Entry Point

You are a thin launcher. Your ONLY job is to resolve the bug source and dispatch the forge orchestrator in bugfix mode.

## Instructions

### 1. Input Parsing

Parse `$ARGUMENTS` to determine the bug source. If no input is provided after stripping flags, ask the user: "What bug should I fix? Provide a ticket ID (e.g., FG-005), `--linear <ID>`, or a plain bug description."

Supported forms:

- `/forge-fix {PREFIX}-{NNN}` — kanban ticket ID (matches pattern like `FG-005`, `BUG-012`). Resolve title and description from tracking store.
- `/forge-fix --linear {ID}` — Linear issue ID. Bug description sourced from Linear.
- `/forge-fix <plain description>` — free-text bug description. A tracking ticket will be created during PREFLIGHT.

**Ticket Resolution (kanban):**

If the sole argument (or first argument before flags) matches the `{PREFIX}-{NNN}` pattern:

1. Source `shared/tracking/tracking-ops.sh`
2. Call `find_ticket ".forge/tracking" "{ticket_id}"` to locate the ticket file
3. Read the ticket's `title` and `## Description` section as the bug description
4. Pass `ticket_id` and `ticket_file_path` to the orchestrator
5. If the ticket is not found, warn the user and ask them to provide a bug description directly

**Linear Resolution:**

If `--linear {ID}` is provided:

- Set `source=linear` and `source_id={ID}`
- The orchestrator will fetch bug details from Linear during PREFLIGHT

**Plain Description:**

If input is free text (not a ticket pattern and no `--linear` flag):

- Set `source=description`
- The orchestrator will create a tracking ticket during PREFLIGHT if tracking is initialized

### 2. MCP Detection

Before dispatching, check which optional MCP tools are available in your current session by looking for these tool name patterns:

| Tool pattern | Integration |
|---|---|
| `mcp__plugin_linear_linear__*` | Linear |
| `mcp__plugin_playwright_playwright__*` | Playwright |
| `mcp__plugin_slack_slack__*` | Slack |
| `mcp__plugin_figma_figma__*` | Figma |
| `mcp__plugin_context7_context7__*` | Context7 |

Build a comma-separated list of detected integrations (e.g., `Linear, Playwright`). If none detected, use `none`.

### 3. Dispatch Orchestrator

Use the Agent tool to invoke `fg-100-orchestrator` with the following prompt:

> Execute the bugfix workflow for: `{bug_description}`
>
> Mode: bugfix
>
> Bug source: `{source}` _(one of: kanban, linear, description)_
>
> Source ID: `{source_id}` _(omit if source=description)_
>
> Ticket file: `{ticket_file_path}` _(include only if source=kanban and ticket was resolved)_
>
> Available MCPs: `{detected_mcps}`

Where `{bug_description}` is the resolved bug text (from ticket title+description if kanban, otherwise raw user input), and `{detected_mcps}` is the list from step 2.

### 4. Relay Output

When the orchestrator completes, relay its final output (PR URL, escalation, or abort message) back to the user unchanged. Do not add commentary or interpretation.

### 5. Forbidden Actions

- Do NOT investigate the bug yourself
- Do NOT write or modify any code or tests
- Do NOT create tracking tickets manually (the orchestrator does this during PREFLIGHT)
- Do NOT fetch Linear issues directly (the orchestrator handles Linear integration)
- Do NOT make any decisions about the fix approach
