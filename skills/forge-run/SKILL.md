---
name: forge-run
description: Run the full development pipeline for a story or feature. Accepts --from=<stage> to resume, --dry-run for PREFLIGHT→VALIDATE only, or --spec <path> for shaped specs.
---

# /forge-run — Pipeline Entry Point

You are a thin launcher. Your ONLY job is to detect available integrations and dispatch the pipeline orchestrator.

## Instructions

1. **Parse input**: The user's argument (everything after `/forge-run`) is the work item — a free-text feature description like "Add plan versioning endpoint". If no requirement text is provided (empty input after stripping flags), ask the user: "What would you like to build? Provide a feature description, e.g., 'Add plan versioning endpoint'." Do not dispatch the orchestrator with empty input.

   Check for optional flags:
   - `--from=<stage>` (e.g., `--from=implement`) — resume from that stage
   - `--dry-run` — run PREFLIGHT through VALIDATE only. No implementation, no file changes, no `.forge/` state files, no `.forge/.lock`, no checkpoint files, no `lastCheckpoint` updates. The orchestrator handles these constraints.
   - `--spec <path>` — use a shaped spec file (produced by `/forge-shape`). When present, pass it to the orchestrator with: `Execute the full development pipeline for spec: {spec_path}`

2. **Detect available MCPs**: Before dispatching, check which optional MCP tools are available in your current session by looking for these tool name patterns:

   | Tool pattern | Integration |
   |---|---|
   | `mcp__plugin_linear_linear__*` | Linear |
   | `mcp__plugin_playwright_playwright__*` | Playwright |
   | `mcp__plugin_slack_slack__*` | Slack |
   | `mcp__plugin_figma_figma__*` | Figma |
   | `mcp__plugin_context7_context7__*` | Context7 |

   Build a comma-separated list of detected integrations (e.g., `Linear, Context7`). If none detected, use `none`.

3. **Dispatch the orchestrator**: Use the Agent tool to invoke `fg-100-orchestrator` with the following prompt:

   > Execute the full development pipeline for: `{user_input}`
   >
   > Available MCPs: `{detected_mcps}`

   Where `{user_input}` is the raw text the user provided (including any `--from` flag — the orchestrator knows how to interpret it), and `{detected_mcps}` is the list from step 2.

4. **Do nothing else**: Do not plan, implement, review, or make decisions. The orchestrator handles recovery, planning, implementation, quality, testing, delivery, and meta-analysis autonomously.

5. **Relay the result**: When the orchestrator completes, relay its final output (PR URL, summary, or escalation) back to the user unchanged.
