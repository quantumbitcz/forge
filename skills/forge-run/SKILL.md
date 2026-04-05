---
name: forge-run
description: Universal pipeline entry point. Auto-classifies intent (feature, bugfix, migration, bootstrap, multi-feature) and routes to the correct pipeline mode. Accepts --from=<stage>, --dry-run, --spec <path>, --sprint, --parallel.
---

# /forge-run — Universal Pipeline Entry Point

You are the universal entry point for the forge pipeline. Your job is to classify the user's intent, detect available integrations, and dispatch the correct agent. You handle routing — not planning, implementation, or review.

## Instructions

1. **Parse input**: The user's argument (everything after `/forge-run`) is the work item — a free-text feature description like "Add plan versioning endpoint". If no requirement text is provided (empty input after stripping flags), ask the user: "What would you like to build? Provide a feature description, e.g., 'Add plan versioning endpoint'." Do not dispatch the orchestrator with empty input.

   ### Input Parsing

   Parse the user's input. Supported forms:
   - `/forge-run <requirement description>` — standard feature mode
   - `/forge-run --spec <path>` — use shaped spec (may have associated ticket)
   - `/forge-run --from=<stage>` — resume from stage
   - `/forge-run --dry-run <requirement>` — analysis only
   - `/forge-run --ticket FG-001 <requirement>` — link to existing kanban ticket
   - `/forge-run FG-001` — shorthand: look up ticket, use its description as requirement

   ### Mode Prefixes

   If the requirement starts with a recognized prefix, pass the mode to the orchestrator:
   - `bugfix: <description>` or `fix: <description>` → `Mode: bugfix`
   - `migrate: <description>` or `migration: <description>` → `Mode: migration`
   - `bootstrap: <description>` or `Bootstrap: <description>` → `Mode: bootstrap`
   - (no prefix) → `Mode: standard`

   The prefix is stripped before passing the requirement to the orchestrator.

   Note: For bugfix mode, prefer `/forge-fix` which provides richer source resolution (kanban tickets, Linear issues). The `bugfix:` prefix in `/forge-run` is a convenience shortcut equivalent to `/forge-fix "description"`.

   Check for optional flags:
   - `--from=<stage>` (e.g., `--from=implement`) — resume from that stage
   - `--dry-run` — run PREFLIGHT through VALIDATE only. No implementation, no file changes, no `.forge/` state files, no `.forge/.lock`, no checkpoint files, no `lastCheckpoint` updates. The orchestrator handles these constraints.
   - `--spec <path>` — use a shaped spec file (produced by `/forge-shape`). When present, pass it to the orchestrator with: `Execute the full development pipeline for spec: {spec_path}`
   - `--ticket <id>` — link pipeline run to an existing kanban ticket (e.g., `--ticket FG-001`)

   **Ticket Resolution:**

   If a ticket ID is provided (via `--ticket` flag or as sole argument matching `{PREFIX}-{NNN}` pattern):
   1. Source `shared/tracking/tracking-ops.sh`
   2. Call `find_ticket ".forge/tracking" "{ticket_id}"` to locate the ticket file
   3. Read ticket's `title` and `## Description` section as the requirement
   4. Pass `ticket_id` to the orchestrator in the dispatch prompt
   5. If ticket not found, warn user and ask for requirement description

   If no ticket ID provided, the orchestrator will create one during PREFLIGHT (if tracking is initialized).

2. **Classify intent**: Unless the user provided an explicit mode prefix (step 1) or flag (`--sprint`, `--parallel`), classify the requirement to determine the correct pipeline mode. Reference: `shared/intent-classification.md`.

   **Classification order** (first match wins):
   1. Explicit prefix/flag → use that mode directly (skip classification)
   2. Bugfix signals (fix, bug, broken, regression, error, stack traces) → `Mode: bugfix`
   3. Migration signals (upgrade X to Y, replace X with Y, migrate) → `Mode: migration`
   4. Bootstrap signals (scaffold, create new, start from scratch, empty project) → `Mode: bootstrap`
   5. Multi-feature signals (3+ distinct domain nouns, enumerated capabilities) → `Mode: multi-feature`
   6. Vague signals (very short/long input, no ACs, exploratory language) → `Mode: vague`
   7. Default → `Mode: standard`

   **Config check**: If `routing.auto_classify` is `false` in `forge-config.md`, skip classification and use `Mode: standard`.

   **Autonomous mode**: Read `autonomous` from `forge-config.md` (default: `false`).
   - If `autonomous: false`: Present classification result via AskUserQuestion:
     - Header: "Intent Classification"
     - Question: "This looks like a **{classified_mode}** based on: {signal_summary}. Proceed with this routing?"
     - Options:
       - "{classified_mode} mode" (description: "Route to {target_agent}")
       - "Override: standard feature" (description: "Treat as single feature, route to fg-100")
       - "Override: choose mode" (description: "Let me pick the mode manually")
   - If `autonomous: true`: Use classified mode directly. Log: `[AUTO-ROUTE] Classified as {mode} based on: {signals}`

   ### Scope Fast Scan

   If classification didn't already detect multi-feature mode (and `scope.fast_scan` is not `false` in `forge-config.md`), perform a quick text scan:
   - 3+ distinct domain nouns joined by "and", "plus", comma-separated
   - Enumerated capabilities ("1. X 2. Y 3. Z")
   - Additive language ("also add", "on top of that", "additionally")

   If detected: set `Mode: multi-feature`.

3. **Detect available MCPs**: Before dispatching, check which optional MCP tools are available in your current session by looking for these tool name patterns:

   | Tool pattern | Integration |
   |---|---|
   | `mcp__plugin_linear_linear__*` | Linear |
   | `mcp__plugin_playwright_playwright__*` | Playwright |
   | `mcp__plugin_slack_slack__*` | Slack |
   | `mcp__plugin_figma_figma__*` | Figma |
   | `mcp__plugin_context7_context7__*` | Context7 |

   Build a comma-separated list of detected integrations (e.g., `Linear, Context7`). If none detected, use `none`.

4. **Route by mode**: Based on the classified mode (or explicit prefix/flag):

   | Mode | Dispatch Target |
   |------|----------------|
   | `--sprint` or `--parallel` flag | `fg-090-sprint-orchestrator` with `$ARGUMENTS` |
   | `multi-feature` | `fg-015-scope-decomposer` with requirement + MCPs |
   | `vague` | `fg-010-shaper` with requirement; on spec output, re-invoke with `--spec {path}` |
   | `bugfix` | `fg-100-orchestrator` with `Mode: bugfix` |
   | `migration` | `fg-100-orchestrator` with `Mode: migration` |
   | `bootstrap` | `fg-100-orchestrator` with `Mode: bootstrap` |
   | `standard` (default) | `fg-100-orchestrator` |

   **For multi-feature mode**, dispatch `fg-015-scope-decomposer`:
   > Decompose this multi-feature requirement into independent features:
   >
   > Requirement: `{user_input}`
   >
   > Source: fast_scan
   > Available MCPs: `{detected_mcps}`

   **For vague mode**, dispatch `fg-010-shaper`:
   > Shape this requirement into a structured spec:
   >
   > `{user_input}`
   >
   > When the shaper returns a spec path, re-dispatch as: `/forge-run --spec {spec_path}`

   **For all other modes** (bugfix, migration, bootstrap, standard), dispatch `fg-100-orchestrator`:
   > Execute the full development pipeline for: `{user_input}`
   >
   > Mode: `{classified_mode}`
   > Available MCPs: `{detected_mcps}`
   >
   > Ticket ID: `{ticket_id}` _(omit if no ticket)_

5. **Do nothing else**: Do not plan, implement, review, or make decisions. The dispatched agent handles everything autonomously.

6. **Relay the result**: When the dispatched agent completes, relay its final output (PR URL, summary, decomposition plan, or escalation) back to the user unchanged.
