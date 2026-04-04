# CLI UI Patterns Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend AskUserQuestion, TaskCreate/TaskUpdate, and EnterPlanMode/ExitPlanMode to all applicable forge agents using a declarative `ui:` frontmatter schema and shared contract.

**Architecture:** New shared contract `shared/agent-ui.md` defines patterns. Agents declare capabilities via `ui:` frontmatter section. Structural test enforces consistency between `ui:` declarations and `tools:` list. 20 agents modified across 4 tiers.

**Tech Stack:** Markdown (agent definitions), YAML (frontmatter), Bash/Bats (structural tests)

**Spec:** `docs/superpowers/specs/2026-04-04-cli-ui-patterns-design.md`

---

### Task 1: Create shared contract `shared/agent-ui.md`

**Files:**
- Create: `shared/agent-ui.md`

- [ ] **Step 1: Write the shared contract**

```markdown
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

\```
header: "<Context>" (1-3 words)
question: "<Single clear question>"
options:
  - "<Option A>" (description: "<What this does and its trade-off>")
  - "<Option B>" (description: "...")
  - "<Option C>" (description: "...")
\```

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
```

Note: Escape the triple backticks in the actual file (the `\``` ` above should be ` ``` ` in the real file).

- [ ] **Step 2: Commit**

```bash
git add shared/agent-ui.md
git commit -m "feat: add shared agent UI contract"
```

---

### Task 2: Write structural validation test

**Files:**
- Create: `tests/contract/ui-frontmatter-consistency.bats`

- [ ] **Step 1: Write the test file**

```bash
#!/usr/bin/env bats
# Contract tests: agent UI frontmatter consistency.
# Validates that ui: declarations match tools: lists and vice versa.

load '../helpers/test-helpers'

AGENTS_DIR="$PLUGIN_ROOT/agents"

# ---------------------------------------------------------------------------
# Helper: extract ui.X value from frontmatter (returns "true", "false", or "")
# ---------------------------------------------------------------------------
get_ui_field() {
  local file="$1" field="$2"
  # Extract YAML frontmatter between first and second ---
  awk '/^---$/{n++; next} n==1{print}' "$file" | grep "^  ${field}:" | awk '{print $2}' | tr -d ' '
}

# Helper: check if tool is in tools list
has_tool() {
  local file="$1" tool="$2"
  grep -q "'${tool}'" "$file" || grep -q "\"${tool}\"" "$file"
}

# ---------------------------------------------------------------------------
# 1. Agents with ui.tasks: true must have TaskCreate and TaskUpdate in tools
# ---------------------------------------------------------------------------
@test "ui-frontmatter: ui.tasks: true requires TaskCreate + TaskUpdate in tools" {
  local failures=()
  for agent_file in "$AGENTS_DIR"/*.md; do
    local val
    val="$(get_ui_field "$agent_file" "tasks")"
    if [[ "$val" == "true" ]]; then
      if ! has_tool "$agent_file" "TaskCreate" || ! has_tool "$agent_file" "TaskUpdate"; then
        failures+=("$(basename "$agent_file"): ui.tasks: true but missing TaskCreate/TaskUpdate in tools")
      fi
    fi
  done
  if (( ${#failures[@]} > 0 )); then
    printf '%s\n' "${failures[@]}"
    fail "UI frontmatter inconsistency: ${#failures[@]} agents"
  fi
}

# ---------------------------------------------------------------------------
# 2. Agents with ui.ask: true must have AskUserQuestion in tools
# ---------------------------------------------------------------------------
@test "ui-frontmatter: ui.ask: true requires AskUserQuestion in tools" {
  local failures=()
  for agent_file in "$AGENTS_DIR"/*.md; do
    local val
    val="$(get_ui_field "$agent_file" "ask")"
    if [[ "$val" == "true" ]]; then
      if ! has_tool "$agent_file" "AskUserQuestion"; then
        failures+=("$(basename "$agent_file"): ui.ask: true but missing AskUserQuestion in tools")
      fi
    fi
  done
  if (( ${#failures[@]} > 0 )); then
    printf '%s\n' "${failures[@]}"
    fail "UI frontmatter inconsistency: ${#failures[@]} agents"
  fi
}

# ---------------------------------------------------------------------------
# 3. Agents with ui.plan_mode: true must have EnterPlanMode + ExitPlanMode
# ---------------------------------------------------------------------------
@test "ui-frontmatter: ui.plan_mode: true requires EnterPlanMode + ExitPlanMode in tools" {
  local failures=()
  for agent_file in "$AGENTS_DIR"/*.md; do
    local val
    val="$(get_ui_field "$agent_file" "plan_mode")"
    if [[ "$val" == "true" ]]; then
      if ! has_tool "$agent_file" "EnterPlanMode" || ! has_tool "$agent_file" "ExitPlanMode"; then
        failures+=("$(basename "$agent_file"): ui.plan_mode: true but missing EnterPlanMode/ExitPlanMode in tools")
      fi
    fi
  done
  if (( ${#failures[@]} > 0 )); then
    printf '%s\n' "${failures[@]}"
    fail "UI frontmatter inconsistency: ${#failures[@]} agents"
  fi
}

# ---------------------------------------------------------------------------
# 4. Reverse check: agents with UI tools must have corresponding ui: declaration
# ---------------------------------------------------------------------------
@test "ui-frontmatter: agents with TaskCreate in tools must have ui.tasks: true" {
  local failures=()
  for agent_file in "$AGENTS_DIR"/*.md; do
    if has_tool "$agent_file" "TaskCreate"; then
      local val
      val="$(get_ui_field "$agent_file" "tasks")"
      if [[ "$val" != "true" ]]; then
        failures+=("$(basename "$agent_file"): has TaskCreate in tools but ui.tasks is not true")
      fi
    fi
  done
  if (( ${#failures[@]} > 0 )); then
    printf '%s\n' "${failures[@]}"
    fail "UI frontmatter drift: ${#failures[@]} agents"
  fi
}

@test "ui-frontmatter: agents with AskUserQuestion in tools must have ui.ask: true" {
  local failures=()
  for agent_file in "$AGENTS_DIR"/*.md; do
    if has_tool "$agent_file" "AskUserQuestion"; then
      local val
      val="$(get_ui_field "$agent_file" "ask")"
      if [[ "$val" != "true" ]]; then
        failures+=("$(basename "$agent_file"): has AskUserQuestion in tools but ui.ask is not true")
      fi
    fi
  done
  if (( ${#failures[@]} > 0 )); then
    printf '%s\n' "${failures[@]}"
    fail "UI frontmatter drift: ${#failures[@]} agents"
  fi
}

@test "ui-frontmatter: agents with EnterPlanMode in tools must have ui.plan_mode: true" {
  local failures=()
  for agent_file in "$AGENTS_DIR"/*.md; do
    if has_tool "$agent_file" "EnterPlanMode"; then
      local val
      val="$(get_ui_field "$agent_file" "plan_mode")"
      if [[ "$val" != "true" ]]; then
        failures+=("$(basename "$agent_file"): has EnterPlanMode in tools but ui.plan_mode is not true")
      fi
    fi
  done
  if (( ${#failures[@]} > 0 )); then
    printf '%s\n' "${failures[@]}"
    fail "UI frontmatter drift: ${#failures[@]} agents"
  fi
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
./tests/lib/bats-core/bin/bats tests/contract/ui-frontmatter-consistency.bats
```

Expected: FAIL — agents that already have UI tools (fg-100-orchestrator has TaskCreate but no `ui:` section, fg-010-shaper has AskUserQuestion but no `ui:` section, etc.)

- [ ] **Step 3: Commit test file**

```bash
git add tests/contract/ui-frontmatter-consistency.bats
git commit -m "test: add UI frontmatter consistency contract tests (RED)"
```

---

### Task 3: Add `ui:` frontmatter to Tier 1 agents (5 agents)

**Files:**
- Modify: `agents/fg-100-orchestrator.md` (frontmatter)
- Modify: `agents/fg-010-shaper.md` (frontmatter + tools)
- Modify: `agents/fg-200-planner.md` (frontmatter + tools)
- Modify: `agents/fg-160-migration-planner.md` (frontmatter + tools)
- Modify: `agents/fg-050-project-bootstrapper.md` (frontmatter + tools)

- [ ] **Step 1: Update fg-100-orchestrator frontmatter**

Add `ui:` section after the `tools:` line. This agent already has all required tools — only the declaration is needed:

```yaml
tools: ['Read', 'Grep', 'Glob', 'Bash', 'Agent', 'TaskCreate', 'TaskUpdate', 'AskUserQuestion', 'neo4j-mcp']
ui:
  tasks: true
  ask: true
  plan_mode: false
```

Add reference in the agent body after the Philosophy line:

```markdown
**UI contract:** Follow `shared/agent-ui.md` for TaskCreate/TaskUpdate lifecycle and AskUserQuestion format.
```

- [ ] **Step 2: Update fg-010-shaper frontmatter**

Add `TaskCreate`, `TaskUpdate` to tools list. Add `ui:` section:

```yaml
tools: ['Read', 'Grep', 'Glob', 'Bash', 'Agent', 'AskUserQuestion', 'EnterPlanMode', 'ExitPlanMode', 'TaskCreate', 'TaskUpdate', 'neo4j-mcp']
ui:
  tasks: true
  ask: true
  plan_mode: true
```

Add reference in agent body:

```markdown
**UI contract:** Follow `shared/agent-ui.md` for TaskCreate/TaskUpdate lifecycle, AskUserQuestion format, and plan mode usage.
```

Add task blueprint section to agent body:

```markdown
## Task Blueprint

Create these tasks at start:
1. "Gather project context"
2. "Explore requirements"
3. "Shape feature scope"
4. "Present shaped brief"
```

- [ ] **Step 3: Update fg-200-planner frontmatter**

Add `AskUserQuestion`, `TaskCreate`, `TaskUpdate` to tools list. Add `ui:` section:

```yaml
tools: ['Read', 'Grep', 'Glob', 'Bash', 'Agent', 'EnterPlanMode', 'ExitPlanMode', 'AskUserQuestion', 'TaskCreate', 'TaskUpdate', 'mcp__plugin_context7_context7__resolve-library-id', 'mcp__plugin_context7_context7__query-docs', 'neo4j-mcp']
ui:
  tasks: true
  ask: true
  plan_mode: true
```

Add reference and task blueprint:

```markdown
**UI contract:** Follow `shared/agent-ui.md` for TaskCreate/TaskUpdate lifecycle, AskUserQuestion format, and plan mode usage.

## Task Blueprint

Create these tasks at start:
1. "Analyze convention stack"
2. "Decompose into tasks"
3. "Build parallel groups"
4. "Generate challenge brief"
5. "Present implementation plan"
```

- [ ] **Step 4: Update fg-160-migration-planner frontmatter**

This agent's frontmatter currently has an empty `tools:` line. Set tools and add `ui:`:

```yaml
tools: ['Read', 'Grep', 'Glob', 'Bash', 'Agent', 'EnterPlanMode', 'ExitPlanMode', 'AskUserQuestion', 'TaskCreate', 'TaskUpdate', 'mcp__plugin_context7_context7__resolve-library-id', 'mcp__plugin_context7_context7__query-docs']
ui:
  tasks: true
  ask: true
  plan_mode: true
```

Add reference and task blueprint:

```markdown
**UI contract:** Follow `shared/agent-ui.md` for TaskCreate/TaskUpdate lifecycle, AskUserQuestion format, and plan mode usage.

## Task Blueprint

Create these tasks at start:
1. "Analyze current state"
2. "Map migration steps"
3. "Identify rollback points"
4. "Present migration plan"
```

- [ ] **Step 5: Update fg-050-project-bootstrapper frontmatter**

Add `AskUserQuestion`, `TaskCreate`, `TaskUpdate` to tools list. Add `ui:`:

```yaml
tools: ['Read', 'Write', 'Edit', 'Bash', 'Glob', 'Grep', 'Agent', 'EnterPlanMode', 'ExitPlanMode', 'AskUserQuestion', 'TaskCreate', 'TaskUpdate', 'mcp__plugin_context7_context7__resolve-library-id', 'mcp__plugin_context7_context7__query-docs']
ui:
  tasks: true
  ask: true
  plan_mode: true
```

Add reference and task blueprint:

```markdown
**UI contract:** Follow `shared/agent-ui.md` for TaskCreate/TaskUpdate lifecycle, AskUserQuestion format, and plan mode usage.

## Task Blueprint

Create these tasks at start:
1. "Detect project type"
2. "Select stack components"
3. "Generate project structure"
4. "Configure tooling"
```

- [ ] **Step 6: Run tests**

```bash
./tests/lib/bats-core/bin/bats tests/contract/ui-frontmatter-consistency.bats
```

Expected: Still failing (Tier 2 and 3 agents not yet updated)

- [ ] **Step 7: Commit**

```bash
git add agents/fg-100-orchestrator.md agents/fg-010-shaper.md agents/fg-200-planner.md agents/fg-160-migration-planner.md agents/fg-050-project-bootstrapper.md
git commit -m "feat: add ui: frontmatter to Tier 1 agents (5 agents)"
```

---

### Task 4: Add `ui:` frontmatter to Tier 2 agents (8 agents)

**Files:**
- Modify: `agents/fg-020-bug-investigator.md`
- Modify: `agents/fg-400-quality-gate.md`
- Modify: `agents/fg-500-test-gate.md`
- Modify: `agents/fg-600-pr-builder.md`
- Modify: `agents/fg-310-scaffolder.md`
- Modify: `agents/fg-350-docs-generator.md`
- Modify: `agents/fg-250-contract-validator.md`
- Modify: `agents/fg-150-test-bootstrapper.md`

- [ ] **Step 1: Update fg-020-bug-investigator**

Add `TaskCreate`, `TaskUpdate` to tools. Add `ui:`:

```yaml
tools: ['Read', 'Write', 'Grep', 'Glob', 'Bash', 'Agent', 'AskUserQuestion', 'TaskCreate', 'TaskUpdate', 'neo4j-mcp']
ui:
  tasks: true
  ask: true
  plan_mode: false
```

Add reference and blueprint:

```markdown
**UI contract:** Follow `shared/agent-ui.md` for TaskCreate/TaskUpdate lifecycle and AskUserQuestion format.

## Task Blueprint

Create these tasks at start:
1. "Reproduce the bug"
2. "Analyze root cause"
3. "Map affected code paths"
```

- [ ] **Step 2: Update fg-400-quality-gate**

Add `AskUserQuestion`, `TaskCreate`, `TaskUpdate` to tools. Add `ui:`:

```yaml
tools: ['Read', 'Grep', 'Glob', 'Bash', 'Agent', 'Skill', 'neo4j-mcp', 'AskUserQuestion', 'TaskCreate', 'TaskUpdate']
ui:
  tasks: true
  ask: true
  plan_mode: false
```

Add reference and blueprint:

```markdown
**UI contract:** Follow `shared/agent-ui.md` for TaskCreate/TaskUpdate lifecycle and AskUserQuestion format.

## Task Blueprint

Create one task per configured review batch:
- "Dispatch review batch {N} ({agent_list})"
- "Aggregate findings and compute score"

### AskUserQuestion Trigger

When score is in CONCERNS band (60-79) after convergence exhaustion:

\```
header: "Quality Verdict"
question: "Score is {score}/100 with {N} remaining findings after convergence. How to proceed?"
options:
  - "Accept with concerns" (description: "Proceed to SHIP — document remaining findings in PR")
  - "Continue fixing" (description: "Reset convergence and attempt another fix cycle")
  - "Abort" (description: "Stop the pipeline — manual intervention needed")
\```
```

- [ ] **Step 3: Update fg-500-test-gate**

Add `AskUserQuestion`, `TaskCreate`, `TaskUpdate` to tools. Add `ui:`:

```yaml
tools: ['Read', 'Grep', 'Glob', 'Bash', 'Agent', 'AskUserQuestion', 'TaskCreate', 'TaskUpdate']
ui:
  tasks: true
  ask: true
  plan_mode: false
```

Add reference and blueprint:

```markdown
**UI contract:** Follow `shared/agent-ui.md` for TaskCreate/TaskUpdate lifecycle and AskUserQuestion format.

## Task Blueprint

Create these tasks at start:
1. "Run test suite"
2. "Dispatch test analysis agents"
3. "Validate coverage thresholds"
4. "Compute test verdict"

### AskUserQuestion Trigger

When critical test failures cannot be auto-resolved:

\```
header: "Test Failure"
question: "{N} critical test failures remain after fix attempts. How to proceed?"
options:
  - "Skip failing tests" (description: "Mark tests as known-failing and proceed — risky")
  - "Investigate further" (description: "Re-enter IMPLEMENT with detailed failure context")
  - "Abort" (description: "Stop the pipeline — tests need manual investigation")
\```
```

- [ ] **Step 4: Update fg-600-pr-builder**

Add `AskUserQuestion`, `TaskCreate`, `TaskUpdate` to tools. Add `ui:`:

```yaml
tools: ['Read', 'Grep', 'Glob', 'Bash', 'Agent', 'AskUserQuestion', 'TaskCreate', 'TaskUpdate']
ui:
  tasks: true
  ask: true
  plan_mode: false
```

Add reference and blueprint:

```markdown
**UI contract:** Follow `shared/agent-ui.md` for TaskCreate/TaskUpdate lifecycle and AskUserQuestion format.

## Task Blueprint

Create these tasks at start:
1. "Analyze commit history"
2. "Build PR description"
3. "Create pull request"
4. "Link kanban ticket"

### AskUserQuestion Trigger

When PR strategy has ambiguity (e.g., many files changed across different domains):

\```
header: "PR Strategy"
question: "This change touches {N} files across {M} domains. How to ship?"
options:
  - "Single PR" (description: "One PR with all changes — simpler review, larger diff")
  - "Split into stacked PRs" (description: "One PR per domain — smaller diffs, dependency chain")
  - "Abort" (description: "Return to implementation — rethink the decomposition")
\```
```

- [ ] **Step 5: Update fg-310-scaffolder**

Add `TaskCreate`, `TaskUpdate` to tools. Add `ui:`:

```yaml
tools: ['Read', 'Write', 'Edit', 'Grep', 'Glob', 'Bash', 'Agent', 'TaskCreate', 'TaskUpdate', 'mcp__plugin_context7_context7__resolve-library-id', 'mcp__plugin_context7_context7__query-docs']
ui:
  tasks: true
  ask: false
  plan_mode: false
```

Add reference and blueprint:

```markdown
**UI contract:** Follow `shared/agent-ui.md` for TaskCreate/TaskUpdate lifecycle.

## Task Blueprint

Create one task per file group in the plan:
- "Scaffold {group_name} files"
```

- [ ] **Step 6: Update fg-350-docs-generator**

Add `TaskCreate`, `TaskUpdate` to tools. Add `ui:`:

```yaml
tools: ['Read', 'Glob', 'Grep', 'Bash', 'Write', 'Edit', 'Agent', 'Skill', 'TaskCreate', 'TaskUpdate', 'mcp__plugin_context7_context7__resolve-library-id', 'mcp__plugin_context7_context7__query-docs']
ui:
  tasks: true
  ask: false
  plan_mode: false
```

Add reference and blueprint:

```markdown
**UI contract:** Follow `shared/agent-ui.md` for TaskCreate/TaskUpdate lifecycle.

## Task Blueprint

Create these tasks at start:
1. "Discover documentation gaps"
2. "Generate documentation files"
3. "Validate cross-references"
```

- [ ] **Step 7: Update fg-250-contract-validator**

Add `TaskCreate`, `TaskUpdate` to tools. Add `ui:`:

```yaml
tools: ['Read', 'Bash', 'Glob', 'Grep', 'Agent', 'TaskCreate', 'TaskUpdate']
ui:
  tasks: true
  ask: false
  plan_mode: false
```

Add reference and blueprint:

```markdown
**UI contract:** Follow `shared/agent-ui.md` for TaskCreate/TaskUpdate lifecycle.

## Task Blueprint

Create these tasks at start:
1. "Validate contracts per component"
2. "Cross-repo contract check"
```

- [ ] **Step 8: Update fg-150-test-bootstrapper**

Add `TaskCreate`, `TaskUpdate` to tools. Add `ui:`:

```yaml
tools: ['Read', 'Write', 'Edit', 'Bash', 'Glob', 'Grep', 'Agent', 'TaskCreate', 'TaskUpdate']
ui:
  tasks: true
  ask: false
  plan_mode: false
```

Add reference and blueprint:

```markdown
**UI contract:** Follow `shared/agent-ui.md` for TaskCreate/TaskUpdate lifecycle.

## Task Blueprint

Create these tasks at start:
1. "Detect test framework"
2. "Generate test scaffolding"
3. "Verify test execution"
```

- [ ] **Step 9: Commit**

```bash
git add agents/fg-020-bug-investigator.md agents/fg-400-quality-gate.md agents/fg-500-test-gate.md agents/fg-600-pr-builder.md agents/fg-310-scaffolder.md agents/fg-350-docs-generator.md agents/fg-250-contract-validator.md agents/fg-150-test-bootstrapper.md
git commit -m "feat: add ui: frontmatter to Tier 2 agents (8 agents)"
```

---

### Task 5: Add `ui:` frontmatter to Tier 3 agents (7 agents)

**Files:**
- Modify: `agents/fg-300-implementer.md`
- Modify: `agents/fg-320-frontend-polisher.md`
- Modify: `agents/fg-700-retrospective.md`
- Modify: `agents/fg-130-docs-discoverer.md`
- Modify: `agents/fg-140-deprecation-refresh.md`
- Modify: `agents/fg-650-preview-validator.md`
- Modify: `agents/infra-deploy-verifier.md`

- [ ] **Step 1: Update fg-300-implementer**

Add `TaskCreate`, `TaskUpdate` to tools. Add `ui:`:

```yaml
tools: ['Read', 'Write', 'Edit', 'Grep', 'Glob', 'Bash', 'TaskCreate', 'TaskUpdate', 'mcp__plugin_context7_context7__resolve-library-id', 'mcp__plugin_context7_context7__query-docs']
ui:
  tasks: true
  ask: false
  plan_mode: false
```

Add reference and blueprint:

```markdown
**UI contract:** Follow `shared/agent-ui.md` for TaskCreate/TaskUpdate lifecycle.

## Task Blueprint

Create these tasks per TDD cycle:
1. "Write failing test for {task_name}" (activeForm: "Writing failing test for {task_name}")
2. "Implement to pass test" (activeForm: "Implementing {task_name}")
3. "Verify: run tests + lint" (activeForm: "Running TDD verify cycle")

On verify failure: leave task as `in_progress`, create new task "Fix: {failure_reason}".
```

- [ ] **Step 2: Update fg-320-frontend-polisher**

This agent has empty `tools:`. Set tools and add `ui:`:

```yaml
tools: ['Read', 'Write', 'Edit', 'Grep', 'Glob', 'Bash', 'TaskCreate', 'TaskUpdate']
ui:
  tasks: true
  ask: false
  plan_mode: false
```

Add reference and blueprint:

```markdown
**UI contract:** Follow `shared/agent-ui.md` for TaskCreate/TaskUpdate lifecycle.

## Task Blueprint

Create these tasks at start:
1. "Audit design tokens" (activeForm: "Auditing design tokens")
2. "Fix spacing and alignment" (activeForm: "Fixing spacing and alignment")
3. "Verify motion and transitions" (activeForm: "Verifying motion and transitions")
```

- [ ] **Step 3: Update fg-700-retrospective**

Add `TaskCreate`, `TaskUpdate` to tools. Add `ui:`:

```yaml
tools: ['Read', 'Write', 'Edit', 'Grep', 'Glob', 'Bash', 'Skill', 'TaskCreate', 'TaskUpdate']
ui:
  tasks: true
  ask: false
  plan_mode: false
```

Add reference and blueprint:

```markdown
**UI contract:** Follow `shared/agent-ui.md` for TaskCreate/TaskUpdate lifecycle.

## Task Blueprint

Create these tasks at start:
1. "Compute run scoring" (activeForm: "Computing run scoring")
2. "Extract learnings" (activeForm: "Extracting learnings")
3. "Auto-tune forge-config.md" (activeForm: "Auto-tuning configuration")
```

- [ ] **Step 4: Update fg-130-docs-discoverer**

Add `TaskCreate`, `TaskUpdate` to tools. Add `ui:`:

```yaml
tools: ['Read', 'Glob', 'Grep', 'Bash', 'TaskCreate', 'TaskUpdate']
ui:
  tasks: true
  ask: false
  plan_mode: false
```

Add reference and blueprint:

```markdown
**UI contract:** Follow `shared/agent-ui.md` for TaskCreate/TaskUpdate lifecycle.

## Task Blueprint

Create these tasks at start:
1. "Scan documentation files" (activeForm: "Scanning documentation files")
2. "Build documentation index" (activeForm: "Building documentation index")
3. "Enrich graph with doc nodes" (activeForm: "Enriching graph with doc nodes")
```

- [ ] **Step 5: Update fg-140-deprecation-refresh**

This agent has empty `tools:`. Set tools and add `ui:`:

```yaml
tools: ['Read', 'Write', 'Edit', 'Grep', 'Glob', 'Bash', 'TaskCreate', 'TaskUpdate']
ui:
  tasks: true
  ask: false
  plan_mode: false
```

Add reference and blueprint:

```markdown
**UI contract:** Follow `shared/agent-ui.md` for TaskCreate/TaskUpdate lifecycle.

## Task Blueprint

Create these tasks at start:
1. "Detect dependency versions" (activeForm: "Detecting dependency versions")
2. "Scan deprecation registries" (activeForm: "Scanning deprecation registries")
3. "Update known-deprecations.json" (activeForm: "Updating deprecation registries")
```

- [ ] **Step 6: Update fg-650-preview-validator**

This agent has empty `tools:`. Set tools and add `ui:`:

```yaml
tools: ['Read', 'Bash', 'Glob', 'Grep', 'TaskCreate', 'TaskUpdate']
ui:
  tasks: true
  ask: false
  plan_mode: false
```

Add reference and blueprint:

```markdown
**UI contract:** Follow `shared/agent-ui.md` for TaskCreate/TaskUpdate lifecycle.

## Task Blueprint

Create these tasks at start:
1. "Deploy preview" (activeForm: "Deploying preview")
2. "Run preview checks" (activeForm: "Running preview checks")
3. "Generate preview report" (activeForm: "Generating preview report")
```

- [ ] **Step 7: Update infra-deploy-verifier**

Add `TaskCreate`, `TaskUpdate` to tools. Add `ui:`:

```yaml
tools: ['Read', 'Bash', 'Glob', 'Grep', 'TaskCreate', 'TaskUpdate', 'mcp__plugin_context7_context7__resolve-library-id', 'mcp__plugin_context7_context7__query-docs']
ui:
  tasks: true
  ask: false
  plan_mode: false
```

Add reference and blueprint:

```markdown
**UI contract:** Follow `shared/agent-ui.md` for TaskCreate/TaskUpdate lifecycle.

## Task Blueprint

Create one task per verification tier:
1. "Tier 1: Static validation" (activeForm: "Running static validation")
2. "Tier 2: Container validation" (activeForm: "Running container validation")
3. "Tier 3: Cluster validation" (activeForm: "Running cluster validation")

Skip tasks for tiers above `infra.max_verification_tier` — mark as `completed` with note "Skipped: above max tier".
```

- [ ] **Step 8: Run tests**

```bash
./tests/lib/bats-core/bin/bats tests/contract/ui-frontmatter-consistency.bats
```

Expected: All 6 tests PASS

- [ ] **Step 9: Commit**

```bash
git add agents/fg-300-implementer.md agents/fg-320-frontend-polisher.md agents/fg-700-retrospective.md agents/fg-130-docs-discoverer.md agents/fg-140-deprecation-refresh.md agents/fg-650-preview-validator.md agents/infra-deploy-verifier.md
git commit -m "feat: add ui: frontmatter to Tier 3 agents (7 agents)"
```

---

### Task 6: Update shared contracts

**Files:**
- Modify: `shared/agent-defaults.md`
- Modify: `shared/agent-communication.md`
- Modify: `shared/stage-contract.md`

- [ ] **Step 1: Update agent-defaults.md**

Add a new section referencing the UI contract. Add after the existing Forbidden Actions section:

```markdown
## UI Contract

Agents with `ui:` section in frontmatter MUST follow `shared/agent-ui.md` for:
- AskUserQuestion format (structured options, never bare yes/no)
- TaskCreate/TaskUpdate lifecycle (create upfront, in_progress/completed transitions)
- Three-level task nesting maximum (orchestrator → coordinator → leaf)
- Autonomous mode behavior (`autonomous: true` in forge-config.md)
```

- [ ] **Step 2: Update agent-communication.md**

Add a new section on task hierarchy. Add after the existing Inter-Stage Data Flow section:

```markdown
## Task Hierarchy

Task visibility follows the agent dispatch hierarchy:

- **Level 1 (Orchestrator):** fg-100-orchestrator creates 10 stage-level tasks. These are the top-level progress indicators.
- **Level 2 (Coordinators):** Agents dispatched by the orchestrator (fg-400, fg-500, fg-600, fg-200, fg-310, etc.) create sub-tasks within their stage for batches, phases, or file groups.
- **Level 3 (Leaf agents):** Agents dispatched by coordinators (fg-300 TDD cycles, infra-deploy-verifier tiers) create sub-sub-tasks for their internal steps.

Maximum nesting depth: 3 levels. Leaf agent sub-tasks are the finest granularity.

Tasks are session-scoped (not persisted to state.json). They provide real-time visual progress in the Claude Code UI but do not survive conversation restarts.
```

- [ ] **Step 3: Update stage-contract.md**

Add autonomous mode to the Cross-Cutting Constraints section:

```markdown
### Autonomous Mode

When `autonomous: true` in `forge-config.md`:
- All `AskUserQuestion` calls are replaced with automatic recommended-choice selection
- All auto-decisions are logged to stage notes with `[AUTO]` prefix
- TaskCreate/TaskUpdate still active (visual progress is always useful)
- EnterPlanMode/ExitPlanMode still active — plans are auto-approved after fg-210 validator passes
- The pipeline does not pause for user input at any point except on CRITICAL errors that cannot be auto-resolved
```

- [ ] **Step 4: Commit**

```bash
git add shared/agent-defaults.md shared/agent-communication.md shared/stage-contract.md
git commit -m "feat: update shared contracts with UI patterns and autonomous mode"
```

---

### Task 7: Update CLAUDE.md

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Add agent-ui.md to key entry points table**

In the "Key entry points" table, add:

```markdown
| UI patterns      | `shared/agent-ui.md` (AskUserQuestion, TaskCreate, plan mode)     |
```

- [ ] **Step 2: Update agent file rules section**

Add to the "Agent file rules" section after the existing `tools` bullet:

```markdown
- YAML frontmatter `ui:` section declares interactive capabilities: `tasks` (TaskCreate/TaskUpdate), `ask` (AskUserQuestion), `plan_mode` (EnterPlanMode/ExitPlanMode). Omitting `ui:` entirely = all false (Tier 4). Structural test `ui-frontmatter-consistency.bats` enforces that `ui:` declarations match `tools:` list. See `shared/agent-ui.md` for patterns.
- Agent UI tiers: Tier 1 (tasks+ask+plan_mode): orchestrator, shaper, planner, migration planner, bootstrapper. Tier 2 (tasks+ask): bug investigator, quality gate, test gate, PR builder, scaffolder, docs generator, contract validator, test bootstrapper. Tier 3 (tasks only): implementer, frontend polisher, retrospective, docs discoverer, deprecation refresh, preview validator, infra verifier. Tier 4 (no UI): all 10 reviewers, validator, feedback capture, recap.
```

- [ ] **Step 3: Add autonomous mode to gotchas**

Add to the Pipeline modes subsection:

```markdown
- **Autonomous mode:** `autonomous: true` in `forge-config.md` replaces all AskUserQuestion with auto-selection (logged with `[AUTO]` prefix). Plans auto-approved after validator passes. Tasks still created. Pipeline never pauses except on unrecoverable CRITICAL errors.
```

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md with UI tier classification and autonomous mode"
```

---

### Task 8: Run full test suite and verify

- [ ] **Step 1: Run UI frontmatter tests**

```bash
./tests/lib/bats-core/bin/bats tests/contract/ui-frontmatter-consistency.bats
```

Expected: All 6 tests PASS

- [ ] **Step 2: Run full test suite**

```bash
./tests/run-all.sh
```

Expected: All tests PASS (no regressions from frontmatter changes)

- [ ] **Step 3: Commit any fixes if needed**

If any existing tests broke due to agent count changes or frontmatter validation:

```bash
git add -A
git commit -m "fix: resolve test regressions from UI frontmatter changes"
```
