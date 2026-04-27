# AskUserQuestion Patterns

Canonical payload templates for agents invoking the Claude Code `AskUserQuestion` tool. Enforced where bats-testable (see §4).

## 1. Pattern — Single-choice with preview

Use when two or three architecturally distinct options benefit from side-by-side visual comparison (code snippets, configs, diagrams).

```json
{
  "question": "Which caching strategy should we use?",
  "header": "Cache strategy",
  "multiSelect": false,
  "options": [
    {"label": "In-memory LRU (Recommended)", "description": "Fast, ephemeral.", "preview": "import { LRU } from '...';\nconst c = new LRU({max: 500});"},
    {"label": "Redis", "description": "Persistent, distributed.", "preview": "import Redis from 'ioredis';\nconst r = new Redis(process.env.REDIS_URL);"}
  ]
}
```

## 2. Pattern — Multi-select

Use when choices stack non-exclusively. Triggers the "Review your answers" confirmation screen.

```json
{
  "question": "Which log levels should emit to stderr?",
  "header": "Log levels",
  "multiSelect": true,
  "options": [
    {"label": "error", "description": "Errors and fatal conditions"},
    {"label": "warn", "description": "Warnings"},
    {"label": "info", "description": "Informational"},
    {"label": "debug", "description": "Verbose diagnostics"}
  ]
}
```

## 3. Pattern — Single-choice with explicit recommendation

Use for safe-default escalations where one path is strongly preferred.

```json
{
  "question": "Build is failing after 3 retry cycles. How should we proceed?",
  "header": "Escalation",
  "multiSelect": false,
  "options": [
    {"label": "Invoke /forge-recover diagnose (Recommended)", "description": "Read-only state analysis."},
    {"label": "Abort this run", "description": "Graceful stop; preserves state for /forge-recover resume."},
    {"label": "Force-continue despite failures", "description": "Mark failures non-blocking (dangerous)."}
  ]
}
```

## 4. Pattern — Free-text via auto "Other"

Claude Code auto-appends an "Other" option with text input. NEVER add a literal "Other" option — it is duplicated.

## 5. Prohibitions (bats-enforced)

- No `Options: (1)...(2)...` plain-text menus in agent `.md` bodies or stage-note templates.
- No yes/no prompts (labels matching `/^(Yes|No)$/i`) when distinct labeled options exist.
- No `AskUserQuestion` payload without `header` (required ≤12-char chip label).

## 6. Authoring guidance (not bats-enforced)

- Prefer `multiSelect: true` when options are semantically non-exclusive; reviewer judgment applies here.
- Order options with Recommended first, destructive last.
- Keep `description` fields under ~25 words for terminal fit.

## 7. Confirmed-tier injection gate (added in forge 3.1.0)

**Trigger:** a Confirmed-tier (T-C) piece of external data is about to be passed to an agent whose `tools:` list includes `Bash`.

**Rule:** the orchestrator MUST call `AskUserQuestion` before dispatching that agent — **even when `autonomous: true`**. This is an intentional, documented exception to the autonomy contract (see `shared/untrusted-envelope.md` and the prompt-injection hardening release notes).

**Question template:**

```
Title: "Confirm dispatch after T-C data ingress"
Body:  "Agent {agent_name} is about to receive confirmed-tier external data
        from {source} (origin: {origin}). The agent has Bash capability. Proceed?"
Options: ["Proceed", "Abort stage"]
```

**Autonomous fallback:** when no interactive user is available (background run or CI), the orchestrator writes an escalation record to `.forge/alerts.json` with severity `high` and pauses the run per `shared/background-execution.md`. The run resumes only when a user acknowledges the alert or `/forge-recover resume` is invoked.

**Counter:** each invocation increments `state.json:security.injection_confirmations_requested` (see `shared/state-schema.md`).

## 8. Pattern — Cost-ceiling breach (Phase 6)

**Trigger:** `state.cost.spent_usd + tier_estimate_usd[resolved_tier] > config.cost.ceiling_usd` AND `autonomous: false`.

**Rule:** `fg-100-orchestrator` MUST call `AskUserQuestion` with exactly this payload (values substituted) before any `Agent(...)` call.

```json
{
  "question": "Next dispatch would breach cost ceiling (${ceiling_usd}). Projected: ${projected_usd}. How should we proceed?",
  "header": "Cost ceiling",
  "multiSelect": false,
  "options": [
    {"label": "Raise ceiling to ${ceiling_usd_raised}", "description": "Continues run. Records new ceiling in state for this run only."},
    {"label": "Downgrade remaining agents (Recommended)", "description": "Switches premium->standard, standard->fast where safe. Excludes pinned agents and safety-critical reviewers."},
    {"label": "Abort to ship current state", "description": "Runs pre-ship verifier on what's in the worktree, then ships or exits."},
    {"label": "Abort fully", "description": "Stops immediately. Preserves state for /forge-recover resume."}
  ]
}
```

- Header is exactly `"Cost ceiling"` (12 chars — max).
- `ceiling_usd_raised` = `ceiling_usd * 1.4` rounded to nearest dollar (e.g. $25 -> $35).
- Options ordered Recommended-first, destructive-last (matches §3).

**Autonomous mode:** NEVER invoke this AskUserQuestion. Follow `agents/fg-100-orchestrator.md` §Cost Governance autonomous decision tree. Every decision is logged as `COST-ESCALATION-AUTO` INFO and written to `.forge/cost-incidents/*.json`.

## Default Timeouts (Phase 6)

Interactive `AskUserQuestion` prompts in forge default to a **300-second** response window when no explicit timeout is declared. On timeout:

| Pattern | Timeout default | Fallback action |
|---|---|---|
| §3 Escalation (recovery) | 300s | Default to "Abort this run" |
| §7 Confirmed-tier injection | 300s | Pause run, write `.forge/alerts.json` severity=high |
| §8 Cost-ceiling breach | 300s | Default to "Abort to ship current state" |

Log `{PATTERN}-TIMEOUT` INFO on every fallback.
