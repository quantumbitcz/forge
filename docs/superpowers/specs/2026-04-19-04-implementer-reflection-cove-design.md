# Phase 04 — Implementer Reflection (Chain-of-Verification) Design

**Status:** Draft
**Priority:** P0 (A+ roadmap, Phase 04)
**Owner:** forge plugin
**Date:** 2026-04-19

## 1. Goal

Insert a fresh-context critic (`fg-301-implementer-critic`) between the GREEN and REFACTOR phases of `fg-300-implementer`'s TDD loop so that diffs which merely pass tests — but fail to satisfy test intent — are caught per-task, before the reviewer panel runs downstream.

## 2. Motivation

**Audit W4** identified that fg-300 today can make a failing test pass with a subtly wrong implementation (hardcoded return value matching the assertion, over-narrow conditional, swallowed branch) and the Stage-6 reviewer panel is too far downstream to catch this per-task — by the time CRITICAL findings surface, the implementer has moved on and the worktree contains several layered tasks. Chain-of-Verification (CoVe) — a standalone adversarial critic with clean context — has been reported to lift coding-benchmark scores from 80%→91% when inserted into agentic TDD loops.

Forge already has fg-300 Self-Review (§5.4 Self-Review Checkpoint) and an inner loop for lint+test (§5.4.1) — but both run **inside the same agent instance** that just wrote the code. Self-review by the author of a diff is a weak signal; a fresh critic is not.

**References:**
- ReAct vs Plan-and-Execute: https://dev.to/jamesli/react-vs-plan-and-execute-a-practical-comparison-of-llm-agent-patterns-4gh9
- Superpowers 2-stage review pattern: https://blog.fsck.com/2025/10/09/superpowers/
- TDD with AI agents: https://qaskills.sh/blog/tdd-ai-agents-best-practices
- Audit W4 (internal A+ roadmap audit)

## 3. Scope

### In scope

- New subagent: `agents/fg-301-implementer-critic.md` (Tier-4 UI, fast tier, clean-slate dispatch).
- Integration point: fg-300's TDD loop, **between GREEN (§5.3) and REFACTOR (§5.4)**.
- Fresh-context dispatch: the critic receives **only** (task description from plan, test code, implementation diff). It does NOT see the implementer's reasoning, prior iterations, PREEMPT items, conventions stack, or scaffolder output.
- Per-task counter: `implementer_reflection_cycles` in `state.json`, parallel to `implementer_fix_cycles`. Does NOT feed into convergence counters, `total_retries`, or `total_iterations`.
- Max 2 reflections per task. After 2 REVISE verdicts, escalate to a `REFLECT-DIVERGENCE` finding (WARNING) and continue to REFACTOR so the reviewer panel and quality gate get a chance.
- New scoring categories: `REFLECT-DIVERGENCE`, `REFLECT-HARDCODED-RETURN`.
- Model routing: critic uses `fast` tier.
- Config gates: `implementer.reflection.enabled`, `implementer.reflection.max_cycles`, `implementer.reflection.fresh_context`.

### Out of scope

- Replacing or modifying the Stage-6 reviewer panel (`fg-400-quality-gate` and its 8 reviewers).
- Replacing fg-300's existing Self-Review Checkpoint (§5.4) or inner-loop lint/test validation (§5.4.1). Both remain; reflection is a third, orthogonal gate.
- Cross-task reflection (critic only sees one task's diff at a time).
- Reflection during targeted re-implementation (fix loops from VERIFY/REVIEW) — rationale in §10.
- Backcompat paths for projects with pre-existing `state.json` files (per task brief: no backcompat).

## 4. Architecture

### 4.1 Where CoVe fires

The reflection step is inserted **inside fg-300's per-task TDD cycle**, not at stage boundaries. Each task goes through:

```
§5.2 RED (write failing test)
  ↓
§5.3 GREEN (implement to pass test)
  ↓
§5.3a REFLECT  ← NEW, dispatched as sub-subagent
  ↓   verdict == PASS       → §5.4 REFACTOR
  ↓   verdict == REVISE && cycles < max → re-implement (GREEN again), then REFLECT again
  ↓   verdict == REVISE && cycles >= max → emit REFLECT-DIVERGENCE (WARNING), continue to §5.4
§5.4 REFACTOR
  ↓
§5.4.1 Inner-loop lint + affected tests
```

Reflection runs **after GREEN is verified green** (test passes via `commands.test_single`) and **before REFACTOR**. It never fires if:
- `§5.7` exemptions apply (domain models, migrations, mappers, configs — no test was written, nothing to reflect on).
- `implementer.reflection.enabled` is `false`.
- The current task is a **targeted re-implementation** from a VERIFY or REVIEW fix loop (see §3 Out of scope).

### 4.2 What the critic sees

Dispatched as a **sub-subagent** (`Task` tool invocation from within fg-300), which gives the critic a clean Claude context window — no inherited system prompt carryover from fg-300, no prior tool calls visible. The critic's input payload is exactly three items, packed as a single structured message:

```yaml
task:
  id: "FG-042-3"
  description: "Implement CreateUserUseCase.execute() — validate email, persist user, return UserId. AC: duplicate email → DuplicateEmailError."
  acceptance_criteria:
    - "Given a unique email, when execute is called, then a User is persisted and UserId returned."
    - "Given a duplicate email, when execute is called, then DuplicateEmailError is raised."

test_code: |
  // Full contents of the test file written in RED phase.
  // Verbatim — no summarization.

implementation_diff: |
  // Unified diff (git diff HEAD) restricted to files in this task.
  // Includes production code only — test file excluded from diff since shown above.
```

### 4.3 What the critic does NOT see

- fg-300's prior reasoning, scratch notes, tool-call history, or Self-Review output.
- PREEMPT checklist items.
- The conventions stack, pattern files, or context7 docs.
- Scaffolder output for unrelated files.
- Prior reflection iterations of this task (each reflection is independent — critic cannot anchor on its own previous verdict).
- Other tasks from the plan (one-task-at-a-time isolation).

This isolation is the core design value: a reviewer who has read the implementer's justification is biased toward agreeing with it. A fresh critic reads only the contract (task + test) and the artifact (diff) and answers one question: **does the diff plausibly satisfy the test's intent, or does it satisfy the test's letter only?**

### 4.4 Critic output

Strictly structured, ≤600 tokens:

```yaml
verdict: PASS | REVISE
confidence: HIGH | MEDIUM | LOW
findings:   # Empty when verdict == PASS
  - category: REFLECT-HARDCODED-RETURN | REFLECT-DIVERGENCE | REFLECT-OVER-NARROW | REFLECT-MISSING-BRANCH
    severity: WARNING | INFO
    file: "src/domain/CreateUserUseCase.kt"
    line: 42
    explanation: "Returns UserId(1) unconditionally — test asserts `userId != null` but does not pin the value; the implementation hardcodes the happy-path result without persisting or generating an ID."
    suggestion: "Generate a new UserId from the repository and persist before returning."
```

`REFLECT-*` findings are stored on the **task-level** state entry, not surfaced as Stage-6 findings directly. They become first-class scoring inputs only if `cycles >= max_cycles` (see §4.5).

### 4.5 Failure handling

| Cycle | Verdict | Action |
|---|---|---|
| 1 | PASS | Proceed to §5.4 REFACTOR. |
| 1 | REVISE | fg-300 re-enters GREEN with the critic's findings appended to its context. `implementer_reflection_cycles++`. Re-run test. Dispatch critic again (fresh context, new sub-subagent). |
| 2 | PASS | Proceed to REFACTOR. |
| 2 | REVISE | Emit `REFLECT-DIVERGENCE` finding (WARNING, -5pts at Stage 6). Proceed to REFACTOR so reviewer panel has a chance. Log task-level stage note: `REFLECT_EXHAUSTED: {task_id} — critic rejected 2 consecutive implementations.` |

Critic dispatch timeout: 90s. Timeout → log INFO in stage notes, skip reflection for this task, continue to REFACTOR. Never block the pipeline on a critic failure.

### 4.6 Alternatives considered

**Alt-A: Inline self-critique within fg-300** (no sub-subagent — fg-300 adds a "pretend you're a critic" prompt step to its own context after GREEN).

Rejected. This is exactly what §5.4 Self-Review Checkpoint already does, and the W4 audit found it too weak. The same context window that wrote the code cannot convincingly critique it — confirmation bias is in the KV cache. Sub-subagent dispatch is the cheapest path to a truly fresh context.

**Alt-B: Post-task review in the existing quality gate** (route REFLECT-* checks through `fg-410-code-reviewer` or add a dedicated reflection reviewer at Stage 6).

Rejected. Stage 6 runs once per the whole IMPLEMENT stage output, not per task. By then, multiple tasks have stacked diffs and the critic cannot cheaply isolate which test a given line was written against. The W4 finding specifically calls out **per-task** catch rate as the key lift — batching loses the signal. Additionally, Stage-6 reviewers use `standard` or `premium` model tier (they run rarely); per-task reflection is viable only because it uses `fast` tier, which Stage-6 reviewers cannot cost-effectively adopt without diluting their other responsibilities.

## 5. Components

### 5.1 NEW: `agents/fg-301-implementer-critic.md`

Full frontmatter and body sketch:

```markdown
---
name: fg-301-implementer-critic
description: Fresh-context critic that verifies an implementation diff satisfies the intent (not just the letter) of a test.
model: fast
color: lime
tools: ['Read']
ui:
  tasks: false
  ask: false
  plan_mode: false
---

# Implementer Critic (fg-301)

Adversarial per-task reviewer. Dispatched from fg-300 between GREEN and REFACTOR.
See `shared/agent-philosophy.md` — Principle 4 (disconfirming evidence) applies maximally here.

## 1. Identity

You are a fresh reviewer. You have never seen this codebase before this message.
You receive exactly three inputs:
1. `task` — description + acceptance criteria
2. `test_code` — the test written in RED phase
3. `implementation_diff` — the code written in GREEN phase

You do NOT receive: the implementer's reasoning, prior iterations, conventions,
PREEMPT items, or other tasks. This is by design. Do not ask for more context —
if you cannot decide from the three inputs, return `verdict: REVISE, confidence: LOW`.

## 2. Question

Does the diff plausibly satisfy the **intent** of the test, or does it satisfy only the **letter**?

Intent satisfaction examples:
- Test asserts `userId != null` → implementation generates/persists a real ID (PASS).
- Test asserts `userId != null` → implementation `return UserId(1)` (REVISE: REFLECT-HARDCODED-RETURN).
- Test asserts `result == "ok"` with single input → implementation `return "ok"` (REVISE: REFLECT-HARDCODED-RETURN).
- Test covers only happy path → implementation covers only happy path (PASS — the test defines the contract).
- Test has one duplicate-email assertion → implementation checks email but silently swallows other validation (REVISE: REFLECT-MISSING-BRANCH — AC mentions "validate email" beyond duplicate check).

## 3. Decision rules

1. If the diff is a literal constant matching the test's one assertion, and the task description implies real computation → REVISE (REFLECT-HARDCODED-RETURN).
2. If the diff's control flow handles fewer branches than the AC describes → REVISE (REFLECT-MISSING-BRANCH).
3. If the diff narrows the input domain more than the AC allows → REVISE (REFLECT-OVER-NARROW).
4. If the diff passes the test and reasonably matches the AC → PASS.
5. When uncertain → REVISE with `confidence: LOW`. The implementer will re-check; false PASS is worse than false REVISE.

## 4. Output format

Return ONLY this YAML. No preamble, no markdown fences.

    verdict: PASS | REVISE
    confidence: HIGH | MEDIUM | LOW
    findings:
      - category: REFLECT-HARDCODED-RETURN | REFLECT-MISSING-BRANCH | REFLECT-OVER-NARROW | REFLECT-DIVERGENCE
        severity: WARNING | INFO
        file: <path>
        line: <int>
        explanation: <one sentence, ≤30 words>
        suggestion: <one sentence, ≤30 words>

Max total output: 600 tokens. Prefer fewer, higher-quality findings.

## 5. Forbidden

- Do NOT read files beyond those in the diff (the `Read` tool is present only for cross-file context inside the diff scope — do not use it to explore the repo).
- Do NOT suggest refactors or style fixes. Intent satisfaction only.
- Do NOT ask for more information. Decide with what you have.
- Do NOT assume the test is wrong — the test is the contract.
```

### 5.2 MODIFY: `agents/fg-300-implementer.md`

Add §5.3a between §5.3 (GREEN) and §5.4 (REFACTOR). Snippet to insert:

```markdown
### 5.3a Reflect (Chain-of-Verification)

After GREEN verifies the test passes, dispatch `fg-301-implementer-critic` as a
sub-subagent via Task tool. The critic runs in a fresh Claude context (no
inherited reasoning).

Skip this step when:
- `implementer.reflection.enabled` is `false`
- Task falls under §5.7 exemptions (domain models, migrations, mappers, configs)
- Current invocation is a targeted re-implementation from VERIFY/REVIEW fix loop

**Dispatch payload (exactly three fields):**
```yaml
task:
  id: {task.id}
  description: {task.description}
  acceptance_criteria: {task.acceptance_criteria}
test_code: {verbatim contents of test file written in RED}
implementation_diff: {git diff of production files modified in GREEN}
```

**Handle verdict:**
- `PASS` → proceed to §5.4 REFACTOR.
- `REVISE` and `implementer_reflection_cycles[task.id] < implementer.reflection.max_cycles`:
  1. Increment `implementer_reflection_cycles[task.id]`.
  2. Re-enter §5.3 GREEN with the critic's findings appended to context.
  3. Re-run test, then re-dispatch critic (new sub-subagent, fresh context).
- `REVISE` and budget exhausted:
  1. Emit `REFLECT-DIVERGENCE` finding (WARNING, file/line from critic).
  2. Log stage note: `REFLECT_EXHAUSTED: {task.id} — critic rejected N consecutive implementations.`
  3. Proceed to §5.4 REFACTOR. Stage-6 reviewer panel will make the final call.

**Critic timeout:** 90s. On timeout, log INFO and proceed to REFACTOR.

**Counter:** `implementer_reflection_cycles` is a per-task integer in `state.json`
(see state-schema §Task-level). It is strictly separate from
`implementer_fix_cycles` and does NOT feed into `total_retries`, `total_iterations`,
`verify_fix_count`, `test_cycles`, or `quality_cycles`.
```

Also update §7 "Inner Loop vs Fix Loop" table to add a third column for Reflection loop, and update §15 Output Format to add a `Reflection Summary` section (total reflections, tasks reflecting, REFLECT-DIVERGENCE count).

### 5.3 MODIFY: `shared/stage-contract.md`

In Stage 4 (IMPLEMENT) § "Actions" step 4, expand the per-task flow:

```
4. For each parallel group (sequential order, after conflict detection):
   - For each task in group (concurrent up to `implementation.parallel_threshold`):
     a. `fg-310-scaffolder` generates boilerplate (if `scaffolder_before_impl: true`).
     b. Write tests (RED phase).
     c. `fg-300-implementer` writes implementation to pass tests (GREEN).
     d. **`fg-301-implementer-critic` reflects on diff vs test intent (sub-subagent, fresh context).** [NEW]
        - PASS → continue.
        - REVISE within budget → re-enter GREEN, then reflect again.
        - REVISE beyond budget → emit REFLECT-DIVERGENCE, continue.
     e. Refactor + self-review.
     f. Inner-loop lint + affected tests (§5.4.1 of fg-300).
     g. Verify with `commands.build` or `commands.test_single`.
```

No changes to stage-level entry/exit conditions — reflection is entirely internal to Stage 4.

### 5.4 MODIFY: `shared/state-schema.md`

Add task-level field. Locate the task state entry (`tasks[*]`, anchored at the existing `task_id` entry around line 1213) and add:

```json
{
  "task_id": "FG-042-3",
  "status": "IMPLEMENTING",
  "implementer_fix_cycles": 0,
  "implementer_reflection_cycles": 0,
  "reflection_verdicts": []
}
```

Schema additions:

| Field | Type | Required | Description |
|---|---|---|---|
| `tasks[*].implementer_reflection_cycles` | integer | Yes | Per-task reflection cycle count. Starts at 0. Incremented each time `fg-301-implementer-critic` returns REVISE and budget permits re-entry. Capped by `implementer.reflection.max_cycles` (default 2). Does NOT feed into `total_retries`, `total_iterations`, or any convergence counter. Parallel to `implementer_fix_cycles`. |
| `tasks[*].reflection_verdicts` | array of object | No | Audit trail of reflection cycles for this task. Each entry: `{cycle: int, verdict: "PASS"\|"REVISE", confidence: "HIGH"\|"MEDIUM"\|"LOW", finding_count: int, duration_ms: int}`. Trimmed to last 5 entries. |

Add a run-level aggregate field alongside `implementer_fix_cycles`:

| Field | Type | Required | Description |
|---|---|---|---|
| `implementer_reflection_cycles_total` | integer | Yes | Sum of `tasks[*].implementer_reflection_cycles` across the run. Reported by retrospective. |
| `reflection_divergence_count` | integer | Yes | Tasks that exhausted reflection budget (REVISE at cycle == max_cycles). Starts at 0. |

### 5.5 MODIFY: `shared/scoring.md`

Add two categories to the dispatched registry (and to `shared/checks/category-registry.json`):

| Category | Default Severity | Owner Agent | Score Impact |
|---|---|---|---|
| `REFLECT-DIVERGENCE` | WARNING | fg-301-implementer-critic | -5 per occurrence at Stage 6. Emitted only when critic budget is exhausted with REVISE. |
| `REFLECT-HARDCODED-RETURN` | INFO | fg-301-implementer-critic | -2 per occurrence, but only surfaces to Stage 6 if the finding persists after REFACTOR (i.e., critic flagged it and implementer didn't address it). Normally resolved in-loop and never reaches scoring. |

Additional sub-categories `REFLECT-OVER-NARROW` and `REFLECT-MISSING-BRANCH` are wildcarded under `REFLECT-*` — treat as INFO by default, owner fg-301.

Deduplication: `REFLECT-*` findings dedup against other findings by the standard `(component, file, line, category)` key. They are **not** SCOUT-class — they count toward the score.

## 6. Data / State / Config

### 6.1 New config keys

Add to `forge-config-template.md` under `implementer:`:

```yaml
implementer:
  inner_loop:
    enabled: true
    max_fix_cycles: 3
    run_lint: true
    run_tests: true
  reflection:
    enabled: true          # default: true. Set false to disable per-task CoVe.
    max_cycles: 2          # default: 2. Range: 1-3. Max 3 to bound cost.
    fresh_context: true    # default: true. If false, critic runs as same-context step (discouraged — matches alt-A).
    timeout_seconds: 90    # default: 90. Range: 30-180.
```

### 6.2 PREFLIGHT constraint validation

Add to `shared/preflight-constraints.md`:
- `implementer.reflection.max_cycles` in [1, 3]; violated → log WARNING, use default 2.
- `implementer.reflection.timeout_seconds` in [30, 180]; violated → log WARNING, use default 90.
- `implementer.reflection.enabled` boolean; non-boolean → default true.
- `implementer.reflection.fresh_context` boolean; non-boolean → default true.

### 6.3 State initialization

At PREFLIGHT, initialize:
- `state.implementer_reflection_cycles_total: 0`
- `state.reflection_divergence_count: 0`
- For each task created at PLAN: `tasks[i].implementer_reflection_cycles = 0`, `tasks[i].reflection_verdicts = []`.

### 6.4 Model routing

Add to `shared/model-routing.md`:

| Agent | Tier | Rationale |
|---|---|---|
| `fg-301-implementer-critic` | `fast` | Per-task, clean slate, short input (≤1 task + 1 test + 1 diff), short output (≤600 tokens). Fast tier is sufficient for pattern-recognition critic work and keeps per-task latency under 10s. |

Resolution order unchanged: config overlay > stage default > this default.

### 6.5 Token budget

Per reflection cycle: ≤4k input tokens, ≤600 output tokens. With max 2 cycles per task and typical 4 tasks per feature, reflection adds ~32k tokens per run — well under the 5% pipeline cost ceiling at `fast` tier.

## 7. Compatibility

**Explicit: no backwards compatibility required (per task brief).** Breaking changes:

1. **IMPLEMENT stage now has a sub-step (§5.3a REFLECT).** Any retrospective dashboard or playbook that expects the fg-300 task lifecycle to be `GREEN → REFACTOR` needs updating to `GREEN → REFLECT → REFACTOR`.
2. **New state fields** (`tasks[*].implementer_reflection_cycles`, `tasks[*].reflection_verdicts`, `state.implementer_reflection_cycles_total`, `state.reflection_divergence_count`) are now required at PREFLIGHT initialization. Existing state files from pre-Phase-04 runs lack these fields; on resume, PREFLIGHT must default-initialize them to 0 / [].
3. **Retrospective memories (`forge-log.md`) that aggregated fix cycles as a single metric must be updated** to distinguish `reflection_cycles` from `fix_cycles`. Migration note (not migration code — per brief, just documentation): add a one-line marker to `forge-log.md` on first Phase-04 run: `# Schema change: reflection_cycles tracked separately from fix_cycles starting {date}.` This is a read-only note; retrospective continues to process older entries without reflection fields present.
4. **Playbooks that hardcoded a task duration ceiling** may need to relax it by ~10-20s (one critic dispatch per task at fast tier).
5. **Scoring: `REFLECT-DIVERGENCE` is a new WARNING category.** Projects at the PASS/CONCERNS boundary (score near 80) may see a one-cycle dip until the implementer adapts to the stricter gate. This is expected behavior, not regression.

## 8. Testing Strategy

> Reminder: per project memory, no local test execution. CI measures the lift.

### 8.1 Eval harness additions

Add to the forge eval harness (if present; otherwise stubbed for Phase-04-dependent CI job):

**Scenario set: "Deliberately wrong-but-passing implementations"** — planted defects in `tests/eval/scenarios/reflection/`:
1. `hardcoded-return.yaml` — test asserts `userId != null`, plant implementation that returns `UserId(1)` without persisting. Expect: critic catches with REFLECT-HARDCODED-RETURN.
2. `over-narrow.yaml` — test asserts single-input happy path, plant implementation that only handles that exact input string. Expect: critic catches with REFLECT-OVER-NARROW.
3. `missing-branch.yaml` — test has one assertion, AC mentions 2 branches, plant implementation covering only the tested branch. Expect: critic catches with REFLECT-MISSING-BRANCH.
4. `legit-minimal.yaml` — test passes with a minimal but correct implementation (both branches covered per AC). Expect: critic returns PASS (false-positive guard).
5. `legit-trivial.yaml` — test asserts a constant that legitimately is a constant (config value lookup). Expect: critic returns PASS.

### 8.2 CI measurements

The existing CI eval job adds two new metrics, tracked per-run in `.forge/eval-metrics.json`:

1. **Reflection rate** — `reflection_triggers_that_returned_REVISE / total_reflection_triggers`. Baseline expectation: 40-60% on curated scenario set, 5-15% on real pipelines (most implementations are fine; critic should not be hyperactive).
2. **Reflection accuracy** — on the curated planted-defect scenarios (§8.1): `correct_verdict / total`. Target: ≥70% correct on planted-defect scenarios, ≤10% false-positive rate on legit scenarios.
3. **Overall eval score lift** — full eval harness score with Phase-04 on vs off. Target: +3 points absolute.

### 8.3 Assertion of no local run

CI alone decides pass/fail. No `./tests/run-all.sh` invocation is part of the acceptance criteria. The existing structural-test suite (`./tests/validate-plugin.sh`) will catch agent frontmatter consistency issues in CI (`ui-frontmatter-consistency.bats`); we rely on that.

## 9. Rollout

Single PR. Scope:
- `agents/fg-301-implementer-critic.md` (new)
- `agents/fg-300-implementer.md` (§5.3a inserted, §7 table updated, §15 output format updated)
- `shared/stage-contract.md` (Stage 4 action step expanded)
- `shared/state-schema.md` (task-level fields + run-level aggregates added)
- `shared/scoring.md` + `shared/checks/category-registry.json` (`REFLECT-*` categories)
- `shared/preflight-constraints.md` (constraint ranges)
- `shared/model-routing.md` (fast-tier entry for fg-301)
- `CLAUDE.md` agent count: 42 → 43. Review cluster unchanged (fg-301 is an implementer-adjacent critic, not a reviewer).
- `forge-config-template.md` (new `implementer.reflection.*` block)
- `tests/lib/module-lists.bash` (agent count bump)

Feature flag: `implementer.reflection.enabled: true` by default. If eval shows regression in the first 5 pipeline runs post-merge, ship a follow-up flipping default to `false` while investigating — do **not** revert the code.

Version: bump plugin to 3.1.0 (minor — new capability, breaking state-schema change).

## 10. Risks / Open Questions

### Risks

1. **Critic false-REVISE loops.** A hyperactive critic could force fg-300 to rewrite working code. Mitigation: `max_cycles: 2` hard cap, REFLECT-DIVERGENCE emitted on exhaustion rather than pipeline stall, and eval harness false-positive ceiling at 10%. If CI shows false-positive rate >15% on `legit-*` scenarios, the critic prompt is the problem — tune in §5.1, don't loosen the cap.
2. **Token cost overshoot.** If real pipelines trigger reflection on nearly every task (contrary to §6.5 estimate), per-run cost rises meaningfully. Mitigation: `fast` tier keeps per-call cost low; §8.2 tracks reflection rate. If rate >20% sustained, tune the skip rules (§5.7 exemptions) to be broader.
3. **Fresh-context dispatch mechanics.** Forge dispatches sub-subagents today (quality gate → reviewers), but fg-300 has not itself dispatched a sub-subagent before. Need to verify that Task tool dispatch from within fg-300 gives a truly isolated context (no system-prompt bleed). Mitigation: if bleed is observed, fall back to `implementer.reflection.fresh_context: false` (same-context critic — alt-A fallback) until Task isolation is fixed upstream.
4. **Targeted re-implementation skip is load-bearing.** If reflection runs during Stage-5/Stage-6 fix loops, the critic sees only the targeted-fix diff (not the full task diff) and will REVISE almost every time because the diff lacks context. Mitigation: explicit skip condition in §5.3a, enforced by fg-300 checking the dispatch mode flag from the orchestrator.
5. **Interaction with `/forge-recover resume`.** Mid-reflection interruptions (OS kill, lock timeout) leave `tasks[*].reflection_verdicts` partially populated. On resume, PREFLIGHT must not re-use stale verdicts — reset `reflection_verdicts` to `[]` but preserve `implementer_reflection_cycles` count (so budget is not freshly restored mid-task). Document in `shared/preflight-constraints.md`.

### Open questions

1. Should reflection also fire during **initial scaffolder output** (§5.1 of fg-310)? Current scope says no — scaffolders emit boilerplate with no test-intent contract yet. Defer.
2. Should the critic's prior REVISE findings be **accumulated across cycles within a task** and surfaced as INFO findings to Stage 6 even on final PASS? Current scope: no — only emit if budget exhausted. Defer to Phase-05 if signal is useful.
3. Should parallel task groups **serialize reflection** to avoid fast-tier rate-limit bursts? Current scope: no — `fast` tier has generous RPM budget. Monitor in §8.2.

## 11. Success Criteria

Measurable, evaluated in CI within first 2 weeks post-merge:

1. **Eval harness score lift: +3 points absolute** (baseline measured in the PR that merges this spec, compared to the same eval run with `implementer.reflection.enabled: false`).
2. **Reflection accuracy on planted-defect scenarios ≥ 70%** (§8.1 scenario set 1-3): critic correctly returns REVISE with the right category.
3. **False-positive rate on legit-minimal / legit-trivial scenarios ≤ 10%** (§8.1 scenario set 4-5).
4. **No measurable regression in end-to-end pipeline duration** beyond +15% on median run (fast-tier critic keeps this under budget).
5. **Zero CRITICAL findings added to Stage 6** as a direct consequence of reflection (reflection only emits WARNING/INFO via REFLECT-* categories).
6. **Structural test suite green in CI** (`./tests/validate-plugin.sh` + `./tests/run-all.sh` on CI — not local).

## 12. References

- Audit W4 — internal A+ roadmap audit, Phase-04 motivation document
- ReAct vs Plan-and-Execute: https://dev.to/jamesli/react-vs-plan-and-execute-a-practical-comparison-of-llm-agent-patterns-4gh9
- Superpowers 2-stage review pattern: https://blog.fsck.com/2025/10/09/superpowers/
- TDD with AI agents: https://qaskills.sh/blog/tdd-ai-agents-best-practices
- Chain-of-Verification (Dhuliawala et al., 2023): https://arxiv.org/abs/2309.11495
- forge `agents/fg-300-implementer.md` (existing TDD loop)
- forge `shared/stage-contract.md` (Stage 4 — IMPLEMENT)
- forge `shared/state-schema.md` (task-level schema, existing `implementer_fix_cycles`)
- forge `shared/scoring.md` (category registry, SCOUT handling for counter-example)
- forge `shared/model-routing.md` (tier definitions)
- forge `shared/agent-philosophy.md` (Principle 4 — disconfirming evidence)
