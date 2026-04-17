# Agent Role Hierarchy

Reference for agent UI tiers, dispatch relationships, and role classification.

## UI Tiers

### Tier 1 — Tasks + Ask + Plan

Full interactive capability: task tracking, user questions, plan mode.

| Agent | Role |
|---|---|
| `fg-010-shaper` | Feature shaping |
| `fg-015-scope-decomposer` | Multi-feature decomposition |
| `fg-050-project-bootstrapper` | Project scaffolding |
| `fg-090-sprint-orchestrator` | Sprint parallel orchestration |
| `fg-160-migration-planner` | Migration planning and execution |
| `fg-200-planner` | Implementation planning |

### Tier 2 — Tasks + Ask

Task tracking and user questions (no plan mode).

| Agent | Role |
|---|---|
| `fg-020-bug-investigator` | Bug reproduction and analysis |
| `fg-100-orchestrator` | Pipeline coordinator (never writes code) |
| `fg-103-cross-repo-coordinator` | Multi-repo orchestration |
| `fg-210-validator` | Plan validator (GO/REVISE/NO-GO across 7 perspectives; REVISE AskUserQuestion owned by orchestrator in 3.0.0, migrates here in Phase 4) |
| `fg-400-quality-gate` | Review dispatch and scoring |
| `fg-500-test-gate` | Test verification |
| `fg-600-pr-builder` | PR creation |
| `fg-710-post-run` | Post-pipeline feedback handling |

### Tier 3 — Tasks Only

Task tracking only (no user interaction).

| Agent | Role |
|---|---|
| `fg-130-docs-discoverer` | Documentation discovery |
| `fg-135-wiki-generator` | Wiki generation |
| `fg-140-deprecation-refresh` | Deprecation registry updates |
| `fg-150-test-bootstrapper` | Test infrastructure setup |
| `fg-250-contract-validator` | Consumer-driven contract validation |
| `fg-300-implementer` | TDD implementation (inner loop) |
| `fg-310-scaffolder` | Code scaffolding |
| `fg-320-frontend-polisher` | Frontend quality (conditional) |
| `fg-350-docs-generator` | Documentation generation |
| `fg-505-build-verifier` | Build verification |
| `fg-515-property-test-generator` | Property-based test generation (conditional) |
| `fg-590-pre-ship-verifier` | Evidence-based ship gate |
| `fg-610-infra-deploy-verifier` | Infrastructure verification (conditional) |
| `fg-620-deploy-verifier` | Deployment health monitoring (conditional) |
| `fg-650-preview-validator` | Preview environment validation |
| `fg-700-retrospective` | Run retrospective and learning |

### Tier 4 — None (Silent)

No UI capabilities. Produce findings only.

| Agent | Role |
|---|---|
| `fg-101-worktree-manager` | Worktree lifecycle |
| `fg-102-conflict-resolver` | Merge conflict resolution |
| `fg-205-planning-critic` | Silent adversarial plan reviewer; emits CRITIC findings consumed by fg-210-validator |
| `fg-410-code-reviewer` | Code quality review |
| `fg-411-security-reviewer` | Security review |
| `fg-412-architecture-reviewer` | Architecture review |
| `fg-413-frontend-reviewer` | Frontend review (4 modes) |
| `fg-416-performance-reviewer` | Performance review |
| `fg-417-dependency-reviewer` | Dependency review |
| `fg-418-docs-consistency-reviewer` | Documentation consistency |
| `fg-419-infra-deploy-reviewer` | Infrastructure review |
| `fg-510-mutation-analyzer` | Mutation testing analysis |

## Dispatch Graph

### Pipeline Dispatch (fg-100-orchestrator)

```
fg-100-orchestrator
  ├── PREFLIGHT
  │   ├── fg-101-worktree-manager
  │   ├── fg-130-docs-discoverer
  │   ├── fg-135-wiki-generator
  │   ├── fg-140-deprecation-refresh
  │   ├── fg-150-test-bootstrapper
  │   └── fg-160-migration-planner (migration mode)
  ├── EXPLORING
  │   └── (orchestrator performs directly)
  ├── PLANNING
  │   └── fg-200-planner
  ├── VALIDATING
  │   ├── fg-210-validator
  │   └── fg-250-contract-validator
  ├── IMPLEMENTING
  │   ├── fg-310-scaffolder (serial, first)
  │   ├── fg-300-implementer (parallel per task)
  │   └── fg-320-frontend-polisher (conditional)
  ├── VERIFYING
  │   ├── fg-505-build-verifier
  │   └── fg-500-test-gate
  ├── REVIEWING
  │   ├── fg-400-quality-gate (dispatches reviewers)
  │   └── fg-510-mutation-analyzer
  ├── DOCUMENTING
  │   └── fg-350-docs-generator
  ├── SHIPPING
  │   ├── fg-590-pre-ship-verifier
  │   ├── fg-600-pr-builder
  │   ├── fg-620-deploy-verifier (conditional)
  │   ├── fg-650-preview-validator (conditional)
  │   └── fg-610-infra-deploy-verifier (conditional)
  └── LEARNING
      ├── fg-700-retrospective
      └── fg-710-post-run
```

### Quality Gate Dispatch (fg-400-quality-gate)

```
fg-400-quality-gate
  ├── fg-410-code-reviewer (always)
  ├── fg-411-security-reviewer (always)
  ├── fg-412-architecture-reviewer (always)
  ├── fg-413-frontend-reviewer (if frontend files)
  ├── fg-416-performance-reviewer (always)
  ├── fg-417-dependency-reviewer (always)
  ├── fg-418-docs-consistency-reviewer (always)
  └── fg-419-infra-deploy-reviewer (if infra files)
```

### Pre-Pipeline Dispatch

```
/forge-shape     → fg-010-shaper
/forge-fix       → fg-020-bug-investigator
/forge-bootstrap → fg-050-project-bootstrapper
/forge-sprint    → fg-090-sprint-orchestrator
                     └── fg-100-orchestrator (per feature)
/forge-migration → fg-160-migration-planner
```

### Supporting Dispatch

```
fg-100-orchestrator
  ├── fg-102-conflict-resolver (on merge conflicts)
  └── fg-103-cross-repo-coordinator (multi-repo mode)

fg-015-scope-decomposer (from fg-100 when multi-feature detected)
  └── fg-090-sprint-orchestrator
```

## Related

- `shared/agent-consolidation-analysis.md` -- Analysis of potential agent consolidation opportunities
- `shared/agent-registry.md` -- Full agent registry with frontmatter
- `shared/agent-ui.md` -- UI capability rules and interaction patterns
- `shared/agent-philosophy.md` -- Agent design principles
