# Sprint State Schema

Defines the `.forge/sprint-state.json` schema used by `fg-090-sprint-orchestrator` to coordinate parallel multi-feature development within a single sprint.

---

## sprint-state.json

Root sprint state file. Created when a sprint run begins, updated as features progress through the pipeline.

### Schema

~~~json
{
  "version": "1.0.0",
  "sprint_id": "sprint-2026-04-1",
  "source": "linear",
  "started": "2026-04-04T09:00:00Z",
  "status": "executing",
  "features": [
    {
      "id": "FG-42",
      "name": "Add plan comment feature",
      "status": "executing",
      "waiting_for": null,
      "repos": [
        {
          "project_id": "git@github.com:org/backend.git",
          "status": "implementing",
          "waiting_for": null,
          "run_dir": ".forge/runs/FG-42",
          "worktree": ".forge/worktrees/FG-42",
          "branch": "feat/FG-42-add-plan-comment",
          "pr_url": null
        },
        {
          "project_id": "git@github.com:org/frontend.git",
          "status": "waiting",
          "waiting_for": "git@github.com:org/backend.git",
          "run_dir": "/path/to/frontend/.forge/runs/FG-42",
          "worktree": "/path/to/frontend/.forge/worktrees/FG-42",
          "branch": null,
          "pr_url": null
        }
      ]
    },
    {
      "id": "FG-43",
      "name": "Add client export",
      "status": "approved",
      "waiting_for": null,
      "repos": [
        {
          "project_id": "git@github.com:org/backend.git",
          "status": "planning",
          "waiting_for": null,
          "run_dir": ".forge/runs/FG-43",
          "worktree": ".forge/worktrees/FG-43",
          "branch": null,
          "pr_url": null
        }
      ]
    }
  ],
  "parallel_groups": [
    ["FG-42", "FG-43"],
    ["FG-44"]
  ],
  "serial_chains": [
    ["FG-45", "FG-46"]
  ],
  "conflicts": [
    {
      "pair": ["FG-42", "FG-47"],
      "files": ["src/main/kotlin/Plan.kt"],
      "resolution": "serialize"
    }
  ]
}
~~~

### Field Reference

| Field | Type | Values | Description |
|-------|------|--------|-------------|
| `version` | string | `"1.0.0"` | Schema version |
| `sprint_id` | string | — | Unique sprint identifier (from Linear cycle or manual) |
| `source` | string | `linear \| manual` | How the sprint was initiated |
| `started` | string | ISO 8601 | When the sprint run began |
| `status` | string | `gathering \| analyzing \| approved \| executing \| merging \| complete \| failed` | Overall sprint lifecycle state |
| `features[].id` | string | — | Feature ticket ID (e.g., `FG-42`) |
| `features[].name` | string | — | Human-readable feature name |
| `features[].status` | string | `gathering \| analyzing \| approved \| executing \| merging \| complete \| failed` | Per-feature lifecycle state |
| `features[].waiting_for` | string\|null | feature id or null | Feature this one is blocked on (serial chain dependency) |
| `features[].repos[].project_id` | string | git remote URL | Unique project identifier for this repo |
| `features[].repos[].status` | string | `waiting \| planning \| implementing \| verifying \| reviewing \| shipping \| complete \| failed` | Per-repo per-feature pipeline state |
| `features[].repos[].waiting_for` | string\|null | project_id or null | Repo this one is waiting on (e.g., FE waits for BE contract) |
| `features[].repos[].run_dir` | string | absolute path | Directory holding per-run forge state (state.json, checkpoints, stage notes) |
| `features[].repos[].worktree` | string\|null | absolute path or null | Git worktree path for this feature+repo combination |
| `features[].repos[].branch` | string\|null | branch name or null | Git branch name (set after worktree creation) |
| `features[].repos[].pr_url` | string\|null | URL or null | Pull request URL (set after SHIP stage) |
| `parallel_groups` | array of arrays | feature ID lists | Groups of features that can execute concurrently |
| `serial_chains` | array of arrays | feature ID lists | Ordered sequences that must execute sequentially |
| `conflicts` | array | — | Detected file/symbol conflicts between features |
| `conflicts[].pair` | array | two feature IDs | The conflicting feature pair |
| `conflicts[].files` | array | file paths | Shared files causing the conflict |
| `conflicts[].resolution` | string | `serialize \| manual` | How the conflict is resolved. `serialize`: the first feature in the pair completes its SHIP stage (stage 8) before the second feature enters IMPLEMENT (stage 4) — both features may still run exploration/planning in parallel. `manual`: the sprint orchestrator escalates to the user via `AskUserQuestion` to decide the resolution strategy. |

---

## State Synchronization

The sprint orchestrator (`fg-090`) polls per-feature state to coordinate parallel execution:

- **Polling interval:** Every 30 seconds (configurable via `sprint.poll_interval_seconds` in `forge-config.md`, default: 30, range: 10-120).
- **Mechanism:** Read each feature's `.forge/runs/{feature-id}/state.json` and extract `story_state`, `score_history`, and error flags.
- **Sprint state update:** After each poll, update `sprint-state.json` with the latest per-repo status derived from the per-run state files.
- **Stale data detection:** If a feature's `state.json` has not been modified for more than 5 minutes and its status is not `complete` or `failed`, log WARNING in sprint notes. If stale for more than `sprint.dependency_timeout_minutes` (default: 60), mark the feature as `failed` with reason `"stale_timeout"`.

## Waiting State Behavior

When a feature repo's status is `waiting` (i.e., `waiting_for` is set):

- The feature's `fg-100-orchestrator` instance is **not dispatched**. No stage work occurs.
- The sprint orchestrator polls the dependency's status. When the dependency's status reaches the required threshold (default: `shipping` for cross-repo contract producers, `complete` for serial chain dependencies), the waiting feature transitions to `planning`.
- **Timeout:** If a waiting feature remains in `waiting` for more than `sprint.dependency_timeout_minutes` (default: 60), the sprint orchestrator escalates to the user with options: "Continue waiting", "Skip dependency and proceed", "Abort feature". This is the same timeout as documented in the [Waiting Dependency Timeout](#waiting-dependency-timeout) section below.

---

## Directory Structure

Each feature+repo combination gets an isolated run directory and worktree:

```
.forge/
+-- sprint-state.json                    # Root sprint state (this schema)
+-- runs/
|   +-- {feature-id}/                    # Per-feature run directory (primary repo)
|       +-- state.json                   # Standard forge state for this feature run
|       +-- checkpoint-{id}.json         # Recovery checkpoint
|       +-- stage_N_notes_{id}.md        # Per-stage notes (N = 0-9)
|       +-- .lock                        # Per-run lock file (PID-based)
+-- worktrees/
    +-- {feature-id}/                    # Isolated worktree for this feature
        (git worktree pointing to feature branch)
```

Related projects (cross-repo) use the same structure under their own `.forge/` directory:

```
/path/to/related-project/
+-- .forge/
    +-- runs/
    |   +-- {feature-id}/
    +-- worktrees/
        +-- {feature-id}/
```

---

## Lifecycle Table

Who sets each field and when:

| Field | Set By | When |
|-------|--------|------|
| `sprint_id` | `fg-090-sprint-orchestrator` | Sprint start |
| `source` | `fg-090-sprint-orchestrator` | Sprint start (from Linear cycle or manual) |
| `started` | `fg-090-sprint-orchestrator` | Sprint start |
| `status` | `fg-090-sprint-orchestrator` | Each sprint phase transition |
| `features[].status` | `fg-090-sprint-orchestrator` | Each feature phase transition |
| `features[].waiting_for` | `fg-102-conflict-resolver` | After conflict analysis (serial chains) |
| `features[].repos[].status` | `fg-090-sprint-orchestrator` | After reading per-run state.json |
| `features[].repos[].waiting_for` | `fg-103-cross-repo-coordinator` | After producer/consumer dependency analysis |
| `features[].repos[].run_dir` | `fg-090-sprint-orchestrator` | At feature+repo initialization |
| `features[].repos[].worktree` | `fg-101-worktree-manager` | After `create` operation |
| `features[].repos[].branch` | `fg-101-worktree-manager` | After `create` operation |
| `features[].repos[].pr_url` | `fg-600-pr-builder` | After SHIP stage |
| `parallel_groups` | `fg-102-conflict-resolver` | After conflict analysis |
| `serial_chains` | `fg-102-conflict-resolver` | After conflict analysis |
| `conflicts` | `fg-102-conflict-resolver` | After conflict analysis |

---

## Lock Model

**Sprint mode (multi-feature):** Per-run locks only. Each feature+repo combination holds its own `.forge/runs/{feature-id}/.lock` file. Features running in parallel each hold their own lock. The global `.forge/.lock` is NOT used in sprint mode — it would serialize the entire sprint.

**Single-feature mode (standard):** Global `.forge/.lock` with PID check and 24-hour stale timeout. See `shared/state-schema.md`.

Lock acquisition order when multiple repos are involved in a single feature: alphabetical by `project_id` (git remote URL). This ordering is mandatory and enforced by `fg-103-cross-repo-coordinator` to prevent deadlocks.

Lock stale detection: a lock is considered stale if the PID is no longer running OR the lock file is older than 24 hours. `fg-101-worktree-manager detect-stale` checks both conditions.

---

## Conflict Detection Algorithm

`fg-102-conflict-resolver` detects conflicts between features using a two-level analysis:

1. **File-level overlap:** For each feature pair, compute the intersection of files touched by their plans. If any files overlap, create a conflict entry with `resolution: "serialize"`. The feature with higher priority (earlier in the sprint backlog) executes first.
2. **Symbol-level overlap (graph-enhanced):** When Neo4j is available, query pattern 19 (Cross-Feature File Overlap) extends file-level detection with import/dependency analysis. If feature A modifies a file that feature B imports, this creates an indirect conflict even without direct file overlap.

If no graph is available, only file-level overlap is used. Conflict resolution always prefers `serialize` over `manual` unless the user explicitly overrides.

---

## Waiting Dependency Timeout

Features and repos with `waiting_for` set are subject to a timeout:

- **Default:** 60 minutes per waiting dependency (configurable via `sprint.dependency_timeout_minutes` in `forge-config.md`).
- **Detection:** `fg-090-sprint-orchestrator` checks waiting features every iteration. If a feature has been waiting longer than the timeout, escalate to user with options: (1) Continue waiting, (2) Skip the dependency, (3) Abort the waiting feature.
- **Cascading abort on skip/abort:** When a dependency is skipped or aborted, ALL features and repos with `waiting_for` pointing to that dependency (direct or transitive) must be updated:
  1. Set their status to `failed` with reason `"dependency_skipped"` or `"dependency_aborted"`.
  2. Clear their `waiting_for` field (dependency no longer exists to wait on).
  3. If the affected feature has repos with worktrees, clean up the worktrees via `fg-101-worktree-manager delete`.
  4. Log each cascading failure in sprint notes for the sprint summary.
- **Deadlock detection:** If feature A waits for B and B waits for A (direct or transitive cycle), escalate immediately without waiting for timeout. Use topological sort on the `waiting_for` graph — if sort produces fewer nodes than input, a cycle exists.
- **Lock ordering normalization:** When sorting by `project_id` for lock acquisition, normalize URLs first: strip protocol prefix (`git@`, `https://`), strip trailing `.git`, lowercase the result. E.g., `git@github.com:Org/Backend.git` normalizes to `github.com:org/backend`.

---

## Sprint Completion Criteria

Sprint transitions from `merging` to `complete` when ALL of:
1. All features have status `complete` or `failed`
2. All PRs (primary and cross-repo) are created (merged is not required — user merges)
3. No features have status `executing` or `waiting`

Sprint transitions to `failed` only if zero features completed successfully and at least one feature has status `failed`. A sprint where some features completed and others failed is still marked `complete` (partial success) — the failed features are reported in the sprint summary for follow-up.
