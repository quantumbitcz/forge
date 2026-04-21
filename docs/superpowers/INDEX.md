# Forge A+ Roadmap — Specs, Plans, Reviews

This directory contains the design specs, implementation plans, and code reviews for the forge plugin's A+ roadmap. It covers every weakness and gap identified in the April 2026 architecture audit.

**Branch:** `docs/a-plus-roadmap-specs`
**Date:** 2026-04-19
**Methodology:** Anthropic Superpowers — `brainstorming` (specs) → `requesting-code-review` (reviews) → `writing-plans` (plans) → `requesting-code-review` (plan reviews)
**Constraints:** No backwards compatibility (break things freely). No local test execution — rely on CI.

## Roadmap overview

15 phases grouped by priority. Total: ~6,200 lines of specs + ~30,500 lines of implementation plans across 249 tasks.

| P | # | Phase | Status | Spec | Plan (tasks) | Spec review | Plan review |
|---|---|---|---|---|---|---|---|
| P0 | 01 | Evaluation Harness | Done | [spec](specs/2026-04-19-01-evaluation-harness-design.md) (327L) | [plan](plans/2026-04-19-01-evaluation-harness-plan.md) (2815L, 20) | [CONCERNS](reviews/2026-04-19-01-evaluation-harness-spec-review.md) | [CONCERNS](reviews/2026-04-19-01-evaluation-harness-plan-review.md) |
| P0 | 02 | Cross-Platform Python Hooks | Done | [spec](specs/2026-04-19-02-cross-platform-python-hooks-design.md) (497L) | [plan](plans/2026-04-19-02-cross-platform-python-hooks-plan.md) (3506L, 23) | [REVISE](reviews/2026-04-19-02-cross-platform-python-hooks-spec-review.md) | [APPROVE](reviews/2026-04-19-02-cross-platform-python-hooks-plan-review.md) |
| P0 | 03 | Prompt Injection Hardening | Done | [spec](specs/2026-04-19-03-prompt-injection-hardening-design.md) (413L) | [plan](plans/2026-04-19-03-prompt-injection-hardening-plan.md) (2388L, 23) | [APPROVE](reviews/2026-04-19-03-prompt-injection-hardening-spec-review.md) | [APPROVE](reviews/2026-04-19-03-prompt-injection-hardening-plan-review.md) |
| P0 | 04 | Implementer Reflection (CoVe) | Done | [spec](specs/2026-04-19-04-implementer-reflection-cove-design.md) (472L) | [plan](plans/2026-04-19-04-implementer-reflection-cove-plan.md) (1312L, 17) | [APPROVE](reviews/2026-04-19-04-implementer-reflection-cove-spec-review.md) | [APPROVE](reviews/2026-04-19-04-implementer-reflection-cove-plan-review.md) |
| P1 | 05 | Skill Consolidation (35→28) | Done | [spec](specs/2026-04-19-05-skill-consolidation-design.md) (404L) | [plan](plans/2026-04-19-05-skill-consolidation-plan.md) (1622L, 12) | [APPROVE](reviews/2026-04-19-05-skill-consolidation-spec-review.md) | [APPROVE](reviews/2026-04-19-05-skill-consolidation-plan-review.md) |
| P1 | 06 | Documentation Architecture | Partial | [spec](specs/2026-04-19-06-documentation-architecture-design.md) (438L) | [plan](plans/2026-04-19-06-documentation-architecture-plan.md) (2116L, 19) | [APPROVE](reviews/2026-04-19-06-documentation-architecture-spec-review.md) | [APPROVE](reviews/2026-04-19-06-documentation-architecture-plan-review.md) |
| P1 | 07 | Agent Layer Refactor | Done | [spec](specs/2026-04-19-07-agent-layer-refactor-design.md) (385L) | [plan](plans/2026-04-19-07-agent-layer-refactor-plan.md) (1694L, 15) | [APPROVE](reviews/2026-04-19-07-agent-layer-refactor-spec-review.md) | [APPROVE](reviews/2026-04-19-07-agent-layer-refactor-plan-review.md) |
| P1 | 08 | Module Additions (Flask/Laravel/Rails/Swift) | Done | [spec](specs/2026-04-19-08-module-additions-design.md) (493L) | [plan](plans/2026-04-19-08-module-additions-plan.md) (1151L, 6) | [APPROVE](reviews/2026-04-19-08-module-additions-spec-review.md) | [REVISIONS](reviews/2026-04-19-08-module-additions-plan-review.md) |
| P1 | 09 | OpenTelemetry GenAI Semconv | Done | [spec](specs/2026-04-19-09-otel-genai-semconv-design.md) (420L) | [plan](plans/2026-04-19-09-otel-genai-semconv-plan.md) (2362L, 18) | [APPROVE](reviews/2026-04-19-09-otel-genai-semconv-spec-review.md) | [APPROVE](reviews/2026-04-19-09-otel-genai-semconv-plan-review.md) |
| P2 | 10 | Repo-Map PageRank | Done | [spec](specs/2026-04-19-10-repo-map-pagerank-design.md) (350L) | [plan](plans/2026-04-19-10-repo-map-pagerank-plan.md) (2312L, 16) | [APPROVE](reviews/2026-04-19-10-repo-map-pagerank-spec-review.md) | [APPROVE](reviews/2026-04-19-10-repo-map-pagerank-plan-review.md) |
| P2 | 11 | Self-Consistency Voting | Done | [spec](specs/2026-04-19-11-self-consistency-voting-design.md) (565L) | [plan](plans/2026-04-19-11-self-consistency-voting-plan.md) (1601L, 14) | [APPROVE](reviews/2026-04-19-11-self-consistency-voting-spec-review.md) | [APPROVE](reviews/2026-04-19-11-self-consistency-voting-plan-review.md) |
| P2 | 12 | Speculative Plan Branches | Done | [spec](specs/2026-04-19-12-speculative-plan-branches-design.md) (520L) | [plan](plans/2026-04-19-12-speculative-plan-branches-plan.md) (2425L, 17) | [APPROVE](reviews/2026-04-19-12-speculative-plan-branches-spec-review.md) | [APPROVE](reviews/2026-04-19-12-speculative-plan-branches-plan-review.md) |
| P2 | 13 | Memory Decay (Ebbinghaus) | Done | [spec](specs/2026-04-19-13-memory-decay-ebbinghaus-design.md) (304L) | [plan](plans/2026-04-19-13-memory-decay-ebbinghaus-plan.md) (1571L, 18) | [APPROVE](reviews/2026-04-19-13-memory-decay-ebbinghaus-spec-review.md) | [APPROVE](reviews/2026-04-19-13-memory-decay-ebbinghaus-plan-review.md) |
| P2 | 14 | Time-Travel Checkpoints | Done | [spec](specs/2026-04-19-14-time-travel-checkpoints-design.md) (199L) | [plan](plans/2026-04-19-14-time-travel-checkpoints-plan.md) (2121L, 15) | [APPROVE](reviews/2026-04-19-14-time-travel-checkpoints-spec-review.md) | [APPROVE](reviews/2026-04-19-14-time-travel-checkpoints-plan-review.md) |
| P2 | 15 | Reference Deployment + Marketplace | Blocked | [spec](specs/2026-04-19-15-reference-deployment-design.md) (415L) | [plan](plans/2026-04-19-15-reference-deployment-plan.md) (1534L, 16) | [APPROVE](reviews/2026-04-19-15-reference-deployment-spec-review.md) | [APPROVE](reviews/2026-04-19-15-reference-deployment-plan-review.md) |

## Dependency graph

```
Phase 01 (Eval Harness)  ──┬──► 04, 10, 11, 12, 13, 14, 15
                           │
Phase 02 (Python Hooks)  ──┼──► 09, 10, 11, 12, 13, 14
                           │
Phase 03 (Prompt Injection) independent
Phase 05 (Skill Consolidation) independent
Phase 06 (Docs Architecture) ──► 07 (agent-* docs merged)
Phase 07 (Agent Refactor) independent of runtime phases
Phase 08 (Modules) independent
Phase 15 (Reference Deployment) depends on 01-14 shipped
```

**Suggested execution order:**
1. Phase 01 (eval harness) — foundational measurement
2. Phase 02 (Python hooks) — cross-platform; unblocks 09, 10-14
3. Phases 03, 04 in parallel (security + reflection)
4. Phases 05, 06, 07, 08 in parallel (consolidation + coverage)
5. Phase 09 (OTel) after 02
6. Phases 10-14 in parallel (advanced patterns) after 01, 02
7. Phase 15 (marketing) last

## Priority rationale

- **P0** — without it, forge cannot prove improvement (01), lose Windows users (02), is injection-vulnerable (03), produces wrong-but-passing implementations (04).
- **P1** — sprawl drag (05, 06), coverage gaps (07, 08), observability blind spots (09).
- **P2** — advanced patterns lifting quality 5-15% each; fine to ship after P0/P1 validated.

## How to use this roadmap

1. **Pick a phase** and read the design spec.
2. **Read the spec review** to understand known weaknesses in the design.
3. **Read the implementation plan** — it addresses spec-review feedback in its top "Review feedback incorporated" section.
4. **Read the plan review** to understand remaining gotchas.
5. **Execute the plan** task-by-task. The plan uses `superpowers:writing-plans` TDD format with checkbox steps.
6. **Run `superpowers:requesting-code-review`** after each task per the plan's embedded methodology.

## Status legend

- **Done** — shipped to master (skipped final-validation tasks counted as done; CI enforces them automatically)
- **Partial** — majority of tasks shipped; remaining work is tracked in the relevant plan file
- **Blocked** — prerequisite phases still in flight

### Phase 06 remaining work

Phase 06 (Documentation Architecture) is the only "Partial" row. Shipped: Tasks 1–6, 8–10, 14–18 and T16 Step 1. Outstanding: T7 (state-schema split — high-risk, reserved for a dedicated session), T11–T13 (rewrite `agent-communication.md`, delete the three merged sources, sweep cross-refs repo-wide — unblocked now that T10 has landed), and T16 Steps 2–4.

## Review verdict legend

- **APPROVE** — ready to execute; only suggestions
- **APPROVE WITH MINOR** — minor mechanical fixes; execute with caution
- **CONCERNS / REVISIONS** — substantive issues; resolve during implementation (review issues captured in plan's top section)
- **REVISE / FAIL** — blocker; fix before execution

## Known blockers to resolve at implementation time

| Phase | Blocker | Source |
|---|---|---|
| 01 | Fixture recipes for scenarios 05/06/10 deferred; TDD gaps in Task 6 | Plan review |
| 08 | 6 tasks for ~40 file touches; Task 2 has 13 steps (too large) | Plan review |
| 11 | Agent-to-Python dispatch bridge not defined (blocker) | Plan review |
| 14 | Task 3 method placement ambiguity (module-level vs class) | Plan review |

Implementers should read the relevant plan-review file first and plan to address these items in-flight.

## Methodology

This roadmap was produced entirely by the Anthropic **Superpowers** plugin skills:

- `superpowers:brainstorming` → design spec format
- `superpowers:writing-plans` → implementation plan format (TDD, bite-sized tasks, complete code, commit steps)
- `superpowers:requesting-code-review` → dispatched `superpowers:code-reviewer` subagent for each spec + plan
- `superpowers:dispatching-parallel-agents` → 15 agents in parallel per phase (writing, reviewing, writing plans, reviewing plans)

Total subagent dispatches: 60 (4 rounds × 15 phases). Wall-clock: ~3 rounds of ~3-4 minutes each (fully parallelized within each round).
