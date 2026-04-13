# Context Condensation

This document defines the orchestrator-managed context condensation system that reduces token consumption during long convergence loops. Condensation replaces verbose prior-iteration content with a structured LLM-generated summary while retaining tagged "must-keep" content.

## Overview

During Stages 4-6 (IMPLEMENT, VERIFY, REVIEW), the convergence engine drives iterative improvement. Each iteration accumulates context: stage notes, findings, fix attempts, test results, and convergence evaluations. By iteration 8-10, accumulated context can consume 60-80% of the model's context window, causing super-linear cost growth.

Condensation is an orchestrator-internal operation that sits between convergence evaluation and the next agent dispatch. It does not introduce new agents or stages. Agents receive condensed context transparently.

## Token Estimation

Token counts are estimated from character counts using content-type-aware ratios:

| Content Type | Ratio | Rationale |
|---|---|---|
| Code-heavy content (convergence loop context, findings, diffs) | chars / 3.5 | Code tokens are shorter on average (identifiers, operators, punctuation) |
| Prose (documentation, user messages) | chars / 4 | English prose tokenizes more efficiently |

Convergence loop content is predominantly code and findings, so the system defaults to `chars / 3.5` for threshold calculations. This is intentionally conservative -- triggering slightly early is better than hitting context limits.

## Model Context Windows

| Model | Context Window |
|---|---|
| Haiku (Claude 4.x) | 200K tokens |
| Sonnet (Claude 4.x) | 200K tokens |
| Opus (Claude 4.x) | 200K tokens |

The threshold percentage is applied against the context window of the model currently in use by the orchestrator.

## Trigger Conditions

Condensation triggers when ALL of the following are true:

1. **Threshold exceeded**: Accumulated context (estimated tokens) >= `condensation.threshold_pct` % of the current model's context window (default: 60%).
2. **Minimum iterations met**: `convergence.total_iterations >= condensation.min_iterations_before` (default: 3). Condensing before iteration 3 has no meaningful history to summarize.
3. **Not recently condensed**: `condensation.last_condensed_at_iteration != total_iterations - 1`. Prevents condensation on consecutive iterations.

```
FUNCTION should_condense(state, config):
  IF state.convergence.total_iterations < config.condensation.min_iterations_before:
    RETURN false

  IF state.convergence.condensation.last_condensed_at_iteration == state.convergence.total_iterations - 1:
    RETURN false

  current_tokens = estimate_context_tokens(
    orchestrator_prompt,
    stage_notes,
    active_findings,
    convergence_history,
    agent_dispatch_context
  )
  model_window = get_model_context_window(current_model)
  usage_pct = (current_tokens / model_window) * 100

  IF usage_pct >= config.condensation.threshold_pct:
    RETURN true

  RETURN false
```

`estimate_context_tokens` uses `forge-token-tracker.sh` with `chars / 3.5` for code-heavy content.

## LLM-Powered Summarization

When condensation triggers, the orchestrator generates a structured summary using the **fast tier model** (haiku). The prompt template is defined in `shared/prompts/condensation-summary.md`.

### Execution Flow

```
FUNCTION condense(state, config, context):
  # 1. Partition context into condensable and retained sections
  retained = []
  condensable = []

  FOR section in context.iteration_history:
    IF section.iteration > (state.total_iterations - config.retain_last_n_iterations):
      retained.append(section)        # Keep recent iterations verbatim
    ELSE:
      condensable.append(section)     # Older iterations get condensed

  # 2. Extract tagged must-keep content from condensable sections
  must_keep = extract_tagged_content(condensable)

  # 3. Generate summary via LLM (fast tier)
  summary = llm_summarize(
    prompt = CONDENSATION_PROMPT,
    content = condensable,
    must_keep = must_keep,
    target_tokens = config.summary_target_tokens,
    model_tier = config.model_tier    # Default: fast (haiku)
  )

  # 4. Assemble condensed context
  condensed_context = [
    condensation_marker(state.total_iterations, condensed_range),
    summary,
    must_keep_section,     # Tagged content preserved verbatim
    retained               # Recent iterations preserved verbatim
  ]

  # 5. Update state
  state.convergence.condensation.count += 1
  state.convergence.condensation.last_condensed_at_iteration = state.total_iterations
  state.convergence.condensation.total_tokens_saved += (
    count_tokens(condensable) - count_tokens(summary)
  )
  state.convergence.condensation.retained_tags = must_keep.tags

  # 6. Log condensation event
  log("Context condensed at iteration {N}. Tokens: {before} -> {after}")

  RETURN condensed_context
```

## Summary Structure

The condensed summary follows a fixed structure (see `shared/prompts/condensation-summary.md` for the full prompt template):

```markdown
<!-- CONDENSED at iteration N (covering iterations 1-M) -->

## Goal
[What we are trying to achieve]

## Progress
[What has been done, files changed, tests passing]

## Remaining
[What still needs to happen]

## Active Findings
[Unresolved findings, severity, file:line]

## Test Status
[Pass/fail/skip counts, specific failures]

## Convergence Trajectory
[One line per iteration: iteration number, score, finding counts]

## Key Decisions
[Significant implementation decisions made during condensed iterations]

<!-- END CONDENSED -->
```

Target summary length: ~2000 tokens (configurable via `condensation.summary_target_tokens`).

## Tag-Based Retention

Content tagged as "must-keep" survives condensation verbatim, even when it originates from old iterations. Tags are markdown comments applied by the orchestrator when assembling context and by agents when producing output.

### Tag Format

```markdown
<!-- tag:active_findings -->
... content ...
<!-- /tag:active_findings -->
```

### Retention Tags

| Tag | Content | Rationale |
|---|---|---|
| `active_findings` | All unresolved CRITICAL and WARNING findings | Agents need to know what to fix |
| `test_status` | Current test pass/fail summary with failing test names | Implementer needs to know what is broken |
| `acceptance_criteria` | ACs from the active spec | Must not lose track of what we are building |
| `convergence_trajectory` | Score history (one line per iteration) | Agents need convergence context |
| `active_errors` | Current build/lint errors | Must not lose error details |
| `user_decisions` | User responses to AskUserQuestion | Explicit user intent must never be condensed away |

### Tag Application Rules

- Tags are extracted before the LLM summarization call and re-inserted after.
- The orchestrator wraps tagged content when assembling stage notes and dispatch prompts.
- Agents can tag their own output: if a reviewer tags a finding block, it survives condensation.
- If tagged content alone exceeds `summary_target_tokens * 2`, log WARNING and increase the effective target to accommodate. Never truncate tagged content.

## Condensation Boundaries

Condensation operates **within** a convergence phase, not across phases:

- **Phase transitions reset context naturally**: When moving from Correctness to Perfection, the Phase 1 history is already summarized in stage notes. No condensation needed at the boundary.
- **Safety gate re-entry**: If the safety gate fails and routes back to Phase 1, the Phase 2 history is condensed normally. The Phase 1 restart gets fresh context.
- **Sprint isolation**: Each sprint task has independent convergence. Condensation state is per-task in `.forge/runs/{id}/state.json`.

## Transparency

Condensation events are logged and marked for full transparency:

- **Markers**: Condensed context includes `<!-- CONDENSED at iteration N (covering iterations 1-M) -->` and `<!-- END CONDENSED -->` markers. Agents see these markers and know they are working with summarized history.
- **Logging**: Each condensation emits a log line: `"Context condensed at iteration {N}. Tokens: {before} -> {after}"`.
- **Event emission**: When F07 event logging is active, a `CONDENSATION` event is emitted with `tokens_before`, `tokens_after`, `tokens_saved`, and `retained_tags` fields.

## Cost Tracking

Condensation savings are tracked in `state.json.tokens`:

| Field | Type | Description |
|---|---|---|
| `condensation_savings` | integer | Total input tokens avoided by condensation |
| `condensation_count` | integer | Total condensation operations performed |
| `condensation_cost` | integer | Tokens consumed by the condensation LLM call itself |
| `effective_token_ratio` | float | `actual_tokens / (actual_tokens + savings)` -- lower is better |

Additionally, per-run condensation state is tracked under `state.json.convergence.condensation`:

| Field | Type | Description |
|---|---|---|
| `count` | integer | Number of condensations performed in this run |
| `last_condensed_at_iteration` | integer\|null | Iteration number of last condensation |
| `total_tokens_saved` | integer | Cumulative tokens saved across all condensations |
| `retained_tags` | string[] | Tags that survived the last condensation |

## Configuration

```yaml
condensation:
  enabled: true                      # Master toggle (default: true)
  threshold_pct: 60                  # Trigger when context exceeds this % of model window (default: 60)
  min_iterations_before: 3           # Don't condense before this many iterations (default: 3)
  summary_target_tokens: 2000        # Target size for the condensed summary (default: 2000)
  retain_last_n_iterations: 2        # Always keep full detail for the last N iterations (default: 2)
  model_tier: fast                   # Model tier for the condensation call (default: fast)
  preserve_last_n_findings: 20       # Keep N most recent findings verbatim (default: 20)
```

### PREFLIGHT Constraints

| Parameter | Range | Rationale |
|---|---|---|
| `threshold_pct` | 30-90 | Below 30 triggers too aggressively; above 90 triggers too late |
| `min_iterations_before` | 2-10 | Below 2 condenses after first iteration (no history to summarize) |
| `summary_target_tokens` | 500-5000 | Below 500 loses too much detail; above 5000 defeats the purpose |
| `retain_last_n_iterations` | 1-5 | Must always keep at least the most recent iteration |
| `model_tier` | fast \| standard \| premium | Condensation is a summarization task -- fast is sufficient |
| `preserve_last_n_findings` | 5-50 | Must keep enough findings for agent context |

## Error Handling

| Scenario | Behavior |
|---|---|
| Condensation LLM call fails (timeout, error) | Log WARNING. Skip condensation for this iteration. Dispatch agent with full (uncondensed) context. Retry on next iteration. |
| Summary exceeds `summary_target_tokens * 3` | Truncate at `summary_target_tokens * 3`. Log WARNING. |
| Summary missing required sections | Use as-is with WARNING tag. Missing sections mean agents lose some context but can still proceed. |
| Tagged content exceeds model context window | Log ERROR. Escalate to user -- too many unresolved findings accumulating. |
| Consecutive condensation guard triggers | Expected behavior. Minimum gap is 1 iteration between condensations. |
| Sprint parallel tasks | Each task has independent convergence state. Condensation is per-task, no cross-task interference. |

## Integration Points

| System | Integration | Direction |
|---|---|---|
| fg-100-orchestrator | Trigger check, execute condensation, pass condensed context | Owner |
| `forge-token-tracker.sh` | Token counting for threshold check and savings tracking | Read |
| `state.json` | Condensation state under `convergence.condensation` and `tokens` | Read + Write |
| Convergence engine | Condensation runs between convergence evaluations, not during | Tightly coupled |
| fg-300-implementer | Receives condensed context (transparent) | Consumer |
| fg-400-quality-gate | Receives condensed context (transparent) | Consumer |
| fg-500-test-gate | Receives condensed context (transparent) | Consumer |
| F07 event log | CONDENSATION events emitted | Write |
| F05 living specs | AC content tagged for retention | Read |
| `forge-compact-check.sh` | Coexists: condensation handles inner-loop, compaction handles session-level | Coexists |
| Model routing | Condensation uses configured model tier | Read |

## Interaction with forge-compact-check.sh

The existing `forge-compact-check.sh` hook detects when compaction is needed at the session level. Context condensation operates at the convergence-loop level. Both coexist:

- **Condensation**: Summarizes iteration history within a convergence phase. Triggered by the orchestrator between iterations.
- **Compaction**: Session-level context management. Triggered by the PostToolUse hook when the overall session grows too large.

Condensation reduces the need for compaction by keeping convergence loop context manageable, but does not replace it.
