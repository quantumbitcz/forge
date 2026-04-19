# Phase 14 — Time-Travel Checkpoints (LangGraph-Style Rewind)

**Priority:** P2
**Status:** Design
**Date:** 2026-04-19
**Owner:** forge plugin maintainers

## 1. Goal

Enable backward rewind to any prior checkpoint mid-run via `/forge-recover rewind --to=<checkpoint-id>`, atomically restoring pipeline state, worktree HEAD, event log, and memory snapshot so the pipeline can resume forward from that exact point.

## 2. Motivation

Audit W14 (A+ roadmap) flagged forge's recovery model as one-way: `resume` only restores the *latest* checkpoint, and `rollback` touches only the worktree, leaving `state.json` and `events.jsonl` divergent. Engineers cannot explore "what if we had taken a different branch at PLAN?" without nuking the run. LangGraph's time-travel checkpointing solves exactly this: every node write produces an immutable snapshot, and any snapshot can become the current execution head ([DataCamp: CrewAI vs LangGraph vs AutoGen](https://www.datacamp.com/tutorial/crewai-vs-langgraph-vs-autogen)). Porting that model unlocks (a) debugging with rewind-and-retry, (b) hypothesis testing across reviewer verdicts, and (c) a safe "undo" primitive that covers the full four-tuple (state, git, events, memory) instead of just one facet.

## 3. Scope

### In

- Content-addressable checkpoint store at `.forge/checkpoints/by-hash/<sha256>/`.
- Per-checkpoint bundle: `state.json` snapshot, worktree commit SHA, event-log slice, memory snapshot (PREEMPT + stage notes + wiki refs).
- Human-readable checkpoint IDs: `<stage>.<task>.<seq>` (e.g. `IMPLEMENT.T3.007`), resolved via `.forge/checkpoints/index.json` to content hashes.
- `/forge-recover rewind --to=<id>` — atomic restore of ALL four facets; subsequent `/forge-recover resume` continues from the rewound head.
- `/forge-recover list-checkpoints` — DAG-shaped tree (children = checkpoints created on branches after a prior rewind).
- Immutability window: no checkpoint is deleted while its owning run is active. GC runs post-SHIP or on a cron (`retention_days` TTL).

### Out

- Cross-run rewind: run X's checkpoints are NOT addressable from run Y. Each run owns its CAS subtree.
- Speculative parallel forks (concurrent sibling branches without rewinding first) — deferred to Phase 12.
- Partial-facet rewind (e.g. "rewind only state, keep worktree") — explicit non-goal; restores are atomic all-or-nothing.

## 4. Architecture

### 4.1 CAS layout

```
.forge/checkpoints/
+-- by-hash/
|   +-- <sha256 prefix aa>/<sha256-tail>/
|       +-- manifest.json          # {state_hash, worktree_sha, events_hash, memory_hash, parent_ids[]}
|       +-- state.json             # frozen state snapshot
|       +-- events.slice.jsonl     # events since parent checkpoint
|       +-- memory.tar.zst         # PREEMPT + stage_notes + forge-log excerpt
+-- index.json                     # {"<human-id>": "<sha256>", ...} — forward index
+-- tree.json                      # DAG: {"<sha>": {parents: [...], children: [...], created_at, stage, task}}
+-- HEAD                           # current active checkpoint sha (updated on every write + rewind)
```

**CAS key** = `sha256( state.json-canonical || worktree_sha || sort(events.slice) || memory.tar.zst )`. Identical pipeline states across rewind-and-retry iterations deduplicate to a single on-disk bundle; only `tree.json` grows an edge.

### 4.2 Checkpoint tree, not linear chain

The classical log is a linear list. Rewind breaks that: after `rewind --to=X` the next write creates Y whose parent is X, not the most-recent tip. `tree.json` models this as a DAG — each node has `parents: [sha]` (single-parent except for future merge/fork) and `children: [sha*]`. `HEAD` points at the currently-active leaf. `list-checkpoints` renders the DAG as an indented tree, marking `HEAD` and dead branches (leaves with no `complete: true` run attached).

```
ROOT
+-- PREFLIGHT.-.001  [complete]
    +-- EXPLORE.-.002
        +-- PLAN.-.003
            +-- IMPLEMENT.T1.004
            |   +-- IMPLEMENT.T2.005  <-- dead branch (rewound)
            +-- IMPLEMENT.T1.006      <-- after rewind; HEAD
                +-- IMPLEMENT.T2.007  [HEAD]
```

### 4.3 Atomic restore protocol

`rewind --to=<id>` executes this sequence, aborting with no side-effects on any failure:

1. **Pre-flight gate**: resolve id -> sha; abort if unknown. Abort if worktree dirty (`git status --porcelain` non-empty). Abort if `.forge/.lock` shows a live PID (stale locks are forcibly cleared).
2. **Stage writes into `.forge/.rewind-tx/`**: copy `state.json`, write new `events.jsonl` (truncated at target), stage `git reset --hard <worktree_sha>` command. Nothing touches live `.forge/` yet.
3. **Commit**: rename `state.json` via `forge-state-write.sh` (atomic WAL), `mv events.jsonl.new events.jsonl`, run `git reset --hard <worktree_sha>` in worktree, unpack `memory.tar.zst` into `.forge/stage_notes/` + `.claude/forge-log.md`.
4. **Update `HEAD`** to target sha. Append a `RewoundEvent` to the *fresh* `events.jsonl`.
5. **Release lock, return**.

Between step 2 and step 4, a hard kill leaves `.forge/.rewind-tx/` intact; next invocation detects and either replays or rolls back via `recovery.time_travel.repair_rewind_tx` subroutine in `hooks/_py/checkpoint_cas.py`.

### 4.4 Alternatives considered

**(a) SQLite snapshot DB.** Store each checkpoint as a row in `.forge/checkpoints.db` with BLOB columns for state/events/memory. Wins on query power (ad-hoc SQL over checkpoints). Loses on: (i) no natural dedup — identical state still stored twice unless we implement content hashing ourselves, which brings us back to CAS; (ii) binary worktree snapshots would balloon the DB (gigabytes after a few runs); (iii) git already solves worktree content addressing — mixing a second CAS (SQLite blobs for code diffs) fights git. **Rejected.**

**(b) Full event-sourced replay.** Never snapshot; instead replay `events.jsonl` from genesis to reconstruct any prior state. Wins on minimum disk. Loses catastrophically on: (i) worktree contents are NOT in the event log (agents mutate files directly), so replay cannot reconstruct them; (ii) replay time is O(run length) — a 2-hour run takes minutes to rewind; (iii) replay is only deterministic if every agent is pure, which implementer explicitly is not (calls LLM). **Rejected.**

**(c) CAS (chosen).** Dedup via SHA-256 keys, git handles worktree content addressing natively (just store the commit SHA), event slices are small (delta since parent). O(1) rewind. Disk growth bounded by retention policy. **Selected.**

## 5. Components

| Change | Type | Detail |
|---|---|---|
| `skills/forge-recover/SKILL.md` | modify | Add `rewind` and `list-checkpoints` subcommands to the subcommand table, flags section (`--to=<id>`, `--force`), examples, exit codes (5 = dirty worktree abort, 6 = unknown checkpoint id) |
| `shared/recovery/time-travel.md` | new | Full protocol spec: CAS layout, atomic restore sequence, tx directory semantics, GC rules, failure recovery |
| `hooks/_py/checkpoint_cas.py` | new | Python module: `write_checkpoint()`, `resolve_id()`, `rewind()`, `list_tree()`, `gc()`, `repair_rewind_tx()`. Called by orchestrator via `python3 hooks/_py/checkpoint_cas.py <op> ...`. Uses stdlib only (`hashlib`, `json`, `tarfile`, `zstandard` via optional import — falls back to gzip if zstd missing) |
| `shared/state-schema.md` §Checkpoints | modify | Replace the current `checkpoint-{storyId}.json` file pattern with `.forge/checkpoints/by-hash/...` layout. Add `state.checkpoints` array. Document `HEAD` file. Mark old format as removed (no back-compat per task constraint) |
| `shared/state-transitions.md` | modify | Add transitions: `* -> REWINDING` (triggered by rewind op), `REWINDING -> <restored state>` on success, `REWINDING -> FAILED` on abort. Document that `REWINDING` is a terminal-within-op pseudo-state: it appears only inside the rewind transaction and never persists to `state.story_state` |
| `agents/fg-100-orchestrator.md` §Recovery op dispatch | modify | Add `rewind` and `list-checkpoints` to the recovery_op switch; wire to `checkpoint_cas.py` |

## 6. Data / State / Config

### Config (`.claude/forge-config.md`)

```yaml
recovery:
  time_travel:
    enabled: true                  # master switch
    retention_days: 7              # GC TTL post-SHIP
    max_checkpoints_per_run: 100   # hard cap; oldest non-critical checkpoints GC'd when exceeded
    require_clean_worktree: true   # abort rewind if worktree dirty (safety)
    compression: zstd              # zstd | gzip | none
```

### State schema additions (`state.json`)

```json
{
  "checkpoints": [
    {
      "id": "IMPLEMENT.T1.004",
      "hash": "a3f9...c1",
      "stage": "IMPLEMENTING",
      "task": "T1",
      "created_at": "2026-04-19T10:14:22Z",
      "parents": ["a1b2...f0"]
    }
  ],
  "head_checkpoint": "a3f9...c1"
}
```

`state.checkpoints` is append-only within a run (pre-rewind entries are retained for audit; post-rewind writes append new entries). `head_checkpoint` mirrors `.forge/checkpoints/HEAD`.

## 7. Compatibility

**Breaking change (intentional, per task constraint — no back-compat).**

- Old `.forge/checkpoint-{storyId}.json` files are invalidated on the first rewind-capable run. `checkpoint_cas.py` at startup detects legacy files and emits a one-time WARNING then deletes them (or moves to `.forge/checkpoints/legacy-trash/` if `recovery.time_travel.preserve_legacy: true`, off by default).
- `state.json` version bumps `1.7.0 -> 1.8.0`. Runs with older state are refused by the orchestrator with clear error: "state.json v1.7.0 detected; Phase 14 requires v1.8.0. Run `/forge-recover reset` to start fresh."
- `/forge-recover resume` semantics change: now resumes from `head_checkpoint` (which by default is the latest write; behaviour is identical for users who never rewind).

## 8. Testing Strategy

Forge does not run tests locally (per CLAUDE.md). All tests run in CI via the existing `tests/run-all.sh` harness.

### Eval harness (new, under `tests/eval/time-travel/`)

1. **round-trip.bats** — write checkpoint, read back, assert byte-identical state/events/memory; assert git SHA matches.
2. **rewind-convergence.bats** — run scripted scenario to IMPLEMENT.T3, rewind to PLAN, re-run implementation with seeded LLM replies, assert final `state.json` equivalent to the non-rewound baseline (modulo timestamps + `checkpoints[]`).
3. **dedup-storage.bats** — generate 10 checkpoints where 3 have identical state; assert `by-hash/` dir count == 8 (3 dedup'd to 1). Fails if dedup ratio < 1.25x for this scenario.
4. **dirty-worktree-abort.bats** — mutate a file, attempt rewind, assert exit 5 and zero side-effects (state.json, events.jsonl, HEAD, worktree all untouched).
5. **crash-mid-rewind.bats** — SIGKILL the rewind process between stage 2 and stage 4 of §4.3; re-invoke; assert either full completion or full rollback (no half-state).
6. **tree-dag.bats** — checkpoint tree with 2 rewinds produces 3 leaves; `list-checkpoints` output matches golden file.

### CI gates

- Dedup ratio assertion: `.forge/checkpoints/by-hash/` size / raw-bundle-size-sum must be <= 0.75 across the eval scenarios (25%+ dedup).
- Storage ceiling: per-run checkpoint dir < 50 MB for standard scenario.
- Rewind wall-time < 2 s for 50-checkpoint run on reference hardware.

## 9. Rollout

Single PR. Includes:

- `hooks/_py/checkpoint_cas.py` + unit tests under `tests/unit/py/checkpoint_cas/`.
- `shared/recovery/time-travel.md`.
- `skills/forge-recover/SKILL.md` update.
- `shared/state-schema.md` update + state version bump.
- `shared/state-transitions.md` update.
- `agents/fg-100-orchestrator.md` recovery_op dispatch update.
- Eval harness under `tests/eval/time-travel/`.
- CHANGELOG entry noting breaking state.json version bump.

Feature defaults `enabled: true` out of the gate — no opt-in phase. Consistent with the no-back-compat constraint.

## 10. Risks / Open Questions

1. **Worktree reset destroys uncommitted user edits.** Mitigated by the `require_clean_worktree` pre-flight check (default on): rewind aborts with exit 5 and a clear message listing dirty paths. User must `git stash` or `git commit` before rewinding. `--force` flag overrides (documented as destructive).
2. **Memory snapshot covers PREEMPT + stage notes but NOT external MCP state** (Linear tickets, Neo4j graph, wiki regeneration). Post-rewind, those remain "forward" of the checkpoint. Documented as known limitation; orchestrator logs a WARNING listing out-of-sync MCP surfaces after every rewind. Phase 12+ may address via MCP-replay hooks.
3. **Disk pressure on long runs.** 100-checkpoint cap + 7-day retention + CAS dedup should bound worst-case to low-hundreds of MB. GC is best-effort (never blocks a run); if the run crashes mid-GC, next invocation retries.
4. **Open question: cross-run rewind.** Deferred explicitly. Would require promoting `run-history.db` to carry checkpoint refs. Revisit after 3 months of usage data.
5. **Open question: zstandard dependency.** Python stdlib lacks zstd. We fall back to gzip transparently, but the docs should note ~3x storage benefit from `pip install zstandard`. Since forge bans forced Python deps, this stays optional.

## 11. Success Criteria

- `rewind --to=<id>` succeeds on any checkpoint in `state.checkpoints` for the active run, restoring state+worktree+events+memory atomically.
- Forward replay from a rewound checkpoint converges to the same final `state.story_state` as a clean run under seeded-LLM eval conditions.
- Storage overhead per run <= 3x the on-disk size of a single checkpoint bundle (measured via `du -sh .forge/checkpoints/`).
- `list-checkpoints` completes in under 500 ms for runs with up to 100 checkpoints.
- Zero data loss across `crash-mid-rewind.bats` (atomicity guarantee).
- `/forge-recover resume` continues to work identically for users who never invoke `rewind` (backward-compatible at the skill-surface level even though on-disk format changes).

## 12. References

- DataCamp — CrewAI vs LangGraph vs AutoGen: https://www.datacamp.com/tutorial/crewai-vs-langgraph-vs-autogen
- LangGraph persistence / time-travel: https://langchain-ai.github.io/langgraph/concepts/persistence/#replay
- LangGraph checkpointer API: https://langchain-ai.github.io/langgraph/reference/checkpoints/
- Git `reset --hard` semantics: https://git-scm.com/docs/git-reset
- Content-addressable storage in Git: https://git-scm.com/book/en/v2/Git-Internals-Git-Objects
- forge shared/recovery/recovery-engine.md — existing recovery strategies
- forge shared/state-schema.md §Checkpoints — current checkpoint schema being superseded
