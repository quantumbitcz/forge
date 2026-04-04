# Parallel Multi-Feature Development Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a sprint orchestrator that decomposes multiple features, analyzes independence, and dispatches parallel forge pipeline instances. Decompose the existing orchestrator into focused sub-agents.

**Architecture:** New `fg-090-sprint-orchestrator` sits above `fg-100-orchestrator`. Three sub-agents extracted from fg-100: worktree manager (fg-101), conflict resolver (fg-102), cross-repo coordinator (fg-103). Per-feature isolation via git worktrees + shared Neo4j graph.

**Tech Stack:** Markdown (agent definitions), Bash (worktree/lock scripts), Cypher (conflict queries), Bats (tests)

**Spec:** `docs/superpowers/specs/2026-04-04-parallel-multi-feature-design.md`

**Prerequisites:** Plan 2 (Neo4j Multi-Project Namespacing) must be implemented first.

---

### Task 1: Create sprint state schema

**Files:**
- Create: `shared/sprint-state-schema.md`

- [ ] **Step 1: Write the schema document**

```markdown
# Sprint State Schema

Defines the schema for `.forge/sprint-state.json`, used by `fg-090-sprint-orchestrator` to track parallel feature execution.

## Schema

\```json
{
  "version": "1.0.0",
  "sprint_id": "CYC-42 | manual",
  "source": "linear | manual",
  "started": "2026-04-04T10:00:00Z",
  "status": "gathering | analyzing | approved | executing | merging | complete | failed",
  "features": [
    {
      "id": "FG-042",
      "name": "Add user avatar upload",
      "status": "pending | implementing | verifying | reviewing | shipping | complete | failed | waiting",
      "waiting_for": "quantumbitcz/wellplanned-be | null",
      "repos": [
        {
          "project_id": "quantumbitcz/wellplanned-be",
          "status": "pending | implementing | verifying | reviewing | shipping | complete | failed | waiting",
          "waiting_for": "null | project_id",
          "run_dir": ".forge/runs/FG-042-be/",
          "worktree": ".forge/worktrees/FG-042-be/",
          "branch": "feat/FG-042-add-avatars",
          "pr_url": "null | https://github.com/..."
        }
      ]
    }
  ],
  "parallel_groups": [
    ["FG-042", "FG-044"]
  ],
  "serial_chains": [
    ["FG-045", "FG-046"]
  ],
  "conflicts": [
    {
      "pair": ["FG-042", "FG-043"],
      "files": ["src/UserService.kt"],
      "resolution": "symbol-level independent (different methods)"
    }
  ]
}
\```

## Directory Structure

\```
.forge/
  sprint-state.json
  runs/
    {feature-id}/
      state.json
      checkpoint-*.json
      stage_N_notes_*.md
      .lock
  worktrees/
    {feature-id}/          # git worktree
\```

## Lifecycle

| Field | Set By | When |
|-------|--------|------|
| `sprint_id` | fg-090 | GATHER phase |
| `features` | fg-090 | GATHER phase |
| `parallel_groups` | fg-090 via fg-102 | ANALYZE phase |
| `feature.status` | fg-090 | Each status transition |
| `feature.repos[].status` | fg-090 (reads from per-run state.json) | Polled during MONITOR |
| `feature.repos[].pr_url` | fg-090 | MERGE phase |

## Lock Model

Sprint mode uses per-run locks at `.forge/runs/{feature-id}/.lock` instead of the global `.forge/.lock`. The sprint orchestrator coordinates via sprint-state.json — no global lock needed.

Single-feature mode (`/forge-run` without `--parallel`/`--sprint`) still uses global `.forge/.lock` unchanged.
```

- [ ] **Step 2: Commit**

```bash
git add shared/sprint-state-schema.md
git commit -m "docs: add sprint state schema"
```

---

### Task 2: Create fg-101-worktree-manager agent

**Files:**
- Create: `agents/fg-101-worktree-manager.md`

- [ ] **Step 1: Write the agent definition**

```markdown
---
name: fg-101-worktree-manager
description: |
  Manages git worktree lifecycle — creation, cleanup, branch naming, and stale detection. Called by the orchestrator at PREFLIGHT (create) and LEARN (cleanup). Extracted from fg-100-orchestrator.
model: inherit
color: gray
tools: ['Bash', 'Read', 'Glob']
---

# Worktree Manager (fg-101)

You manage git worktree lifecycle for the forge pipeline. You create isolated worktrees for implementation, clean them up after completion, and detect stale worktrees from interrupted runs.

**Philosophy:** Apply principles from `shared/agent-philosophy.md` — challenge assumptions, consider alternatives, seek disconfirming evidence.

Execute: **$ARGUMENTS**

---

## Operations

### create

**Input:** `create <ticket_id> <slug> [--base-dir <path>]`

**Steps:**
1. Derive branch name: `{type}/{ticket_id}-{slug}` (type from state.json.mode: feat/fix/refactor/chore)
2. Check if branch exists: `git branch --list $branch_name`
3. If exists: append epoch suffix — `{branch_name}-{epoch_seconds}`
4. Create worktree: `git worktree add <base-dir>/worktree -b $branch_name`
5. Verify worktree is functional: `git -C <worktree-path> status`

**Output (via stage notes):**
\```
worktree_path: /path/to/.forge/worktree
branch_name: feat/FG-042-add-avatars
\```

**Base directory:**
- Single-feature mode: `.forge/worktree`
- Sprint mode: `.forge/worktrees/{feature-id}/`

### cleanup

**Input:** `cleanup <worktree_path> [--delete-branch]`

**Steps:**
1. Check worktree exists: `git worktree list | grep $worktree_path`
2. Remove worktree: `git worktree remove $worktree_path --force`
3. If `--delete-branch`: `git branch -D $branch_name`
4. Prune stale worktrees: `git worktree prune`

### detect-stale

**Input:** `detect-stale`

**Steps:**
1. List all worktrees: `git worktree list --porcelain`
2. For each forge worktree (path contains `.forge`):
   - Check if corresponding state.json exists and has `complete: false`
   - Check if lock file exists and is stale (>24h or PID not running)
3. Report stale worktrees for orchestrator to decide on

**Output (via stage notes):**
\```
stale_worktrees:
  - path: /path/to/.forge/worktree
    branch: feat/FG-040-old-feature
    state: interrupted (lock stale, state incomplete)
\```

## Constraints

- Never force-delete a worktree that has uncommitted changes — report to orchestrator instead
- Never delete branches that are not forge-created (no `feat/`/`fix/`/`refactor/`/`chore/` prefix)
- Git conventions from `shared/git-conventions.md` apply to branch naming
```

- [ ] **Step 2: Commit**

```bash
git add agents/fg-101-worktree-manager.md
git commit -m "feat: add fg-101-worktree-manager agent"
```

---

### Task 3: Create fg-102-conflict-resolver agent

**Files:**
- Create: `agents/fg-102-conflict-resolver.md`

- [ ] **Step 1: Write the agent definition**

```markdown
---
name: fg-102-conflict-resolver
description: |
  Analyzes file and symbol-level conflicts between tasks or features. Produces parallel groups and serial chains. Used by fg-100 (task-level) and fg-090 (feature-level). Queries Neo4j graph for impact analysis.
model: inherit
color: gray
tools: ['Read', 'Grep', 'Glob', 'neo4j-mcp']
---

# Conflict Resolver (fg-102)

You analyze dependencies and conflicts between work items (tasks within a feature, or features within a sprint). You produce safe parallel execution groups.

**Philosophy:** Apply principles from `shared/agent-philosophy.md` — challenge assumptions, consider alternatives, seek disconfirming evidence.

Analyze: **$ARGUMENTS**

---

## Algorithm

### Phase 1 — File-Level (always available)

1. For each work item, estimate affected files:
   - Explicit file references in the requirement/task description
   - Graph query (if Neo4j available):
     \```cypher
     MATCH (f:ProjectFile {project_id: $project_id})-[:IMPORTS*0..2]->(dep:ProjectFile)
     WHERE f.path IN $seed_files
     RETURN DISTINCT dep.path
     \```
   - Heuristic: item mentions "UserService" → include files matching `**/UserService*`, `**/*UserService*Test*`, and their importers
2. Build conflict matrix: Item A vs Item B = set intersection of affected files
3. Empty intersection → independent (can parallelize)
4. Non-empty intersection → proceed to Phase 2 if graph enrichment available, otherwise serialize

### Phase 2 — Symbol-Level (when graph has enrichment)

1. For overlapping files, query ProjectClass and ProjectFunction:
   \```cypher
   MATCH (c:ProjectClass {file_path: $file_path, project_id: $project_id})
   RETURN c.name, c.kind
   \```
2. Different classes/functions in same file → independent
3. Same class, different methods → independent (with WARNING)
4. Same method → serialize

### Output Format

Return via stage notes:

\```yaml
parallel_groups:
  - [item-1, item-3]
  - [item-2]
serial_chains:
  - [item-4, item-5]
conflicts:
  - pair: [item-1, item-2]
    files: [src/UserService.kt]
    resolution: "symbol-level independent (different methods)"
    confidence: HIGH
\```

## Constraints

- When Neo4j is unavailable: file-level analysis only, skip Phase 2
- When graph enrichment is incomplete: log INFO, conservative file-level grouping
- Maximum parallel group size: configurable via `implementation.parallel_threshold` (default 3)
- Cross-project analysis: query multiple `project_id` values when analyzing cross-repo features
```

- [ ] **Step 2: Commit**

```bash
git add agents/fg-102-conflict-resolver.md
git commit -m "feat: add fg-102-conflict-resolver agent"
```

---

### Task 4: Create fg-103-cross-repo-coordinator agent

**Files:**
- Create: `agents/fg-103-cross-repo-coordinator.md`

- [ ] **Step 1: Write the agent definition**

```markdown
---
name: fg-103-cross-repo-coordinator
description: |
  Coordinates cross-repo operations — worktree creation in related projects, lock ordering, PR linking, and timeout management. Called by fg-100 and fg-090 for cross-repo features.
model: inherit
color: gray
tools: ['Bash', 'Read', 'Grep', 'Glob', 'Agent', 'AskUserQuestion', 'TaskCreate', 'TaskUpdate']
ui:
  tasks: true
  ask: true
  plan_mode: false
---

# Cross-Repo Coordinator (fg-103)

You coordinate work across multiple related repositories. You create worktrees, manage locks, and link PRs across repos.

**Philosophy:** Apply principles from `shared/agent-philosophy.md` — challenge assumptions, consider alternatives, seek disconfirming evidence.

**UI contract:** Follow `shared/agent-ui.md` for TaskCreate/TaskUpdate lifecycle and AskUserQuestion format.

Coordinate: **$ARGUMENTS**

---

## Operations

### setup-worktrees

**Input:** List of related projects and their tasks.

**Steps:**
1. Create one task per related project: "Set up worktree for {project_name}"
2. Sort projects alphabetically (lock ordering to prevent deadlocks)
3. For each project (in alphabetical order):
   - Dispatch fg-101-worktree-manager to create worktree in that project's directory
   - Acquire per-project lock at `{project_root}/.forge/runs/{feature-id}/.lock`
4. Return worktree paths for all projects

### coordinate-implementation

**Input:** Multi-repo execution plan with dependency ordering.

**Steps:**
1. Create task per repo: "Implement in {project_name}"
2. Dispatch contract producers first (BE, Infra — order 1)
3. Wait for producers to reach VERIFY stage
4. Dispatch contract consumers (FE — order 2)
5. Monitor all repos, report progress

**Wait mechanism:** Poll `sprint-state.json` or per-run `state.json` for dependency status. Poll interval: 30 seconds. Timeout: `cross_repo.timeout_minutes` (default 30).

### link-prs

**Input:** PR URLs from all repos for a single feature.

**Steps:**
1. For each PR, add cross-references in the PR body: "Related PRs: ..."
2. If Linear configured, link all PRs to the same story
3. Return consolidated PR list

### AskUserQuestion Triggers

**Lock conflict:**
\```
header: "Cross-Repo Lock"
question: "Project {name} has an active lock from another run. How to proceed?"
options:
  - "Wait" (description: "Wait for the other run to complete")
  - "Force" (description: "Break the lock and proceed — risk of state corruption")
  - "Skip" (description: "Skip this project and continue with others")
\```

**Timeout:**
\```
header: "Cross-Repo Timeout"
question: "Project {name} exceeded {N} minute timeout. How to proceed?"
options:
  - "Extend" (description: "Double the timeout and continue waiting")
  - "Skip" (description: "Mark this project as failed, continue main pipeline")
  - "Abort" (description: "Stop the entire sprint execution")
\```

## Constraints

- Alphabetical lock ordering is mandatory — prevents deadlocks
- Per-project timeout: configurable via `cross_repo.timeout_minutes` (default 30)
- PR failures in related repos don't block the main PR
- Lock stale detection: same 24h/PID rules as the main pipeline
```

- [ ] **Step 2: Commit**

```bash
git add agents/fg-103-cross-repo-coordinator.md
git commit -m "feat: add fg-103-cross-repo-coordinator agent"
```

---

### Task 5: Create fg-090-sprint-orchestrator agent

**Files:**
- Create: `agents/fg-090-sprint-orchestrator.md`

- [ ] **Step 1: Write the agent definition**

This is a large agent (~500 lines). Write the full definition covering all 7 lifecycle phases (GATHER, ANALYZE, GROUP, APPROVE, DISPATCH, MONITOR, MERGE), with concrete dispatch patterns, state management, and error handling.

Key sections to include:
- Identity and frontmatter (Tier 1 UI: tasks + ask + plan_mode)
- GATHER phase: Linear API integration (`mcp__plugin_linear_linear__list_issues` with cycle filter) + manual input parsing
- ANALYZE phase: dispatch fg-102-conflict-resolver with all features
- GROUP phase: partition into parallel groups and serial chains
- APPROVE phase: EnterPlanMode, present grouping, AskUserQuestion for approval
- DISPATCH phase: for each feature, dispatch fg-101 (worktree) then fg-100 (pipeline) with `--run-dir` and `--wait-for`
- MONITOR phase: poll per-run state files, detect runtime conflicts, handle failures via AskUserQuestion
- MERGE phase: dispatch fg-103 for cross-repo PR linking, collect all PR URLs

```yaml
---
name: fg-090-sprint-orchestrator
description: |
  Sprint-level orchestrator — decomposes a sprint into independent features, analyzes conflicts, and dispatches parallel fg-100 pipeline instances. Entry point: /forge-run --sprint or --parallel.
model: inherit
color: magenta
tools: ['Read', 'Grep', 'Glob', 'Bash', 'Agent', 'TaskCreate', 'TaskUpdate', 'AskUserQuestion', 'EnterPlanMode', 'ExitPlanMode', 'neo4j-mcp']
ui:
  tasks: true
  ask: true
  plan_mode: true
---
```

Full agent body should cover the 7 phases with concrete instructions, dispatch patterns, state file management, and error handling. Reference `shared/sprint-state-schema.md` for state format and `shared/agent-ui.md` for UI patterns.

- [ ] **Step 2: Commit**

```bash
git add agents/fg-090-sprint-orchestrator.md
git commit -m "feat: add fg-090-sprint-orchestrator agent"
```

---

### Task 6: Create forge-sprint skill

**Files:**
- Create: `skills/forge-sprint/SKILL.md`

- [ ] **Step 1: Write the skill definition**

```markdown
---
name: forge-sprint
description: |
  Execute multiple features in parallel from a Linear sprint or manual list.
  Entry point for sprint-level orchestration.

  Usage:
    /forge-sprint                    — reads current active Linear cycle
    /forge-sprint CYC-42             — reads specific Linear cycle
    /forge-sprint "Feature A" "Feature B"  — manual feature list
allowed-tools: ['Read', 'Grep', 'Glob', 'Bash', 'Agent', 'TaskCreate', 'TaskUpdate', 'AskUserQuestion', 'EnterPlanMode', 'ExitPlanMode', 'neo4j-mcp']
---

# Sprint Execution

Dispatch the sprint orchestrator to analyze and execute multiple features in parallel.

## Pre-Flight Checks

1. Verify no global `.forge/.lock` exists (or is stale)
2. Verify `.forge/sprint-state.json` doesn't indicate an active sprint (or is stale)
3. Verify Neo4j is available (optional but recommended for conflict analysis)

## Dispatch

\```
dispatch fg-090-sprint-orchestrator "$ARGUMENTS"
\```

The sprint orchestrator handles everything from here — gathering features, analyzing independence, getting user approval, dispatching pipelines, and coordinating merges.
```

- [ ] **Step 2: Update forge-run skill to accept --parallel and --sprint flags**

In `skills/forge-run/SKILL.md`, add:

```markdown
## Sprint/Parallel Mode

If arguments include `--sprint` or `--parallel`:
- Dispatch `fg-090-sprint-orchestrator` instead of `fg-100-orchestrator`
- Pass all arguments through

\```
if [[ "$ARGUMENTS" == *"--sprint"* ]] || [[ "$ARGUMENTS" == *"--parallel"* ]]; then
  dispatch fg-090-sprint-orchestrator "$ARGUMENTS"
else
  dispatch fg-100-orchestrator "$ARGUMENTS"
fi
\```
```

- [ ] **Step 3: Commit**

```bash
git add skills/forge-sprint/SKILL.md skills/forge-run/SKILL.md
git commit -m "feat: add forge-sprint skill and --parallel/--sprint flags"
```

---

### Task 7: Refactor fg-100-orchestrator (extract sub-agents)

**Files:**
- Modify: `agents/fg-100-orchestrator.md`

- [ ] **Step 1: Replace worktree management with fg-101 dispatch**

Find all worktree creation/cleanup logic in the orchestrator. Replace with dispatch calls:

```markdown
### Worktree Creation (PREFLIGHT)

Dispatch fg-101-worktree-manager:
\```
dispatch fg-101-worktree-manager "create ${ticket_id} ${slug} --base-dir ${base_dir}"
\```

Read result from stage notes: `worktree_path`, `branch_name`.
Store in state.json: `branch_name`, update working directory to worktree_path.
```

Replace the cleanup section similarly:

```markdown
### Worktree Cleanup (LEARN)

Dispatch fg-101-worktree-manager:
\```
dispatch fg-101-worktree-manager "cleanup ${worktree_path}"
\```
```

- [ ] **Step 2: Replace conflict detection with fg-102 dispatch**

Find the parallel task grouping / conflict detection logic. Replace with:

```markdown
### Parallel Group Construction (IMPLEMENT)

Dispatch fg-102-conflict-resolver with the plan's task list:
\```
dispatch fg-102-conflict-resolver "analyze --project-id ${project_id} --tasks ${task_list_json}"
\```

Read result from stage notes: `parallel_groups`, `serial_chains`, `conflicts`.
```

- [ ] **Step 3: Replace cross-repo coordination with fg-103 dispatch**

Find cross-repo worktree creation and PR linking logic. Replace with:

```markdown
### Cross-Repo Setup (IMPLEMENT)

If related_projects configured:
\```
dispatch fg-103-cross-repo-coordinator "setup-worktrees --feature ${feature_id} --projects ${related_projects}"
\```

### Cross-Repo PR Linking (SHIP)

\```
dispatch fg-103-cross-repo-coordinator "link-prs --feature ${feature_id} --prs ${pr_urls}"
\```
```

- [ ] **Step 4: Add --run-dir and --wait-for parameters**

Add to the argument parsing section:

```markdown
### New Parameters (Sprint Mode)

- `--run-dir <path>`: Override state directory (default: `.forge/`). Used by sprint orchestrator to isolate per-feature state.
- `--wait-for <project_id>`: Block at PREFLIGHT until the specified project reaches VERIFY stage. Poll `sprint-state.json` every 30 seconds. Timeout: `cross_repo.timeout_minutes`.
- `--project-root <path>`: Override project root (default: current directory). Used for cross-repo dispatch.
```

- [ ] **Step 5: Verify the orchestrator is significantly shorter**

The orchestrator should now be ~1000-1200 lines (down from ~2300). Verify no logic was lost — the extracted sections should map 1:1 to the new agents.

- [ ] **Step 6: Commit**

```bash
git add agents/fg-100-orchestrator.md
git commit -m "refactor: extract worktree, conflict, and cross-repo logic from orchestrator"
```

---

### Task 8: Update shared contracts

**Files:**
- Modify: `shared/stage-contract.md`
- Modify: `shared/agent-communication.md`
- Modify: `shared/state-schema.md`

- [ ] **Step 1: Add sprint mode to stage-contract.md**

Add a new section:

```markdown
## Sprint Mode

When `/forge-run --sprint` or `/forge-run --parallel` is used:

- `fg-090-sprint-orchestrator` runs the top-level lifecycle (GATHER → MERGE)
- Each feature gets its own `fg-100-orchestrator` instance with isolated state
- Per-feature state in `.forge/runs/{feature-id}/`
- Per-feature worktree in `.forge/worktrees/{feature-id}/`
- No global `.forge/.lock` — per-run locks only
- Cross-repo features: contract producers complete through VERIFY before consumers enter IMPLEMENT

### Sprint → Feature Orchestrator Interface

The sprint orchestrator passes to each feature orchestrator:
- `--run-dir .forge/runs/{feature-id}/`
- `--project-root /path/to/project`
- `--wait-for <project_id>` (for cross-repo dependencies)
- Standard requirement and ticket arguments
```

- [ ] **Step 2: Add sprint communication to agent-communication.md**

```markdown
## Sprint ↔ Feature Communication

The sprint orchestrator (fg-090) communicates with feature orchestrators (fg-100) through:

1. **Sprint state file:** `.forge/sprint-state.json` — shared across all feature runs
2. **Per-run state files:** `.forge/runs/{feature-id}/state.json` — per-feature
3. **Agent dispatch:** fg-090 dispatches fg-100 instances as sub-agents

Feature orchestrators do NOT write to `sprint-state.json`. The sprint orchestrator polls per-run state files and updates the sprint state.

### Wait Mechanism

When `--wait-for <project_id>` is set, the feature orchestrator:
1. Reads `sprint-state.json` for the dependency project's status
2. Blocks at PREFLIGHT until dependency status >= `verifying`
3. Poll interval: 30 seconds
4. Timeout: `cross_repo.timeout_minutes` (default 30)
```

- [ ] **Step 3: Update state-schema.md with per-run directory**

Add:

```markdown
### Per-Run State (Sprint Mode)

In sprint mode, each feature gets its own state directory:

\```
.forge/runs/{feature-id}/
  state.json              # Same schema as root state.json
  checkpoint-*.json       # Same as root
  stage_N_notes_*.md      # Same as root
  .lock                   # Per-run lock
\```

The root `.forge/state.json` is NOT used in sprint mode. Each `runs/{feature-id}/state.json` is a complete, independent pipeline state.
```

- [ ] **Step 4: Commit**

```bash
git add shared/stage-contract.md shared/agent-communication.md shared/state-schema.md
git commit -m "feat: update shared contracts with sprint mode"
```

---

### Task 9: Write contract tests for new agents

**Files:**
- Modify: `tests/contract/agent-frontmatter.bats` (update agent count)
- Modify: `tests/lib/module-lists.bash` (update MIN_AGENTS if applicable)

- [ ] **Step 1: Verify agent count**

After adding 4 new agents (fg-090, fg-101, fg-102, fg-103), total should be 37. Update any hardcoded count guards.

```bash
ls agents/*.md | wc -l
```

Expected: 37

- [ ] **Step 2: Update count guards if needed**

Check `tests/lib/module-lists.bash` for agent count constants and bump them.

- [ ] **Step 3: Run full test suite**

```bash
./tests/run-all.sh
```

Expected: All tests PASS

- [ ] **Step 4: Commit**

```bash
git add tests/
git commit -m "test: update agent count guards for 4 new agents"
```

---

### Task 10: Update CLAUDE.md

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Add new agents to agent list**

In the "Pipeline agents" section, add:

```markdown
- Sprint orchestration: `fg-090-sprint-orchestrator`
- Orchestrator helpers: `fg-101-worktree-manager`, `fg-102-conflict-resolver`, `fg-103-cross-repo-coordinator`
```

Update the agent count from 33 to 37.

- [ ] **Step 2: Add sprint mode to pipeline modes**

```markdown
- **Sprint mode:** `/forge-run --sprint` or `/forge-run --parallel "A" "B" "C"`. Dispatches `fg-090-sprint-orchestrator` which decomposes features, analyzes independence via `fg-102-conflict-resolver`, and dispatches parallel `fg-100-orchestrator` instances per feature. Per-feature isolation: `.forge/runs/{feature-id}/` for state, `.forge/worktrees/{feature-id}/` for git worktrees. Shared Neo4j graph for cross-feature conflict detection. Cross-repo features execute contract producers before consumers. State in `.forge/sprint-state.json`. See `shared/sprint-state-schema.md`.
```

- [ ] **Step 3: Add key entry points**

```markdown
| Sprint orchestration | `shared/sprint-state-schema.md` (sprint state, per-run isolation) |
```

- [ ] **Step 4: Add skills**

Update the skills count and list to include `forge-sprint`.

- [ ] **Step 5: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md with sprint mode and 4 new agents"
```
