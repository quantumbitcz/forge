# Shared Logging Rules

Cross-cutting logging conventions that apply regardless of language or framework. Language-specific modules reference this file and add their language-specific library choices and API patterns.

## Section A: Application Logging Rules

These rules govern logging in the consuming project's application code. Review agents enforce these via CONV-LOG-* and SEC-* findings.

- **No PII in logs**: Never log email, name, phone, credentials (tokens, passwords, API keys), or financial data (card numbers). Log internal IDs (`userId`, `orderId`) instead.
- **No print-style logging**: Never use the language's print/console function for operational logging — it lacks levels, structure, and routing.
- **Structured logging**: Use key-value or structured format for searchability. Avoid string interpolation/concatenation in log messages.
- **Lazy evaluation**: Log messages should only be constructed if the level is enabled (use lambda/supplier patterns where available).
- **Request-scoped context**: Use the language's MDC/context propagation mechanism for correlation IDs and trace IDs — set once in middleware, not per call site.
- **Log levels**: Use appropriate levels — DEBUG for development diagnostics, INFO for business events, WARN for recoverable issues, ERROR for failures requiring attention.

## Section B: Pipeline Logging Rules

These rules govern how forge agents log within the pipeline itself. All agents must follow these conventions for consistent, budget-aware logging.

### Log Levels

| Level | When to use | Examples |
|-------|------------|---------|
| `DEBUG` | Development/diagnostic only. Never in production pipeline output. | Raw tool output parsing, regex match details |
| `INFO` | Stage transitions, agent dispatch, key decisions. | "Dispatching fg-300-implementer with 3 tasks", "Transitioning to REVIEWING" |
| `WARNING` | Fallbacks, degraded mode, minor failures. | "MCP Linear unavailable, skipping sync", "Component cache invalidated" |
| `ERROR` | Failures requiring attention or recovery. | "Build failed (exit 1)", "Recovery budget exhausted" |

### Log Format

All structured log entries in stage notes follow this format:

    [{level}] [{agent_id}] {message}

Examples:
- `[INFO] [fg-100-orchestrator] Transitioning IMPLEMENTING -> VERIFYING`
- `[WARNING] [fg-400-quality-gate] Reviewer fg-411 timed out, coverage gap filed`
- `[ERROR] [fg-500-test-gate] Test command exited with code 1 (3 failures)`

### Where Agents Log

| Agent tier | Log destination | Visibility |
|------------|----------------|-----------|
| Orchestrator (fg-100) | `state.json` fields + stage notes | Persistent across runs |
| Coordinators (fg-400, fg-500, fg-600) | Stage notes (stage_N_notes) | Per-run, read by retrospective |
| Leaf agents (fg-300, fg-410-420) | Return value to coordinator | Coordinator summarizes in stage notes |
| Hook scripts | `.forge/.hook-failures.log` | Persistent, surfaced by forge-status |

### Token Budget for Logging

Agent log sections in stage notes MUST stay within **500 tokens**. If an agent would produce more:

1. **Summarize:** "12 findings (3 CRITICAL, 5 WARNING, 4 INFO)" instead of listing all
2. **Reference:** "Full findings in quality gate report" instead of duplicating
3. **Truncate with count:** "Showing top 5 of 23 entries"

This budget is separate from the 2,000-token stage notes cap defined in `agent-communication.md`. The 500-token limit applies to each agent's log section within those stage notes.

### Per-Agent Logging Guidance

- **Reviewers (fg-410 through fg-419):** Emit structured findings, not log messages. Findings ARE the output. Do not wrap findings in log entries.
- **Coordinators (fg-400, fg-500, fg-600):** Log dispatch decisions ("Dispatching batch 2 with 4 agents"), cycle outcomes ("Quality cycle 2: score 85 -> 88"), and escalation triggers ("Second consecutive dip detected, escalating").
- **Implementer (fg-300):** Log task completion status ("Task 1/3 complete, 2 files modified") and PREEMPT markers. Do not log code diffs.
- **Orchestrator (fg-100):** Log state transitions, convergence phase changes, and recovery actions. Use both stage notes and state.json fields.

### Output Compression Interaction

Pipeline logging follows the output compression levels from `shared/output-compression.md`:
- **Stage notes** follow the stage's verbosity level (e.g., VERIFYING stage notes use level 3 minimal — structured data only)
- **Findings** are always pipe-delimited per `output-format.md` (effectively level 3 regardless of stage)
- **Decision log entries** use level 2 (terse) — `[subject] [action] [reason]` pattern, no articles or filler

When `output_compression.enabled: false`, all logging reverts to normal verbosity.

### What NOT to Log

The following are prohibited in all pipeline log output:

- **File contents** — reference by path: `src/main/App.kt:42`
- **Full tool output** — extract structured data: exit code, counts, durations
- **User data, credentials, or PII** — per Section A rules; applies equally to pipeline logs
- **Secrets or API keys** — even if found during security review, reference by finding ID, not value
- **Conversation history or LLM reasoning traces** — these consume excessive tokens and leak prompt internals
- **Raw JSON state** — reference field names: `state.convergence.phase`, not the full JSON blob
