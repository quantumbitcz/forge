# Phase 04 — Implementer Reflection (CoVe) Spec Review

**Spec:** `/Users/denissajnar/IdeaProjects/forge/docs/superpowers/specs/2026-04-19-04-implementer-reflection-cove-design.md`
**Reviewer role:** Senior Code Reviewer
**Date:** 2026-04-19
**Verdict:** APPROVE WITH MINOR REVISIONS

---

## 1. Criteria coverage matrix

| # | Criterion | Status | Evidence / Notes |
|---|---|---|---|
| 1 | All 12 required sections present | PASS | §1 Goal, §2 Motivation, §3 Scope, §4 Architecture, §5 Components, §6 Data/State/Config, §7 Compatibility, §8 Testing Strategy, §9 Rollout, §10 Risks/Open Questions, §11 Success Criteria, §12 References — all present and non-stub. |
| 2 | No placeholders | PASS | No `TBD`, `TODO`, `FIXME`, `???`, `<PLACEHOLDER>`, or `[pending]` markers anywhere. All tables populated. All numbers concrete (2 cycles, 90s, 600 tokens, 5-15% rate). Example payloads are realistic (`FG-042-3`, `CreateUserUseCase`). |
| 3 | Fresh-context mechanism specified | PASS | §4.2–§4.3 define isolation precisely: Task-tool sub-subagent dispatch, exactly-three-field payload (`task`, `test_code`, `implementation_diff`), explicit NOT-seen list (reasoning, PREEMPT, conventions, prior iterations, scaffolder output, other tasks). §5.1 reinforces in agent system prompt ("You have never seen this codebase"). Risk #3 acknowledges the unverified upstream Task-isolation behavior and provides fallback (`fresh_context: false` → alt-A). Good engineering humility. |
| 4 | Critic inputs/outputs defined exactly | PASS | **Inputs:** §4.2 YAML schema with `task.id`, `task.description`, `task.acceptance_criteria`, `test_code` (verbatim), `implementation_diff` (unified git diff, production-only). **Outputs:** §4.4 strict YAML: `verdict` (PASS\|REVISE), `confidence` (HIGH\|MEDIUM\|LOW), `findings[]` with `category`, `severity`, `file`, `line`, `explanation`, `suggestion`. ≤600 token cap. §5.1 §4 repeats format with ≤30-word caps per field. |
| 5 | Counter wired NOT to feed convergence (explicit) | PASS | §3 Scope: "Does NOT feed into convergence counters, `total_retries`, or `total_iterations`." §5.2 dispatch snippet: "strictly separate from `implementer_fix_cycles` and does NOT feed into `total_retries`, `total_iterations`, `verify_fix_count`, `test_cycles`, or `quality_cycles`." §5.4 schema table repeats. Named all 5 convergence counters from `scoring.md` explicitly. Triply stated. |
| 6 | fg-301 frontmatter sketched | PASS | §5.1 has full frontmatter: `name`, `description`, `model: fast`, `color: lime`, `tools: ['Read']`, `ui: {tasks: false, ask: false, plan_mode: false}` (Tier-4, consistent with reviewer cluster per `agent-registry.md`). Name matches filename convention `fg-301-implementer-critic`. Body sketch includes Identity, Question, Decision rules, Output format, Forbidden sections. |
| 7 | New REFLECT-* scoring categories | PASS | §5.5 adds `REFLECT-DIVERGENCE` (WARNING, -5pts, owner fg-301) and `REFLECT-HARDCODED-RETURN` (INFO, -2pts). Wildcards `REFLECT-OVER-NARROW` and `REFLECT-MISSING-BRANCH` under `REFLECT-*`. Explicitly not SCOUT-class (score-counting). Dedup key uses standard `(component, file, line, category)`. Mentions update to `shared/checks/category-registry.json` — aligns with 87-category registry in `scoring.md`. |
| 8 | Testing uses Phase 01 eval harness (explicit dependency) | PARTIAL | §8.1 references "forge eval harness (if present; otherwise stubbed for Phase-04-dependent CI job)." This is hedged rather than asserting a hard dependency on Phase 01. The spec brief requires explicit dependency. See Issue 1. |
| 9 | 2 alternatives considered | PASS | §4.6 Alt-A (inline self-critique in fg-300) rejected with reasoning (matches existing §5.4 Self-Review; confirmation bias "in the KV cache"). Alt-B (post-task review in Stage-6 quality gate) rejected with reasoning (per-task signal is the lift; fast-tier economics). Both rejections substantive. |
| 10 | Max reflection cap (2) enforced | PASS | §3 "Max 2 reflections per task." §4.5 failure table enforces cycle 2 REVISE → REFLECT-DIVERGENCE WARNING + proceed. §5.2 dispatch flow checks `< implementer.reflection.max_cycles`. §6.1 config `max_cycles: 2` default, range [1,3]. §6.2 PREFLIGHT constraint clamps. Enforced at ≥4 layers. |

**Tally:** 9 PASS, 1 PARTIAL. No FAIL.

---

## 2. Strengths

- **Motivation rooted in a specific existing gap** (§5.4 Self-Review), not a generic "more review is better" pitch. The observation that self-review "by the same context that wrote the code" shares a KV cache with the implementation's reasoning is sharp and correct.
- **Counter isolation is over-specified in a good way.** Naming all 5 convergence counters by hand prevents future drift if `scoring.md` adds a 6th — reviewer reading this spec will know the intent, not just the current list.
- **Skip conditions are load-bearing and called out.** §5.7 exemptions + targeted-re-implementation skip + `enabled: false` config gate + timeout → skip. Reflection degrades gracefully at every failure mode.
- **§5.1 agent body is already implementation-ready.** Not a sketch — the Decision rules section is a usable prompt. Rule 5 ("When uncertain → REVISE with LOW confidence; false PASS is worse than false REVISE") is the right asymmetry for an adversarial critic and matches Principle 4 in `agent-philosophy.md`.
- **Alt-B rejection reasoning is technically correct.** Quality gate at Stage 6 sees the stacked diff from all tasks; per-task test-intent signal is lost once tasks layer. This isn't a "we chose A over B for taste" rejection — it's an information-theoretic point about when the signal exists.
- **Ties into existing forge contracts.** Uses existing sub-subagent Task dispatch, fast-tier model routing, `shared/checks/category-registry.json`, standard dedup key, Tier-4 UI frontmatter — zero new infrastructure invented.
- **Success criteria are measurable** (§11): +3 absolute eval score, ≥70% planted-defect accuracy, ≤10% false-positive, ≤15% duration increase. Each falsifiable in CI.

---

## 3. Issues

### CRITICAL
None.

### IMPORTANT

**Issue 1 — Phase 01 eval harness dependency is hedged, not asserted.**
§8.1 opens with "Add to the forge eval harness (if present; otherwise stubbed…)". The task brief requires Phase 01's eval harness as an **explicit dependency**. The hedge leaves Phase 04 technically mergeable before Phase 01 lands, which defeats the point of the CI-only gating strategy — there would be no eval harness to measure the +3-point lift against, and success criterion #1 (§11) becomes unfalsifiable.

*Recommendation:* Replace the hedge with a hard dependency declaration. Add a §3 bullet:

> **Dependency:** Phase 01 (eval harness) MUST be merged before this phase. Phase-04 PR cannot be merged until `tests/eval/` infrastructure is in place and `.forge/eval-metrics.json` schema is committed.

And change §8.1 opening to "Add to the Phase-01 eval harness at `tests/eval/scenarios/reflection/` (see Phase 01 spec § [ref])." This makes the dependency checkable by a reviewer and by CI.

**Issue 2 — §4.5 failure-handling table has a first-cycle PASS/REVISE row but skips cycle 0 (initial dispatch).**
Reading §4.5 literally, "Cycle 1 PASS" could be interpreted as "after one re-implementation" rather than "on initial dispatch." The state-schema in §5.4 defaults `implementer_reflection_cycles: 0`, so the very first critic dispatch happens at cycle count **0**, not 1. The table should either start at "Initial dispatch" (counter == 0) or be reworded to "1st reflection" / "2nd reflection" to avoid off-by-one ambiguity downstream (e.g., in retrospective aggregation).

*Recommendation:* Reword §4.5 first column as:

| Reflection # | Verdict | Action |
|---|---|---|
| 1st (counter 0→0 on PASS, 0→1 on REVISE) | PASS | Proceed to §5.4 REFACTOR. |
| 1st | REVISE | Increment counter to 1. Re-enter GREEN. Re-dispatch. |
| 2nd (counter 1→1 on PASS, 1→2 on REVISE) | PASS | Proceed to REFACTOR. |
| 2nd | REVISE | Emit REFLECT-DIVERGENCE. Counter at max. Proceed. |

This also eliminates the §5.2 ambiguity of whether `< max_cycles` is evaluated before or after increment.

### SUGGESTIONS

**Suggestion 1 — §5.1 agent body should reference `shared/agent-defaults.md` to shave tokens.**
Per `CLAUDE.md` "Token management" guidance, new agents should compress constraints via reference. The §5.1 body has ~250 lines of inline prompt; sections like "Forbidden" and "Output format" overlap with patterns already canonicalized in `shared/agent-defaults.md` and `shared/checks/output-format.md`. Replacing ~40 lines with 2-line references would reduce the per-dispatch token cost. This is the agent that runs per-task × 2 max — token budget multiplies fast.

**Suggestion 2 — §5.5 scoring table omits score-impact stage for REFLECT-HARDCODED-RETURN.**
The category description says findings "surface to Stage 6 if the finding persists after REFACTOR" but the scoring contract needs explicit wording: does Stage 6 re-evaluate the REFACTOR'd code for the same finding? The mechanism for persistence-check is not specified. Either (a) Stage-6 reviewers independently rediscover it, (b) fg-301 re-runs post-REFACTOR, or (c) findings are stored on the task and bubble up at Stage 6. Pick one.

**Suggestion 3 — §10 Risk 3 (fresh-context unverified) deserves an explicit pre-merge check.**
The risk acknowledges that fg-300 has not previously dispatched sub-subagents and Task isolation is unverified. This is a **blocker** for the "fresh context" claim in criterion 3 if the assumption is wrong. Add a pre-merge verification step to §9 Rollout:

> Before merging: run a smoke test that logs the critic's observable system-prompt prefix and tool-call history, verifying neither contains fg-300 artifacts. If system-prompt bleed is observed, delay merge — do not ship with `fresh_context: false` as the default fallback; the whole value prop is fresh context.

**Suggestion 4 — §11 Success criteria #5 (zero CRITICAL from reflection) is already guaranteed by design.**
The scoring table (§5.5) defines REFLECT-* categories at WARNING/INFO only. There's no code path to CRITICAL, so the success criterion is vacuous. Replace with something testable, e.g., "Zero reflection-triggered pipeline aborts in the first 5 runs."

**Suggestion 5 — §6.5 token budget estimate (~32k/run) is optimistic.**
Assumes 4 tasks/feature and avg cycle 1.5 (midpoint of 0-2). Real pipelines average 6-12 tasks. At 8 tasks × 2 cycles × (4k in + 600 out) = ~73k tokens/run, not 32k. Still under budget at fast-tier pricing, but the stated figure will be questioned when it lands in a retrospective. Use a realistic 8-task assumption and show the math.

---

## 4. Final verdict

**APPROVE WITH MINOR REVISIONS.**

Design is sound, architecturally well-placed, and respects existing forge contracts. The two IMPORTANT issues (Phase 01 dependency hedge, cycle-counting off-by-one) are wording fixes rather than design flaws. All 10 criteria substantively met. Once Issue 1 is tightened to a hard dependency and Issue 2's off-by-one ambiguity is resolved, this is ready for implementation.

**Recommended next steps before implementation PR:**
1. Edit §3 and §8.1 to hard-assert Phase 01 eval harness as a blocking dependency.
2. Rewrite §4.5 failure table with unambiguous counter semantics.
3. (Optional) Apply Suggestions 1, 3, 4 for higher quality.
