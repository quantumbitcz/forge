# Agent Registry

Single source of truth for all forge agents. When referencing an agent in skills or shared documents, use the exact ID from this table. When adding, renaming, or removing an agent, update this registry FIRST.

## Registry

| Agent ID | Tier | Dispatches? | Pipeline Stage | Category |
|---|---|---|---|---|
| fg-010-shaper | 1 | Yes | Pre-pipeline | Shaping |
| fg-015-scope-decomposer | 1 | Yes | Pre-pipeline | Decomposition |
| fg-020-bug-investigator | 2 | Yes | Pre-pipeline | Investigation |
| fg-050-project-bootstrapper | 1 | Yes | Pre-pipeline | Bootstrap |
| fg-090-sprint-orchestrator | 1 | Yes | Sprint | Orchestration |
| fg-100-orchestrator | 2 | Yes | Core | Orchestration |
| fg-101-worktree-manager | 4 | No | Core | Git |
| fg-102-conflict-resolver | 4 | No | Core | Analysis |
| fg-103-cross-repo-coordinator | 2 | Yes | Core | Coordination |
| fg-130-docs-discoverer | 3 | No | Preflight | Discovery |
| fg-135-wiki-generator | 3 | No | Preflight | Documentation |
| fg-140-deprecation-refresh | 3 | No | Preflight | Maintenance |
| fg-150-test-bootstrapper | 3 | Yes | Preflight | Testing |
| fg-155-i18n-validator | 3 | No | Preflight | i18n |
| fg-160-migration-planner | 1 | Yes | Preflight | Migration |
| fg-200-planner | 1 | Yes | Plan | Planning |
| fg-205-planning-critic | 4 | No | Plan | Quality |
| fg-210-validator | 4 | No | Validate | Validation |
| fg-250-contract-validator | 3 | Yes | Validate | Contracts |
| fg-300-implementer | 3 | No | Implement | TDD |
| fg-301-implementer-critic | 4 | No | Implement | Reflection (CoVe) |
| fg-310-scaffolder | 3 | Yes | Implement | Scaffolding |
| fg-320-frontend-polisher | 3 | No | Implement | Frontend |
| fg-350-docs-generator | 3 | Yes | Document | Documentation |
| fg-400-quality-gate | 2 | Yes | Review | Coordination |
| fg-410-code-reviewer | 4 | No | Review | Quality |
| fg-411-security-reviewer | 4 | No | Review | Security |
| fg-412-architecture-reviewer | 4 | No | Review | Architecture |
| fg-413-frontend-reviewer | 4 | No | Review | Frontend |
| fg-416-performance-reviewer | 4 | No | Review | Performance |
| fg-417-dependency-reviewer | 4 | No | Review | Dependencies |
| fg-418-docs-consistency-reviewer | 4 | No | Review | Documentation |
| fg-419-infra-deploy-reviewer | 4 | No | Review | Infrastructure |
| fg-500-test-gate | 2 | Yes | Verify | Coordination |
| fg-505-build-verifier | 3 | No | Verify | Build |
| fg-510-mutation-analyzer | 4 | No | Verify | Testing |
| fg-515-property-test-generator | 3 | No | Verify | Testing |
| fg-590-pre-ship-verifier | 3 | Yes | Ship | Verification |
| fg-600-pr-builder | 2 | Yes | Ship | Shipping |
| fg-610-infra-deploy-verifier | 3 | No | Ship | Infrastructure |
| fg-620-deploy-verifier | 3 | No | Ship | Deployment |
| fg-650-preview-validator | 3 | No | Ship | Preview |
| fg-700-retrospective | 3 | No | Learn | Learning |
| fg-710-post-run | 2 | No | Learn | Feedback |

## Tier Definitions

| Tier | UI Capabilities | Description |
|------|-----------------|-------------|
| 1 | tasks + ask + plan_mode | Entry-point agents with full user interaction (shaper, planner, bootstrapper, sprint orchestrator) |
| 2 | tasks + ask | Coordinators that track progress and escalate decisions (orchestrator, quality gate, PR builder) |
| 3 | tasks | Internal agents that report progress but don't ask questions (implementer, scaffolder, reviewers with tasks) |
| 4 | none | Read-only analyzers with no user interaction (all review agents, validator, worktree manager) |

## AI-* Category Assignments

| Category Prefix | Primary Agent | Secondary Agent |
|---|---|---|
| `AI-LOGIC-*` | fg-410-code-reviewer | — |
| `AI-PERF-*` | fg-416-performance-reviewer | — |
| `AI-CONCURRENCY-*` | fg-410-code-reviewer | fg-416-performance-reviewer |
| `AI-SEC-*` | fg-411-security-reviewer | — |

## Rules

1. Agent IDs follow the pattern `fg-{NNN}-{role}` where NNN determines pipeline ordering
2. When referencing an agent in a skill or shared doc, use the exact ID from this table
3. When adding a new agent, add a row here BEFORE creating the agent file
4. When removing an agent, remove the row here AND grep for references across skills/shared docs
5. The Dispatches? column indicates whether the agent has `Agent` in its tools list
