---
name: pipeline-run
description: Run the full development pipeline for a story or feature. Accepts a description or --from=<stage> to resume.
---

# /pipeline-run — Pipeline Entry Point

You are a thin launcher. Your ONLY job is to detect available integrations and dispatch the pipeline orchestrator.

## Instructions

1. **Parse input**: The user's argument (everything after `/pipeline-run`) is the work item — a free-text feature description like "Add plan versioning endpoint". Check for an optional `--from=<stage>` flag (e.g., `--from=implement`) which signals the orchestrator to resume from that stage.

   Check for a `--spec <path>` flag. If present, the path points to a shaped spec file (produced by `/pipeline-shape`). Pass it to the orchestrator:

   > Execute the full development pipeline for spec: `{spec_path}`
   >
   > Available MCPs: `{detected_mcps}`

2. **Detect available MCPs**: Before dispatching, check which optional MCP tools are available in your current session by looking for these tool name patterns:

   | Tool pattern | Integration |
   |---|---|
   | `mcp__plugin_linear_linear__*` | Linear |
   | `mcp__plugin_playwright_playwright__*` | Playwright |
   | `mcp__plugin_slack_slack__*` | Slack |
   | `mcp__plugin_figma_figma__*` | Figma |
   | `mcp__plugin_context7_context7__*` | Context7 |

   Build a comma-separated list of detected integrations (e.g., `Linear, Context7`). If none detected, use `none`.

3. **Dispatch the orchestrator**: Use the Agent tool to invoke `pl-100-orchestrator` with the following prompt:

   > Execute the full development pipeline for: `{user_input}`
   >
   > Available MCPs: `{detected_mcps}`

   Where `{user_input}` is the raw text the user provided (including any `--from` flag — the orchestrator knows how to interpret it), and `{detected_mcps}` is the list from step 2.

4. **Do nothing else**: Do not plan, implement, review, or make decisions. The orchestrator handles recovery, planning, implementation, quality, testing, delivery, and meta-analysis autonomously.

5. **Relay the result**: When the orchestrator completes, relay its final output (PR URL, summary, or escalation) back to the user unchanged.
