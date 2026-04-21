# Time-Travel Checkpoints

**Status:** Active (since state-schema 1.9.0, forge 3.3.0)
**Owner:** forge plugin maintainers
**Implementation:** `hooks/_py/time_travel/` (modules: `cas.py`, `restore.py`, `events.py`, `gc.py`, `__main__.py`)
**CLI:** `python3 -m hooks._py.time_travel <op> --run-dir <dir> --worktree <dir> [...]`

## 1. Purpose

Atomic backward rewind to any prior checkpoint in a run, restoring the full four-tuple (state, worktree, events, memory).

## 2. On-disk layout

```
.forge/runs/<run_id>/
├── state.json
├── events.jsonl
├── .rewind-tx/                       # present only during an in-flight rewind
│   ├── stage                         # "staged" | "committing"
│   ├── state.json                    # target state snapshot
│   ├── events.jsonl.new              # events slice since parent
│   ├── target.sha / worktree.sha / head_before.sha / run_id / forced / dirty_paths.json / triggered_by
│   └── memory/                       # unpacked memory files staged for copy
└── checkpoints/
    ├── by-hash/<aa>/<sha256-tail>/
    │   ├── manifest.json
    │   ├── state.json
    │   ├── events.slice.jsonl
    │   └── memory.tar.(gz|zst|raw)
    ├── index.json
    ├── tree.json
    └── HEAD
```

The tx dir is **per-run** — this is the critical sprint-mode safety invariant. Two concurrent sprint orchestrators cannot collide because their tx dirs live under separate `<run_id>` subtrees.

## 3. CAS key (CAS-INPUT-v1)

```
sha256(
    canonical_state_json_bytes  || 0x00 ||
    worktree_sha_hex_40         || 0x00 ||
    sorted_events_jsonl_bytes   || 0x00 ||
    memory_tar_bytes
)
```

- `canonical_state_json_bytes` = `json.dumps(state, sort_keys=True, separators=(",", ":"))` UTF-8 bytes.
- `sorted_events_jsonl_bytes` = each event canonicalized (sort_keys, compact), lines lexicographically sorted, `\n`-joined.
- `memory_tar_bytes` = compressed tar (gzip default, zstd if installed, none if configured).

Identical four-tuples produce identical bundle directories — the on-disk write is a no-op when `manifest.json` already exists. Only `index.json`, `tree.json` and `HEAD` are updated to record the new pointer.

## 4. Atomic restore protocol

Five steps. Any failure before step 3 is a no-op for the live pipeline.

| Step | Action | Persists if killed? |
|---|---|---|
| 1 | Pre-flight: resolve id→sha (abort 6 if unknown); check `git status --porcelain` (abort 5 if dirty && !force); check `.rewind-tx/` absent (abort 7 if present). | — |
| 2 | Populate `.rewind-tx/`: target state.json, new events.jsonl.new, memory/ tree, metadata files. Last write: `stage = committing`. | Yes, recovered as roll-forward (see §5). |
| 3 | `os.replace(tx/state.json, run/state.json)`; `os.replace(tx/events.jsonl.new, run/events.jsonl)`; `git -C worktree reset --hard <worktree_sha>`; copy `tx/memory/*` onto live paths. | Yes, partial — repair finishes. |
| 4 | Atomically rewrite `checkpoints/HEAD`; append `RewoundEvent` to `events.jsonl`. | Yes. |
| 5 | `shutil.rmtree(tx)`. | — |

## 5. Crash recovery (`repair_rewind_tx`)

Orchestrator invokes `python3 -m hooks._py.time_travel repair --run-id <id>` at every start. Algorithm:

- If `.rewind-tx/` missing: no-op.
- Else if `.rewind-tx/stage == "committing"`: roll forward (re-run steps 3–5 of `_commit_tx`).
- Else: discard `.rewind-tx/` (no live files were touched yet — steps 1–2 only).

The orchestrator must call repair before any other recovery action so a half-finished prior rewind is brought to a deterministic resting state.

## 6. DAG semantics

`tree.json` is a directed acyclic graph. Each node:

```json
"<sha>": {
  "parents": ["<sha>", ...],
  "children": ["<sha>", ...],
  "created_at": "2026-04-19T10:14:22Z",
  "stage": "IMPLEMENTING",
  "task": "T1",
  "human_id": "IMPLEMENT.T1.004"
}
```

Parents is currently a single-entry list (linear history); the array form is reserved for future merge / fork semantics.

After a rewind, the next checkpoint write creates a new child of the rewind target — producing a branch. Dead branches (leaves with no `complete: true` attached run) are GC candidates after TTL.

## 7. RewoundEvent

Appended to live `events.jsonl` after every successful rewind. Schema defined in `hooks/_py/time_travel/events.py`; canonical form:

```json
{
  "type": "REWOUND",
  "schema_version": 1,
  "timestamp": "2026-04-19T12:00:00Z",
  "run_id": "run-abc123",
  "from_sha": "<64-hex>",
  "to_sha": "<64-hex>",
  "to_human_id": "PLAN.-.003",
  "triggered_by": "user",
  "forced": false,
  "dirty_paths": []
}
```

`triggered_by` is one of `user | recovery | retrospective`. The orchestrator emits a `StateTransitionEvent` pair bracketing the rewind with the pseudo-state `REWINDING` (see `shared/state-transitions.md`); that pseudo-state never persists to `state.story_state`.

## 8. GC policy

Invoked post-SHIP and (optionally) by cron. See `hooks/_py/time_travel/gc.py`.

**Hard protections (never deleted):**
1. `HEAD` of this run.
2. Every checkpoint on the path ROOT..HEAD.
3. Any checkpoint if this run's `state.status ∈ {RUNNING, PAUSED, ESCALATED}` — entire run is skipped.
4. Any checkpoint owned by another active run — enforced by per-run CAS subtree isolation.

**Reclamation criteria:**
- TTL expired (`now - created_at >= retention_days`).
- Over the `max_checkpoints_per_run` cap — oldest non-protected checkpoints reclaimed first.

**Orphan subtrees:** after a rewind, unreferenced children of the rewind target are dead branches. They are reclaimable under TTL. If a run crashes (stale PID, status stuck RUNNING), treat as active for `retention_days`; then reclaim. Manual `/forge-recover reset` clears the run's entire subtree.

**Cross-run safety:** GC reads `.forge/runs/*/state.json` to identify active runs but only ever mutates its own `checkpoints/` subtree. Parallel sprint runs cannot delete each other's checkpoints.

## 9. Configuration

See `shared/state-schema.md §recovery.time_travel (new in 1.9.0)`. Defaults:

```yaml
recovery:
  time_travel:
    enabled: true
    retention_days: 7
    max_checkpoints_per_run: 100
    require_clean_worktree: true
    compression: zstd     # falls back to gzip if zstandard not installed
    preserve_legacy: false
```

Setting `enabled: false` makes the orchestrator skip checkpoint writes entirely; `/forge-recover rewind` then fails with a clear error.

## 10. Failure modes

| Mode | Detection | Response |
|---|---|---|
| Dirty worktree | `git status --porcelain` non-empty | Exit 5, no side effects. `--force` overrides. |
| Unknown checkpoint id | id not in `index.json` and not a valid sha in `by-hash/` | Exit 6. |
| Concurrent rewind tx | `.rewind-tx/` exists | Exit 7. Run `repair` to clear or complete. |
| zstandard not installed | ImportError | Transparent fallback to gzip. INFO logged. |
| Corrupt bundle (hash mismatch) | Manifest hash ≠ recomputed | Exit 1; bundle quarantined under `by-hash/.quarantine/`. |
| Missing `--to` / `--run-id` | Argparse / explicit check | Exit 2 (usage error). |

## 11. Testing

- Unit: `tests/unit/time_travel/` (Python: `test_cas_write_read.py`, `test_cli.py`, `test_gc_policy.py`, `test_rewind_tx_repair.py`, `test_rewound_event.py`).
- Eval: `tests/evals/time-travel/` (bats: round-trip, dedup, dirty-abort, crash-mid-rewind, tree-dag golden, rewind-convergence).
- CI gates per design spec §8: dedup ratio ≥ 1.25× across repeated identical states; ≤ 50 MB storage per run after GC; rewind wall-time < 2 s for 50 checkpoints.
