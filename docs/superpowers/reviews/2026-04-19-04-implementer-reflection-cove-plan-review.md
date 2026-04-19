# Phase 04 — Implementer Reflection (CoVe) Plan Review

**Plan:** `/Users/denissajnar/IdeaProjects/forge/docs/superpowers/plans/2026-04-19-04-implementer-reflection-cove-plan.md`
**Spec:** `/Users/denissajnar/IdeaProjects/forge/docs/superpowers/specs/2026-04-19-04-implementer-reflection-cove-design.md`
**Prior review:** `/Users/denissajnar/IdeaProjects/forge/docs/superpowers/reviews/2026-04-19-04-implementer-reflection-cove-spec-review.md`
**Reviewer role:** Senior Code Reviewer
**Date:** 2026-04-19
**Verdict:** APPROVE

---

## 1. Criteria coverage matrix

| # | Criterion | Status | Evidence |
|---|---|---|---|
| 1 | writing-plans format (goal, arch, tech stack, file structure, task sequence, self-review) | PASS | Header has Goal / Architecture / Tech Stack. "File Structure" section lists all touched files with create/modify labels. "Task Sequence" with 17 numbered tasks. "Self-Review" section at end. Checkbox (`- [ ]`) tracking syntax throughout. Sub-skill pointer at top (subagent-driven-development / executing-plans). |
| 2 | No placeholders | PASS | No `TBD`, `TODO`, `FIXME`, `<PLACEHOLDER>`, `???`. All commands, paths, and values concrete. Self-Review section explicitly asserts placeholder scan. |
| 3 | Type consistency for `implementer_reflection_cycles` | PASS | Name used identically in Tasks 5 (registry), 6 (schema tests), 7 (schema), 9 (preflight), 10 (fg-300 dispatch), 13 (config templates), 14 (CLAUDE.md). Run-level sibling `implementer_reflection_cycles_total` and task-level `reflection_verdicts` also consistent. Self-Review §Type consistency explicitly enumerates. |
| 4 | TDD ordering | PASS | Task 2 (RED frontmatter test) → Task 3 (GREEN agent file). Task 4 (RED category test) → Task 5 (GREEN registry). Task 6 (RED schema test) → Task 7 (GREEN schema). Commit messages encode `(RED)` / `(GREEN)` phase tags. Task 12 fresh-context test asserts pre-merge invariant AFTER Tasks 3/10 land — acceptable because it is a static contract check, not a TDD pair. |
| 5 | Each task commits | PASS | 15 of 17 tasks end with `git commit -m`. Tasks 1 and 17 are explicitly verification-only (Phase 01 gate and final structural check + PR open), which is correct — no artifact produced. Self-Review predicts "15 commits". Commit style: conventional commits, no Co-Authored-By, no AI attribution — matches `shared/git-conventions.md`. |
| 6 | Spec coverage | PASS | **fg-301 creation:** Tasks 2+3 (frontmatter test + agent body). **fg-300 modification:** Task 10 inserts §5.3a, updates §7 inner-loop table, §15 output format. **State field:** Tasks 6+7 add task-level `implementer_reflection_cycles` + `reflection_verdicts` + run-level aggregates + changelog v1.8.0. **Scoring categories:** Tasks 4+5 register `REFLECT-*` wildcard + 4 discretes + scoring.md subsection. **Dispatch mechanics:** Task 10 specifies Task-tool sub-subagent, 3-field payload, verdict handling, budget semantics table. All 12 spec sections map to tasks (Self-Review §1). |
| 7 | Review feedback addressed | PASS | Explicit "Review feedback resolutions" section cross-references spec review. **Issue 1 (Phase 01 dep):** Task 1 is a hard gate with STOP conditions on missing harness or schema test. **Issue 2 (off-by-one):** Task 7 rewrites table with "1st dispatch / 2nd dispatch" wording and `count < max_cycles` BEFORE increment. Task 10 §5.3a repeats the budget-check-before-increment semantics with a table. **Suggestion 3 (fresh-context smoke):** Task 12 creates `fg-301-fresh-context.bats` — 8 assertions on dispatch contract + critic body. Suggestions 1/2/4/5 noted as non-blocking. |
| 8 | Phase 01 dependency gate explicit | PASS | Task 1 Step 1 `test -d tests/evals && test -f README.md && test -f framework.bash && ls tests/evals/agents/` — any failure outputs `PHASE_01_MISSING` and plan STOPs. Step 2 asserts eval metrics schema contract test exists. Step 3 records Phase 01 baseline SHA for PR description. Gate runs before any other task. |
| 9 | Contract test for fresh-context isolation | PASS | Task 12 creates `tests/contract/fg-301-fresh-context.bats` with 8 assertions: (1) fg-300 dispatches via Task tool, (2) payload has exactly 3 top-level fields via awk block extraction, (3) fg-300 explicitly forbids PREEMPT/conventions/scaffolder/prior-reasoning, (4) fg-301 identity asserts fresh reviewer, (5) fg-301 forbidden list blocks repo exploration, (6) fg-301 tools contain ONLY `Read` (negative checks: no Edit/Write/Bash/Grep/Glob/Task/WebFetch), (7) fg-301 forbids "ask for more", (8) prior reflection iterations excluded. Static check — acceptable since bats cannot launch real sub-subagents. |
| 10 | Max-2 cap enforced at multiple layers | PASS | Layer 1 — config schema (Task 13 `max_cycles: 2` default). Layer 2 — PREFLIGHT constraint (Task 9 clamps to [1,3] with default 2). Layer 3 — state schema (Task 7 documents `count < max_cycles` budget check before increment). Layer 4 — fg-300 dispatch logic (Task 10 §5.3a 4-row semantics table). Layer 5 — scoring.md (Task 5 REFLECT-DIVERGENCE -5 only on exhaustion). 5 enforcement layers. |

**Tally:** 10 PASS, 0 PARTIAL, 0 FAIL.

---

## 2. Strengths

- **Review feedback traceability is first-class.** Dedicated section at top maps spec-review Issues/Suggestions to specific tasks. Reviewer can check resolution without cross-referencing.
- **Task 1 is a real gate, not ceremony.** Shell command `test -d && test -f && ls && echo PHASE_01_READY || echo PHASE_01_MISSING` gives a binary go/no-go signal. STOP instructions are unambiguous. This is how dependency gates should look.
- **Off-by-one fix is over-specified in a useful way.** Task 7 and Task 10 both carry a 4-row transition table with identical counter semantics (before/after columns). Redundancy here is the right call — future readers of either fg-300 or state-schema see the same contract.
- **Task 12 fresh-context test covers both sides of the contract.** fg-300 side: exactly 3 payload fields + explicit NOT-sent list. fg-301 side: Read-only tools, fresh-reviewer identity, forbidden repo exploration. The awk extraction for payload fields is a clever static approximation of runtime isolation.
- **Tool isolation enforced negatively.** Task 2 frontmatter test asserts `Read` present AND `Edit/Write/Bash` absent. Task 12 extends to `Grep/Glob/Task/WebFetch`. Prevents future drift where someone adds a tool "because it's useful."
- **Commit atomicity is disciplined.** Each task produces one commit touching only the files that task declared. No cross-task file bleed. Easy to revert individual tasks.
- **Self-Review section re-verifies all 10 review criteria.** Not just a re-statement — each criterion cites the task(s) that cover it.

---

## 3. Issues

### CRITICAL
None.

### IMPORTANT
None.

### SUGGESTIONS

**Suggestion 1 — Task 14 wildcard count math may be wrong.**
Task 14 Step 3 says "27 wildcard prefixes + 60 discrete" → "28 wildcard prefixes + 64 discrete". CLAUDE.md current text is "27 wildcard prefixes + 60 discrete" (see `CLAUDE.md` §Scoring). Adding `REFLECT-*` makes 28 wildcards. Adding 4 discretes (`REFLECT-DIVERGENCE`, `REFLECT-HARDCODED-RETURN`, `REFLECT-OVER-NARROW`, `REFLECT-MISSING-BRANCH`) makes 64 discretes — but note that in Task 5, `REFLECT-OVER-NARROW` and `REFLECT-MISSING-BRANCH` are both listed as *discrete* entries (they each get a registry object), so 4 is correct. Verify at implementation time that the registry doesn't already count SCOUT sub-categories differently. Low risk, easy to correct if off by 1-2.

**Suggestion 2 — Task 13 framework template fan-out could be batched with a script.**
The plan asks the implementer to Edit every `modules/frameworks/*/forge-config-template.md` that contains an `implementer:` block. With 21 frameworks, that's potentially 21 manual edits if most have the block. A one-off sed/awk script inserted into the commit (plus manual verification) would be faster and less error-prone, but this is a style preference — the current approach is safe and matches the plan's "no script magic" preference elsewhere.

**Suggestion 3 — Task 12 assertion 2 regex may over-match.**
The awk block in Task 12 extracts top-level keys from the first `^```yaml$` fenced block in fg-300.md. Task 10 places the dispatch payload inside §5.3a, but the fg-300.md body already contains other YAML blocks (e.g., output format examples, configuration examples). The test relies on the first yaml block containing `task:`, `test_code:`, `implementation_diff:`, but if another yaml block lands above §5.3a after a future refactor, the test silently validates the wrong block. Consider anchoring by a preceding marker line (e.g., `## 5.3a` header or a comment). Not blocking — implementers should notice if the first yaml block is wrong.

**Suggestion 4 — Task 17 PR body template omits Suggestions 1/2/4/5 status.**
The plan says suggestions 1/2/4/5 from the spec review are "noted inline in the relevant tasks but not blocking." The PR body template lists success criteria but does not include a checklist entry for these suggestions. Reviewers reading the PR won't know which suggestions were intentionally deferred vs accidentally dropped. One line in PR body: "Spec-review suggestions 1/2/4/5 deferred per plan header; not blocking." Low priority cosmetic fix.

**Suggestion 5 — Task 10 Step 1 `grep ... | head -40` may miss §7 / §15 if fg-300 is long.**
The pre-edit recon grep limits to 40 header lines. fg-300 is a large agent file with many headers. If §7 or §15 falls past the 40th header match, the implementer's recorded line numbers would be wrong. Low risk — the implementer uses Read anyway to confirm. Consider removing `| head -40` or bumping to 100.

---

## 4. Top 3 Issues

(per requested summary)

1. **Task 14 wildcard/discrete count math is a potential off-by-one** — verify against current `CLAUDE.md` and `category-registry.json` at implementation time; easy to correct.
2. **Task 12 awk block anchors on first yaml fence** — could match wrong block if fg-300.md grows; anchor by §5.3a header for safety.
3. **Task 17 PR body omits suggestion-deferral note** — add a one-liner explaining Suggestions 1/2/4/5 are intentionally deferred.

All three are SUGGESTIONS, not blockers.

---

## 5. Final verdict

**APPROVE.**

Plan is tight, reviewable, and execution-ready. All 10 review criteria substantively met. TDD ordering is clean, Phase 01 gate is a real STOP condition, off-by-one fix is over-specified correctly, max-2 cap is enforced at 5 independent layers, and the fresh-context smoke test covers both sides of the isolation contract. Zero CRITICAL or IMPORTANT issues. 5 SUGGESTIONS are polish, not blockers.

The plan is ready to hand off to `superpowers:subagent-driven-development` or `superpowers:executing-plans` for implementation, conditional on the Task 1 gate passing (Phase 01 eval harness merged).

**Recommended next steps:**
1. Proceed to implementation once Phase 01 has landed.
2. (Optional) Apply Suggestions 1–5 during implementation for higher polish.
3. After implementation, run the fresh-context smoke test first as a quick sanity check before full CI.
