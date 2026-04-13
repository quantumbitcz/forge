# Model Routing

Defines how the orchestrator selects model tiers for agent dispatch. Read at PREFLIGHT from `forge-config.md`. Applied on every `Agent(...)` call. Enabled by default.

## Tier Definitions

| Tier | Model Parameter | Use Case | Cost Ratio |
|------|----------------|----------|-----------|
| `fast` | `haiku` | Pattern matching, scaffolding, docs, deprecation refresh, git operations, report generation | ~0.05x |
| `standard` | `sonnet` | Default — reviewers, test/build gates, coordinators, retrospective | 1.0x (baseline) |
| `premium` | `opus` | Planning, validation, implementation, architecture review, bug investigation, orchestration, shaping, scoping | ~5x |

The `model` parameter on the Agent tool accepts exactly: `haiku`, `sonnet`, `opus`.

## Default Tier Assignments

All 40 agents have explicit tier assignments (9 fast, 17 standard, 14 premium). Agents not listed in `tier_1_fast` or `tier_3_premium` overrides use `default_tier` (standard).

### Fast (haiku) — 9 agents

| Agent | Rationale |
|---|---|
| `fg-101-worktree-manager` | Git operations, deterministic commands |
| `fg-102-conflict-resolver` | Merge conflict resolution, pattern-based |
| `fg-130-docs-discoverer` | File listing and metadata extraction |
| `fg-135-wiki-generator` | Templated wiki generation from structured data |
| `fg-140-deprecation-refresh` | Pattern matching against deprecation registries |
| `fg-310-scaffolder` | File structure creation from templates |
| `fg-350-docs-generator` | Documentation generation from structured inputs |
| `fg-505-build-verifier` | Runs build/lint commands and reads output — deterministic |
| `fg-710-post-run` | Report generation and recap formatting |

These perform structured, template-driven, or command-execution tasks. Haiku handles them at equivalent quality because the reasoning is in the prompt/template, not in the model.

### Standard (sonnet) — 17 agents

| Agent | Rationale |
|---|---|
| `fg-250-contract-validator` | API contract validation, breaking change detection |
| `fg-410-code-reviewer` | Code quality analysis, convention matching |
| `fg-411-security-reviewer` | Security pattern detection, vulnerability assessment |
| `fg-413-frontend-reviewer` | UI/UX convention checking |
| `fg-416-backend-performance-reviewer` | Performance pattern detection |
| `fg-417-version-compat-reviewer` | Version compatibility analysis |
| `fg-418-docs-consistency-reviewer` | Documentation accuracy checking |
| `fg-419-infra-deploy-reviewer` | Infrastructure review |
| `fg-420-dependency-reviewer` | Dependency health analysis |
| `fg-400-quality-gate` | Review coordination, finding synthesis |
| `fg-500-test-gate` | Test coordination, Phase A/B routing |
| `fg-510-mutation-analyzer` | Mutation testing with LLM-generated mutants |
| `fg-590-pre-ship-verifier` | Evidence verification, build/test/lint |
| `fg-600-pr-builder` | PR description generation, Linear updates |
| `fg-610-infra-deploy-verifier` | Infrastructure deployment verification |
| `fg-650-preview-validator` | Preview environment validation |
| `fg-700-retrospective` | Run analysis, pattern detection, config tuning |

These perform analytical tasks requiring judgment (finding classification, severity assessment, pattern recognition) but do not make architectural decisions. Sonnet provides sufficient reasoning quality.

### Premium (opus) — 14 agents

| Agent | Rationale |
|---|---|
| `fg-010-shaper` | Requirement refinement, ambiguity resolution, stakeholder modeling |
| `fg-015-scope-decomposer` | Multi-feature decomposition, dependency analysis |
| `fg-020-bug-investigator` | Root cause analysis, reproduction strategy |
| `fg-050-project-bootstrapper` | Technology stack selection, architecture design |
| `fg-090-sprint-orchestrator` | Multi-feature coordination, dependency ordering |
| `fg-100-orchestrator` | Pipeline coordination, convergence decisions, escalation judgment |
| `fg-103-cross-repo-coordinator` | Cross-repository coordination |
| `fg-150-test-bootstrapper` | Test infrastructure setup and strategy |
| `fg-160-migration-planner` | Migration strategy, breaking change analysis |
| `fg-200-planner` | Implementation planning, task decomposition, acceptance criteria |
| `fg-210-validator` | 7-perspective plan validation, challenge brief review |
| `fg-300-implementer` | TDD implementation, code design, refactoring decisions |
| `fg-320-frontend-polisher` | Visual polish, design system alignment |
| `fg-412-architecture-reviewer` | Architectural boundary validation, SOLID analysis |

These make decisions that cascade through the pipeline. A poor plan (fg-200) wastes the entire implementation. A poor implementation (fg-300) triggers fix loops. A missed architecture violation (fg-412) survives to production. The premium tier's deeper reasoning directly prevents costly rework.

## Configuration

In `forge-config.md`:

    model_routing:
      enabled: true
      default_tier: standard
      overrides:
        tier_1_fast:
          - fg-101-worktree-manager
          - fg-102-conflict-resolver
          - fg-130-docs-discoverer
          - fg-135-wiki-generator
          - fg-140-deprecation-refresh
          - fg-310-scaffolder
          - fg-350-docs-generator
          - fg-710-post-run
        tier_3_premium:
          - fg-010-shaper
          - fg-015-scope-decomposer
          - fg-020-bug-investigator
          - fg-050-project-bootstrapper
          - fg-090-sprint-orchestrator
          - fg-100-orchestrator
          - fg-103-cross-repo-coordinator
          - fg-150-test-bootstrapper
          - fg-160-migration-planner
          - fg-200-planner
          - fg-210-validator
          - fg-300-implementer
          - fg-320-frontend-polisher
          - fg-412-architecture-reviewer

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

If the resolved model is unavailable at runtime (Claude Code returns an error mentioning model availability), the orchestrator applies a cascade:

    premium (opus)   -> standard (sonnet) -> [no model param] (platform default)
    standard (sonnet) -> [no model param] (platform default)
    fast (haiku)      -> [no model param] (platform default)

Steps:
1. Log WARNING: "Model {tier} unavailable for {agent}, falling back"
2. Retry with the next tier down in the cascade
3. If the fallback tier also fails, retry without `model` parameter (platform default)
4. Record each fallback in `state.json.tokens.model_fallbacks[]`

Max 2 retries per dispatch (original tier + 1 fallback + 1 no-param).

## PREFLIGHT Constraints

Validated at PREFLIGHT. If violated, log WARNING and use plugin defaults:

| Parameter | Valid Values | Default |
|-----------|-------------|---------|
| `model_routing.enabled` | `true`, `false` | `true` |
| `model_routing.default_tier` | `fast`, `standard`, `premium` | `standard` |
| `model_routing.overrides.tier_1_fast[]` | valid agent IDs from agent-registry.md | 8 agents (see Default Tier Assignments) |
| `model_routing.overrides.tier_3_premium[]` | valid agent IDs from agent-registry.md | 14 agents (see Default Tier Assignments) |

Agent IDs in overrides are validated against `shared/agent-registry.md`. Unknown agent IDs produce WARNING (typo protection) but do not fail PREFLIGHT.

## Retrospective Auto-Tuning

`fg-700-retrospective` may suggest tier changes based on:
- Finding quality per agent: if a `fast`-tier agent produces findings that are frequently overridden or have low confidence, suggest upgrading to `standard`
- Cost efficiency: if a `premium`-tier agent's findings are consistently identical to what a `standard`-tier run produces, suggest downgrading
- At most two model routing adjustments per run
- `default_tier` and `enabled` are never auto-tuned (intentional project decisions)

Auto-tuning respects `<!-- locked -->` fences in `forge-config.md`.

## Prompt Caching Strategy

Agent `.md` files serve as system prompts for dispatched agents. These files are static within a run (they change only when the plugin is updated). Prompt caching allows subsequent dispatches of the same agent to reuse the cached system prompt, reducing input token costs.

**Prompt prefix ordering:** For maximum cache hit rate, the orchestrator should construct dispatch prompts with static content first and dynamic content last:

1. **Static prefix** (cacheable): agent `.md` system prompt + convention files loaded for the component
2. **Dynamic suffix** (varies per dispatch): task specification, findings from previous iterations, stage notes, context snippets

This ordering ensures the longest possible cache prefix match. The Anthropic API automatically applies prompt caching when the same prefix is sent within the cache TTL — the cached portion is billed at the `cache_read` rate instead of the full `input` rate.

**Convention file stability:** Convention files loaded by agents are stable across a run (convention drift check in `fg-300-implementer` detects but does not modify them). Including conventions in the cached prefix maximizes cache efficiency.

This is advisory guidance for the orchestrator's dispatch logic. Model routing itself does not enforce prompt ordering.

## Stage Notes

The orchestrator records model assignments in `stage_0_notes`:

    ## Model Routing
    - Mode: enabled
    - Default tier: standard (sonnet)
    - Overrides: 9 fast, 14 premium, 17 standard (remaining)
    - Total agents: 40
