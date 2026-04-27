# Feature Lifecycle Policy

Every feature in `CLAUDE.md` §Features passes through three states based on
usage tracked in `.forge/run-history.db` (`feature_usage` table, populated by
`fg-700-retrospective`).

## States

### 1. Active

Any run in the last 90 days. Default state for all features at landing time.

### 2. Flagged -- zero runs for >=90 days

`python shared/feature_matrix_generator.py` emits a trailing marker
`<!-- FLAGGED -->` on the row in `shared/feature-matrix.md`. No automatic
action. The plugin author reviews flagged features during the next retro.

### 3. Candidate for removal -- zero runs for >=180 days

A separate CI job runs `python shared/feature_deprecation_check.py`. If any
feature crosses the 180-day threshold, the script opens a PR titled
`chore(features): propose removal of F{id}` with a generated diff that
removes:
- The feature's config section in `forge-config.md`.
- The row in CLAUDE.md §Features.
- Any `agents/` conditional gates keyed on the feature's config flag.

Human merge is always required. The removal PR must reference a 180-day usage
window snapshot as evidence.

## Feature usage table schema

Columns in `feature_usage`:
- `feature_id TEXT NOT NULL` -- e.g. `F17`, `F34`.
- `ts DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP` -- wall-clock UTC.
- `run_id TEXT NOT NULL` -- foreign key to `runs.id`.

Index: `(feature_id, ts DESC)` for fast 30/90/180-day window queries.

## Write path

Orchestrator (`fg-100`) emits `feature_used` events into `.forge/events.jsonl`
at the moment a feature's code path first runs in a pipeline invocation.
Retrospective (`fg-700`) aggregates those events at LEARN stage and writes
one row per unique `feature_id` per run into `feature_usage`.

Orchestrator emit is preferred over retrospective emit so that runs which
abort before LEARN still credit usage accurately.

## Example workflow

1. F20 (Monorepo tooling) used in 4 runs across April 2026.
2. Author stops using Nx; May 2026 -- no F20 runs.
3. Day 90 (late-July 2026): matrix flips to `<!-- FLAGGED -->`.
4. Day 180 (late-October 2026): `feature_deprecation_check.py` opens PR.
5. Author reviews; either merges (removing F20) or documents why it stays.

## Non-goals

- This policy does not auto-merge removal PRs.
- It does not delete user data (run history is append-only).
- It does not affect opt-out (features with `enabled: false` in forge-config.md
  still count if their code path ran -- the gate is "code path executed," not
  "user said yes").
