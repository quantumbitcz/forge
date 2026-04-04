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
| `conflicts[].resolution` | string | `serialize \| manual` | How the conflict is resolved |

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
