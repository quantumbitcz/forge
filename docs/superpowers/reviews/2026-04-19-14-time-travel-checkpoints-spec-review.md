# Review — Phase 14: Time-Travel Checkpoints Design Spec

**Spec:** `/Users/denissajnar/IdeaProjects/forge/docs/superpowers/specs/2026-04-19-14-time-travel-checkpoints-design.md`
**Reviewer:** Senior Code Reviewer
**Date:** 2026-04-19
**Length:** 199 lines (short-end; verified not under-specified)

---

## Verdict

**APPROVE with minor revisions.** The spec is dense, not thin — every section carries substance. 199 lines is short because the author compressed rather than padded. The CAS design is architecturally sound, the 5-step atomic protocol is precise, alternatives are rejected with technical rationale, and the DAG model is explicit with a worked example. A handful of edges need tightening (see Issue #1–#3 below) before implementation.

---

## Criteria Pass/Fail Matrix

| # | Criterion | Status | Evidence |
|---|---|---|---|
| 1 | All 12 sections with substance | PASS | Goal, Motivation, Scope (In/Out), Architecture (§4.1–4.4), Components (7-row table), Data/State/Config, Compatibility, Testing (6 eval scenarios + 3 CI gates), Rollout, Risks (5 items), Success Criteria (6), References (7). No skeletal sections. |
| 2 | No placeholders | PASS | No `TBD`, `TODO`, `FIXME`, `<placeholder>`, `XXX`, or Lorem text. All directory paths, file names, config keys, flag names, exit codes, and schema fields are concrete. |
| 3 | CAS key formation spec | PASS | Line 50: `sha256(state.json-canonical \|\| worktree_sha \|\| sort(events.slice) \|\| memory.tar.zst)`. Four components explicit; canonicalization and sort ordering called out (dedup-critical). |
| 4 | Atomic 5-step protocol | PASS | §4.3 steps 1–5 are numbered and each specifies (a) operations, (b) failure semantics, (c) where data lives mid-step. `.forge/.rewind-tx/` staging with `repair_rewind_tx` crash-recovery subroutine (line 77). |
| 5 | Worktree safety (clean + --force) | PASS | `require_clean_worktree: true` default (line 108). `--force` override documented line 176, flagged destructive. Exit code 5 for dirty-worktree abort (line 91). `dirty-worktree-abort.bats` asserts zero side-effects on abort (line 149). |
| 6 | DAG explicit (not linear) | PASS | §4.2 dedicated subsection; `tree.json` schema with `parents[]`/`children[]`; ASCII worked example (lines 57–65) showing dead branch + post-rewind HEAD; `list-checkpoints` renders DAG. |
| 7 | Retention/GC timing | PASS | `retention_days: 7` default (line 107), `max_checkpoints_per_run: 100` hard cap, GC runs post-SHIP or cron, best-effort (line 178), immutability window during active run (line 25). |
| 8 | Migration/invalidation | PASS | §7 explicit breaking change. Old `checkpoint-{storyId}.json` deleted with WARNING or archived via `preserve_legacy`. `state.json` version bump 1.7.0→1.8.0 with clear error message. |
| 9 | 2 alternatives rejected with rationale | PASS | §4.4 rejects (a) SQLite blob DB — 3 reasons: dedup, disk balloon, fights git's native CAS; (b) event replay — 3 reasons: worktree not in event log, O(run length), non-determinism from LLM calls. Rationale technically accurate. |
| 10 | 199 lines under-specified? | PASS | **Not under-specified.** Density verified: each section earns its space. Spec is terser than predecessors (e.g., Phase 01 eval harness) because the problem is narrower. Missing-but-justifiable: no pseudocode for `checkpoint_cas.py` internals (reasonable — that's impl detail). No ADR-style decision log (matches other Phase specs). |

---

## Strengths

- **CAS key is well-formed.** The four-tuple (state ⋁ worktree-sha ⋁ sorted-events ⋁ memory-tar) correctly captures the full pipeline-visible world. Canonicalization (`state.json-canonical`) and `sort(events.slice)` show the author thought about dedup determinism, not just hashing. Event sort matters because event order within a slice shouldn't change the key if the set is equivalent.
- **Git-native worktree snapshotting is the right call.** Storing a commit SHA rather than a diff or tarball correctly delegates to git's own CAS. The SQLite-blob alternative is rejected for exactly this reason (line 81).
- **Atomic protocol is genuinely atomic.** Staging via `.forge/.rewind-tx/` + `repair_rewind_tx` on restart is the standard crash-safe-rename pattern. `crash-mid-rewind.bats` is the right test to lock the invariant in.
- **DAG semantics are explicit.** `parents[]` as a list (single-element today, multi-element for future merge) is future-proofed without over-engineering. The dead-branch concept (leaves without `complete: true`) is named and handled.
- **Alternatives rejection is substantive.** Both (a) and (b) have 3 concrete technical objections each, not strawmen. Event-replay's LLM-determinism objection is a particularly sharp observation.
- **Breaking change is owned.** §7 doesn't apologize — it names the state-version bump, offers a clear error-to-action recovery (`/forge-recover reset`), and provides an opt-in preservation knob for paranoid users.

---

## Issues

### CRITICAL (must fix before implementation)

None. Spec is implementation-ready.

### IMPORTANT (should fix before merge)

**Issue #1 — `RewoundEvent` schema not specified (line 74).**
Step 4 says "Append a `RewoundEvent` to the *fresh* events.jsonl" but the event shape is undefined. This matters because downstream tools (`/forge-insights`, run-history-db, replay harness) will consume it. Needs at minimum: `{type: "REWOUND", from_sha, to_sha, triggered_by, timestamp, forced: bool}`. Without a schema, the eval harness can't golden-file `tree-dag.bats` output deterministically.
**Fix:** Add a 3-line code block in §4.3 after step 4 showing the event JSON shape.

**Issue #2 — GC interaction with active runs is underspecified.**
Line 25 says "no checkpoint is deleted while its owning run is active" and line 178 says "GC is best-effort (never blocks a run)". These are consistent but don't answer: (a) how does GC identify "active"? (PID file, run-history status, HEAD pointer liveness?) (b) what if user has 3 runs in parallel (sprint mode) and one is crashed — is its checkpoint subtree orphaned forever, or is there a crash-recovery GC pass? (c) does GC respect `HEAD` being inside a to-be-collected subtree?
**Fix:** Add 4-line paragraph in §4.1 or §10 clarifying: GC reads `.forge/runs/*/state.json` for `status: RUNNING|PAUSED`; orphan subtrees (stale PID, no matching run dir, TTL-expired) are reclaimable; GC refuses to delete any checkpoint on the path from ROOT to any active-run HEAD.

**Issue #3 — `rewind-tx/` collision under concurrent rewinds.**
Sprint mode supports multiple parallel orchestrators (per CLAUDE.md "Sprint" section). If two runs both attempt rewind simultaneously, they share `.forge/.rewind-tx/` and will corrupt each other. Lock file (§4.3 step 1) covers *one* live run, but multi-run coordination isn't addressed.
**Fix:** Either (a) scope tx dir per-run: `.forge/runs/<id>/.rewind-tx/`, or (b) document that rewind is mutually exclusive across runs via `.forge/.rewind.lock` (separate from `.forge/.lock`). Option (a) aligns better with the existing `.forge/runs/{id}/` isolation model already documented in CLAUDE.md.

### SUGGESTIONS (nice to have)

- **Line 50 CAS input ordering:** Consider making the hash input ordering canonical via a named spec (e.g., "CAS-INPUT-v1 = sha256(canonical_state_json_bytes + NUL + worktree_sha_hex_40 + NUL + sorted_events_jsonl_bytes + NUL + memory_tar_bytes)"). Naming the format lets future schema migrations version it explicitly.
- **§8 eval harness:** `rewind-convergence.bats` (line 147) is the most valuable test but also the hardest to make deterministic. Consider adding "seeded LLM replies" as a harness fixture spec — list the exact fixture format somewhere, because a flaky convergence test will undermine trust in the whole feature.
- **§10 Risk #2 (MCP state drift):** The `WARNING listing out-of-sync MCP surfaces after every rewind` is good but doesn't say *what* user action is expected. Add one line: "User may need to manually rollback Linear ticket state / regenerate wiki / requery graph. Phase 12+ will automate via MCP-replay hooks."
- **Success criterion 3 (line 186):** "Storage overhead per run ≤ 3x the on-disk size of a single checkpoint bundle" — define "single checkpoint bundle" numerically (ballpark MB) so this is measurable in CI, not just philosophically asserted. Currently `dedup-storage.bats` enforces 1.25x dedup and CI gate enforces ≤ 50 MB total; the 3x success criterion doesn't map cleanly to either.
- **References (§12):** Add forge-internal references: `shared/state-schema.md §Checkpoints` (line 199 cites this), `shared/recovery/recovery-engine.md` — consider also linking `shared/state-transitions.md` and the `REWINDING` pseudo-state addition, since §5 references transitions but §12 doesn't.

---

## Under-Specification Analysis (red-flag check)

The task description flagged 199 lines as potentially short. Verified **not under-specified**:

- Line density: ~1 substantive claim per 2 lines on average; no filler paragraphs.
- All 12 required sections present with concrete content (not section headers alone).
- Testing §8 has 6 distinct bats scenarios + 3 quantified CI gates (dedup ratio, storage ceiling, wall-time).
- Config block (§6) has 5 settings with types, defaults, and semantics.
- Components table (§5) has 7 rows, each specifying Type (new/modify) and what changes.
- Risks (§10) has 5 items, each with mitigation and at least one with `--force` override path.

The only genuine specification gaps are Issues #1–#3 above, and they are gap-at-edges (event schema, GC policy edge cases, concurrent rewind coordination), not gap-at-core. Core architecture (CAS, DAG, atomic protocol) is thorough.

Comparable specs in the same directory for calibration: Phase 01 (eval harness) is ~350 lines but covers a broader surface (fixtures + runners + CI + golden files); Phase 03 (prompt injection hardening) is ~250 lines. Phase 14's narrower surface (one CAS layout + one command + one Python module) justifies its tighter word budget.

---

## Recommendation

Address Issues #1, #2, #3 (each is a 3–5 line addition to existing sections; no architectural rework required). Optionally incorporate suggestions. Then proceed to implementation.

The author clearly understands the problem domain (content addressing, atomic file ops, git internals, DAG vs linear chain semantics, LLM non-determinism). The spec reads like it was written by someone who has shipped a similar feature before. Green-light with the three listed tightenings.
