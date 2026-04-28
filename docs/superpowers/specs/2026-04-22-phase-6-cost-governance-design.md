# Phase 6: Cost Governance — Design

**Status:** Draft
**Date:** 2026-04-22
**Audience:** forge maintainers (solo)
**Depends on:** Phase 1 (truth+observability), Phase 5 (reviewer lazy-load)
**Supersedes:** partial overlap with the token-based `cost_alerting` subsystem in `shared/cost_alerting.py` — Phase 6 extends that module rather than replacing it.

## Goal

Make the pipeline aware of **USD cost** at every dispatch boundary, enforce a hard per-run ceiling, and give agents just enough budget information to make locally-correct decisions (skip a refactor cycle, downgrade a tier, bail out of a cost-inefficient reviewer). The target is a forge run that spends predictably — no more "Sonnet ran a 3-hour loop and I didn't notice" — without rewriting the model-routing system.

## Problem Statement

Three concrete gaps in today's pipeline:

1. **Agents are blind to token/cost budgets.** The `state.json.tokens` and `state.json.cost` sections (CLAUDE.md §Supporting systems, `shared/state-schema.md` v1.10.0 lines 211–231) already accumulate input/output tokens per agent, per stage, and translate to USD via the pricing table in `shared/forge-token-tracker.sh:147-151`. But none of this enters an agent's dispatch brief. `fg-300-implementer` enters `implementer_reflection_cycles == 2` without knowing the run has already spent 92% of what the user is willing to pay. The reflect-then-refactor-then-reflect loop in `fg-300-implementer.md:155-219` is a closed circuit with no cost sensor.
2. **No hard USD ceiling.** `forge-config.md` has retry budgets (`total_retries_max`), convergence limits (`quality_cycles`), and scoring thresholds — but the only cost gate is `cost_alerting.budget_ceiling_tokens` (token-denominated, default 2,000,000). That fires E8 `token_budget_exhausted` (`shared/state-transitions.md:94`), which is an absolute safety net, not a dispatch-time guardrail. `shared/model-routing.md` fixes tiers statically; there is no feedback loop from cost-spent back into tier selection. Sprint mode multiplies this: nine reviewers × three convergence batches × retry budget can reach the documented [$8K–$15K runaway incident](https://www.aicosts.ai/blog/claude-code-subagent-cost-explosion-887k-tokens-minute-crisis) (887K tokens/minute).
3. **Reviewer prompts eager-loaded.** `fg-400-quality-gate` concatenates nine reviewer system prompts at stage entry even when only two reviewers dispatch on small changes. Phase 5 addresses the loading; Phase 6 is responsible for *accounting* — when Phase 5 deletes eager loading, the savings must land in `tokens.by_stage["reviewing"]` and flow to retrospective as a "token-efficiency regression averted" metric.

The existing token-denominated `cost_alerting` (`shared/cost_alerting.py`) fires at 50%/75%/90% of a token ceiling and can write a routing downgrade via `apply-downgrade`. Phase 6 is an **USD-denominated, dispatch-time superset** that reuses the same plumbing (state keys, events, OTel spans) where possible.

## Non-Goals

- **Not replacing model routing.** `shared/model-routing.md` stays as-is. Phase 6 overlays dynamic downgrade logic on top of the static tier defaults; `default_tier` and `tier_1_fast`/`tier_3_premium` semantics are untouched.
- **Not changing per-agent tier defaults.** The 10/18/14 split in `model-routing.md` lines 19–80 is frozen. Cost-aware routing can temporarily downshift any agent, but the file-declared tier is still the recovery target.
- **Not shipping a billing system.** No invoicing, no per-project accounting, no multi-tenant ledger. Runs write a single per-run cost number. Retrospective aggregates trends.
- **Not rewriting `cost_alerting.py`.** The token-denominated code stays and continues to fire E8 at the absolute ceiling. Phase 6 adds a parallel USD layer that calls into the same state mutations.
- **Not adding backwards-compat shims.** Per user's [no-backcompat policy](MEMORY.md feedback_no_backcompat.md) — `state-schema.md` bumps to v2.0.0 as a coordinated cross-phase reshape (see §Cross-Phase Coordination below); old state files are reset on version mismatch.

## Approach

### Information injection over coercion

Trust agents with the number. When `fg-300-implementer` is entering a refactor cycle, the dispatch brief already tells it "`implementer_fix_cycles 1/3`." Phase 6 adds "`budget_remaining $21.58 of $25.00 ceiling`." The agent is capable of deciding that a second micro-refactor is not worth $0.40 when the run has 120 tasks queued. Hard-blocking agents on every dispatch would overfit the numeric model; we let the policy concentrate at the ceiling.

### Hierarchical downgrade over outright skip

Never silently skip a safety-critical agent (`fg-411-security-reviewer`, `fg-412-architecture-reviewer`, `fg-250-contract-validator`, `fg-210-validator`). When cost pressure demands a reduction, *first* downgrade the tier (premium → standard → fast), *then* escalate to the user. Only agents explicitly listed as `skippable_under_cost_pressure` (none by default) are eligible for dispatch suppression. This mirrors the recovery-engine philosophy: degrade the cheapest signal first.

### Reuse existing plumbing

Piggyback on: `state.json.cost.estimated_cost_usd` (USD already accumulated per agent, forge-token-tracker.sh:192–220); `state.json.cost_alerting.routing_override` (agent→tier map, model-routing.md:228); OTel `forge.agent.dispatch` spans; AskUserQuestion pattern §3.

## Components

### 0. Pre-delivery: refresh `shared/forge-token-tracker.sh` pricing table

The live `DEFAULT_PRICING_TABLE` in `shared/forge-token-tracker.sh:145-151` is stale (Haiku 3 at $0.25/$1.25, Opus 3 at $15/$75). Before any other Phase 6 component ships, that table MUST be updated to the current Anthropic rates (verified 2026-04-22 against [platform.claude.com/docs/en/about-claude/pricing](https://platform.claude.com/docs/en/about-claude/pricing)):

```python
DEFAULT_PRICING_TABLE = {
    "haiku":   {"input": 1.00, "output": 5.00},   # Haiku 4.5
    "sonnet":  {"input": 3.00, "output": 15.00},  # Sonnet 4.6
    "opus":    {"input": 5.00, "output": 25.00},  # Opus 4.7
}
```

This is a prerequisite, not a side effect. Every USD value computed elsewhere in Phase 6 (tier estimates, ceiling defaults, cost-per-finding thresholds) assumes this table is current. Ship it as the first commit of Phase 6.

### 1. Budget propagation into dispatch context

The orchestrator computes, just before every `Agent(...)` call:

```
ceiling         = config.cost.ceiling_usd
spent           = state.cost.estimated_cost_usd
remaining       = max(0, ceiling - spent)
pct_consumed    = spent / ceiling
tier_estimate   = state.cost.tier_estimates[resolved_tier]
```

And injects a short section into the dispatch brief (authored by the orchestrator, appended after the agent's static system prompt, before per-task dynamic content so prompt caching is preserved — see `shared/model-routing.md` §Prompt Caching Strategy):

```markdown
## Cost Budget
- Spent: $3.42 of $25.00 ceiling (13.7%)
- Remaining: $21.58
- Your tier: standard (est $0.047 per iteration)
- Budget permits ~459 more iterations at your tier. Act accordingly.
```

This is **informational only**. Agents that want to use it (fg-300-implementer, fg-400-quality-gate deliberation loop) read it; agents that don't (fg-130-docs-discoverer doing one pass) ignore it. The brief never tells the agent to stop; only the orchestrator can stop.

**Staleness contract.** The injected `Spent` value is the last-recorded `state.cost.spent_usd` at the moment of dispatch-brief construction — written by `forge-token-tracker.sh record` *after* the previous dispatch returned. The projected cost of the *impending* dispatch is **not** pre-added to the displayed Spent line; the brief tells the agent the baseline. The tier estimate is listed separately as "Your tier: standard (est $0.047 per iteration)" so the agent can do its own projection if it wants to. Staleness ceiling: at most 1 dispatch behind the wall clock, which is acceptable — the ceiling-breach check in §3 uses the same stale-by-one value and the orchestrator's own gate (not the agent's self-assessment) is authoritative.

### 2. Soft throttling in implementer

`fg-300-implementer` gets a new §5.3b section (between REFLECT and REFACTOR) that reads `budget_remaining / ceiling` from state. Behavior:

| Remaining fraction | Action |
|---|---|
| `> 0.20` | Full behavior (refactor + reflect as today) |
| `0.10 < x ≤ 0.20` | Emit `COST-THROTTLE-IMPL` INFO. Skip second refactor pass (do minimal cleanup only). Still dispatch `fg-301-implementer-judge`. |
| `≤ 0.10` | Emit `COST-THROTTLE-IMPL` WARNING. Skip second refactor, skip critic (record as `REFLECT_SKIPPED_COST` INFO, not `REFLECT_EXHAUSTED`). |

Finding schema:

```json
{
  "category": "COST-THROTTLE-IMPL",
  "severity": "INFO|WARNING",
  "message": "Skipped refactor pass #2 — budget at {pct}% consumed",
  "confidence": "HIGH",
  "suggestion": "Raise cost.ceiling_usd or accept slightly lower polish"
}
```

Throttling NEVER skips the GREEN phase, the initial RED, or inner-loop lint/test validation. Correctness gates are immune.

### 3. Hard ceiling in orchestrator (with AskUserQuestion)

Before every `Agent(...)` dispatch, `fg-100-orchestrator` runs:

```
projected = state.cost.estimated_cost_usd + tier_estimate_usd[resolved_tier]
if projected > config.cost.ceiling_usd:
    escalate_ceiling_breach(agent, resolved_tier, projected)
```

`escalate_ceiling_breach` branches on `state.autonomous`:

**Interactive mode** — AskUserQuestion per `shared/ask-user-question-patterns.md` §3 (single-choice, explicit recommendation):

```json
{
  "question": "Next dispatch would breach cost ceiling ($25.00). Projected: $25.74. How should we proceed?",
  "header": "Cost ceiling",
  "multiSelect": false,
  "options": [
    {"label": "Raise ceiling to $35", "description": "Continues run. Records new ceiling in state for this run only."},
    {"label": "Downgrade remaining agents (Recommended)", "description": "Switches premium→standard, standard→fast where safe. Excludes pinned agents and safety-critical reviewers."},
    {"label": "Abort to ship current state", "description": "Runs pre-ship verifier on what's in the worktree, then ships or exits."},
    {"label": "Abort fully", "description": "Stops immediately. Preserves state for /forge-admin recover resume."}
  ]
}
```

Header stays ≤12 chars ("Cost ceiling" is exactly 12). Options follow recommended-first, destructive-last.

**Autonomous mode** — NEVER AskUserQuestion (per `autonomous: true` semantics in CLAUDE.md §Pipeline modes). Auto-select (B) downgrade. If the projected cost after downgrade still breaches, auto-select (C) abort-to-ship. Log both choices as `COST-ESCALATION-AUTO` INFO events.

**On every escalation (both modes)** — Write `.forge/cost-incidents/<ISO8601>.json`:

```json
{
  "timestamp": "2026-04-22T14:31:07Z",
  "ceiling_usd": 25.00,
  "spent_usd": 24.72,
  "projected_usd": 25.74,
  "next_agent": "fg-412-architecture-reviewer",
  "resolved_tier": "premium",
  "decision": "downgrade",
  "autonomous": true,
  "run_id": "feat-plan-comments-20260422"
}
```

### 4. Dynamic model tier downgrade

A new `cost.aware_routing` flag in `forge-config.md` (default `true`, matching the nested-block convention used by `model_routing:`, `speculation:`, etc.) activates per-dispatch downgrade logic. When enabled, before resolving the static tier via `model-routing.md` resolution order:

```
for each dispatch:
  resolved = static_resolve(agent)
  effective_estimate = tier_estimate[resolved] * conservatism_multiplier[resolved]
  if cost.aware_routing and remaining < 5 * effective_estimate:
    if agent in config.cost.pinned_agents: keep resolved
    else if resolved == premium: resolved = standard
    else if resolved == standard: resolved = fast
    else if resolved == fast:
      if agent in SAFETY_CRITICAL: keep fast
      else: escalate_to_orchestrator_decision  # NEVER auto-skip
  log "COST-DOWNGRADE agent={agent} from={original} to={resolved}"
```

`SAFETY_CRITICAL` is a hardcoded set in `shared/model-routing.md` (new section):

```yaml
safety_critical_agents:
  - fg-210-validator
  - fg-250-contract-validator
  - fg-411-security-reviewer
  - fg-412-architecture-reviewer
  - fg-414-license-reviewer           # legal binding; cannot be downgraded silently
  - fg-419-infra-deploy-reviewer      # prod deployment cost overrun is precisely what this checks
  - fg-505-build-verifier
  - fg-506-migration-verifier         # migration mode only; still safety-critical when active
  - fg-500-test-gate
  - fg-590-pre-ship-verifier
```

`fg-506-migration-verifier` is only dispatched when `state.mode == "migration"`; it is not a no-op on non-migration runs but simply never reached. Listing it here ensures it is never silently dropped during migration runs under cost pressure.

Fast-tier agents in this list that would otherwise be skipped force an orchestrator decision (AskUserQuestion in interactive, `abort-to-ship` in autonomous). They are NEVER silently dropped. The rationale: a run that ships without a security review to save $0.30 is a bug, not a feature.

### 5. Config schema additions

`forge-config.md` new top-level block:

```yaml
cost:
  ceiling_usd: 25.00          # hard ceiling per run (0 = disabled)
  warn_at: 0.75               # INFO event at 75% consumed
  throttle_at: 0.80           # implementer soft throttle activates
  abort_at: 1.00              # hard stop (== ceiling; kept for semantic clarity)
  aware_routing: true         # dynamic tier downgrades
  pinned_agents: []           # agents that never downgrade regardless of budget
  tier_estimates_usd:         # user-editable per-iteration cost estimates
    fast: 0.016
    standard: 0.047
    premium: 0.078
  conservatism_multiplier:    # per-tier buffer applied when evaluating `remaining < N × tier_estimate`
    fast: 1.0
    standard: 1.0
    premium: 1.0              # raise (e.g. 3.0) if planner loops show high variance
  skippable_under_cost_pressure: []  # opt-in list for agents that CAN be skipped
```

Per-iteration estimates are derived consistently from the same 8k input + 1.5k output assumption across all three tiers; see §Cost Estimation Tables for the arithmetic. `conservatism_multiplier` defaults to 1.0 for every tier. The downgrade trip point becomes `remaining < 5 × (tier_estimate × conservatism_multiplier[resolved_tier])`, letting the user inflate any single tier's buffer without skewing the published estimate.

PREFLIGHT validation (added to `shared/preflight-constraints.md`):
- `cost.ceiling_usd` — float ≥ 0; 0 means disabled. Warn if < 1.00 (likely typo).
- `cost.warn_at < cost.throttle_at < cost.abort_at` — ordering enforced.
- `cost.tier_estimates_usd.*` — float > 0; warn if `premium / fast > 200` (likely wrong).
- `cost.pinned_agents[]` — agent IDs validated against `agents.md#registry`; unknown → WARNING.
- `cost.aware_routing` — boolean; requires `model_routing.enabled: true` (PREFLIGHT fails with CRITICAL if inconsistent).
- `cost.conservatism_multiplier.{fast,standard,premium}` — float ≥ 1.0; warn if > 10.0 (likely typo, would disable downgrade entirely).

### 6. Telemetry extensions

Extend `hooks/_py/otel.py` `record_agent_result` (and its attribute schema in `otel_attributes.py`) with:

| Attribute | Type | Emitted on | Meaning |
|---|---|---|---|
| `forge.run.budget_total_usd` | double | every span | Configured ceiling |
| `forge.run.budget_remaining_usd` | double | every span | At span start |
| `forge.agent.tier_estimate_usd` | double | dispatch span | Per-iteration estimate for resolved tier |
| `forge.agent.tier_original` | string | dispatch span | Tier from static routing before downgrade |
| `forge.agent.tier_used` | string | dispatch span | Tier actually dispatched |
| `forge.cost.throttle_reason` | string | on throttle event | One of: `none`, `soft_20pct`, `soft_10pct`, `ceiling_breach`, `dynamic_downgrade` |

These flow through `BatchSpanProcessor` (the live stream) and are rebuilt deterministically by `replay()` from `.forge/events.jsonl`. Retrospective queries them via the OTel exporter → ClickHouse/Grafana pipeline (or, for solo users, jq against the replay output).

### 7. Retrospective cost analytics

`fg-700-retrospective` (new subsection §Cost Analytics) emits:

**Per-run cost incident summary.** Reads `.forge/cost-incidents/*.json`, summarizes counts and decisions. Appears in the retrospective report under "## Cost Governance".

**Per-agent cost-per-finding** (reviewers only — fg-410 through fg-419):
```
unique_findings(agent, severity_filter) =
    {f | f.agent == agent AND f.severity in severity_filter
         AND f not duplicated by peer reviewer in same run}

cost_per_actionable_finding(agent) =
    agent.cost_usd / |unique_findings(agent, {CRITICAL, WARNING})|
```

Cost-per-finding applies **only** when at least one `CRITICAL` or `WARNING` finding exists across the reviewer's peer cohort for that run. A reviewer that correctly emits zero findings on clean code is NOT flagged — that is the reviewer working as intended. `INFO`-only reviewers are likewise excluded from the numerator: an `INFO`-heavy reviewer on a clean run is not evidence of inefficiency.

Flag agents where `cost_per_actionable_finding > 3 * median` across the reviewer cohort of the same run, AND the cohort actually produced actionable findings — candidate for `model_routing` downgrade suggestion (subject to the existing 2-tier-change-per-run cap).

**30-day trend.** Reads `.forge/run-history.db` (SQLite FTS5, F29). New columns in `run_summary`:
- `ceiling_usd REAL`
- `spent_usd REAL`
- `ceiling_breaches INTEGER`
- `throttle_events INTEGER`

Retrospective SQL (example, executed by `fg-700`):

```sql
SELECT
  DATE(started_at) AS day,
  AVG(spent_usd) AS avg_cost,
  SUM(ceiling_breaches) AS total_breaches,
  AVG(spent_usd / NULLIF(ceiling_usd, 0)) AS avg_utilization
FROM run_summary
WHERE started_at > datetime('now', '-30 days')
GROUP BY day;
```

Output appended to `reports/forge-{YYYY-MM-DD}.md`.

## Data Model

### `state.json` v2.0.0 cost block (breaking reshape, coordinated with Phase 5/7)

```json
{
  "version": "2.0.0",
  "cost": {
    "ceiling_usd": 25.00,
    "spent_usd": 3.42,
    "remaining_usd": 21.58,
    "estimated_cost_usd": 3.42,
    "per_stage": {
      "implementing": {"cost_usd": 2.10, "score_delta": 12}
    },
    "per_agent": {
      "fg-300-implementer": {"cost_usd": 1.80, "dispatches": 14, "tier_original": "premium", "tier_used": "premium"}
    },
    "tier_estimates_usd": {"fast": 0.016, "standard": 0.047, "premium": 0.078},
    "conservatism_multiplier": {"fast": 1.0, "standard": 1.0, "premium": 1.0},
    "throttle_events": 0,
    "ceiling_breaches": 0,
    "downgrades": []
  }
}
```

`estimated_cost_usd` is kept as an alias of `spent_usd` for compatibility with `forge-token-tracker.sh` (it writes the old name; we read either). On version-mismatch load, reset cost block to defaults and log INFO. This is the only concession to the old name — no other backcompat shims.

### Cost incident schema (`.forge/cost-incidents/*.json`)

See Component 3. One file per escalation. Appended — never overwritten. Survives `/forge-admin recover reset` (same policy as `events.jsonl`).

## Cost Estimation Tables

Per-1M-token pricing fetched from [Anthropic pricing docs](https://platform.claude.com/docs/en/about-claude/pricing) via WebSearch on 2026-04-22:

| Tier | Model (2026) | Input $/MTok | Output $/MTok | Source |
|---|---|---|---|---|
| `fast` | Claude Haiku 4.5 | $1.00 | $5.00 | [platform.claude.com](https://platform.claude.com/docs/en/about-claude/pricing) |
| `standard` | Claude Sonnet 4.6 | $3.00 | $15.00 | [evolink.ai 2026 guide](https://evolink.ai/blog/claude-api-pricing-guide-2026) |
| `premium` | Claude Opus 4.6/4.7 | $5.00 | $25.00 | [metacto.com 2026 breakdown](https://www.metacto.com/blogs/anthropic-api-pricing-a-full-breakdown-of-costs-and-integration) |

**Per-iteration estimates** (8k input + 1.5k output per call, sourced from `forge-token-tracker.sh` distributions): fast ≈ **$0.016**, standard ≈ **$0.047**, premium ≈ **$0.078**.

**Published defaults in `forge-config.md`** (consistent with the 8k+1.5k derivation above — no hidden multipliers):

```yaml
tier_estimates_usd:
  fast: 0.016      # haiku 4.5 — 8k@$1.00 + 1.5k@$5.00 per MTok
  standard: 0.047  # sonnet 4.6 — 8k@$3.00 + 1.5k@$15.00 per MTok
  premium: 0.078   # opus 4.7 — 8k@$5.00 + 1.5k@$25.00 per MTok
```

If a specific agent's real-world dispatch profile has higher variance (notably `fg-200-planner` on plan-level decisions where a single call may pull in large repo context), raise `conservatism_multiplier.premium` (e.g. to `3.0`) rather than inflating the published per-iteration number. The downgrade check `remaining < 5 × tier_estimate × conservatism_multiplier[tier]` then trips earlier without distorting the dispatch-brief display or cost-per-finding math.

**Critical footnote:** these values drift. The `forge-config.md` block MUST be user-editable; `fg-700-retrospective` computes actual cost-per-dispatch per agent and emits an `EST-DRIFT` WARNING when `|actual - estimated| / estimated > 2.0` across 10+ dispatches. The user updates the config; no auto-tune on estimates (too easy to self-reinforce).

## Data Flow

```
    dispatch(agent):
      resolved = model_routing.resolve(agent)
      projected = state.cost.spent_usd + tier_estimates_usd[resolved]
      ↓
      if projected > cost.ceiling_usd:
        escalate_ceiling_breach(agent, resolved, projected)  # §3
        return  (may abort, may get new tier)
      ↓
      if cost.aware_routing and remaining < 5 * tier_estimate[resolved]:
        resolved = downgrade(resolved, agent)                # §4
      ↓
      brief = static_system_prompt(agent)
           + "\n## Cost Budget\n" + budget_block()           # §1
           + dynamic_task_content
      ↓
      Agent(subagent_type=agent, model=resolved, prompt=brief)
      ↓
      result = await agent
      ↓
      state.cost.spent_usd += actual_cost(result.tokens, resolved)
      otel.record_agent_result(attributes including §6)
      events.append(cost_update_event)
      ↓
      if state.cost.spent_usd / ceiling > warn_at and not warned:
        log [COST] INFO: warn_at threshold crossed
      ↓
      return to orchestrator main loop
```

## Error Handling

| Failure | Behavior |
|---|---|
| Cost estimate off by >2× (actual_cost / tier_estimate > 2.0) over 10+ dispatches | Emit `EST-DRIFT` WARNING finding. Do NOT auto-adjust — user edits config. |
| AskUserQuestion timeout (interactive mode, no response in 300s — Phase-6 local convention pending a shared default in `shared/ask-user-question-patterns.md` §Default timeouts) | Default to option (C) abort-to-ship. Log `COST-ESCALATION-TIMEOUT`. |
| `state.cost` corrupt or missing fields after read | Reset cost block to schema defaults, log WARNING, continue. Do NOT abort the run. |
| OTel exporter unavailable | Proceed silently. Budget enforcement does NOT depend on OTel (state.json is source of truth). |
| `cost.aware_routing: true` but `model_routing.enabled: false` | PREFLIGHT fails with CRITICAL. Config is inconsistent. |
| `cost.ceiling_usd: 0` (disabled) | All Phase 6 gates no-op. Budget injection still occurs (shows "unlimited"). No breach escalations. |
| Autonomous mode breach after downgrade-still-breaches | Abort-to-ship. `fg-590-pre-ship-verifier` runs; if verdict SHIP, PR posts; else `abort_fully` + alert to `.forge/alerts.json`. |
| Tier estimate NaN/negative/missing for resolved tier | Fallback to `tier_estimates_usd.standard`; log INFO. |

## Testing Strategy

### Unit tests (`tests/unit/cost-governance.bats`)

- `budget_check` function: synthetic state with `spent_usd=24.50`, `ceiling=25.00`, `tier=standard (0.048)` → projected `24.548`, no breach.
- `budget_check` function: `spent_usd=24.97`, same tier → projected `25.018`, breach detected.
- `downgrade` function: `premium` with `remaining=0.20`, `tier_estimate[premium]=0.24` → returns `standard`.
- `downgrade` function: `fast` safety-critical agent (`fg-411-security-reviewer`) → returns `fast` unchanged.
- `downgrade` function: `fg-200-planner` pinned in config → returns `premium` unchanged.

### Scenario tests (`tests/scenarios/cost-governance/`)

- `ceiling-interactive.bats`: feed a pipeline with `ceiling_usd=0.50` and a planner that will cost $0.60; assert AskUserQuestion payload matches pattern §3, assert state shows `ceiling_breaches: 1` after user chooses (D) abort.
- `ceiling-autonomous.bats`: same setup with `autonomous: true`; assert no AskUserQuestion, assert `COST-ESCALATION-AUTO` event emitted, assert tier downgraded from premium to standard.
- `soft-throttle.bats`: pipeline at 85% of ceiling entering implementer refactor; assert `COST-THROTTLE-IMPL` INFO finding, assert second refactor skipped, assert `fg-301-implementer-judge` still dispatched.
- `hard-throttle.bats`: 95% of ceiling; assert `COST-THROTTLE-IMPL` WARNING, critic NOT dispatched, `REFLECT_SKIPPED_COST` event emitted.

### Integration test

- `cost-incident-write.bats`: assert every escalation writes a `.forge/cost-incidents/*.json`, JSON schema validated against `shared/schemas/cost-incident.schema.json`.

### OTel attribute test

- `otel-cost-attrs.bats`: run replay from a fixture `events.jsonl`, parse emitted spans, assert all six new attributes present and well-typed.

### Regression guard

- `no-silent-safety-skip.bats`: construct a scenario where `fg-411-security-reviewer` is resolved to `fast` (by config override) and budget is at 99%. Assert it is NOT silently skipped — either dispatched (fast tier) or escalated.

## Documentation Updates

| File | Section | Change |
|---|---|---|
| `CLAUDE.md` | §Supporting systems | Add cost-governance subsection pointing to this spec |
| `CLAUDE.md` | §Pipeline modes → Autonomous | Note: cost ceiling auto-decisions in autonomous mode |
| `CLAUDE.md` | §Quick start — "Configuration" | Mention `cost.ceiling_usd` default $25 |
| `shared/model-routing.md` | New §Cost-Aware Routing | Downgrade algorithm, safety-critical list |
| `shared/state-schema.md` | Bump to v2.0.0 | Cost block reshape, new fields. Coordinated with Phase 5/7 — single bump, not three. |
| `shared/observability.md` | §GenAI attributes + new §Namespace Contract | Six new `forge.cost.*` + `forge.agent.tier_*` attributes. Add namespace contract: "All forge-emitted span attributes MUST use `forge.*` root; Phase 4's `learning.*` emissions must be renamed to `forge.learning.*`." |
| `shared/preflight-constraints.md` | New §Cost | Validation rules for `cost.*` block |
| `shared/ask-user-question-patterns.md` | New §8 + new §Default timeouts | Cost-ceiling escalation canonical payload. Add `Default timeouts` section proposing 300s as the cross-skill default for interactive prompts (Phase 6 adopts it locally pending that section landing). |
| `agents/fg-100-orchestrator.md` | Before-dispatch block | Ceiling check + AskUserQuestion flow |
| `agents/fg-300-implementer.md` | New §5.3b Soft Cost Throttle | Between REFLECT and REFACTOR |
| `agents/fg-700-retrospective.md` | New §Cost Analytics | Per-run summary + 30d trend + cost-per-finding |
| `shared/run-history/schema.sql` | `run_summary` | Add four cost columns |
| `README.md` | §Configuration | One-liner on cost ceiling |

## Acceptance Criteria

1. **AC-601:** `forge-config.md` accepts a `cost:` block with the schema in §5; PREFLIGHT validates all six fields; invalid config (e.g. `warn_at > throttle_at`) produces CRITICAL and aborts.
2. **AC-602:** Every dispatch brief sent by `fg-100-orchestrator` contains a `## Cost Budget` section with non-empty Spent/Remaining/Tier lines (asserted via scenario test capturing one dispatch payload).
3. **AC-603:** When `state.cost.spent_usd + tier_estimate > cost.ceiling_usd`, orchestrator does NOT call `Agent(...)` without first calling `AskUserQuestion` (interactive) or auto-choosing per §3 (autonomous).
4. **AC-604:** In autonomous mode, ceiling breach auto-selects tier downgrade. If downgrade cannot help (already at fast), auto-selects abort-to-ship. NO AskUserQuestion is ever invoked.
5. **AC-605:** Every ceiling breach writes a `.forge/cost-incidents/<timestamp>.json` matching the schema in §3.
6. **AC-606:** `fg-300-implementer` emits `COST-THROTTLE-IMPL` INFO at 80%+ consumption and skips second refactor pass; WARNING at 90%+ and also skips critic dispatch.
7. **AC-607:** `cost.aware_routing: true` with `remaining < 5 × (tier_estimate[resolved] × conservatism_multiplier[resolved])` downgrades the resolved tier one step; the decision is logged to `state.cost.downgrades[]`.
8. **AC-608:** `fg-210-validator`, `fg-250-contract-validator`, `fg-411-security-reviewer`, `fg-412-architecture-reviewer`, `fg-414-license-reviewer`, `fg-419-infra-deploy-reviewer`, `fg-500-test-gate`, `fg-505-build-verifier`, `fg-506-migration-verifier` (migration mode), `fg-590-pre-ship-verifier` are never silently skipped regardless of cost pressure. If cost gate would skip them, the orchestrator escalates instead.
9. **AC-609:** Agents in `cost.pinned_agents[]` retain their original tier even when cost-aware routing is active (verified by unit test).
10. **AC-610:** OTel spans for every dispatch carry the six new attributes from §6; they round-trip through `otel.replay()` without loss.
11. **AC-611:** `fg-700-retrospective` report under `## Cost Governance` includes: total spent, ceiling, breach count, throttle-event count, top-3 cost-per-actionable-finding reviewers flagged (only when peer cohort produced CRITICAL/WARNING findings; zero-finding clean runs do NOT flag anyone).
12. **AC-612:** `.forge/run-history.db` `run_summary` table has the four new columns populated on every retrospective completion.
13. **AC-613:** When actual cost drifts >2× from `tier_estimates_usd` across 10+ dispatches, retrospective emits `EST-DRIFT` WARNING pointing to the stale config key.
14. **AC-614:** With `cost.ceiling_usd: 0`, no breach logic fires; budget injection shows "unlimited"; no regression in existing runs (full scenario suite passes).
15. **AC-615:** State schema version bumps to `2.0.0` (coordinated with Phase 5/7 — single bump, not three); old state files (any `1.x.x`) get the cost block reset on load with a single INFO log entry. Verifies no-backcompat policy compliance.
16. **AC-616:** `shared/forge-token-tracker.sh` `DEFAULT_PRICING_TABLE` matches current Anthropic rates — Haiku 4.5 `{input: 1.00, output: 5.00}`, Sonnet 4.6 `{input: 3.00, output: 15.00}`, Opus 4.7 `{input: 5.00, output: 25.00}` — verified as the first commit of Phase 6 delivery. Asserted by `tests/unit/token-tracker-pricing.bats` (new) which reads the file and checks the literals.

## Cross-Phase Coordination

**State schema v2.0.0 is a coordinated bump across Phases 5/6/7.** Rather than chaining v1.11 (Phase 5) → v1.12 (Phase 6) → v1.13 (Phase 7), all three phases land a single v2.0.0 cut of `shared/state-schema.md`. Old state auto-resets on version mismatch per the no-backcompat policy — there is no migration path, no shim, no opt-in rollout.

Practical consequence: Phase 6 cannot ship `state.cost` reshape independently of Phase 5's reviewer-loading rework and Phase 7's (to-be-designed) fields. The three specs must agree on the merged schema before any one of them writes the final `"version": "2.0.0"` literal into `shared/state-schema.md`. Phase 6 owns §`cost` and §`cost_alerting` (deprecated-in-place); Phase 5 owns reviewer-loading metadata; Phase 7 owns whatever Phase 7 owns.

**OTel namespace contract.** All forge-emitted span attributes MUST use the `forge.*` root. Phase 4 currently emits `learning.*` unprefixed — that is a bug and a Phase-4 rename to `forge.learning.*` is a prerequisite for Phase 6 merging. This phase consistently uses `forge.cost.*`, `forge.agent.*`, and `forge.run.*` and does not introduce any unprefixed roots. The contract is cited in §Documentation Updates under `shared/observability.md`.

## Open Questions

1. **Cache-read discount in tier estimates.** Prompt caching reduces cached-input cost 90%. Derive `tier_estimates_usd` from cache-hit-rate? Initial answer: NO — keep static+user-editable, rely on `EST-DRIFT`. Revisit if drift is persistently downward.
2. **Sprint-mode ceiling.** Per-run or shared pool? Proposed: per-run (each child gets its own ceiling). Shared pool = Phase 7.
3. **Recovery vs cost.** If recovery dispatches would breach: cost ceiling wins. Recovery applications that would breach are skipped with `RECOVERY_SUPPRESSED_COST` INFO.
4. **Batch API.** 50% discount, 24h latency — not for interactive pipelines. `fg-700`/`fg-350` post-ship could batch in Phase 8.
5. **Default `pinned_agents` to safety list?** No — pinning blocks safe downgrades. Safety is handled by the separate hardcoded `SAFETY_CRITICAL` list (never-skip, can-still-downgrade-within-tiers).
