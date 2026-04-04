# CLI UI Patterns — Consistent Interactive UX Across All Forge Agents

> **Scope:** Extend AskUserQuestion, TaskCreate/TaskUpdate, and EnterPlanMode/ExitPlanMode to all applicable forge agents using a declarative frontmatter schema and shared contract. Part of v1.5.0.
>
> **Status:** Design approved
>
> **Dependencies:** None (ships independently)

---

## 1. Problem Statement

Currently only 4 agents use `AskUserQuestion` (shaper, orchestrator, bug investigator, feedback capture), only the orchestrator uses `TaskCreate`/`TaskUpdate`, and only 4 agents use `EnterPlanMode`/`ExitPlanMode`. This means:

- Users see no progress during long-running agents (quality gate batches, TDD cycles, infra verification tiers)
- Decision points inside coordinator agents are made silently without user input
- No consistent pattern exists for how agents should present choices or track work
- Adding UI to a new agent requires reinventing the patterns each time

## 2. Design Decisions

### Considered Alternatives

1. **Inline rules only** — Add UI instructions directly into each agent's body. Rejected: inconsistent patterns, no single source of truth, more tokens duplicating instructions.
2. **UI middleware agent** — Wrapper agent that intercepts dispatch and adds UI behavior externally. Rejected: adds latency, agents can't make context-specific decisions, over-engineered.
3. **Annotation-based (chosen)** — Declarative `ui:` section in frontmatter + shared contract. Consistent, auditable, single source of truth.

### Justification

The annotation-based approach was chosen because:
- Frontmatter is already the established pattern for agent metadata
- A shared contract keeps token cost low (reference vs duplication)
- Structural tests can enforce consistency between declarations and tools
- New agents get UI patterns by adding 5 lines of frontmatter + 1 reference line

## 3. Agent UI Classification

### 3.1 Tier 1 — Full UI (tasks + ask + plan_mode)

Design-phase agents that present plans and need user input.

| Agent | Currently Has | Adds |
|-------|--------------|------|
| `fg-100-orchestrator` | TaskCreate, TaskUpdate, AskUserQuestion | — (already complete) |
| `fg-010-shaper` | AskUserQuestion, EnterPlanMode, ExitPlanMode | TaskCreate, TaskUpdate |
| `fg-200-planner` | EnterPlanMode, ExitPlanMode | AskUserQuestion, TaskCreate, TaskUpdate |
| `fg-160-migration-planner` | EnterPlanMode, ExitPlanMode | AskUserQuestion, TaskCreate, TaskUpdate |
| `fg-050-project-bootstrapper` | EnterPlanMode, ExitPlanMode | AskUserQuestion, TaskCreate, TaskUpdate |

### 3.2 Tier 2 — Tasks + Ask (coordinator agents)

Multi-step agents that dispatch others and have escalation decision points.

| Agent | Currently Has | Adds |
|-------|--------------|------|
| `fg-020-bug-investigator` | AskUserQuestion | TaskCreate, TaskUpdate |
| `fg-400-quality-gate` | Agent | AskUserQuestion, TaskCreate, TaskUpdate |
| `fg-500-test-gate` | Agent | AskUserQuestion, TaskCreate, TaskUpdate |
| `fg-600-pr-builder` | Agent | AskUserQuestion, TaskCreate, TaskUpdate |
| `fg-310-scaffolder` | Agent | TaskCreate, TaskUpdate |
| `fg-350-docs-generator` | Agent | TaskCreate, TaskUpdate |
| `fg-250-contract-validator` | Agent | TaskCreate, TaskUpdate |
| `fg-150-test-bootstrapper` | Agent | TaskCreate, TaskUpdate |

### 3.3 Tier 3 — Tasks only (multi-step leaf agents)

Long-running agents whose internal progress users want to see.

| Agent | What Tasks Track |
|-------|-----------------|
| `fg-300-implementer` | TDD cycle: write test → implement → verify |
| `fg-320-frontend-polisher` | Polish passes: tokens → spacing → motion |
| `fg-700-retrospective` | Analysis phases: scoring → learnings → auto-tune |
| `fg-130-docs-discoverer` | Scan phases: files → index → graph |
| `fg-140-deprecation-refresh` | Scan phases: deps → registries → update |
| `fg-650-preview-validator` | Validation: deploy → check → report |
| `infra-deploy-verifier` | 3 tiers: static → container → cluster |

### 3.4 Tier 4 — No UI (leaf reviewers, single-pass agents)

Fast, single-purpose agents that return findings. No decisions, no multi-step work. No `ui:` section needed.

Agents: `architecture-reviewer`, `security-reviewer`, `frontend-reviewer`, `frontend-design-reviewer`, `frontend-a11y-reviewer`, `frontend-performance-reviewer`, `backend-performance-reviewer`, `version-compat-reviewer`, `infra-deploy-reviewer`, `docs-consistency-reviewer`, `fg-210-validator`, `fg-710-feedback-capture`, `fg-720-recap`.

## 4. Shared Contract: `shared/agent-ui.md`

New shared contract referenced by all UI-enabled agents. Defines patterns for all three UI capabilities.

### 4.1 AskUserQuestion Format

All agents must use structured options:

```
header: "<Context>" (1-3 words: "Convergence Stuck", "PR Strategy", "Test Failure")
question: "<Single clear question>"
options:
  - "<Option A>" (description: "<What this does and its trade-off>")
  - "<Option B>" (description: "...")
  - "<Option C>" (description: "...")
```

Rules:
- 2-4 options, never bare yes/no or `(1)...` patterns
- Always include at least one non-destructive fallback option (e.g., "Abort", "Skip and continue", "Defer to next stage") so the user can exit the decision without committing to a risky path
- Autonomous mode override: if `forge-config.md` has `autonomous: true`, agents make the recommended choice automatically and log it instead of asking

### 4.2 TaskCreate/TaskUpdate Patterns

**Naming convention:**
- Tier 1/2 agents: `subject` = imperative verb + noun (`"Dispatch review batch 1"`, `"Validate test coverage"`)
- Tier 3 agents: `activeForm` for spinner display (`"Writing unit test for UserService"`, `"Running TDD verify cycle"`)

**Lifecycle:**
1. Create all known tasks upfront at agent start
2. Set `in_progress` before starting each task
3. Set `completed` on success
4. If blocked/failed: leave `in_progress`, create a new task describing the blocker

**Three-level nesting maximum:**
- Level 1: Orchestrator stage tasks (`"Stage 4: Implement"`)
- Level 2: Coordinator sub-tasks (`"Dispatch review batch 1"`)
- Level 3: Leaf agent sub-sub-tasks (`"Write failing test for UserService"`)
- No deeper nesting.

### 4.3 EnterPlanMode/ExitPlanMode

Unchanged from current behavior. Only Tier 1 design-phase agents use plan mode. In autonomous mode (`autonomous: true`), plan mode is still entered but auto-approved after the validator (fg-210) passes.

### 4.4 Autonomous Mode

When `autonomous: true` in `forge-config.md`:
- `AskUserQuestion` calls replaced with automatic recommended-choice selection
- Tasks still created (visual progress always useful)
- PlanMode still used but auto-approved after validator passes
- All auto-decisions logged to stage notes with `[AUTO]` prefix

## 5. Frontmatter Schema Extension

### 5.1 Schema

New `ui:` section in agent YAML frontmatter:

```yaml
ui:
  tasks: true|false      # Agent creates TaskCreate/TaskUpdate for its steps
  ask: true|false        # Agent uses AskUserQuestion for decisions
  plan_mode: true|false  # Agent uses EnterPlanMode/ExitPlanMode
```

Rules:
- Omitting `ui:` entirely = all false (Tier 4 default)
- `ui.tasks: true` requires `TaskCreate` and `TaskUpdate` in `tools:` list
- `ui.ask: true` requires `AskUserQuestion` in `tools:` list
- `ui.plan_mode: true` requires `EnterPlanMode` and `ExitPlanMode` in `tools:` list

### 5.2 Examples

**Tier 1 — Planner:**
```yaml
---
name: fg-200-planner
description: Creates implementation plan with parallel task groups
tools: ['Read', 'Grep', 'Glob', 'Bash', 'Agent', 'EnterPlanMode', 'ExitPlanMode', 'AskUserQuestion', 'TaskCreate', 'TaskUpdate', 'mcp__plugin_context7_context7__resolve-library-id', 'mcp__plugin_context7_context7__query-docs', 'neo4j-mcp']
ui:
  tasks: true
  ask: true
  plan_mode: true
---
```

**Tier 2 — Quality Gate:**
```yaml
---
name: fg-400-quality-gate
description: Dispatches review agents in batches, aggregates findings, computes quality score
tools: ['Read', 'Grep', 'Glob', 'Bash', 'Agent', 'Skill', 'neo4j-mcp', 'AskUserQuestion', 'TaskCreate', 'TaskUpdate']
ui:
  tasks: true
  ask: true
  plan_mode: false
---
```

**Tier 3 — Implementer:**
```yaml
---
name: fg-300-implementer
description: Implements a single plan task using TDD
tools: ['Read', 'Write', 'Edit', 'Grep', 'Glob', 'Bash', 'mcp__plugin_context7_context7__resolve-library-id', 'mcp__plugin_context7_context7__query-docs', 'TaskCreate', 'TaskUpdate']
ui:
  tasks: true
  ask: false
  plan_mode: false
---
```

## 6. Per-Agent Task Blueprints

### 6.1 Tier 1 — Design Agents

**fg-010-shaper:**
- "Gather project context"
- "Explore requirements"
- "Shape feature scope"
- "Present shaped brief"

**fg-200-planner:**
- "Analyze convention stack"
- "Decompose into tasks"
- "Build parallel groups"
- "Generate challenge brief"
- "Present implementation plan"

**fg-160-migration-planner:**
- "Analyze current state"
- "Map migration steps"
- "Identify rollback points"
- "Present migration plan"

**fg-050-project-bootstrapper:**
- "Detect project type"
- "Select stack components"
- "Generate project structure"
- "Configure tooling"

### 6.2 Tier 2 — Coordinators

**fg-400-quality-gate:**
- "Dispatch review batch 1 (architecture, security)"
- "Dispatch review batch 2 (frontend, performance)"
- "Dispatch review batch 3 (docs, compat)"
- "Aggregate findings and compute score"
- AskUserQuestion trigger: score in CONCERNS band (60-79) after convergence exhaustion — "Accept with concerns / Continue fixing / Abort"

**fg-500-test-gate:**
- "Run test suite"
- "Dispatch test analysis agents"
- "Validate coverage thresholds"
- "Compute test verdict"
- AskUserQuestion trigger: critical test failures can't be auto-resolved — "Skip failing tests / Investigate further / Abort"

**fg-600-pr-builder:**
- "Analyze commit history"
- "Build PR description"
- "Create pull request"
- "Link kanban ticket"
- AskUserQuestion trigger: PR strategy ambiguity — "Single PR / Split into stacked PRs"

**fg-310-scaffolder:**
- "Scaffold {group_name} files" (one task per file group in the plan)

**fg-350-docs-generator:**
- "Discover documentation gaps"
- "Generate documentation files"
- "Validate cross-references"

**fg-250-contract-validator:**
- "Validate contracts per component"
- "Cross-repo contract check"

**fg-150-test-bootstrapper:**
- "Detect test framework"
- "Generate test scaffolding"
- "Verify test execution"

**fg-020-bug-investigator:**
- "Reproduce the bug"
- "Analyze root cause"
- "Map affected code paths"

### 6.3 Tier 3 — Leaf Agents

**fg-300-implementer (TDD cycle):**
- "Write failing test for {task_name}"
- "Implement to pass test"
- "Verify: run tests + lint"
- Repeats on failure (task stays `in_progress`, new sub-task for fix iteration)

**fg-320-frontend-polisher:**
- "Audit design tokens"
- "Fix spacing and alignment"
- "Verify motion and transitions"

**fg-700-retrospective:**
- "Compute run scoring"
- "Extract learnings"
- "Auto-tune forge-config.md"

**fg-130-docs-discoverer:**
- "Scan documentation files"
- "Build documentation index"
- "Enrich graph with doc nodes"

**fg-140-deprecation-refresh:**
- "Detect dependency versions"
- "Scan deprecation registries"
- "Update known-deprecations.json"

**fg-650-preview-validator:**
- "Deploy preview"
- "Run preview checks"
- "Generate preview report"

**infra-deploy-verifier:**
- "Tier 1: Static validation"
- "Tier 2: Container validation"
- "Tier 3: Cluster validation"

## 7. Impact Analysis

### 7.1 Files Modified

| File | Change |
|------|--------|
| `shared/agent-ui.md` | **New** — shared contract defining all UI patterns |
| `shared/agent-defaults.md` | Add reference to `agent-ui.md` for UI-enabled agents |
| `shared/agent-communication.md` | Add section on task hierarchy (orchestrator → coordinator → leaf) |
| `shared/stage-contract.md` | Add `autonomous` mode behavior to cross-cutting constraints |
| 20 agent `.md` files | Add `ui:` frontmatter + tools + reference to `agent-ui.md` |
| `CLAUDE.md` | Update agent section with UI tier classification, document `ui:` frontmatter, add `agent-ui.md` to key entry points |
| `tests/structural/` | New test: `ui-frontmatter-consistency.bats` |

### 7.2 Files NOT Modified

- 13 Tier 4 agents (leaf reviewers, validator, feedback capture, recap)
- `shared/scoring.md`, `shared/state-schema.md` — no impact (TaskCreate/TaskUpdate is session-scoped, not persisted)
- `hooks/hooks.json` — no new hooks
- Module files — no impact

### 7.3 Token Budget Impact

- `agent-ui.md`: ~150 lines (loaded by reference, not inline)
- Per-agent additions: ~5 lines frontmatter + ~3 lines reference = ~8 lines per agent
- Total across 20 agents: ~160 lines added
- Net: modest. Shared contract replaces what would otherwise be ~50 lines duplicated per agent.

### 7.4 Structural Validation

New test `ui-frontmatter-consistency.bats` verifies:
1. Every agent with `ui.tasks: true` has `TaskCreate` + `TaskUpdate` in tools
2. Every agent with `ui.ask: true` has `AskUserQuestion` in tools
3. Every agent with `ui.plan_mode: true` has `EnterPlanMode` + `ExitPlanMode` in tools
4. No agent has UI tools in `tools:` without the corresponding `ui:` declaration (catches drift)

### 7.5 Backwards Compatibility

None needed. Agents without `ui:` section are Tier 4 by default. No migration path, no deprecated aliases.
