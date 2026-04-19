# Plan Review — Phase 02: Cross-Platform Python Hook Migration

**Plan:** `/Users/denissajnar/IdeaProjects/forge/docs/superpowers/plans/2026-04-19-02-cross-platform-python-hooks-plan.md`
**Spec:** `/Users/denissajnar/IdeaProjects/forge/docs/superpowers/specs/2026-04-19-02-cross-platform-python-hooks-design.md`
**Prior spec review:** `/Users/denissajnar/IdeaProjects/forge/docs/superpowers/reviews/2026-04-19-02-cross-platform-python-hooks-spec-review.md` (verdict: REVISE)
**Reviewer:** Senior Code Reviewer (forge review agent)
**Date:** 2026-04-19

---

## Verdict

**APPROVE WITH MINOR REVISIONS.** The plan is long (3506 lines, 23 tasks) but the length is earned — every task follows the TDD writing-plans format (Files → failing test → run & fail → implement → pass → commit), uses conventional commits with no AI attribution, and covers every spec mapping. All three blocking issues from the spec review (C1 hook count, C2 bash-ism scope, C3 off-by-two) are explicitly resolved up front with ground-truthed evidence. A few non-blocking gaps remain — fix inline or during execution.

---

## Strengths

1. **Review feedback incorporated as a first-class section.** Lines 13-55 enumerate the three spec-review issues (C1/C2/C3) and show the resolution, including ground-truth from `hooks/hooks.json` that reconciles the "7 hooks" count as 7 *command entries across 6 entry scripts* — consistent with everything downstream (§File Structure, Task 12, Task 21 Step 2).
2. **Hard-break discipline holds.** No dual-path, no `.sh.deprecated` zombies, no deprecation window. Each port task deletes its `.sh` originals in the same commit (`git rm …` appears in Tasks 1, 9, 10, 11, 13, 14, 16, 20; verified in Task 22's structural allowlist test).
3. **TDD ordering is uniform.** Every task opens with a failing `pytest` file, runs it to confirm failure, implements, reruns green, then commits. No task skips the red step.
4. **Each task is independently committable** and uses conventional-commit scopes (`feat(phase02)`, `refactor(phase02)`, `test(phase02)`, `ci(phase02)`, `docs(phase02)`, `chore(phase02)`). Task 23 Step 5 even codifies the `fix-forward` convention rather than `--amend` — consistent with the repo's git rules.
5. **Spec → task coverage matrix.** The self-review at lines 3462-3479 tracks every §3 scope item and every §11 success criterion to a specific task. Only one gap is declared (SC #7 hook latency; called out explicitly as a Phase 02 follow-up).
6. **Type/name consistency across tasks.** `ToolInput` dataclass (Task 2) used identically in Tasks 8 and 10. `atomic_json_update(path, mutate, *, default=None)` signature matches in Tasks 2/4/6. `DispatchResult` (Task 10) has consistent fields across test and impl. `CheckResult` is scoped to the validator module only — no cross-file drift.
7. **hooks.json rewrite is complete and syntactically correct.** Task 12 Step 4 shows the full JSON — 7 command entries (PreToolUse + 3× PostToolUse + Stop + SessionStart), all using `python3 ${CLAUDE_PLUGIN_ROOT}/hooks/<entry>.py`, all with appropriate timeouts (5/10/5/3/3/3), and the companion test (`test_hook_entries.py`) asserts zero `.sh` references.
8. **Windows CI matrix is concrete.** Task 17 shows the full YAML block (fail-fast: false, 3×3 matrix, `actions/setup-python@v6`, `shell: bash` for `tests/run-all.sh`) and Task 18 extends it to `eval.yml`.
9. **Delete-all-.sh is enforced structurally.** Task 22 creates `tests/structural/python-hook-migration.bats` with three assertions: `hooks/` has zero `.sh`, `shared/` top-level matches an explicit allowlist, `hooks.json` contains no `.sh`. This is exactly what the hard-break mandate needs to stay enforced after merge.
10. **Self-review section** (lines 3460-3494) explicitly scans for placeholders, types, and spec coverage before handoff. Acknowledges the one declared ellipsis (Task 13 Step 3) as a mechanical-port size annotation, not an engineering decision — acceptable.

---

## Critical

None. All three prior-review blockers are resolved.

---

## Important

### I1 — `_parse_yaml_subset` in Task 10 is fragile and undertested

Task 10's hand-rolled YAML parser (lines 1667-1717) handles the exact shape used by `forge-config.md`'s `automations:` block, but the implementation has known limitations: the `current_list` state machine (lines 1679, 1694-1700) tracks at most one open list and the comment on line 1714-1716 concedes "our loop doesn't hit that case." Three risks:

- The two unit tests (`test_cli_no_automation_returns_2`, `test_cli_cooldown_suppresses_second_dispatch`) cover only the **happy paths** — they never exercise comments, multi-line values, or sibling lists. A shape drift in any user's `forge-config.md` will silently parse to wrong structure and skip automations rather than failing loudly.
- The spec review's I2 ("`pip install pyyaml` contradicts stdlib-only") was resolved by hand-parsing, but that trade must either be rock-solid or fail-loud. Currently it is neither.
- **Recommendation (fix in execution, not a plan blocker):** add `test_parse_yaml_rejects_unsupported_shape()` that feeds mapping-of-lists and nested-list-of-lists inputs and asserts a clear error rather than silent mis-parse. Alternatively, gate on detection of unsupported constructs and print "parser limitation: upgrade to `pip install pyyaml` or simplify config."

### I2 — `hooks/_py/__init__.py` creation is implicit in Task 2

Task 2 Files block lists `hooks/_py/__init__.py` but Steps 3-5 never show its content (even if empty) nor `chmod`/permissions. `pytest` imports like `from hooks._py import automation_trigger_cli` (Task 10 test line 1557) rely on this package marker existing **before Task 10**. Task 2 is the only earlier task that could create it.

**Recommendation:** Task 2 Step 3 should show the literal `# hooks/_py/__init__.py` (empty file) as part of its implementation chunk, or Task 2 should explicitly say `touch hooks/_py/__init__.py`. Otherwise an executor who batches the tests could find imports working in their local dev (already-existing `_py/` from a prior task) but breaking on fresh clone.

### I3 — Task 19 replacement table lists a lossy mapping for `forge-state-write.sh` and `config-validator.sh`

Task 19's replacement table (lines 3210-3211) gives:

| Old | New |
| `bash shared/forge-state-write.sh` | `python3 -c 'from hooks._py.state_write import …'` (or scripted replacement) |
| `bash shared/config-validator.sh` | `python3 -m hooks._py.config_validator` |

The `python3 -c '…'` suggestion is a lossy shortcut — if a bats test currently invokes `bash shared/forge-state-write.sh some/key some/value`, the one-liner doesn't preserve argv. The `(or scripted replacement)` qualifier punts the decision to the executor, but the plan should name what the actual argv surface is. Tasks 4 and 13 need to document the CLI entry signatures explicitly (e.g., `python3 -m hooks._py.state_write <path> --set <key>=<value>` or whatever is chosen) so Task 19 can do a mechanical substitution.

**Recommendation:** Task 4 and Task 13 should each end with a "CLI signature (for Task 19 substitution)" callout block. Otherwise Task 19's executor invents it, and argv drift across call-sites becomes likely.

### I4 — Task 8 (engine.py dispatch glue) is the heaviest task and has the thinnest visible detail

Task 8 ports ~380 LOC of engine.sh dispatch glue into Python. Based on its section length relative to other tasks (Tasks 1, 2, 4, 10 each run 200+ lines of plan), Task 8 would need similar depth. Confirm by reviewing that Task 8 covers: L1 regex dispatch, L2 linter adapter invocation, L3 AI-driven check gating, `rules-override.json` extension semantics, `learned-rules-override.json` merge, skip-tracking in `.forge/.check-engine-skipped`, the `engine.py` existing-core integration, and the `--hook` invocation contract. Any missed surface here becomes a silent regression in check-engine behavior.

**Recommendation:** Read Task 8 end-to-end once more; if any of the above bullets is not covered by a failing test, add it before execution. This is the one task where TDD completeness determines whether the hard-break lands cleanly.

### I5 — Task 22 allowlist collides with Task 15's in-place bash-3.2 fix

Task 15 fixes `shared/convergence-engine-sim.sh` in place (keeps it as bash, patches the `<<<` here-string). Task 22's structural test (line 3367) lists `shared/convergence-engine-sim.sh` in the allowlist — consistent. But the allowlist also names `shared/forge-linear-sync.sh`, `shared/forge-otel-export.sh`, `shared/run-linter.sh`, `shared/state-integrity.sh` without any prior task auditing whether those files contain the same bash-4 here-string / process-substitution bashisms that motivated Phase 02.

**Recommendation:** Add a sub-step to Task 22 that runs the same bash-ism regex (`<<<`, `< <(`, `declare -A`) against each allowlisted file and asserts zero hits, or explicitly bless them as known-bash-4-dependent developer-only. Otherwise Success Criterion 3 ("Git Bash users can run the full pipeline") remains untested for these paths.

---

## Minor

### M1 — Task 23 Step 2 says "All 24 created `.py` files" but the File Structure lists more

§File Structure lists ~25 new `.py` files (`pyproject.toml` + ~24 `.py`); the PR description template hardcodes "24 created." Fine detail, but reconcile by either making the PR description template more generic ("all created Python files") or auditing to an exact count.

### M2 — `FORGE_PYTHON` retirement in Task 20 assumes safe `:-python3` fallback

Task 20 Step 2 replaces `"${FORGE_PYTHON:-python3}"` with literal `"python3"`. Safe in most cases, but does any evals script expect a different Python (e.g., a pinned venv via `FORGE_PYTHON=/path/to/venv/bin/python`)? The plan doesn't check. Low impact since Phase 02's directive is "rely on CI," but a one-line audit: `grep -rln 'FORGE_PYTHON=' .` before the replacement.

### M3 — Task 21 version bump says `3.1.0` and cites SemVer rationale; spec review M1 argued for `4.0.0`

Plan (Task 21 Step 3) explicitly defends `3.1.0` with a SemVer note: "runtime prerequisite change is a platform-requirements update, not a contract break." This defends the position the spec review called out — good response. If the maintainers disagree, bumping to `4.0.0` is a one-line change; flagging because the argument is judgment-based, not mechanical.

### M4 — Task 12 `chmod +x` includes `hooks/automation_trigger.py` but Task 10 already created and committed it

Task 12 Step 3 `chmod +x` list includes `hooks/automation_trigger.py` (line 2256), but that file is created in Task 10 (earlier commit). The `chmod` is harmless-but-redundant; better to move it into Task 10's implementation, or acknowledge in Task 12 that the bit may already be set.

### M5 — Task 19 sub-step 3 deletes `tests/hooks/session-start-bash-warning.bats` without confirming it exists

Task 19 Step 3 mentions deleting this file as an obsolete bash-warning test. Add a guard: `if [[ -f tests/hooks/session-start-bash-warning.bats ]]; then git rm …; fi` so an executor doesn't fail the task if it was already pruned.

### M6 — pytest discovery scope

`pyproject.toml` (Task 1 line 272) sets `testpaths = ["tests/unit"]`. Task 22 runs `python3 -m pytest tests/unit/ -v` which is consistent. Just confirm no Phase 02 task adds tests outside `tests/unit/` — if one does, the discovery needs a broader path.

---

## Overall

Strong, executable plan. 23 tasks × ~150 LOC each = a week of focused work, but every task is atomic and buildable. The review-feedback-incorporated section at the top of the plan is an exemplary pattern: it quotes each blocker verbatim, shows ground truth, and maps the resolution to specific tasks. Type and name consistency across tasks is maintained (verified `ToolInput`, `atomic_json_update`, `DispatchResult`, `CheckResult`).

The five Important issues are all fix-in-execution-or-tighten-before-merge items, not architectural flaws: (I1) tighten the YAML parser tests, (I2) name `__init__.py` explicitly in Task 2, (I3) nail down CLI signatures in Tasks 4 and 13 so Task 19 is mechanical, (I4) sanity-check Task 8's depth against the 380-LOC dispatch surface, (I5) run bash-ism regex over Task 22's allowlist to make SC #3 enforceable.

**Recommendation:** APPROVE for execution with the expectation that I2, I3, I5 are fixed inline (tiny edits to the plan) before kickoff, and I1/I4 are fixed during their respective task executions.

**Score (informal):** 92/100 — would be 96+ after the five Important revisions.

---

## Top 3 Issues (distilled)

1. **I3 — CLI signature for `state_write` / `config_validator` unspecified.** Task 19's `(or scripted replacement)` qualifier pushes undefined work onto the executor. Tasks 4 and 13 must publish their exact argv surface so Task 19 is mechanical.
2. **I1 — Hand-rolled YAML parser in Task 10 is undertested.** Happy-path tests only; a mis-parse silently skips automations. Add shape-drift negative tests or fail-loud when unsupported constructs are seen.
3. **I5 — Task 22 allowlist untested for bash-4 bash-isms.** Four out of seven allowlisted `shared/*.sh` files were never audited against the `<<<` / `< <(` / `declare -A` regex. Add the audit step to keep Success Criterion 3 honest.
