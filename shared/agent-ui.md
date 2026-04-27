# Agent UI Contract

This contract defines the interactive UI patterns available to forge agents. Agents declare their UI capabilities via the `ui:` section in YAML frontmatter and reference this contract for behavior rules.

## UI Capabilities

| Capability | Frontmatter | Tools Required | Purpose |
|-----------|-------------|----------------|---------|
| Task tracking | `ui.tasks: true` | `TaskCreate`, `TaskUpdate` | Visual progress for multi-step work |
| User questions | `ui.ask: true` | `AskUserQuestion` | Structured decision points |
| Plan mode | `ui.plan_mode: true` | `EnterPlanMode`, `ExitPlanMode` | Design presentation before execution |

Every agent MUST declare an explicit `ui:` block with three boolean keys: `tasks`, `ask`, `plan_mode`. Implicit omission is invalid and rejected by `tests/contract/ui-frontmatter-consistency.bats`. Tier 4 agents declare `ui: { tasks: false, ask: false, plan_mode: false }`.

## AskUserQuestion Format

All agents with `ui.ask: true` MUST use structured options:

    header: "<Context>" (1-3 words)
    question: "<Single clear question>"
    options:
      - "<Option A>" (description: "<What this does and its trade-off>")
      - "<Option B>" (description: "...")
      - "<Option C>" (description: "...")

Rules:
- 2-4 options. Never bare yes/no or `(1)...` or `(y/n)` patterns.
- Always include at least one non-destructive fallback option (e.g., "Abort", "Skip and continue", "Defer to next stage").
- When `autonomous: true` in `forge-config.md`: make the recommended choice automatically and log with `[AUTO]` prefix to stage notes.

## TaskCreate/TaskUpdate Patterns

### Naming Convention
- Tier 1/2 agents: `subject` = imperative verb + noun (e.g., `"Dispatch review batch 1"`)
- Tier 3 agents: use `activeForm` for spinner display (e.g., `"Writing unit test for UserService"`)

### Lifecycle
1. Create all known tasks upfront at agent start.
2. Set `in_progress` before starting each task.
3. Set `completed` on success.
4. If blocked/failed: leave as `in_progress`, create a new task describing the blocker.

### Three-Level Nesting Maximum
- **Level 1:** Orchestrator stage tasks (`"Stage 4: Implement"`)
- **Level 2:** Substage tasks with agent color dots (`"🟢 Dispatching fg-300-implementer"`)
- **Level 3:** Leaf agent sub-sub-tasks (`"Write failing test for UserService"`)
- No deeper nesting.

### Substage Tasks

When entering a stage, the orchestrator creates substage tasks for each discrete step within that stage. Substages are children of the stage task (Level 2).

**Naming format:** `{color_dot} Dispatching {agent_name}` (for agent dispatches) or `{description}` (for inline work).

**Color dots identify agent roles** (from agent frontmatter `color:` field):
- 🟢 green: implementers, scaffolders, docs, infra (fg-300, fg-310, fg-350, fg-419, fg-610, fg-620, fg-650)
- 🔴 red: quality gates, security, pre-ship (fg-400, fg-411, fg-590)
- 🔵 blue: planners, PR builders (fg-200, fg-600)
- 🟡 yellow: validators, performance, test gates, build verifiers (fg-210, fg-250, fg-416, fg-500, fg-505)
- 🟣 magenta: shapers, polishers, retrospective, bootstrappers (fg-010, fg-015, fg-050, fg-090, fg-320, fg-700, fg-710)
- 🟤 purple: bug investigators (fg-020)
- 🔷 teal: frontend reviewers (fg-413)
- 🟠 orange: migration planner (fg-160)
- ⚪ cyan: orchestrator, code reviewers, docs, dependency (fg-100, fg-130, fg-135, fg-140, fg-150, fg-410, fg-412, fg-417, fg-510, fg-515)
- ⬜ gray: worktree, conflict, cross-repo (fg-101, fg-102, fg-103)
- ⬛ white: docs-consistency (fg-418)

Default: ⚪ cyan for agents without `color:` in frontmatter.

**Lifecycle:** Create when entering stage → `in_progress` when starting → `completed` when done. Conditional substages (frontend polish, preview, fix loops) only created when triggered. Dynamic substages for convergence iterations and fix loops are created on-the-fly.

## EnterPlanMode/ExitPlanMode

Only Tier 1 design-phase agents use plan mode. In autonomous mode (`autonomous: true`), plan mode is still entered but auto-approved after the validator (fg-210) passes.

## Autonomous Mode

When `autonomous: true` in `forge-config.md`:
- `AskUserQuestion` → automatic recommended-choice selection, logged with `[AUTO]` prefix
- Tasks → still created (visual progress is always useful)
- PlanMode → still used, auto-approved after validator passes

### Autonomous Mode Activation

The `autonomous` flag is resolved at PREFLIGHT from `forge-config.md`:

```yaml
autonomous: false  # Default. Set to true for fully autonomous pipeline.
```

**Propagation:**
1. Orchestrator reads `autonomous` from config at PREFLIGHT
2. Stored in `state.json.autonomous` (boolean)
3. Passed to dispatched agents via dispatch context
4. Agents check `autonomous` in dispatch context to decide AskUserQuestion vs auto-selection

**When autonomous is true:**
- AskUserQuestion → automatic recommended-choice selection, logged `[AUTO]`
- EnterPlanMode → still entered, auto-approved after validator (fg-210) passes
- Escalation (E1-E4) → still escalates (safety overrides autonomous mode)
- User's 3 touchpoints reduced to 2: Start and Escalation (Approval is automatic)

**When autonomous is false (default):**
- All UI affordances work normally per agent tier
- Plan mode requires explicit user approval
- AskUserQuestion pauses for user input

## Agent Tier Reference

| Tier | UI Capabilities | Agents |
|------|----------------|--------|
| 1 | tasks + ask + plan_mode | fg-010-shaper, fg-015-scope-decomposer, fg-200-planner, fg-160-migration-planner, fg-050-project-bootstrapper, fg-090-sprint-orchestrator |
| 2 | tasks + ask | fg-100-orchestrator, fg-020-bug-investigator, fg-210-validator, fg-400-quality-gate, fg-500-test-gate, fg-600-pr-builder, fg-103-cross-repo-coordinator, fg-710-post-run |
| 3 | tasks only | fg-300-implementer, fg-320-frontend-polisher, fg-700-retrospective, fg-130-docs-discoverer, fg-135-wiki-generator, fg-140-deprecation-refresh, fg-650-preview-validator, fg-590-pre-ship-verifier, fg-610-infra-deploy-verifier, fg-310-scaffolder, fg-350-docs-generator, fg-250-contract-validator, fg-150-test-bootstrapper, fg-505-build-verifier, fg-515-property-test-generator, fg-620-deploy-verifier |
| 4 | none | All 8 reviewers (fg-410 through fg-419), fg-205-plan-judge, fg-301-implementer-judge, fg-510-mutation-analyzer, fg-101-worktree-manager, fg-102-conflict-resolver |

## Enforcement

Contract compliance is enforced by `tests/contract/ui-frontmatter-consistency.bats`. See `shared/agent-colors.md` for the cluster-scoped color uniqueness assertion.
