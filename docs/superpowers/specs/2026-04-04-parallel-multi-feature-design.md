# Parallel Multi-Feature Development — Sprint-Level Orchestration

> **Scope:** Add a sprint orchestrator that decomposes multiple features, analyzes independence, and dispatches parallel forge pipeline instances across features and repos. Includes orchestrator decomposition into focused sub-agents. Part of v1.5.0.
>
> **Status:** Design approved
>
> **Dependencies:** Spec 2 (Neo4j Multi-Project Namespacing) — required. Spec 1 (CLI UI Patterns) — recommended.

---

## 1. Problem Statement

Forge currently runs one pipeline per project at a time (enforced by `.forge/.lock`). A single `state.json`, single worktree, and single lock mean that:

- Multiple independent features in a sprint must be developed sequentially
- Cross-repo features (BE + FE + Infra) can only coordinate within a single pipeline run
- The orchestrator at ~2000 lines mixes state machine logic with worktree management, conflict detection, and cross-repo coordination
- No mechanism exists to analyze feature independence and parallelize safe combinations

## 2. Design Decisions

### Considered Alternatives

**Sprint input source:**
1. Linear-only — rejected: requires Linear, not all users have it
2. Manual list only — rejected: misses structured sprint data
3. **Both Linear + manual list (chosen)** — Linear as primary when configured, manual list as fallback

**Independence analysis:**
1. File-level only — rejected: too conservative, serializes features that touch different functions in same file
2. Symbol-level only — rejected: requires complete graph enrichment
3. **Hybrid file + symbol (chosen)** — file-level always available, symbol-level when graph is enriched

**Execution model:**
1. Fully isolated worktrees — rejected: misses opportunity for cross-feature conflict detection
2. Shared worktree, serialized stages — rejected: complex scheduling, interference risk
3. **Isolated worktrees + shared graph (chosen)** — git isolation for files, shared Neo4j for cross-feature awareness

**Sprint orchestrator:**
1. Extend fg-100-orchestrator — rejected: already ~2000 lines, mixing concerns
2. **New fg-090-sprint-orchestrator (chosen)** — clean separation, single responsibility

### Justification

The sprint orchestrator sits above the feature orchestrator as a natural layering: sprint decomposition → feature independence → parallel dispatch → merge coordination. Git worktrees provide proven file isolation. The shared Neo4j graph (namespaced by Spec 2) enables cross-feature and cross-repo analysis without additional infrastructure.

## 3. Orchestrator Decomposition

### Current fg-100-orchestrator (~2000 lines)

Splits into 4 focused agents:

| Agent | Responsibility | ~Lines |
|-------|---------------|--------|
| `fg-100-orchestrator` (slimmed) | State machine, stage dispatch loop, stage note coordination | ~1000 |
| `fg-101-worktree-manager` | Worktree lifecycle: create, cleanup, branch naming, stale detection | ~200 |
| `fg-102-conflict-resolver` | Parallel task conflict detection, shared-file serialization, parallel group construction | ~300 |
| `fg-103-cross-repo-coordinator` | Cross-repo worktree creation, lock ordering, PR linking, timeout management | ~250 |

### What Stays in fg-100-orchestrator

- State machine transitions (PREFLIGHT → ... → LEARNING)
- Stage dispatch (Agent calls to fg-200, fg-300, fg-400, etc.)
- TaskCreate/TaskUpdate for stage-level progress
- AskUserQuestion for escalations (lock conflict, stuck loops, feedback loops)
- Graph update triggers (post-IMPLEMENT, post-VERIFY, pre-REVIEW)
- Recovery coordination (delegates to recovery engine, owns the decision)

### fg-101-worktree-manager

Called at PREFLIGHT and LEARN.

Operations:
- `create(ticket_id, slug)` → returns worktree path and branch name
- `cleanup(worktree_path)` → removes worktree, optionally deletes branch
- Branch collision handling (epoch suffix fallback)
- Stale worktree detection from interrupted runs

```yaml
tools: ['Bash', 'Read', 'Glob']
ui: # omitted — Tier 4
```

### fg-102-conflict-resolver

Called at IMPLEMENT (within-feature task grouping) and by fg-090 (cross-feature independence).

Input: list of tasks/features with their target files.

Process:
1. Query Neo4j graph for file/symbol overlap
2. Build conflict matrix
3. Output parallel groups + serial chains

```yaml
tools: ['Read', 'Grep', 'Glob', 'neo4j-mcp']
ui: # omitted — Tier 4
```

Reused by both `fg-100-orchestrator` (task-level) and `fg-090-sprint-orchestrator` (feature-level) — same algorithm, different scope.

### fg-103-cross-repo-coordinator

Called at IMPLEMENT and SHIP for cross-repo work.

Operations:
- Create worktrees in related project directories
- Manage per-project locks with alphabetical ordering
- Coordinate cross-repo PR creation and linking
- Handle timeout (30min per project, configurable via `cross_repo.timeout_minutes`)

```yaml
tools: ['Bash', 'Read', 'Grep', 'Glob', 'Agent', 'AskUserQuestion', 'TaskCreate', 'TaskUpdate']
ui:
  tasks: true
  ask: true
  plan_mode: false
```

### Communication Pattern

The orchestrator dispatches extracted agents like any other sub-agent:

```
worktree_path = dispatch fg-101-worktree-manager "create FG-042 add-user-avatars"
parallel_groups = dispatch fg-102-conflict-resolver "analyze [task1, task2, task3]"
cross_repo_result = dispatch fg-103-cross-repo-coordinator "implement [api-contract-update]"
```

Results returned via stage notes (standard agent communication pattern).

## 4. Sprint Orchestrator: fg-090-sprint-orchestrator

### Identity

Number `090` — sits above `fg-100-orchestrator` in the dispatch hierarchy.

Entry points:
- `/forge-run --sprint` — reads current active cycle from Linear
- `/forge-run --sprint CYC-42` — reads specific cycle
- `/forge-run --parallel "Feature A" "Feature B" "Feature C"` — manual list

### Tools and UI

```yaml
tools: ['Read', 'Grep', 'Glob', 'Bash', 'Agent', 'TaskCreate', 'TaskUpdate', 'AskUserQuestion', 'EnterPlanMode', 'ExitPlanMode', 'neo4j-mcp']
ui:
  tasks: true
  ask: true
  plan_mode: true
```

### Lifecycle

```
1. GATHER    — Collect features from Linear sprint/cycle or manual input
2. ANALYZE   — Run independence analysis via fg-102-conflict-resolver
3. GROUP     — Partition into parallel groups and serial chains
4. APPROVE   — Present plan to user via AskUserQuestion
5. DISPATCH  — Launch fg-100-orchestrator per feature (isolated worktrees)
6. MONITOR   — Track progress, detect runtime conflicts, handle failures
7. MERGE     — Coordinate PR creation, resolve merge order
```

### Task Blueprint

- "Gather features from {source}"
- "Analyze feature independence"
- "Present parallel execution plan"
- "Dispatch Feature: {feature_name}" (one per feature, parallel)
- "Monitor execution progress"
- "Coordinate merge and PRs"

### Approval Presentation

```
header: "Sprint Plan"
question: "I've analyzed {N} features for independence. Here's the proposed execution:"
options:
  - "Approve" (description: "Run {G} parallel groups + {S} serial chains as shown")
  - "Override" (description: "Let me adjust which features run in parallel")
  - "Serialize all" (description: "Run all features sequentially — safest, slowest")
  - "Abort" (description: "Cancel sprint execution")
```

## 5. Isolation Model

### Per-Feature Resources

| Resource | Location | Isolation |
|----------|----------|-----------|
| Git worktree | `.forge/worktrees/{feature-id}/` | Full — separate working tree, own branch |
| State file | `.forge/runs/{feature-id}/state.json` | Full — independent state machine |
| Checkpoints | `.forge/runs/{feature-id}/checkpoint-*.json` | Full |
| Stage notes | `.forge/runs/{feature-id}/stage_N_notes_*.md` | Full |
| Neo4j graph | Shared instance, scoped by `project_id` | Shared — features see each other's graph updates |
| Lock file | `.forge/runs/{feature-id}/.lock` | Per-feature |
| Kanban ticket | Separate ticket per feature | Full |

### Directory Structure

```
.forge/
  runs/
    FG-042-add-avatars/
      state.json
      checkpoint-*.json
      stage_N_notes_*.md
      .lock
      worktree/              # git worktree for this feature
    FG-043-fix-checkout/
      state.json
      ...
      worktree/
  sprint-state.json          # sprint orchestrator state
  tracking/                  # kanban (unchanged, tickets reference run IDs)
```

### Lock Model

**Sprint mode:** per-run locks at `.forge/runs/{feature-id}/.lock`. The sprint orchestrator manages coordination through the sprint state file, no global lock.

**Single-feature mode:** unchanged — global `.forge/.lock`, `.forge/state.json`, `.forge/worktree`. Full backwards compatibility.

### Shared Graph Coordination

Features share the Neo4j graph (namespaced by `project_id` from Spec 2). When Feature A's implementer modifies `UserService.kt`:
1. Post-IMPLEMENT graph update writes the change to Neo4j
2. Feature B's planner/conflict-resolver can detect the overlap
3. Sprint orchestrator monitors for runtime conflicts — if detected mid-execution, pauses conflicting feature and presents options via AskUserQuestion

Runtime conflict detection query:
```cypher
MATCH (f:ProjectFile {project_id: $project_id})
WHERE f.path IN $feature_a_files AND f.path IN $feature_b_files
AND f.last_modified > $feature_b_start_time
RETURN f.path
```

## 6. Independence Analysis

### Algorithm

Run by `fg-102-conflict-resolver` for both within-feature task grouping and cross-feature independence.

**Phase 1 — File-Level (always available):**
1. For each feature, estimate affected files:
   - Explicit file references in the requirement/story
   - Graph query: files in same package/module as referenced classes
   - Heuristic: feature mentions "UserService" → include `UserService.kt`, `UserServiceTest.kt`, importers
2. Build conflict matrix: Feature X vs Feature Y = set intersection of affected files
3. Empty intersection → independent (can parallelize)
4. Non-empty intersection → check symbol level or serialize

**Phase 2 — Symbol-Level (when graph has enrichment):**
1. For overlapping files, query `ProjectClass` and `ProjectFunction` nodes
2. Different classes/functions in same file → still independent
3. Same class, different methods → still independent (with WARNING)
4. Same method → serialize

**Output:**
```
parallel_groups:
  - [FG-042, FG-044]        # fully independent
  - [FG-043]                 # independent from group 1
serial_chains:
  - [FG-045 → FG-046]       # FG-046 depends on FG-045's output
conflicts:
  - pair: [FG-042, FG-043]
    files: [src/UserService.kt]
    resolution: "symbol-level independent (different methods)"
```

## 7. Cross-Repo Sprint Execution

### Scenario

User runs `/forge-run --sprint` on `wellplanned-be`. Story FG-042 ("Add user avatar upload") requires:
- **BE:** New endpoint, storage service, DB migration
- **FE:** Avatar component, upload form, profile page update
- **Infra:** S3 bucket config, CDN rule, image resize Lambda

### Cross-Repo Discovery

At GATHER phase, the sprint orchestrator:

1. Reads `related_projects` from `forge.local.md`
2. Queries Neo4j for all project graphs:
   ```cypher
   MATCH (pc:ProjectConfig)
   RETURN pc.project_id, pc.component, pc.language
   ```
3. For each feature, analyzes which repos are affected:
   - Graph query: feature references types/endpoints/contracts in other project graphs
   - Pattern matching: feature domain maps to known repo responsibilities
   - Explicit cross-repo markers in Linear stories (labels `backend`, `frontend`, `infra`)

### Cross-Repo Feature Plan

A single feature spanning repos produces a multi-repo plan:

```
feature: FG-042 "Add user avatar upload"
repos:
  - project_id: quantumbitcz/wellplanned-be
    tasks: [api-endpoint, storage-service, db-migration]
    order: 1 (implements contracts first)
  - project_id: quantumbitcz/wellplanned-fe
    tasks: [avatar-component, upload-form, profile-update]
    order: 2 (consumes BE contracts)
  - project_id: quantumbitcz/wellplanned-infra
    tasks: [s3-bucket, cdn-rule, image-resize]
    order: 1 (parallel with BE — no dependency)
```

### Execution Order

Cross-repo dependencies follow the existing rule from `stage-contract.md`: "Backend modules complete through VERIFY before frontend enters IMPLEMENT." Extended to sprint level:

1. **Contract producers first** — repos defining APIs/contracts (BE, Infra)
2. **Contract consumers second** — repos consuming APIs (FE)
3. **Independent repos in parallel** — repos with no dependency (e.g., BE and Infra)

The sprint orchestrator uses `fg-102-conflict-resolver` with cross-project graph queries to determine dependency order.

### Per-Repo Dispatch

Each repo gets its own `fg-100-orchestrator` instance:

```
dispatch fg-100-orchestrator
  --project-root /path/to/wellplanned-be
  --requirement "Add avatar upload endpoint and storage service"
  --ticket FG-042
  --run-dir .forge/runs/FG-042/

dispatch fg-100-orchestrator
  --project-root /path/to/wellplanned-fe
  --requirement "Add avatar component and upload form"
  --ticket FG-042
  --run-dir .forge/runs/FG-042/
  --wait-for wellplanned-be  # blocks until BE reaches VERIFY
```

The `--wait-for` mechanism: the dispatched orchestrator polls `sprint-state.json` for the dependency repo's status to reach `verifying` or later before proceeding past its own PREFLIGHT. Poll interval: 30 seconds. Timeout: inherits from `cross_repo.timeout_minutes` (default 30).

Each creates its own worktree in the respective project directory. State tracked in sprint state file.

### Cross-Repo PR Linking

At SHIP stage, the sprint orchestrator:
1. Collects PR URLs from all per-repo orchestrators
2. Adds cross-references to each PR description ("Related PRs: ...")
3. If Linear configured, links all PRs to the same story
4. Optionally creates a parent tracking issue that references all sub-PRs

### Sprint State File

`.forge/sprint-state.json`:

```json
{
  "version": "1.0.0",
  "sprint_id": "CYC-42",
  "source": "linear",
  "features": [
    {
      "id": "FG-042",
      "name": "Add user avatar upload",
      "status": "implementing",
      "repos": [
        {
          "project_id": "quantumbitcz/wellplanned-be",
          "status": "verifying",
          "run_dir": ".forge/runs/FG-042/",
          "pr_url": null
        },
        {
          "project_id": "quantumbitcz/wellplanned-fe",
          "status": "waiting",
          "waiting_for": "quantumbitcz/wellplanned-be",
          "run_dir": null,
          "pr_url": null
        }
      ]
    }
  ],
  "parallel_groups": [
    ["FG-042", "FG-044"],
    ["FG-043"]
  ],
  "serial_chains": [
    ["FG-045", "FG-046"]
  ],
  "conflicts": []
}
```

## 8. Impact Analysis

### 8.1 Agents Created (4)

| Agent | Purpose | UI Tier |
|-------|---------|---------|
| `fg-090-sprint-orchestrator` | Sprint decomposition, independence analysis, cross-repo dispatch | Tier 1 (tasks + ask + plan_mode) |
| `fg-101-worktree-manager` | Worktree lifecycle (create, cleanup, branch naming) | Tier 4 (no UI) |
| `fg-102-conflict-resolver` | File/symbol conflict detection, parallel group construction | Tier 4 (no UI) |
| `fg-103-cross-repo-coordinator` | Cross-repo worktree, lock ordering, PR linking | Tier 2 (tasks + ask) |

### 8.2 Files Created

| File | Purpose |
|------|---------|
| `agents/fg-090-sprint-orchestrator.md` | Sprint orchestrator agent |
| `agents/fg-101-worktree-manager.md` | Worktree manager agent |
| `agents/fg-102-conflict-resolver.md` | Conflict resolver agent |
| `agents/fg-103-cross-repo-coordinator.md` | Cross-repo coordinator agent |
| `shared/sprint-state-schema.md` | Schema for `.forge/sprint-state.json` |
| `skills/forge-sprint/SKILL.md` | Entry point skill for `--sprint` / `--parallel` |

### 8.3 Files Modified

| File | Change |
|------|--------|
| `agents/fg-100-orchestrator.md` | Extract ~1000 lines to fg-101/102/103, add `--project-root`, `--run-dir`, `--wait-for` parameters |
| `shared/state-schema.md` | Document per-run directory structure, per-run lock model |
| `shared/stage-contract.md` | Add sprint mode cross-cutting constraints, cross-repo execution order |
| `shared/agent-communication.md` | Add sprint ↔ feature orchestrator communication pattern |
| `skills/forge-run/SKILL.md` | Add `--parallel` and `--sprint` flags |
| `shared/graph/query-patterns.md` | Add patterns 18-19 for cross-repo feature impact analysis |
| `CLAUDE.md` | Add sprint orchestrator, new agents, `--parallel`/`--sprint` flags, sprint state schema |

### 8.4 Files NOT Modified

- All 10 review agents — no sprint awareness needed
- Module files — no impact
- Check engine / hooks — no impact
- `shared/scoring.md` — unchanged
- `shared/graph/schema.md` — already handled by Spec 2

### 8.5 Agent Count

Current: 33 agents. After: 37 agents (+4).

### 8.6 Backwards Compatibility

None needed. Single-feature `/forge-run` without `--parallel`/`--sprint` works exactly as before — same `.forge/state.json`, same `.forge/worktree`, same global lock. The per-run directory structure (`.forge/runs/`) is only created in sprint mode.
