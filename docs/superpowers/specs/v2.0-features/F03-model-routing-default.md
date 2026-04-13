# F03: Model Routing Enabled by Default with Cascade Strategy

## Status
DRAFT — 2026-04-13

## Problem Statement

Model routing exists in `shared/model-routing.md` and is fully implemented in the orchestrator's dispatch logic, but it defaults to `enabled: false` in `forge-config-template.md` (line 131). When disabled, the orchestrator omits the `model` parameter from `Agent(...)` calls, and Claude Code uses its platform default (currently Sonnet) for every agent.

**Cost impact:** Running all 40 agents on Sonnet costs roughly 5-15x more than necessary. Agents like `fg-310-scaffolder` (file structure creation), `fg-130-docs-discoverer` (file listing), and `fg-101-worktree-manager` (git operations) perform pattern-matching tasks that Haiku handles at 0.05x the cost with equivalent quality. Conversely, agents like `fg-200-planner` and `fg-300-implementer` benefit materially from Opus-tier reasoning.

**Competitive landscape:** Amazon Q Developer uses multi-model routing by default. GitHub Copilot Workspace routes between models based on task complexity. OpenHands uses a cascade strategy with fallback. Codex routes to GPT-4o-mini for simple completions and GPT-4o for complex reasoning. Every major agentic coding tool does model routing. Forge does not, by default.

**Research validation:** Cascade routing (try cheaper model first, escalate on failure) achieves 70-90% cost reduction with <5% quality loss on standard benchmarks (Martian Router, RouteLLM, Anthropic's own prompt routing). System prompt caching provides an additional 45-80% cost reduction on cache hits (Anthropic prompt caching documentation, 2024).

**Gap:** The infrastructure exists but is off. Users must manually configure tier assignments. Most users never touch `forge-config.md` model routing section, so they run the entire pipeline on a single tier.

## Proposed Solution

1. Change the default from `enabled: false` to `enabled: true` with curated tier assignments.
2. Add pre-run cost estimation to help users understand expected spend before committing.
3. Implement cascade fallback (premium -> standard -> fast) for model availability failures.
4. Add retrospective-driven auto-tuning of tier assignments based on cost-per-quality-point.
5. Define a prompt caching strategy for agent `.md` system prompts.

## Detailed Design

### Architecture

```
/forge-run <requirement>
     |
     v
PREFLIGHT (fg-100-orchestrator)
     |
     +-- 1. Read model_routing config
     +-- 2. Validate tier assignments against agent-registry.md
     +-- 3. Resolve tier for each agent
     +-- 4. Estimate cost (NEW)
     +-- 5. Log tier map in stage_0_notes
     |
     v
Each Agent Dispatch
     |
     +-- Resolve model tier -> model parameter
     +-- Agent(subagent_type: "forge:fg-NNN-name", model: "opus", prompt: "...")
     +-- On model unavailable: cascade fallback (premium -> standard -> platform default)
     +-- Track tokens per agent per tier in forge-token-tracker.sh
     |
     v
LEARN (fg-700-retrospective)
     |
     +-- Analyze cost-per-quality-point per agent
     +-- Suggest tier adjustments (at most 2 per run, up from 1)
     +-- Record suggestions in forge-config.md (respecting locked fences)
```

### Tier Assignments

The default tier assignments are based on the cognitive complexity required by each agent. The classification uses three criteria:

1. **Decision depth:** Does the agent make architectural/design decisions (premium), analytical judgments (standard), or pattern-matching operations (fast)?
2. **Error cost:** Does a mistake cascade into fix loops (premium), produce recoverable findings (standard), or have minimal downstream impact (fast)?
3. **Token volume:** Does the agent process large codebases (premium for quality), moderate context (standard), or small/templated context (fast)?

#### Tier 1: Fast (Haiku)

| Agent | Rationale |
|---|---|
| `fg-101-worktree-manager` | Git operations, deterministic commands |
| `fg-102-conflict-resolver` | Merge conflict resolution, pattern-based |
| `fg-130-docs-discoverer` | File listing and metadata extraction |
| `fg-135-wiki-generator` | Templated wiki generation from structured data |
| `fg-140-deprecation-refresh` | Pattern matching against deprecation registries |
| `fg-310-scaffolder` | File structure creation from templates |
| `fg-350-docs-generator` | Documentation generation from structured inputs |
| `fg-505-build-verifier` | Build command execution and output parsing |
| `fg-710-post-run` | Report generation and recap formatting |

**9 agents.** These perform structured, template-driven, or command-execution tasks. Haiku handles them at equivalent quality because the "reasoning" is in the prompt/template, not in the model.

#### Tier 2: Standard (Sonnet)

| Agent | Rationale |
|---|---|
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
| `fg-150-test-bootstrapper` | Test infrastructure setup |

**17 agents.** These perform analytical tasks requiring judgment (finding classification, severity assessment, pattern recognition) but do not make architectural decisions. Sonnet provides sufficient reasoning quality.

#### Tier 3: Premium (Opus)

| Agent | Rationale |
|---|---|
| `fg-010-shaper` | Requirement refinement, ambiguity resolution, stakeholder modeling |
| `fg-015-scope-decomposer` | Multi-feature decomposition, dependency analysis |
| `fg-020-bug-investigator` | Root cause analysis, reproduction strategy |
| `fg-050-project-bootstrapper` | Technology stack selection, architecture design |
| `fg-090-sprint-orchestrator` | Multi-feature coordination, dependency ordering |
| `fg-100-orchestrator` | Pipeline coordination, convergence decisions, escalation judgment |
| `fg-103-cross-repo-coordinator` | Cross-repository coordination |
| `fg-160-migration-planner` | Migration strategy, breaking change analysis |
| `fg-200-planner` | Implementation planning, task decomposition, acceptance criteria |
| `fg-210-validator` | 7-perspective plan validation, challenge brief review |
| `fg-250-contract-validator` | API contract validation, breaking change detection |
| `fg-300-implementer` | TDD implementation, code design, refactoring decisions |
| `fg-320-frontend-polisher` | Visual polish, design system alignment |
| `fg-412-architecture-reviewer` | Architectural boundary validation, SOLID analysis |

**14 agents.** These make decisions that cascade through the pipeline. A poor plan (fg-200) wastes the entire implementation. A poor implementation (fg-300) triggers fix loops. A missed architecture violation (fg-412) survives to production. The premium tier's deeper reasoning directly prevents costly rework.

**Key changes from v1.20.1 defaults:**
- `fg-412-architecture-reviewer`: PROMOTED from standard to premium. Architecture review errors are the highest-cost misses (they survive review cycles).
- `fg-100-orchestrator`: ASSIGNED to premium. As the coordinator making convergence, escalation, and dispatch decisions, orchestrator quality directly impacts pipeline efficiency.
- `fg-505-build-verifier`: DEMOTED from standard to fast. Build verification is command execution + output parsing.
- `fg-710-post-run`: DEMOTED from standard to fast. Report generation from structured data.

### Pre-Run Cost Estimation

Before the pipeline enters EXPLORE (Stage 1), the orchestrator computes an estimated cost range based on:

1. **Requirement complexity classification:** Simple (5-8 stages, 1-3 tasks), Medium (8-10 stages, 3-8 tasks), Complex (10 stages, 8+ tasks, parallel groups)
2. **Expected agent dispatches per stage:** Based on mode (standard, bugfix, migration, bootstrap) and configured review agents
3. **Token estimates per agent per tier:** Based on agent `.md` file size (system prompt tokens) + expected input/output tokens from historical data

#### Estimation Algorithm

```
FUNCTION estimate_cost(requirement, mode, config):

  complexity = classify_complexity(requirement)
  # Simple: avg 15K tokens total, Medium: avg 40K, Complex: avg 80K+

  # Base token estimate per tier (tokens include system prompt + input + output)
  tier_tokens = {
    fast:     { per_dispatch: 2000,  system_prompt_cache_rate: 0.8 },
    standard: { per_dispatch: 5000,  system_prompt_cache_rate: 0.7 },
    premium:  { per_dispatch: 12000, system_prompt_cache_rate: 0.6 }
  }

  # Count expected dispatches per tier
  dispatches = count_expected_dispatches(mode, complexity, config)
  # Returns: { fast: N, standard: M, premium: K }

  # Pricing (per 1M tokens, current as of 2026-04 — loaded from shared/pricing.json)
  pricing = {
    fast:     { input: 0.25, output: 1.25, cache_read: 0.03 },
    standard: { input: 3.00, output: 15.00, cache_read: 0.30 },
    premium:  { input: 15.00, output: 75.00, cache_read: 1.50 }
  }

  total_low = 0
  total_high = 0
  for tier in [fast, standard, premium]:
    n = dispatches[tier]
    t = tier_tokens[tier]
    p = pricing[tier]
    cache_rate = t.system_prompt_cache_rate

    # Low estimate: high cache hit rate, minimal output
    tokens_input_low = n * t.per_dispatch * 0.6  # 60% of estimate
    tokens_output_low = n * t.per_dispatch * 0.2
    cache_tokens_low = tokens_input_low * cache_rate
    fresh_tokens_low = tokens_input_low * (1 - cache_rate)
    cost_low = (fresh_tokens_low * p.input + cache_tokens_low * p.cache_read + tokens_output_low * p.output) / 1_000_000

    # High estimate: low cache hit rate, verbose output, fix loops
    fix_multiplier = 1.5 if complexity == "complex" else 1.2
    tokens_input_high = n * t.per_dispatch * 1.2 * fix_multiplier
    tokens_output_high = n * t.per_dispatch * 0.4 * fix_multiplier
    cache_tokens_high = tokens_input_high * (cache_rate * 0.5)  # Lower cache rate
    fresh_tokens_high = tokens_input_high * (1 - cache_rate * 0.5)
    cost_high = (fresh_tokens_high * p.input + cache_tokens_high * p.cache_read + tokens_output_high * p.output) / 1_000_000

    total_low += cost_low
    total_high += cost_high

  return { low: round(total_low, 2), high: round(total_high, 2) }
```

**Output format** (displayed by orchestrator at PREFLIGHT):

```
## Cost Estimate
- Estimated cost: $0.45-$1.20
- Model routing: ENABLED (9 fast, 17 standard, 14 premium)
- Prompt caching: ENABLED (estimated 65% cache hit rate)
- Complexity: MEDIUM (6 tasks, standard mode)
```

**`shared/pricing.json`** — New file containing model pricing. Updated manually when Anthropic changes pricing. The orchestrator reads this at PREFLIGHT. If missing, cost estimation is skipped (not an error).

```json
{
  "version": "2026-04",
  "models": {
    "haiku": { "input_per_1m": 0.25, "output_per_1m": 1.25, "cache_read_per_1m": 0.03 },
    "sonnet": { "input_per_1m": 3.00, "output_per_1m": 15.00, "cache_read_per_1m": 0.30 },
    "opus": { "input_per_1m": 15.00, "output_per_1m": 75.00, "cache_read_per_1m": 1.50 }
  }
}
```

### Cascade Fallback Logic

When a model is unavailable at dispatch time, the orchestrator applies a cascade:

```
premium (opus) -> standard (sonnet) -> [no model param] (platform default)
standard (sonnet) -> [no model param] (platform default)
fast (haiku) -> [no model param] (platform default)
```

**Changes from v1.20.1:** The current fallback in `model-routing.md` (section "Fallback Behavior") already implements a 3-step cascade: resolved model -> default_tier -> no model param. This spec formalizes and extends it:

1. **Retry budget per dispatch:** Max 2 retries (original tier + 1 fallback + 1 no-param). Current behavior: 3 retries. Reduced to 2 because the third retry (no-param after default_tier failure) indicates a systemic issue.
2. **Circuit breaker:** After 3 consecutive fallbacks for the same tier within a run, mark that tier as `degraded` for the remainder of the run. All subsequent dispatches for that tier go directly to the fallback tier without attempting the original.
3. **Logging:** Each fallback emits a structured log entry to `state.json.tokens.model_fallbacks[]`:
   ```json
   {
     "agent": "fg-200-planner",
     "requested_tier": "premium",
     "actual_tier": "standard",
     "reason": "model_unavailable",
     "timestamp": "2026-04-13T10:30:00Z"
   }
   ```
4. **Quality impact tracking:** If a premium agent falls back to standard AND the quality gate later produces findings that map to that agent's domain, the retrospective correlates the fallback with the quality impact.

### Retrospective Auto-Tuning (Enhanced)

`fg-700-retrospective` already supports single-adjustment auto-tuning per `model-routing.md`. This spec enhances it:

**Increased adjustment budget:** Up to 2 tier changes per run (from 1). Rationale: with 40 agents across 3 tiers, single adjustments converge too slowly.

**New analysis metric: cost-per-quality-point (CPQP).**

```
CPQP(agent) = agent_token_cost / quality_contribution(agent)
```

Where:
- `agent_token_cost` = tokens consumed * tier price
- `quality_contribution` = findings produced that were confirmed fixed in subsequent iterations (positive contribution for reviewers) or tasks completed without fix loops (positive contribution for implementer)

**Auto-tuning rules (extending `model-routing.md` section "Retrospective Auto-Tuning"):**

| Pattern | Current Rule | Enhanced Rule |
|---|---|---|
| Fast agent produces frequently overridden findings | Suggest upgrade to standard | Upgrade to standard if CPQP > 2x median fast CPQP for 2+ consecutive runs |
| Premium agent findings identical to standard | Suggest downgrade to standard | Downgrade to standard if CPQP > 3x median standard CPQP AND quality_contribution is equivalent for 3+ runs |
| NEW: Standard agent triggers >2 fix loops per run | — | Upgrade to premium if the agent's fix-loop contribution exceeds mean by 1.5x for 2+ runs |
| NEW: Fast agent with 0 fallbacks and 0 quality issues | — | Confirm tier (no change needed, log "tier confirmed") |
| NEW: Premium agent with cascade fallbacks >50% of dispatches | — | Downgrade to standard (tier is unreliable at premium) |

**Constraints (unchanged):**
- `default_tier` and `enabled` are never auto-tuned
- Respects `<!-- locked -->` fences in `forge-config.md`
- Changes logged in `forge-log.md` with rationale

### Prompt Caching Strategy

Agent `.md` files serve as system prompts for dispatched agents. These files are static within a run (they change only when the plugin is updated). Prompt caching allows subsequent dispatches of the same agent to reuse the cached system prompt, reducing input token costs.

**How it works in Claude Code:**

Claude Code's Agent tool sends the agent's `.md` content as the system prompt. When the same system prompt is sent within the cache TTL (currently 5 minutes for Anthropic's API), the API automatically applies prompt caching -- the cached portion is billed at the `cache_read` rate instead of the full `input` rate.

**Forge's caching strategy:**

1. **Static system prompts:** Agent `.md` files are read once at dispatch time. Since forge is doc-only (no build step), these files are stable across a run. This naturally enables prompt caching for agents dispatched multiple times:
   - `fg-300-implementer`: dispatched per task (3-8 times per run)
   - `fg-410` through `fg-420` reviewers: dispatched per review cycle (1-3 times)
   - `fg-505-build-verifier`: dispatched per verify cycle (1-5 times)

2. **Prompt prefix ordering:** For maximum cache hit rate, the orchestrator constructs dispatch prompts with the static content (agent `.md` + conventions file) at the START of the prompt, and the dynamic content (task spec, findings, stage notes) at the END. This ensures the longest possible cache prefix match.

3. **Convention file stability:** Convention files loaded by agents are stable across a run (convention drift check in `fg-300-implementer` section 3 detects but does not modify them). Including conventions in the cached prefix maximizes cache efficiency.

4. **Cache hit rate tracking:** The orchestrator records estimated cache hit rates in `state.json.tokens`:
   ```json
   {
     "tokens": {
       "cache_hits": 45,
       "cache_misses": 12,
       "estimated_cache_savings_usd": 0.35
     }
   }
   ```

**Expected savings by tier:**

| Tier | Agents x Avg Dispatches | Cache Hit Rate | Savings |
|---|---|---|---|
| Fast (haiku) | 9 x 1.5 avg | 80% | ~$0.01-0.02 per run (already cheap) |
| Standard (sonnet) | 17 x 1.8 avg | 70% | ~$0.10-0.30 per run |
| Premium (opus) | 14 x 2.5 avg | 60% | ~$0.50-2.00 per run |

Total estimated caching savings: 30-50% of input token costs, or roughly $0.60-2.30 per run.

### Configuration Schema

Updated `model_routing:` section in `forge-config.md`:

```yaml
model_routing:
  enabled: true                    # DEFAULT CHANGED: was false, now true
  default_tier: standard           # Unchanged
  cost_estimation: true            # NEW: Show cost estimate at PREFLIGHT. Default: true.
  cascade_fallback: true           # NEW: Enable cascade on model unavailability. Default: true.
  circuit_breaker_threshold: 3     # NEW: Consecutive fallbacks before marking tier degraded. Default: 3.
  prompt_caching: true             # NEW: Optimize dispatch prompt ordering for cache hits. Default: true.
  overrides:
    tier_1_fast:                   # EXPANDED with curated defaults
      - fg-101-worktree-manager
      - fg-102-conflict-resolver
      - fg-130-docs-discoverer
      - fg-135-wiki-generator
      - fg-140-deprecation-refresh
      - fg-310-scaffolder
      - fg-350-docs-generator
      - fg-505-build-verifier
      - fg-710-post-run
    tier_3_premium:                # EXPANDED with curated defaults
      - fg-010-shaper
      - fg-015-scope-decomposer
      - fg-020-bug-investigator
      - fg-050-project-bootstrapper
      - fg-090-sprint-orchestrator
      - fg-100-orchestrator
      - fg-103-cross-repo-coordinator
      - fg-160-migration-planner
      - fg-200-planner
      - fg-210-validator
      - fg-250-contract-validator
      - fg-300-implementer
      - fg-320-frontend-polisher
      - fg-412-architecture-reviewer
```

**PREFLIGHT validation constraints (extending `model-routing.md`):**

| Parameter | Range | Default | Rationale |
|---|---|---|---|
| `model_routing.enabled` | boolean | `true` (CHANGED) | Opt-out for users who prefer single-tier |
| `model_routing.default_tier` | `fast`, `standard`, `premium` | `standard` | Unchanged |
| `model_routing.cost_estimation` | boolean | `true` | Disable to skip estimation overhead |
| `model_routing.cascade_fallback` | boolean | `true` | Disable to fail-fast on model unavailability |
| `model_routing.circuit_breaker_threshold` | 1-10 | 3 | Below 1 disables circuit breaker; above 10 is too permissive |
| `model_routing.prompt_caching` | boolean | `true` | Disable if prompt ordering causes issues |
| `model_routing.overrides.tier_1_fast[]` | valid agent IDs | 9 agents (listed above) | Validated against agent-registry.md |
| `model_routing.overrides.tier_3_premium[]` | valid agent IDs | 14 agents (listed above) | Validated against agent-registry.md |

### Data Flow

**PREFLIGHT (Stage 0):**

1. Orchestrator reads `model_routing` from `forge-config.md`
2. If `enabled: false`, proceed as v1.20.1 (no model param on dispatches)
3. Validate agent IDs in overrides against `shared/agent-registry.md` — unknown IDs produce WARNING
4. Build tier map: `{ agent_id: tier_name }` for all 40 agents
5. If `cost_estimation: true`: run estimation algorithm, output cost range
6. Log tier map in `stage_0_notes`: agent count per tier, total agents, mode
7. Set `state.json.model_routing.active: true`, `state.json.model_routing.tier_map: {...}`

**Each Agent Dispatch:**

1. Orchestrator resolves tier from tier map
2. Maps tier to model param: `fast -> "haiku"`, `standard -> "sonnet"`, `premium -> "opus"`
3. Check circuit breaker: if tier is `degraded`, use fallback tier directly
4. Dispatch: `Agent(subagent_type: "forge:fg-NNN-name", model: "opus", prompt: "...")`
5. On model error:
   a. Log fallback to `state.json.tokens.model_fallbacks[]`
   b. Cascade: try next tier down
   c. If cascaded tier also fails: dispatch without `model` param
   d. Update circuit breaker counter for the failed tier
6. Record tokens used in `forge-token-tracker.sh` with agent ID + model tier

**LEARN (Stage 9):**

1. `fg-700-retrospective` reads `state.json.tokens` (per-agent, per-tier breakdown)
2. Computes CPQP for each agent with sufficient data (>= 2 dispatches in this run)
3. Compares against rolling averages from previous runs (stored in `forge-log.md`)
4. Generates up to 2 tier adjustment suggestions
5. Applies adjustments to `forge-config.md` model_routing.overrides (respecting locked fences)

### Integration Points

| File | Change |
|---|---|
| `shared/model-routing.md` | Update default `enabled: false` -> `true`. Add cascade, circuit breaker, cost estimation, caching sections. Expand tier assignments. |
| `modules/frameworks/*/forge-config-template.md` | Update `model_routing:` block with `enabled: true` and curated tier lists |
| `agents/fg-100-orchestrator.md` | Add cost estimation logic to PREFLIGHT. Add circuit breaker tracking to dispatch logic. Update stage_0_notes format. |
| `agents/fg-700-retrospective.md` | Add CPQP analysis. Increase adjustment budget to 2. Add new auto-tuning rules. |
| `shared/state-schema.md` | Add `model_routing.active`, `model_routing.tier_map`, `model_routing.degraded_tiers[]` to state.json. Extend `tokens` with `cache_hits`, `cache_misses`, `estimated_cache_savings_usd`. |
| `shared/pricing.json` | NEW — model pricing reference |
| `shared/agent-defaults.md` | Update "Model Routing" section with new orchestrator responsibilities |
| `CLAUDE.md` | Update model routing description: "enabled by default (v2.0+)" |
| `shared/forge-token-tracker.sh` | Add per-tier token aggregation and cache hit tracking |

### Error Handling

**Failure mode 1: All tiers unavailable.**
- Cascade exhausted (original -> fallback -> no-param all fail)
- Action: Escalate to user with error: "Model unavailable: {agent} could not be dispatched after cascade fallback. Check API key and model access."
- Recovery: User resolves API access, then `/forge-resume`

**Failure mode 2: Pricing file missing.**
- `shared/pricing.json` not found
- Action: Skip cost estimation. Log INFO in stage notes: "Cost estimation skipped: pricing.json not found."
- No pipeline impact

**Failure mode 3: Circuit breaker triggers mid-run.**
- A tier is marked `degraded` after `circuit_breaker_threshold` consecutive fallbacks
- Action: All remaining dispatches for that tier use fallback. Log WARNING in stage notes.
- Retrospective records the degradation event for trend analysis

**Failure mode 4: Auto-tuning suggests invalid configuration.**
- PREFLIGHT validation catches invalid tier assignments on next run
- Action: WARNING logged, plugin defaults used for invalid entries

## Performance Characteristics

**Cost impact (per pipeline run):**

| Scenario | v1.20.1 (all Sonnet) | v2.0 (routed) | Savings |
|---|---|---|---|
| Simple feature (5 tasks) | ~$1.50-3.00 | ~$0.40-1.00 | 60-75% |
| Medium feature (8 tasks) | ~$3.00-6.00 | ~$0.80-2.00 | 65-75% |
| Complex feature (15 tasks) | ~$6.00-15.00 | ~$1.50-5.00 | 65-80% |
| Bugfix (3-5 tasks) | ~$1.00-2.50 | ~$0.30-0.80 | 65-75% |

**Prompt caching additional savings:** 30-50% reduction on input token costs on top of routing savings.

**Latency impact:** Model routing adds 0ms latency (tier resolution is a dictionary lookup). Cascade fallback adds 2-5s per fallback attempt (API round-trip). Circuit breaker eliminates repeated fallback latency for degraded tiers.

**Quality impact:** Premium agents (planner, implementer, architecture reviewer) run on the strongest model, potentially IMPROVING quality over the v1.20.1 all-Sonnet baseline. The net effect is: cheaper AND better for the agents that matter most.

## Testing Approach

### Structural Tests (`tests/structural/`)

1. **Default enabled:** `model-routing.md` and all `forge-config-template.md` files show `enabled: true`
2. **Tier coverage:** Every agent in `agent-registry.md` appears in exactly one tier (fast, standard, or premium via default)
3. **Agent ID validity:** All IDs in `tier_1_fast` and `tier_3_premium` exist in `agent-registry.md`
4. **Pricing file schema:** `shared/pricing.json` exists and has required fields

### Unit Tests (`tests/unit/`)

1. **`model-routing.bats`:**
   - Tier resolution returns correct model for each tier
   - Agents not in overrides use `default_tier`
   - Invalid agent IDs produce WARNING, not error
   - `enabled: false` omits model parameter
   - Circuit breaker triggers after threshold consecutive fallbacks
   - Circuit breaker resets on successful dispatch to degraded tier

2. **`cost-estimation.bats`:**
   - Simple requirement produces lower estimate than complex
   - Missing pricing.json skips estimation without error
   - Estimate includes caching discount when prompt_caching enabled

### Scenario Tests (`tests/scenario/`)

1. **`model-routing-cascade.bats`:**
   - Premium unavailable cascades to standard
   - Standard unavailable cascades to platform default
   - Fallback logged in state.json
   - Circuit breaker prevents repeated failures

## Acceptance Criteria

1. Model routing defaults to `enabled: true` in all config templates and `model-routing.md`
2. All 40 agents have explicit tier assignments (9 fast, 17 standard, 14 premium)
3. Pre-run cost estimate displayed at PREFLIGHT when `cost_estimation: true`
4. Cascade fallback works when a model tier is unavailable
5. Circuit breaker prevents repeated cascade attempts for the same tier
6. Retrospective analyzes cost-per-quality-point and suggests up to 2 tier adjustments
7. Prompt ordering optimized for cache hit rate (static prefix, dynamic suffix)
8. `state.json.tokens` tracks per-agent, per-tier token usage and cache statistics
9. `./tests/validate-plugin.sh` passes with new default configuration
10. Existing projects with `enabled: false` in their `forge-config.md` are NOT affected (explicit config overrides new default)
11. `shared/pricing.json` exists with current model pricing

## Migration Path

**From v1.20.1 to v2.0:**

1. **Existing projects with explicit `model_routing.enabled: false`:** No change. Their explicit config overrides the new default. They continue running all agents on Sonnet.

2. **Existing projects with no model_routing section:** On next run, PREFLIGHT reads the new default (`enabled: true`) from the template. Behavior changes: agents now get tier-appropriate models. This is the intended upgrade path. The cost estimate at PREFLIGHT surfaces the expected cost so users can verify before committing.

3. **Existing projects with custom overrides (e.g., `tier_3_premium: [fg-200-planner]`):** Their overrides are preserved. New default agents added to `tier_1_fast` and `tier_3_premium` in the template only apply if the project regenerates its config (via `/forge-init` or manual update). Agents in user overrides are NOT overwritten.

4. **Rollback:** Users can set `model_routing.enabled: false` in `forge-config.md` to revert to v1.20.1 behavior. No other changes needed.

5. **Partial adoption:** Users can customize tier assignments: move agents between tiers or set `default_tier: premium` to run most agents on Opus. The system is fully configurable.

**Breaking change assessment:** This is a **behavioral change** (agents now run on different models by default) but NOT a breaking change (output format, state schema, and hook contracts are unchanged). Quality should improve for premium-tier agents and remain equivalent for others.

## Dependencies

**This feature depends on:**
- Claude Code Agent tool `model` parameter (already supported)
- Anthropic API prompt caching (automatically applied by the platform)
- `shared/agent-registry.md` for agent ID validation
- `shared/forge-token-tracker.sh` for per-tier token tracking

**Other features that depend on this:**
- F02 (Linter-Gated Editing): benefits from routing -- lower-tier models produce more syntax errors, caught by L0
- F04 (Inner-Loop Lint+Test): the implementer runs on premium tier, making inner-loop reasoning higher quality

**Other features that benefit from this (no hard dependency):**
- All pipeline modes benefit from cost reduction
- Sprint mode (`fg-090-sprint-orchestrator`) benefits the most due to multiple concurrent pipelines
