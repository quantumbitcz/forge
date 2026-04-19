# Review — Phase 14: Time-Travel Checkpoints Implementation Plan

**Plan:** `/Users/denissajnar/IdeaProjects/forge/docs/superpowers/plans/2026-04-19-14-time-travel-checkpoints-plan.md`
**Spec:** `/Users/denissajnar/IdeaProjects/forge/docs/superpowers/specs/2026-04-19-14-time-travel-checkpoints-design.md`
**Spec review:** `/Users/denissajnar/IdeaProjects/forge/docs/superpowers/reviews/2026-04-19-14-time-travel-checkpoints-spec-review.md`
**Reviewer:** Senior Code Reviewer
**Date:** 2026-04-19

---

## Verdict

**APPROVE with IMPORTANT fixes.** 15 tasks, each ending in a concrete commit; TDD loop (write test → run fail → implement → run pass) is uniform; all three spec-review issues are directly resolved (per-run tx dir, GC edge cases, RewoundEvent schema+golden). All 12 spec sections map into tasks per the self-review table. A handful of implementation-level issues need tightening before execution — two would cause tests to fail as written, one would cause CLI collisions.

---

## Criteria Pass/Fail Matrix

| # | Criterion | Status | Evidence |
|---|---|---|---|
| 1 | writing-plans format (checkboxes, TDD, per-task commits) | PASS | Every task ends with `- [ ] **Step N: Commit**` block; tests precede implementation throughout; tasks are independently-shippable. |
| 2 | No placeholders | PASS | Grep clean for TBD/TODO/FIXME/XXX/`<placeholder>`. Golden fixture has `<SHA1>`/`<SHA2>` tokens but they are deliberate substitution markers (Task 12 Step 3 substitutes them). |
| 3 | CAS key formation consistency | PASS | `CAS-INPUT-v1` defined identically in plan §Task 2 docstring, `shared/recovery/time-travel.md` §3 (Task 10), and `manifest.json.cas_input_version`. Byte ordering (state ‖ 0x00 ‖ worktree_sha ‖ 0x00 ‖ sorted_events ‖ 0x00 ‖ memory_tar) is byte-for-byte consistent across all three. |
| 4 | Each task commits | PASS | 15/15 tasks have explicit commit step. Task 15 is the only one with a conditional commit (validation-only). |
| 5 | Spec coverage (CAS, atomic 5-step, DAG, GC, CLI, state-schema) | PASS | CAS → Task 2; atomic 5-step restore → Task 3 (steps map 1:1 to spec §4.3); DAG → Task 2 `_update_tree` + Task 12 golden; GC → Task 4; CLI → Task 5; state-schema → Task 8. |
| 6 | Review feedback addressed | PASS | Issue #1 (RewoundEvent + golden): Task 1 with schema version field. Issue #2 (GC edge cases): Task 4 with 4 unit tests covering HEAD-path protection, TTL orphans, cross-run isolation, cap enforcement. Issue #3 (per-run tx): `_tx_dir` returns `run_dir / ".rewind-tx"`, locked by `test_tx_dir_is_per_run`. |
| 7 | `require_clean_worktree` + `--force` override | PASS | Config key defined in Task 8 Step 3; CLI flag defined in Task 5 `_cmd_rewind`; skill-level flag documented in Task 6 Step 4; test `test_rewind_aborts_on_dirty_worktree` asserts exit 5; `dirty-worktree-abort.bats` asserts zero side effects. |
| 8 | Rewind+rerun eval scenario | PASS (with caveat — see Issue #3) | Task 12 `rewind-convergence.bats` covers "rewind then write identical state converges to same sha" via CAS dedup. This is a sharper deterministic test than the spec's "seeded-LLM convergence" idea — good substitution. |
| 9 | state-schema bump 1.7→1.8 | PASS | Task 8 Step 1 bumps version; Task 8 Step 2 replaces §Checkpoints entirely; refusal behavior at startup documented. |
| 10 | REWINDING state transitions added | PASS | Task 9 adds the pseudo-state, three transition rows (`* → REWINDING`, `REWINDING → <checkpoint.story_state>`, `REWINDING → <prior>`), and a §Rewind transitions section explaining the pseudo-state invariant (`state.story_state` never persists as REWINDING). |

---

## Strengths

- **TDD discipline is uniform.** Every code-bearing task: write failing test → run → confirm fail → implement → run → confirm pass → commit. No shortcuts.
- **Per-task commits are genuinely independent.** Task 1 ships RewoundEvent alone; Task 2 ships CAS write/read; Task 3 layers atomic restore on top. Each commit builds — no broken-intermediate-state commits.
- **Self-review table at the bottom is load-bearing.** The spec-coverage matrix and review-issue-resolution matrix are the kind of audit trail that lets a second reviewer spot-check the plan without re-reading the spec.
- **CAS-INPUT-v1 versioning is explicit.** Naming the hash input format (per spec-review suggestion) with an integer schema version threaded through `manifest.json.cas_input_version` future-proofs the on-disk format for migrations without naming the format "v1" only in comments.
- **`RewoundEvent` carries `schema_version: 1`.** The dataclass pattern + canonical-JSON serializer means golden-file tests won't break on Python dict-order changes across versions.
- **Per-run `.rewind-tx/` is correctly scoped.** `_tx_dir()` returns `run_dir / ".rewind-tx"`, not `.forge/.rewind-tx/`. Sprint-mode safety is real, not just documented.
- **Crash recovery has both branches tested.** `test_repair_rewind_tx_rolls_back_partial` (stage="staged" → discard) and `test_repair_rewind_tx_replays_when_committing` (stage="committing" → roll forward). The state-transition invariant at the rename boundary is the right place to split.

---

## Issues

### CRITICAL (must fix before implementation)

None. No blocking architectural defects.

### IMPORTANT (should fix before merge)

**Issue #1 — Task 3 `rewind`/`_commit_tx`/`repair_rewind_tx` are written as module-level `def`s but prose instructs to "attach them to the class."**
Plan §Task 3 Step 3 ends with: *"Attach the method definitions to the class (move them into `class CheckpointStore:` as methods — in practice, write them directly inside the class body above the final line)."* This is hand-wave — the code block shows `def rewind(self, …):` at module level, not indented under the class. An implementer following literally will produce a broken module (those functions reference `self.ck_dir`, `self._write_head`, etc., all instance attrs). The test `store.rewind(...)` would fail with `AttributeError`.
**Fix:** Either (a) rewrite the code block so methods are indented inside `class CheckpointStore:` verbatim, or (b) write them as module-level functions taking `store: CheckpointStore` explicitly and bind them in the class body with `CheckpointStore.rewind = rewind`. Option (a) is cleaner and matches Task 2's style.

**Issue #2 — Task 5 CLI `op` is a positional arg but `--run-dir`/`--worktree` are declared `required=True` globally — `list-checkpoints` CLI test will work, but the `repair`/`gc` ops have no per-op required-flag validation, and `rewind` validates `--to`/`--run-id` only inside the dispatcher.**
This isn't broken but it scatters contract enforcement. More importantly: `main()` declares `p.add_argument("op", choices=[...])` with `--run-dir` required for ALL ops — that's fine. But `argparse` will exit 2 on missing `--run-dir` before any op-specific validation, which is correct. The real issue is the Task 5 append instruction — "Append to `hooks/_py/checkpoint_cas.py`" — places `main()` at the end of the file but also references `RewindAbort` (defined earlier in Task 3) and `GCPolicy` (defined in Task 4). If Task 3's "attach to class" ambiguity from Issue #1 is resolved incorrectly, `RewindAbort` could end up inside the class and the CLI will `NameError`.
**Fix:** Explicitly place `class RewindAbort(Exception):` and `@dataclass class GCPolicy` at MODULE level in Tasks 3 and 4 (not inside `CheckpointStore`). Add one sentence in each task: "Keep this at module scope, above `class CheckpointStore`."

**Issue #3 — `rewind-convergence.bats` proves dedup but NOT real forward-replay convergence.**
The test writes a checkpoint, rewinds, then writes a *new* checkpoint with an identical state dict via `cas_write "A.-.002b"` — and asserts `sha2b == sha2`. This is a tautology: the CAS hash is deterministic in its inputs, so identical inputs yield identical hashes. The test proves the hash function is deterministic, not that "rewind + forward progress converges." The spec's §8.2 `rewind-convergence.bats` description ("run scripted scenario to IMPLEMENT.T3, rewind to PLAN, re-run implementation with seeded LLM replies, assert final state.json equivalent to non-rewound baseline") is a harder test — this one is easy to green-light without exercising the rewind code path meaningfully.
**Fix:** Restructure the test to (a) perform a real `rewind` CLI call (not just dedup-checking writes), (b) then do a forward write via a scripted "implementer" that reads the current state.json and produces a derived state, (c) compare the HEAD after rewind+forward to a baseline HEAD captured before any rewind. The spec acknowledged this was hardest — the plan as written sidesteps the hard part.

### SUGGESTIONS (nice to have)

- **Task 3 `_commit_tx` does `os.replace(tx/events.jsonl.new, run/events.jsonl)` then `fh.write(ev.to_canonical_json() + "\n")` via `.open("a")`.** If the process dies between the `os.replace` and the append, the live `events.jsonl` will have the slice but no `RewoundEvent` — and `.rewind-tx/` is already gone (no; actually `shutil.rmtree(tx)` is step 5, so tx is still around). Verify that `repair_rewind_tx` can detect "step 4 partial" — currently it only distinguishes "staged" vs "committing", not "post-commit but pre-event-append". Consider a third state `"event_appended"` with the rmtree as the separator.
- **Task 6 skill description exceeds typical Tier-1 description length.** Consider whether the expanded description collides with forge's agent/skill description-tiering rules (CLAUDE.md §Description tiering). A single-line trigger-keyword list inside the description is fine; an essay isn't.
- **Task 8 Step 2 uses `§` as a literal heading character.** Confirm this is the convention in `shared/state-schema.md` — if the existing file uses `##` without `§`, follow the existing pattern instead of introducing new syntax.
- **Task 11 `scenario.bash` `cas_write` helper uses unquoted `$state_json` interpolation into a heredoc** — any apostrophe or special char in the state JSON will break the shell-embedded Python. Today all test fixtures are simple `{"x":N}` so this is safe, but a future scenario with strings will silently misbehave. Consider base64-encoding the JSON into the heredoc.
- **Task 13 Step 2 conditional — "If the script loops over `tests/evals/*/*.bats` already: no change needed."** Verify this condition *before* writing the task. If run-all.sh already auto-discovers, Task 13 should be explicitly marked no-op; if it requires enumeration, the plan shouldn't branch.
- **Task 10 §4 table cell ordering** — the "Persists if killed?" column says step 2 "Yes, recovered as replay." but `repair_rewind_tx` for `stage="staged"` rolls back (i.e. discards), not replays. The table conflicts with the algorithm in §5. Fix: step-2 row should say "Yes, recovered as rollback" or "Yes, staged state recovered and discarded."
- **GC policy and `state.status`** — Task 4 uses `state.get("status") in ("RUNNING", "PAUSED", "ESCALATED")` but the forge state schema uses `state.story_state` (not `state.status`) for pipeline lifecycle. Verify the field name matches `shared/state-schema.md` actuals; if the schema uses `story_state` with values like `IMPLEMENTING`, the GC predicate needs a positive list of active story states rather than checking `status`.

---

## Coverage Analysis

**Spec coverage:** The self-review table (plan §Self-Review Results) cross-checks every spec section to a task. Verified — no spec section is missing a task binding.

**Review-issue resolution:** All three IMPORTANT issues from the spec review are explicitly addressed:
- Issue #1 (RewoundEvent schema) → Task 1 produces both the schema *and* a golden fixture.
- Issue #2 (GC active-run detection, orphans, HEAD-path) → Task 4 has four unit tests one per concern.
- Issue #3 (tx dir collision under sprint mode) → Task 3 per-run tx, `test_tx_dir_is_per_run` locks the invariant.

**Out-of-scope-but-mentioned:** The spec's Risk #2 (MCP state drift post-rewind) is not addressed by the plan — correctly, since it's a known deferred limitation. The spec's suggestion to document "what user action is expected after MCP drift" isn't picked up in the plan; consider adding a line to Task 10's `shared/recovery/time-travel.md` §Failure modes.

---

## Recommendation

Fix Issues #1 and #2 (class-scope ambiguity → ~5-line edits in Tasks 3 and 4). Strongly consider Issue #3 (rewrite `rewind-convergence.bats` to exercise real rewind, not just dedup). Incorporate suggestions as time permits — items #1 (post-commit pre-event-append gap), #4 (quoted JSON in scenario helper), and GC `story_state` vs `status` field name are pre-merge catches that avoid debugging during implementation.

The plan author clearly internalized the spec review and the no-back-compat constraint, sequenced tasks so each ships independently, and has a mature TDD loop. Execution is low-risk once the three IMPORTANT items above are tightened.

---

## Top 3 Issues (short form)

1. **Task 3 method-scope ambiguity.** `rewind`, `_commit_tx`, `repair_rewind_tx` written as module-level `def`s but prose says "attach to class" — implementers will produce broken code referencing `self.` without being methods.
2. **`rewind-convergence.bats` is a CAS-dedup tautology**, not a real forward-replay convergence test. Rewrite to invoke `rewind` CLI and compare a fresh forward-progress HEAD against a baseline.
3. **`RewindAbort`/`GCPolicy` class-level placement unstated.** Tasks 3/4 must explicitly instruct "module-scope, above `class CheckpointStore`" or the CLI in Task 5 will `NameError`.
