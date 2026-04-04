# Agent UI Contract

This contract defines the interactive UI patterns available to forge agents. Agents declare their UI capabilities via the `ui:` section in YAML frontmatter and reference this contract for behavior rules.

## UI Capabilities

| Capability | Frontmatter | Tools Required | Purpose |
|-----------|-------------|----------------|---------|
| Task tracking | `ui.tasks: true` | `TaskCreate`, `TaskUpdate` | Visual progress for multi-step work |
| User questions | `ui.ask: true` | `AskUserQuestion` | Structured decision points |
| Plan mode | `ui.plan_mode: true` | `EnterPlanMode`, `ExitPlanMode` | Design presentation before execution |

Omitting the `ui:` section entirely means all capabilities are `false` (Tier 4 — no UI).

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
- **Level 2:** Coordinator sub-tasks (`"Dispatch review batch 1"`)
- **Level 3:** Leaf agent sub-sub-tasks (`"Write failing test for UserService"`)
- No deeper nesting.

## EnterPlanMode/ExitPlanMode

Only Tier 1 design-phase agents use plan mode. In autonomous mode (`autonomous: true`), plan mode is still entered but auto-approved after the validator (fg-210) passes.

## Autonomous Mode

When `autonomous: true` in `forge-config.md`:
- `AskUserQuestion` → automatic recommended-choice selection, logged with `[AUTO]` prefix
- Tasks → still created (visual progress is always useful)
- PlanMode → still used, auto-approved after validator passes

## Agent Tier Reference

| Tier | UI Capabilities | Agents |
|------|----------------|--------|
| 1 | tasks + ask + plan_mode | fg-100-orchestrator, fg-010-shaper, fg-200-planner, fg-160-migration-planner, fg-050-project-bootstrapper |
| 2 | tasks + ask | fg-020-bug-investigator, fg-400-quality-gate, fg-500-test-gate, fg-600-pr-builder, fg-310-scaffolder, fg-350-docs-generator, fg-250-contract-validator, fg-150-test-bootstrapper |
| 3 | tasks only | fg-300-implementer, fg-320-frontend-polisher, fg-700-retrospective, fg-130-docs-discoverer, fg-140-deprecation-refresh, fg-650-preview-validator, infra-deploy-verifier |
| 4 | none | All 10 reviewers, fg-210-validator, fg-710-feedback-capture, fg-720-recap |
