# F08: Context Condensation for Long Pipeline Runs

## Status
DRAFT -- 2026-04-13

## Problem Statement

Forge's convergence engine drives Stages 4-6 (IMPLEMENT, VERIFY, REVIEW) through three phases: Correctness, Perfection, and Evidence. The `max_iterations` config allows up to 20 iterations (default varies by project). Each iteration involves dispatching agents with accumulated context from prior iterations: previous findings, fix attempts, test results, and convergence evaluations.

The cost problem is structural:

- **Orchestrator context grows linearly**: Each iteration adds stage notes, findings, decisions, and convergence evaluations to the orchestrator's context window. By iteration 10, the orchestrator prompt can consume 60-80% of the model's context window.
- **Agent dispatch context grows linearly**: Agents like `fg-300-implementer` receive previous findings, prior fix attempts, and current test failures. By iteration 8, the implementer prompt can hit 50K+ tokens.
- **Cost scales super-linearly**: LLM costs are proportional to input tokens. A 20-iteration run costs roughly 4x a 5-iteration run due to accumulated context, not 4x the work.

Evidence from comparable systems:
- OpenHands' LLM summarization achieves 2x cost reduction with no measurable performance degradation on SWE-bench tasks.
- SWE-Agent's history processor uses tag-based retention to keep critical information while discarding verbose tool output from prior iterations.
- Forge's own `forge-compact-check.sh` hook detects when compaction is needed but does not perform structured condensation within convergence loops.

Real-world impact: A Forge sprint run with 5 features averaging 8 iterations each can consume 3-5M tokens. With condensation, the same run could consume 1.5-2.5M tokens -- a 40-50% reduction.

## Proposed Solution

Introduce an orchestrator-managed condensation step between convergence iterations. When accumulated context exceeds a configurable threshold, replace verbose prior-iteration content with a structured LLM-generated summary while retaining tagged "must-keep" content. The condensation operates within convergence phases and is transparent to agents (they receive condensed context and a marker indicating condensation occurred).

## Detailed Design

### Architecture

Condensation is an orchestrator-internal operation that sits between convergence evaluation and the next agent dispatch. It does not introduce new agents or stages.

```
Convergence evaluation
  |
  +--> Decision: iterate again
  |
  +--> Context size check (forge-token-tracker.sh)
  |       |
  |       +--> Under threshold: dispatch agent with full context
  |       |
  |       +--> Over threshold: CONDENSE, then dispatch agent with condensed context
  |
  +--> Agent dispatch
```

#### Component Ownership

| Component | Owner | Responsibility |
|-----------|-------|----------------|
| Condensation trigger | fg-100-orchestrator | Checks context size before each dispatch |
| Threshold calculation | `forge-token-tracker.sh` | Computes current context usage percentage |
| Condensation prompt | `shared/condensation-prompt.md` | New shared doc defining the summarization prompt |
| Tag-based retention | fg-100-orchestrator | Identifies and preserves must-keep content |
| Cost tracking | `forge-token-tracker.sh` | Records tokens saved |

### Schema / Data Model

#### Condensation State in state.json

New fields under `state.json.convergence`:

```json
{
  "convergence": {
    "phase": "perfection",
    "state": "IMPROVING",
    "condensation": {
      "count": 2,
      "last_condensed_at_iteration": 7,
      "total_tokens_saved": 53000,
      "retained_tags": ["active_findings", "test_status", "acceptance_criteria"]
    }
  }
}
```

| Field | Type | Description |
|-------|------|-------------|
| `condensation.count` | integer | Number of condensations performed in this run |
| `condensation.last_condensed_at_iteration` | integer | Iteration number of last condensation |
| `condensation.total_tokens_saved` | integer | Cumulative tokens saved across all condensations |
| `condensation.retained_tags` | string[] | Tags that survived the last condensation |

#### Condensed Context Structure

The condensed context replaces the verbose iteration history in the orchestrator's working memory. It is a structured markdown block:

```markdown
<!-- CONDENSED at iteration 7 (covering iterations 1-6) -->

## Condensation Summary

### Goal
Implement UserController REST endpoint with CRUD operations per spec AC-001 through AC-004.

### Progress
- **Files changed**: UserController.kt, UserService.kt, UserRepository.kt, UserControllerTest.kt
- **Tests**: 12 passing, 0 failing (as of iteration 6)
- **Build**: clean
- **Lint**: clean

### Remaining Work
- SEC-INJECTION WARNING in UserController.kt:42 -- unsanitized query parameter in findByName
- TEST-COVERAGE WARNING -- UserService.deleteUser() has no test

### Active Findings (2)
| Category | Severity | File | Line | Message |
|----------|----------|------|------|---------|
| SEC-INJECTION | WARNING | UserController.kt | 42 | Unsanitized query parameter |
| TEST-COVERAGE | WARNING | UserService.kt | - | deleteUser() untested |

### Convergence Trajectory
Iteration 3: score 72 (3 CRITICAL, 2 WARNING)
Iteration 4: score 80 (0 CRITICAL, 4 WARNING) -- CRITICALs resolved
Iteration 5: score 86 (0 CRITICAL, 2 WARNING, 2 INFO)
Iteration 6: score 88 (0 CRITICAL, 2 WARNING, 1 INFO) -- IMPROVING

### Test Status
All 12 tests passing. No flaky tests detected.

<!-- END CONDENSED -->
```

#### Token Tracking Extension

New fields in `state.json.tokens`:

```json
{
  "tokens": {
    "condensation_savings": 53000,
    "condensation_count": 2,
    "condensation_cost": 1200,
    "effective_token_ratio": 0.62
  }
}
```

| Field | Type | Description |
|-------|------|-------------|
| `condensation_savings` | integer | Total input tokens avoided by condensation |
| `condensation_count` | integer | Total condensation operations |
| `condensation_cost` | integer | Tokens consumed by the condensation LLM call itself |
| `effective_token_ratio` | float | `actual_tokens / (actual_tokens + savings)` -- lower is better |

### Configuration

In `forge-config.md`:

```yaml
condensation:
  enabled: true                      # Master toggle (default: true)
  threshold_pct: 60                  # Trigger when context exceeds this % of model window (default: 60)
  min_iterations_before: 3           # Don't condense before this many iterations (default: 3)
  summary_target_tokens: 2000        # Target size for the condensed summary (default: 2000)
  retain_last_n_iterations: 2        # Always keep full detail for the last N iterations (default: 2)
  model_tier: "fast"                 # Model tier for the condensation call (default: fast)
```

Constraints enforced at PREFLIGHT:
- `threshold_pct` must be >= 30 and <= 90. Below 30 triggers too aggressively (no context to condense). Above 90 triggers too late (already near limits).
- `min_iterations_before` must be >= 2 and <= 10. Below 2 means condensing after the first iteration (no history to summarize).
- `summary_target_tokens` must be >= 500 and <= 5000.
- `retain_last_n_iterations` must be >= 1 and <= 5. Must always keep at least the most recent iteration's full detail.
- `model_tier` must be one of `fast`, `standard`, `premium`. Condensation is a summarization task -- `fast` is sufficient.

### Data Flow

#### Condensation Trigger Algorithm

Executed by the orchestrator before each convergence iteration dispatch:

```
FUNCTION should_condense(state, config):
  # Guard: minimum iterations
  IF state.convergence.total_iterations < config.condensation.min_iterations_before:
    RETURN false

  # Guard: recently condensed (don't condense on consecutive iterations)
  IF state.convergence.condensation.last_condensed_at_iteration == state.convergence.total_iterations - 1:
    RETURN false

  # Calculate current context usage
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

`estimate_context_tokens` uses the existing `forge-token-tracker.sh` token counting (character-based estimation: chars / 3.5 for code-heavy content, chars / 4 for English prose; uses the lower ratio since convergence loop content is predominantly code and findings). The threshold is intentionally conservative — triggering slightly early is better than triggering too late and hitting context limits.

#### Condensation Execution

When `should_condense()` returns true:

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

  # 3. Generate summary via LLM
  summary = llm_summarize(
    prompt = CONDENSATION_PROMPT,
    content = condensable,
    must_keep = must_keep,
    target_tokens = config.summary_target_tokens,
    model_tier = config.model_tier
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

  # 6. Emit event (F07 integration)
  emit_event("CONDENSATION", {
    iteration: state.total_iterations,
    tokens_before: count_tokens(context),
    tokens_after: count_tokens(condensed_context),
    tokens_saved: count_tokens(context) - count_tokens(condensed_context),
    retained_tags: must_keep.tags
  })

  RETURN condensed_context
```

#### Tag-Based Retention Rules

Certain content is tagged as "must-keep" and survives condensation even when it comes from old iterations. Tags are applied by the orchestrator when assembling context and by agents when producing output.

| Tag | Content | Rationale |
|-----|---------|-----------|
| `active_findings` | All unresolved CRITICAL and WARNING findings | Agents need to know what to fix |
| `test_status` | Current test pass/fail summary with failing test names | Implementer needs to know what is broken |
| `acceptance_criteria` | ACs from the active spec (F05 integration) | Must not lose track of what we are building |
| `convergence_trajectory` | Score history (one line per iteration: iteration, score, finding counts) | Agents need convergence context |
| `active_errors` | Current build/lint errors | Must not lose error details |
| `user_decisions` | User responses to AskUserQuestion | Explicit user intent must never be condensed away |

**Tag application rules:**
- Tags are markdown comments: `<!-- tag:active_findings -->` ... `<!-- /tag:active_findings -->`
- The orchestrator wraps tagged content when assembling stage notes and dispatch prompts.
- Agents can tag their own output: if a reviewer tags a finding block, it survives condensation.
- Tagged content is extracted before the LLM summarization call and re-inserted after.
- If tagged content alone exceeds `summary_target_tokens * 2`, log WARNING and increase the effective target to accommodate. Never truncate tagged content.

#### Condensation Prompt Template

The condensation prompt (`shared/condensation-prompt.md`) is a structured template:

```markdown
# Context Condensation

You are condensing the iteration history of a development pipeline convergence loop.
Your job is to produce a structured summary that preserves all information an
implementer or reviewer would need to continue working effectively.

## Input
The following sections contain iteration history from iterations {from} to {to}
of a {phase} convergence phase targeting score {target_score}.

{condensable_content}

## Tagged Content (preserved separately -- do not summarize)
The following content is preserved verbatim and will be appended to your summary.
Do not duplicate it.

{tagged_content_list}

## Output Requirements
Produce a summary with EXACTLY these sections:

### Goal
One sentence: what is being built or fixed.

### Progress
Bullet list: files changed, tests passing/failing, build status, lint status.

### Remaining Work
Bullet list: what still needs to happen (unresolved findings, missing tests).

### Convergence Trajectory
One line per iteration: iteration number, score, finding counts (CRITICAL/WARNING/INFO).

### Key Decisions
Bullet list of significant implementation decisions made during condensed iterations
(approach changes, trade-offs, user feedback incorporated).

Target length: {target_tokens} tokens. Be precise and factual. Do not editorialize.
```

#### Integration with Orchestrator Dispatch

The orchestrator's convergence loop is modified:

```
# Existing convergence loop (simplified from convergence-engine.md)
WHILE not converged:
  IF phase == "correctness":
    dispatch_implement(findings)
    verify_result = dispatch_verify()
    evaluate_convergence(verify_result)
  ELIF phase == "perfection":
    dispatch_implement(findings)
    review_result = dispatch_review()
    evaluate_convergence(review_result)

# Modified with condensation:
WHILE not converged:
  IF should_condense(state, config):
    context = condense(state, config, current_context)
    log("Context condensed at iteration {N}. Tokens: {before} -> {after}")

  IF phase == "correctness":
    dispatch_implement(context, findings)   # context now potentially condensed
    verify_result = dispatch_verify()
    evaluate_convergence(verify_result)
  ELIF phase == "perfection":
    dispatch_implement(context, findings)   # context now potentially condensed
    review_result = dispatch_review()
    evaluate_convergence(review_result)
```

Agents receive condensed context transparently. The `<!-- CONDENSED at iteration N -->` marker tells them they are working with summarized history. Agents do not need modification -- they already work with whatever context the orchestrator provides.

#### Condensation Boundaries

Condensation operates within convergence phases, not across them:

- **Phase transition resets context naturally**: When moving from Correctness to Perfection, the Phase 1 history is already summarized in stage notes. No condensation needed at the boundary.
- **Safety gate re-entry**: If the safety gate fails and routes back to Phase 1, the Phase 2 history is condensed normally. The Phase 1 restart gets fresh context.
- **Sprint isolation**: Each sprint task has independent convergence. Condensation state is per-task in `.forge/runs/{id}/state.json`.

### Integration Points

| System | Integration | Direction |
|--------|-------------|-----------|
| fg-100-orchestrator | Trigger check, execute condensation, pass condensed context | Owner |
| `forge-token-tracker.sh` | Token counting for threshold check and savings tracking | Read |
| `state.json` | Condensation state under `convergence.condensation` | Read + Write |
| Convergence engine | Condensation runs between convergence evaluations | Tightly coupled |
| fg-300-implementer | Receives condensed context (transparent) | Consumer |
| fg-400-quality-gate | Receives condensed context (transparent) | Consumer |
| fg-500-test-gate | Receives condensed context (transparent) | Consumer |
| F07 event log | CONDENSATION events emitted | Write |
| F05 living specs | AC content tagged for retention | Read |
| `forge-compact-check.sh` | Existing compaction hook coexists; condensation handles inner-loop, compaction handles session-level | Coexists |
| Model routing | Condensation uses configured model tier | Read |

### Error Handling

| Scenario | Behavior |
|----------|----------|
| Condensation LLM call fails (timeout, error) | Log WARNING. Skip condensation for this iteration. Dispatch agent with full (uncondensed) context. Retry condensation on next iteration. |
| Condensation LLM produces output exceeding `summary_target_tokens * 3` | Truncate at `summary_target_tokens * 3`. Log WARNING: "Condensation summary exceeded target by {ratio}x". |
| Condensation LLM produces output missing required sections | Use the output as-is with a WARNING tag. Missing sections mean agents lose some context but can still proceed. |
| Tagged content exceeds model context window on its own | This indicates too many unresolved findings accumulating. Log ERROR: "Tagged content ({N} tokens) exceeds context budget. Consider aborting or reducing scope." Escalate to user. |
| `threshold_pct` set too low, condensation triggers on every iteration | The `last_condensed_at_iteration` guard prevents consecutive condensations. Minimum gap is 1 iteration. |
| Condensation during sprint parallel tasks | Each task has independent convergence state. Condensation is per-task, no cross-task interference. |

## Performance Characteristics

- **Condensation LLM cost**: One `fast` tier call per condensation, with ~5K input tokens (condensable content) and ~2K output tokens (summary). At $0.25/M input and $1.25/M output for fast tier: ~$0.004 per condensation.
- **Token savings per condensation**: Typical savings of 10K-50K input tokens for subsequent iterations. At $3/M input for standard tier: $0.03-0.15 saved per subsequent iteration.
- **Break-even**: Condensation pays for itself after 1 subsequent iteration (savings >> condensation cost).
- **Cumulative savings**: A 15-iteration run with 3 condensations saves approximately 40-50% of total input tokens compared to uncondensed execution.
- **Latency**: Condensation adds 3-8 seconds per occurrence (fast model, small input). Amortized across the iteration duration (typically 30-120 seconds), this is 3-10% overhead.
- **No impact on quality**: The tagged retention mechanism ensures all actionable information (findings, test status, errors) survives condensation. Only verbose intermediate output (prior fix attempts, resolved findings, old tool output) is summarized.

## Testing Approach

### Structural Tests

1. `shared/condensation-prompt.md` exists and contains all required sections.
2. `condensation` config key documented in forge-config template.
3. State schema includes `convergence.condensation` fields.

### Unit Tests

1. **Trigger algorithm**: Given various context sizes and thresholds, verify `should_condense()` returns correct boolean. Test edge cases: exactly at threshold, just below, min_iterations guard, consecutive-condensation guard.
2. **Tag extraction**: Given markdown with `<!-- tag:X -->` markers, extract tagged content correctly. Test nested tags, missing close tags, overlapping tags.
3. **Context assembly**: Given condensed summary + tagged content + retained iterations, verify correct ordering and no duplication.
4. **Token accounting**: Given before/after token counts, verify `condensation_savings` and `effective_token_ratio` calculations.

### Contract Tests

1. Condensed context passed to `fg-300-implementer` contains the `<!-- CONDENSED -->` marker and all required sections.
2. Tagged content in condensed context matches the original tagged content verbatim.
3. `state.json.convergence.condensation` fields are valid after condensation.

### Scenario Tests

1. **Threshold trigger**: Run a pipeline with `threshold_pct: 30` (aggressive). Verify condensation triggers and subsequent iterations receive condensed context.
2. **Quality preservation**: Run a pipeline with condensation enabled. Compare final quality score and finding count against the same pipeline without condensation. Scores should be within 2 points.
3. **Cost savings**: Run a 10-iteration convergence loop. Verify `condensation_savings > 0` and `effective_token_ratio < 0.8`.
4. **Tagged retention**: Run a pipeline where an active CRITICAL finding spans 5 iterations. Verify the finding text is preserved verbatim in every condensed context.
5. **Disabled mode**: Run with `condensation.enabled: false`. Verify no condensation occurs and no condensation-related state is written.

## Acceptance Criteria

- [AC-001] GIVEN a convergence loop at iteration 5 WHEN accumulated context exceeds `threshold_pct` of the model context window THEN the orchestrator performs condensation before dispatching the next agent, and the agent receives a context containing the `<!-- CONDENSED at iteration 5 -->` marker.
- [AC-002] GIVEN condensation is triggered WHEN the condensable content contains tagged `<!-- tag:active_findings -->` blocks THEN those blocks appear verbatim in the condensed context, outside the LLM-generated summary.
- [AC-003] GIVEN a 12-iteration convergence loop with condensation enabled WHEN the run completes THEN `state.json.tokens.condensation_savings` is greater than zero and `effective_token_ratio` is less than 1.0.
- [AC-004] GIVEN `condensation.min_iterations_before: 3` WHEN the pipeline is at iteration 2 and context exceeds `threshold_pct` THEN condensation does NOT trigger.
- [AC-005] GIVEN `retain_last_n_iterations: 2` WHEN condensation triggers at iteration 8 THEN iterations 7 and 8 are preserved verbatim and iterations 1-6 are condensed into a summary.
- [AC-006] GIVEN condensation LLM call fails WHEN the orchestrator attempts condensation THEN a WARNING is logged, condensation is skipped for this iteration, and the agent receives full (uncondensed) context.
- [AC-007] GIVEN `condensation.enabled: false` WHEN a pipeline run with 15 iterations completes THEN no condensation occurs, no CONDENSATION events are emitted, and `state.json.tokens.condensation_savings` is 0.
- [AC-008] GIVEN a condensation event WHEN event logging is enabled (F07) THEN a CONDENSATION event is emitted with `tokens_before`, `tokens_after`, `tokens_saved`, and `retained_tags` fields.

## Migration Path

1. **v2.0.0**: Ship with `condensation.enabled: true` by default. No agent changes required -- condensation is transparent to consumers.
2. **v2.0.x**: Tune defaults based on real-world token savings data. Adjust `threshold_pct` and `summary_target_tokens` if condensation quality is insufficient.
3. **v2.1.0**: Consider extending condensation to session-level (beyond convergence loops) to address long shaping sessions and sprint orchestration context growth.

## Dependencies

| Dependency | Type | Required? |
|------------|------|-----------|
| `forge-token-tracker.sh` extension | Shared script modification | Yes |
| fg-100-orchestrator modification | Agent modification | Yes |
| `shared/condensation-prompt.md` (new) | New shared doc | Yes |
| `state.json` schema extension | Schema addition | Yes |
| F07 event log (CONDENSATION event type) | Feature dependency | No (graceful: skip event emission if F07 not active) |
| F05 living specs (AC tag retention) | Feature dependency | No (graceful: no AC tags if F05 not active) |
| Model routing (`model_tier` for condensation call) | Existing system | No (falls back to default model if routing disabled) |
