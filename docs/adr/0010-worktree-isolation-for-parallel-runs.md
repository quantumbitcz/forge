# ADR-0010: Worktree isolation for parallel runs

- **Status:** Accepted
- **Date:** 2026-04-19
- **Deciders:** @quantumbitcz
- **Supersedes:** —
- **Superseded by:** —

## Context

Users run the pipeline while keeping their editor open in the same checkout.
Without isolation, the pipeline would dirty their working tree, mid-edit files
would get committed, and parallel sprint runs would collide on the same files.

## Decision

Every pipeline run operates in a git worktree under `.forge/worktree`. The
user's primary working tree is never modified. Branches are named
`{type}/{ticket}-{slug}`; branch collisions append an epoch suffix. Sprint runs
get `.forge/runs/{id}/` and `.forge/worktrees/{id}/` per run. Concurrent runs
acquire `.forge/.lock` (PID + 24h stale timeout).

## Consequences

- **Positive:** Safe to run pipeline with editor open; sprint parallelism works; recovery can inspect the isolated tree without touching user's.
- **Negative:** Disk cost (one worktree per active run); git has some quirks around worktrees and submodules that recovery must handle.
- **Neutral:** Users who *want* the pipeline to write directly to their tree must copy results out manually — intentional.

## Alternatives Considered

- **Option A — Same-tree edits with stash/pop:** Rejected — interacts poorly with user edits and fails on uncommitted rebases.
- **Option B — Docker container isolation:** Rejected — too heavy for the common case; git worktrees are lighter.

## References

- `shared/git-conventions.md`
- `agents/fg-101-worktree-manager.md`
