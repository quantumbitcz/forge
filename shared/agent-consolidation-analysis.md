# Agent Consolidation Analysis

Analysis of review agent overlap and consolidation candidates. This is an advisory document — no implementation changes are proposed here. Any consolidation would be a separate initiative.

**Date:** 2026-04-10
**Context:** 39 agent `.md` files (36 unique agents, orchestrator split across 4 files). 7 review agents dispatched per REVIEW cycle by the quality gate (`fg-400`).

## Review Agent Inventory

| Agent | Focus | System Prompt Cost |
|-------|-------|--------------------|
| `fg-410-code-reviewer` | Code quality (QUAL-*, TEST-*, CONV-*) | High (broad scope) |
| `fg-411-security-reviewer` | Security (SEC-*) | Medium (specialized) |
| `fg-413-frontend-reviewer` | Frontend (FE-PERF-*, A11Y-*, DESIGN-*) | Medium (4 modes) |
| `fg-416-backend-performance-reviewer` | Backend performance (PERF-*) | Medium (specialized) |
| `fg-417-version-compat-reviewer` | Version compatibility (COMPAT-*) | Low (narrow) |
| `fg-418-docs-consistency-reviewer` | Documentation (DOC-*) | Low (narrow) |
| `fg-419-infra-deploy-reviewer` | Infrastructure (INFRA-*) | Medium (specialized) |

## Overlap Analysis

| Agent Pair | Overlap Area | Consolidation Candidate? | Risk |
|------------|-------------|--------------------------|------|
| fg-410 (code) + fg-416 (perf) | Both check code quality patterns | **Yes** — PERF findings are a subset of code quality. Merge perf checks into fg-410 with a `focus: performance` mode. | Medium — perf checks may be less thorough when not the sole focus |
| fg-410 (code) + fg-418 (docs) | Minimal overlap | **No** — docs reviewer checks project docs, not code quality | — |
| fg-411 (security) + fg-410 (code) | Security findings sometimes overlap with QUAL-* | **No** — security requires specialized knowledge, keep separate | — |
| fg-413 (frontend) + fg-410 (code) | Frontend conventions overlap with general conventions | **Partial** — fg-413's `conventions-only` mode could be absorbed into fg-410 when reviewing frontend files | Low |
| fg-417 (version-compat) + fg-140 (deprecation) | Both check versions | **Yes** — merge into single version-aware agent that handles both deprecation and compatibility | Low — both are advisory |
| fg-419 (infra) standalone | No overlap with other reviewers | **No** — infra is a distinct domain | — |

## Recommended Consolidation Path (If Pursued)

1. **Merge fg-417 into fg-140** -> "fg-140-version-reviewer" (deprecation + compatibility)
   - Benefit: Eliminates 1 review agent system prompt load per cycle
   - Risk: Low (both are advisory, similar domain knowledge)
   - Effort: Medium (merge 2 agent files, update quality gate dispatch)

2. **Add `focus: performance` mode to fg-410** -> absorb fg-416 performance checks
   - Benefit: Eliminates 1 review agent system prompt load per cycle
   - Risk: Medium (performance checks may receive less attention in a multi-focus agent)
   - Effort: High (fg-410 is already the largest review agent)

3. **Keep fg-411, fg-413, fg-418, fg-419 separate** (distinct domains)
   - These agents serve clearly differentiated domains with minimal overlap

**Result if fully executed:** 7 reviewers -> 5 reviewers. Saves ~2 system prompt loads per review cycle.

## Not Recommended

**Merging pipeline agents** (fg-100/200/300/400/500/600) — these serve distinct pipeline stages and are already well-scoped. The orchestrator split (4 files) was introduced by P0 specifically to optimize token cost.

**Merging fg-411 (security)** — security review requires specialized knowledge and threat modeling perspective that would be diluted in a general code reviewer. The cost of a false negative in security exceeds the token savings.

## Token Cost Estimate

| Scenario | Review Agents | Estimated Prompt Tokens |
|----------|---------------|------------------------|
| Current (7 agents) | 7 | ~35K tokens per review cycle |
| After consolidation (5 agents) | 5 | ~28K tokens per review cycle |
| Savings | -2 agents | ~7K tokens per cycle (~20% reduction) |

Note: These are estimates. Actual token costs depend on system prompt sizes, which vary by agent.
