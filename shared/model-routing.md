# Model Routing

Defines how the orchestrator selects model tiers for agent dispatch. Read at PREFLIGHT from `forge-config.md`. Applied on every `Agent(...)` call.

## Tier Definitions

| Tier | Model Parameter | Use Case | Cost Ratio |
|------|----------------|----------|-----------|
| `fast` | `haiku` | Pattern matching, scaffolding, docs, deprecation refresh | ~0.05x |
| `standard` | `sonnet` | Default — most agents, reviewers, test gate | 1.0x (baseline) |
| `premium` | `opus` | Planning, validation, security review, architecture review, implementation, bug investigation | ~5x |

The `model` parameter on the Agent tool accepts exactly: `haiku`, `sonnet`, `opus`.

## Configuration

In `forge-config.md`:

    model_routing:
      enabled: true
      default_tier: standard
      overrides:
        tier_1_fast:
          - fg-310-scaffolder
          - fg-350-docs-generator
          - fg-130-docs-discoverer
          - fg-140-deprecation-refresh
        tier_3_premium:
          - fg-200-planner
          - fg-210-validator
          - fg-411-security-reviewer
          - fg-412-architecture-reviewer
          - fg-020-bug-investigator
          - fg-300-implementer

Agents not listed in any override use `default_tier`.

## Resolution Order

1. `forge-config.md` `model_routing.overrides.tier_*` — per-agent explicit tier
2. `forge-config.md` `model_routing.default_tier` — project default
3. Plugin default: `standard` (sonnet)

## Dispatch Integration

The orchestrator resolves the model tier for each agent **before** calling `Agent(...)`. The resolved model is passed as the `model` parameter:

    Agent(
      subagent_type: "forge:fg-200-planner",
      model: "opus",
      prompt: "..."
    )

When `model_routing.enabled` is `false`, the `model` parameter is omitted (Claude Code uses its default).

## Fallback Behavior

If the resolved model is unavailable at runtime (Claude Code returns an error mentioning model availability), the orchestrator:
1. Logs WARNING: "Model {tier} unavailable for {agent}, falling back to {default_tier}"
2. Retries with `default_tier`
3. If `default_tier` also fails, retries without `model` parameter (platform default)
4. Records the fallback in `state.json.tokens.model_fallbacks[]`

## PREFLIGHT Constraints

Validated at PREFLIGHT. If violated, log WARNING and use plugin defaults:

| Parameter | Valid Values | Default |
|-----------|-------------|---------|
| `model_routing.enabled` | `true`, `false` | `false` |
| `model_routing.default_tier` | `fast`, `standard`, `premium` | `standard` |
| `model_routing.overrides.tier_1_fast[]` | valid agent IDs from agent-registry.md | `[]` |
| `model_routing.overrides.tier_3_premium[]` | valid agent IDs from agent-registry.md | `[]` |

Agent IDs in overrides are validated against `shared/agent-registry.md`. Unknown agent IDs produce WARNING (typo protection) but do not fail PREFLIGHT.

## Retrospective Auto-Tuning

`fg-700-retrospective` may suggest tier changes based on:
- Finding quality per agent: if a `fast`-tier agent produces findings that are frequently overridden or have low confidence, suggest upgrading to `standard`
- Cost efficiency: if a `premium`-tier agent's findings are consistently identical to what a `standard`-tier run produces, suggest downgrading
- At most one model routing adjustment per run
- `default_tier` and `enabled` are never auto-tuned (intentional project decisions)

Auto-tuning respects `<!-- locked -->` fences in `forge-config.md`.

## Stage Notes

The orchestrator records model assignments in `stage_0_notes`:

    ## Model Routing
    - Mode: explicit
    - Default tier: standard (sonnet)
    - Overrides: 4 fast, 6 premium, 28 standard
    - Total agents: 38
