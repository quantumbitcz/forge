# Agents — Model, UI Tiers, Dispatch, Registry

> Canonical entry point for *who the agents are*, *how they are classified*, and *how they are dispatched*.
> Runtime communication protocols (stage notes, findings dedup, conflict resolution, PREEMPT tracking,
> structured output) live in [`agent-communication.md`](agent-communication.md). Design principles live
> in [`agent-philosophy.md`](agent-philosophy.md).

<a id="model"></a>

## Model

Forge currently ships 48 agents, each declared as a self-contained Markdown file at `agents/fg-NNN-<role>.md`. The orchestrator loads the agent file as the sub-agent system prompt, so every line in that file is a runtime token cost — keep them terse. See [`agent-philosophy.md`](agent-philosophy.md) for the design rules.

**What an agent IS.** A YAML frontmatter block declaring:

- `name` — must match the filename without the `.md` suffix (validated structurally).
- `description` — short trigger description. Tier 1 entry agents may include an example; Tier 4 leaves stay one-line.
- `tools` — the explicit tool allowlist. Dispatch agents include `Agent` in this list; every other agent is a *leaf* (can report findings but cannot dispatch further sub-agents).
- `ui:` — the UI-capability tier (1–4), explicit per `shared/agent-ui.md`. Implicit Tier-4-by-omission is no longer accepted.
- `color:` — cluster color for the task timeline (see [`agent-colors.md`](agent-colors.md)).

The body of the file is the system prompt: role, constraints, dispatch contract, and output format. Shared constraint language lives in [`agent-defaults.md`](agent-defaults.md) so individual agents can reference it instead of duplicating text.

**What an agent DOES.** An agent's runtime behavior is resolved by three axes:

1. Its **UI tier** (§UI Tiers below) — which of `TaskCreate`/`TaskUpdate`, `AskUserQuestion`, and `EnterPlanMode`/`ExitPlanMode` it may call.
2. Its **cluster** (color) — a visual grouping in the Claude Code task tree; see [`agent-colors.md`](agent-colors.md).
3. Its **position in the dispatch graph** (§Dispatch Graph below) — who dispatches it, whom (if anyone) it dispatches, and the stage it runs in.

Runtime wiring lives in [`agent-ui.md`](agent-ui.md) (task nesting, AskUserQuestion patterns) and in [`agent-communication.md`](agent-communication.md) (stage notes, dedup hints, PREEMPT markers, structured output).

**Who the agents ARE.** 48 agents distributed across the 10 pipeline stages (PREFLIGHT → EXPLORE → PLAN → VALIDATE → IMPLEMENT → VERIFY → REVIEW → DOCS → SHIP → LEARN) plus pre-pipeline entry points and supporting roles. The authoritative list lives in §Registry at the bottom of this file. Every new agent requires **four** coordinated updates:

1. A row in §Registry.
2. A tier assignment in §UI Tiers (and matching `ui:` frontmatter).
3. An entry in the dispatch graph (§Dispatch Graph) if the agent has a deterministic caller.
4. For Tier-4 reviewers: a color-cluster assignment and, where applicable, a contract-test eval directory.

Anything missing trips the structural validator at `tests/validate-plugin.sh`.

<a id="ui-tiers"></a>

## UI Tiers

<a id="tier-1"></a>

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

<a id="tier-2"></a>

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

<a id="tier-3"></a>

### Tier 3 — Tasks Only

Task tracking only (no user interaction).

| Agent | Role |
|---|---|
| `fg-130-docs-discoverer` | Documentation discovery |
| `fg-135-wiki-generator` | Wiki generation |
| `fg-140-deprecation-refresh` | Deprecation registry updates |
| `fg-143-observability-bootstrap` | Observability bootstrap (conditional) |
| `fg-150-test-bootstrapper` | Test infrastructure setup |
| `fg-155-i18n-validator` | i18n static validation (conditional) |
| `fg-250-contract-validator` | Consumer-driven contract validation |
| `fg-300-implementer` | TDD implementation (inner loop) |
| `fg-310-scaffolder` | Code scaffolding |
| `fg-320-frontend-polisher` | Frontend quality (conditional) |
| `fg-350-docs-generator` | Documentation generation |
| `fg-505-build-verifier` | Build verification |
| `fg-506-migration-verifier` | Migration verification (migration mode) |
| `fg-515-property-test-generator` | Property-based test generation (conditional) |
| `fg-555-resilience-tester` | Resilience testing (conditional) |
| `fg-590-pre-ship-verifier` | Evidence-based ship gate |
| `fg-610-infra-deploy-verifier` | Infrastructure verification (conditional) |
| `fg-620-deploy-verifier` | Deployment health monitoring (conditional) |
| `fg-650-preview-validator` | Preview environment validation |
| `fg-700-retrospective` | Run retrospective and learning |

<a id="tier-4"></a>

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
| `fg-414-license-reviewer` | License compliance review (SPDX policy + change detection) |
| `fg-416-performance-reviewer` | Performance review |
| `fg-417-dependency-reviewer` | Dependency review |
| `fg-418-docs-consistency-reviewer` | Documentation consistency |
| `fg-419-infra-deploy-reviewer` | Infrastructure review |
| `fg-510-mutation-analyzer` | Mutation testing analysis |

<a id="dispatch"></a>

## Dispatch Graph

<a id="pipeline-dispatch"></a>

### Pipeline Dispatch (fg-100-orchestrator)

```
fg-100-orchestrator
  ├── PREFLIGHT
  │   ├── fg-101-worktree-manager
  │   ├── fg-130-docs-discoverer
  │   ├── fg-135-wiki-generator
  │   ├── fg-140-deprecation-refresh
  │   ├── fg-143-observability-bootstrap   (conditional: observability_bootstrap.enabled)
  │   ├── fg-150-test-bootstrapper
  │   ├── fg-155-i18n-validator            (conditional: i18n_validator.enabled, default true)
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
  │   ├── fg-506-migration-verifier        (conditional: mode == "migration")
  │   ├── fg-500-test-gate
  │   └── fg-555-resilience-tester         (conditional: resilience_testing.enabled)
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

<a id="quality-gate-dispatch"></a>

### Quality Gate Dispatch (fg-400-quality-gate)

```
fg-400-quality-gate
  ├── fg-410-code-reviewer (always)
  ├── fg-411-security-reviewer (always)
  ├── fg-412-architecture-reviewer (always)
  ├── fg-413-frontend-reviewer (if frontend files)
  ├── fg-414-license-reviewer (always)
  ├── fg-416-performance-reviewer (always)
  ├── fg-417-dependency-reviewer (always)
  ├── fg-418-docs-consistency-reviewer (always)
  └── fg-419-infra-deploy-reviewer (if infra files)
```

<a id="pre-pipeline-dispatch"></a>

### Pre-Pipeline Dispatch

```
/forge-shape     → fg-010-shaper
/forge-fix       → fg-020-bug-investigator
/forge-bootstrap → fg-050-project-bootstrapper
/forge-sprint    → fg-090-sprint-orchestrator
                     └── fg-100-orchestrator (per feature)
/forge-migration → fg-160-migration-planner
```

<a id="supporting-dispatch"></a>

### Supporting Dispatch

```
fg-100-orchestrator
  ├── fg-102-conflict-resolver (on merge conflicts)
  └── fg-103-cross-repo-coordinator (multi-repo mode)

fg-015-scope-decomposer (from fg-100 when multi-feature detected)
  └── fg-090-sprint-orchestrator
```

#### PLAN-stage parallel dispatch (Phase 12)

When speculation triggers (see `shared/speculation.md`), `fg-100-orchestrator` dispatches N parallel `fg-200-planner` instances followed by N parallel `fg-210-validator` instances. Each planner dispatch is a distinct substage task with a blue color dot under the PLAN stage. Non-speculative runs use single-plan dispatch unchanged.

<a id="task-hierarchy"></a>

## Task Hierarchy

Task visibility follows the agent dispatch hierarchy:

- **Level 1 (Orchestrator):** fg-100-orchestrator creates 10 stage-level tasks. These are the top-level progress indicators.
- **Level 2 (Coordinators):** Agents dispatched by the orchestrator (fg-400, fg-500, fg-600, fg-200, fg-310, etc.) create sub-tasks within their stage for batches, phases, or file groups.
- **Level 3 (Leaf agents):** Agents dispatched by coordinators (fg-300 TDD cycles, fg-610-infra-deploy-verifier tiers) create sub-sub-tasks for their internal steps.

Maximum nesting depth: 3 levels. Leaf agent sub-tasks are the finest granularity.

Tasks are session-scoped (not persisted to state.json). They provide real-time visual progress in the Claude Code UI but do not survive conversation restarts.

<a id="conditional-agents"></a>

## Conditional Agents

The following agents are dispatched conditionally and receive data from the orchestrator only when their trigger conditions are met:

| Agent | Stage | Trigger | Receives | Outputs |
|-------|-------|---------|----------|---------|
| `fg-320-frontend-polisher` | 4 (IMPLEMENT) | `frontend_polish.enabled` in config AND frontend component detected | Changed frontend files, design theory, theme tokens | Polished files, `FE-*` findings in stage notes |
| `fg-650-preview-validator` | 8 (SHIP) | Preview/staging URL configured in `ship:` config | PR URL, preview URL | Validation results in stage notes |
| `fg-610-infra-deploy-verifier` | 8 (SHIP) | K8s/infra files in changeset | Changed infra files, Helm charts | Verification results in stage notes |
| `fg-130-docs-discoverer` | 0 (PREFLIGHT) | Always (part of preflight) | Project root, config | `stage_0_docs_discovery.md`, docs-index.json |
| `fg-140-deprecation-refresh` | 0 (PREFLIGHT) | Always (part of preflight) | Detected versions, known-deprecations.json | Updated deprecation rules |
| `fg-150-test-bootstrapper` | 0 (PREFLIGHT) | No test infrastructure detected | Project root, framework conventions | Bootstrapped test config, stage notes |
| `fg-418-docs-consistency-reviewer` | 6 (REVIEW) | Documentation exists in project | Changed files, docs-index.json, discovery summary | `DOC-*` findings |

<a id="plan-mode-integration"></a>

## Plan Mode Integration

Planning agents (`fg-200-planner`, `fg-010-shaper`, `fg-160-migration-planner`, `fg-050-project-bootstrapper`) use `EnterPlanMode`/`ExitPlanMode` to present their designs for user approval in the Claude Code UI before implementation proceeds.

**When to use plan mode:**
- Interactive sessions where the user is present and can approve plans
- Complex plans with architectural decisions that benefit from user review

**When to skip plan mode:**
- Autonomous orchestrator runs (the validator `fg-210` serves as the approval gate)
- Replanning after a REVISE verdict (plan mode was already used for the initial plan)
- Simple, low-risk plans where the overhead is not justified

**Protocol:**
1. Agent calls `EnterPlanMode` at the start of its planning process
2. Agent explores the codebase, analyzes alternatives, designs the plan
3. Agent writes the plan to stage notes (or spec file for shaper)
4. Agent calls `ExitPlanMode` — user sees the plan and approves or requests changes
5. On approval, the orchestrator proceeds to the next stage

<a id="convention-composition"></a>

## Convention File Composition

When an agent receives a convention stack with both generic and framework-binding files for the same layer (e.g., `modules/persistence/exposed.md` + `modules/frameworks/spring/persistence/exposed.md`), compose them as follows:

- **Additive sections** (Dos, Don'ts, Patterns, Architecture Patterns): binding entries are appended to generic entries. Both apply.
- **Override sections** (Configuration, Integration Setup, Scaffolder Patterns): binding content replaces generic content for that section.
- **Contradiction rule:** when the binding explicitly contradicts the generic (e.g., different implementation strategy), the binding wins. When the binding adds without contradicting, both apply.

Agents read BOTH files: generic first (for foundational patterns), then binding (for framework-specific adaptations).

<a id="design-context"></a>

## Design Context in Stage Notes

When Figma MCP is available and the requirement references a Figma URL, the planner extracts design context and stores it in stage notes:

```yaml
design_context:
  source: figma
  file_key: "abc123"
  node_id: "1:2"
  tokens:
    colors: [{name: "primary", value: "#1a73e8"}]
    spacing: [{name: "gap-md", value: "16px"}]
    typography: [{name: "heading-lg", size: "24px", weight: 600}]
  screenshot_taken: true
  code_connect_available: false
```

Downstream agents (polisher, reviewer) read this from stage notes to ground their work in the design.

<a id="registry"></a>

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
| fg-143-observability-bootstrap | 3 | No | Preflight | Observability |
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
| fg-414-license-reviewer | 4 | No | Review | License |
| fg-416-performance-reviewer | 4 | No | Review | Performance |
| fg-417-dependency-reviewer | 4 | No | Review | Dependencies |
| fg-418-docs-consistency-reviewer | 4 | No | Review | Documentation |
| fg-419-infra-deploy-reviewer | 4 | No | Review | Infrastructure |
| fg-500-test-gate | 2 | Yes | Verify | Coordination |
| fg-505-build-verifier | 3 | No | Verify | Build |
| fg-506-migration-verifier | 3 | No | Verify | Migration |
| fg-510-mutation-analyzer | 4 | No | Verify | Testing |
| fg-515-property-test-generator | 3 | No | Verify | Testing |
| fg-555-resilience-tester | 3 | No | Verify | Resilience |
| fg-590-pre-ship-verifier | 3 | Yes | Ship | Verification |
| fg-600-pr-builder | 2 | Yes | Ship | Shipping |
| fg-610-infra-deploy-verifier | 3 | No | Ship | Infrastructure |
| fg-620-deploy-verifier | 3 | No | Ship | Deployment |
| fg-650-preview-validator | 3 | No | Ship | Preview |
| fg-700-retrospective | 3 | No | Learn | Learning |
| fg-710-post-run | 2 | No | Learn | Feedback |

<a id="tier-definitions"></a>

## Tier Definitions

| Tier | UI Capabilities | Description |
|------|-----------------|-------------|
| 1 | tasks + ask + plan_mode | Entry-point agents with full user interaction (shaper, planner, bootstrapper, sprint orchestrator) |
| 2 | tasks + ask | Coordinators that track progress and escalate decisions (orchestrator, quality gate, PR builder) |
| 3 | tasks | Internal agents that report progress but don't ask questions (implementer, scaffolder, reviewers with tasks) |
| 4 | none | Read-only analyzers with no user interaction (all review agents, validator, worktree manager) |

<a id="ai-category-assignments"></a>

## AI-* Category Assignments

| Category Prefix | Primary Agent | Secondary Agent |
|---|---|---|
| `AI-LOGIC-*` | fg-410-code-reviewer | — |
| `AI-PERF-*` | fg-416-performance-reviewer | — |
| `AI-CONCURRENCY-*` | fg-410-code-reviewer | fg-416-performance-reviewer |
| `AI-SEC-*` | fg-411-security-reviewer | — |

<a id="registry-rules"></a>

## Registry Rules

1. Agent IDs follow the pattern `fg-{NNN}-{role}` where NNN determines pipeline ordering
2. When referencing an agent in a skill or shared doc, use the exact ID from this table
3. When adding a new agent, add a row here BEFORE creating the agent file
4. When removing an agent, remove the row here AND grep for references across skills/shared docs
5. The Dispatches? column indicates whether the agent has `Agent` in its tools list

<a id="related"></a>

## Related

- [`agent-philosophy.md`](agent-philosophy.md) — how to design an agent
- [`agent-defaults.md`](agent-defaults.md) — shared constraint language
- [`agent-communication.md`](agent-communication.md) — runtime protocols (stage notes, dedup, PREEMPT, structured output)
- [`agent-colors.md`](agent-colors.md) — cluster palette
- [`agent-ui.md`](agent-ui.md) — UI tools (AskUserQuestion, TaskCreate, plan mode)
- [`composition.md`](composition.md) — convention composition algorithm
- [`agent-registry.md`](agent-registry.md) — source-of-truth registry (will be consolidated into this file in T12)
- [`agent-role-hierarchy.md`](agent-role-hierarchy.md) — source hierarchy doc (will be consolidated in T12)
