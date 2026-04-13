---
name: forge-run
description: "Universal pipeline entry point. Auto-classifies intent and routes to the correct pipeline mode. Use when you want to build a feature, implement a requirement, or run the full development pipeline. Accepts --from=<stage>, --dry-run, --spec <path>, --sprint, --parallel."
---

# /forge-run — Universal Pipeline Entry Point

## Prerequisites

Before any action, verify:

1. **Git repository:** Run `git rev-parse --show-toplevel 2>/dev/null`. If fails: report "Not a git repository. Navigate to a project directory." and STOP.
2. **Forge initialized:** Check `.claude/forge.local.md` exists. If not: report "Forge not initialized. Run /forge-init first." and STOP.

## What to Expect

After dispatch, fg-100-orchestrator will:
1. Run PREFLIGHT checks (config validation, MCP detection, convention loading) — ~30s
2. EXPLORE the codebase for relevant context — ~1-2 min
3. Generate an implementation PLAN and ask for approval (if confidence < 0.7)
4. IMPLEMENT via TDD (tests first, then code) — varies by complexity
5. VERIFY (tests + lint + review) and fix any findings — may loop 2-5 times
6. Generate DOCUMENTATION and create a PR

Total time: 5-30 minutes depending on complexity. You may be asked to approve the plan, resolve ambiguities, or choose between options.

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

2. **Classify intent**: Unless the user provided an explicit mode prefix (step 1) or flag (`--sprint`, `--parallel`), classify the requirement using the priority table and signal rules in `shared/intent-classification.md`. First match wins. Modes: bugfix, migration, bootstrap, multi-feature, testing, documentation, refactor, performance, vague, standard (default).

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

   **Scope fast scan**: If classification didn't detect multi-feature and `scope.fast_scan` is not `false`, scan for 3+ distinct domain nouns, enumerated items, or additive language ("also add", "additionally"). If detected: set `Mode: multi-feature`.

3. **Detect available MCPs**: Detect available MCPs per `shared/mcp-detection.md` detection table. For each MCP, check if its probe tool is available. Mark unavailable MCPs as degraded and apply the documented degradation behavior.

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
   | `testing` | `fg-100-orchestrator` with `Mode: testing` (implementer focuses on test files; reduced reviewer set) |
   | `documentation` | `fg-350-docs-generator` standalone mode (skip pipeline stages 4-6) |
   | `refactor` | `fg-100-orchestrator` with `Mode: refactor` (planner uses refactor constraints: same behavior, no new features) |
   | `performance` | `fg-100-orchestrator` with `Mode: performance` (EXPLORE includes profiling; performance-focused reviewers) |
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

   **For documentation mode**, dispatch `fg-350-docs-generator` directly (standalone mode):
   > Generate documentation for: `{user_input}`
   >
   > Mode: standalone (no pipeline — skip stages 4-6)
   > Available MCPs: `{detected_mcps}`

   **For all other modes** (bugfix, migration, bootstrap, testing, refactor, performance, standard), dispatch `fg-100-orchestrator`:
   > Execute the full development pipeline for: `{user_input}`
   >
   > Mode: `{classified_mode}`
   > Available MCPs: `{detected_mcps}`
   >
   > Ticket ID: `{ticket_id}` _(omit if no ticket)_

5. **Do nothing else**: Do not plan, implement, review, or make decisions. The dispatched agent handles everything autonomously.

6. **Relay the result**: When the dispatched agent completes, relay its final output (PR URL, summary, decomposition plan, or escalation) back to the user unchanged.

## Error Handling

| Condition | Action |
|-----------|--------|
| Prerequisites fail | Report specific error message and STOP |
| Empty requirement (no input after stripping flags) | Ask the user for a requirement description before dispatching |
| Intent classification ambiguous | Present classification result to user for confirmation (unless autonomous mode) |
| Ticket ID not found in tracking store | Warn user and ask for requirement description directly |
| Agent dispatch fails | Report "Pipeline orchestrator failed to start. Check plugin installation." and STOP |
| Orchestrator returns error | Relay the error unchanged. Suggest `/forge-diagnose` for state issues |
| State corruption mid-run | Orchestrator handles recovery. If it escalates, suggest `/repair-state` or `/forge-reset` |

## See Also

- `/forge-fix` -- Preferred entry point for bugfixes (richer source resolution than `bugfix:` prefix)
- `/forge-shape` -- Shape a vague idea into a structured spec before running the pipeline
- `/forge-sprint` -- Execute multiple features in parallel (preferred over `--sprint` flag)
- `/forge-status` -- Check pipeline progress during or after a run
- `/forge-diagnose` -- Diagnose pipeline health issues if a run fails
- `/forge-resume` -- Resume an aborted or failed run from its last checkpoint
