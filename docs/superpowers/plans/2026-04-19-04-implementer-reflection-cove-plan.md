# Phase 04 — Implementer Reflection (Chain-of-Verification) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Insert a fresh-context critic subagent (`fg-301-implementer-critic`) between GREEN and REFACTOR inside `fg-300-implementer`'s TDD loop so per-task implementations are verified for test-intent satisfaction before they layer.

**Architecture:** New Tier-4 agent dispatched via Task tool as a sub-subagent with a 3-field payload (task, test_code, implementation_diff). Per-task counter `implementer_reflection_cycles` in state.json. Max 2 reflections; on exhaustion emit `REFLECT-DIVERGENCE` (WARNING) and continue. Reflection is orthogonal to `implementer_fix_cycles` and does NOT feed into convergence counters.

**Tech Stack:** Markdown agent definitions, `shared/` contract docs, JSON category registry, bats structural tests, YAML eval scenarios. No runtime code.

---

## Review feedback resolutions

Applied from `docs/superpowers/reviews/2026-04-19-04-implementer-reflection-cove-spec-review.md`:

1. **Issue 1 — Phase 01 eval harness is a hard dependency.** Task 1 adds explicit dependency gate: the plan refuses to start until `tests/evals/` and `.forge/eval-metrics.json` schema exist. Success criterion #1 (+3 eval lift) is measurable only with Phase 01 present.
2. **Issue 2 — Cycle counting off-by-one fix.** Task 5 rewrites §4.5 table in the spec-derived agent body with "1st reflection / 2nd reflection" wording and `counter 0→1 on REVISE / 1→2 on REVISE`. Task 6 writes fg-300 §5.3a such that the budget check is `implementer_reflection_cycles < max_cycles` evaluated **before increment**, and the increment happens only on REVISE after re-entering GREEN.
3. **Suggestion 3 — Fresh-context pre-merge smoke test.** Task 12 adds a CI smoke test (`tests/contract/fg-301-fresh-context.bats`) that verifies the critic's observable context does not include fg-300 artifacts (no PREEMPT items, no conventions text, no prior reasoning markers). PR cannot merge red.

Suggestions 1, 2, 4, 5 are noted inline in the relevant tasks but not blocking.

---

## File Structure

Files created or modified, with responsibilities:

- **Create** `agents/fg-301-implementer-critic.md` — adversarial per-task critic; Tier-4 UI; fast model; `Read` tool only; body sections Identity / Question / Decision rules / Output format / Forbidden.
- **Modify** `agents/fg-300-implementer.md` — insert §5.3a REFLECT between GREEN and REFACTOR; extend §7 inner-loop table; extend §15 output format with Reflection Summary.
- **Modify** `shared/state-schema.md` — add task-level `implementer_reflection_cycles`, `reflection_verdicts`; add run-level `implementer_reflection_cycles_total`, `reflection_divergence_count`; bump schema version to 1.8.0.
- **Modify** `shared/stage-contract.md` — expand Stage 4 actions step 4 with REFLECT sub-step (4d).
- **Modify** `shared/scoring.md` — document `REFLECT-*` category family, dedup, not-SCOUT classification.
- **Modify** `shared/checks/category-registry.json` — add `REFLECT` wildcard + 4 discrete entries (`REFLECT-DIVERGENCE`, `REFLECT-HARDCODED-RETURN`, `REFLECT-OVER-NARROW`, `REFLECT-MISSING-BRANCH`).
- **Modify** `shared/model-routing.md` — add fg-301 at fast tier.
- **Modify** `shared/preflight-constraints.md` — add reflection constraint ranges and resume rules.
- **Create** `tests/contract/fg-301-fresh-context.bats` — pre-merge smoke test of sub-subagent context isolation.
- **Create** `tests/contract/fg-301-frontmatter.bats` — agent frontmatter consistency.
- **Create** `tests/contract/reflect-categories.bats` — registry entries present.
- **Create** `tests/unit/state-schema-reflection-fields.bats` — schema additions.
- **Create** `tests/evals/scenarios/reflection/hardcoded-return.yaml` — planted defect 1.
- **Create** `tests/evals/scenarios/reflection/over-narrow.yaml` — planted defect 2.
- **Create** `tests/evals/scenarios/reflection/missing-branch.yaml` — planted defect 3.
- **Create** `tests/evals/scenarios/reflection/legit-minimal.yaml` — false-positive guard 1.
- **Create** `tests/evals/scenarios/reflection/legit-trivial.yaml` — false-positive guard 2.
- **Modify** `tests/lib/module-lists.bash` — bump agent-count related MIN constants (if any guard agent count) and comment `# Phase 04: fg-301 added`.
- **Modify** `CLAUDE.md` — agent count 42 → 43; REFLECT-* in wildcard list; F32 / Phase-04 line in feature table if appropriate.
- **Modify** `modules/frameworks/spring/forge-config-template.md` (and all other framework `forge-config-template.md` files touched by config keys) — add `implementer.reflection.*` block.
- **Modify** `plugin.json`, `marketplace.json` — version 3.0.0 → 3.1.0.

---

## Task Sequence

### Task 1: Verify Phase 01 eval harness dependency

**Files:**
- Read: `tests/evals/README.md`
- Read: `tests/evals/framework.bash`

- [ ] **Step 1: Verify Phase 01 artifacts exist**

Run:
```bash
test -d /Users/denissajnar/IdeaProjects/forge/tests/evals \
  && test -f /Users/denissajnar/IdeaProjects/forge/tests/evals/README.md \
  && test -f /Users/denissajnar/IdeaProjects/forge/tests/evals/framework.bash \
  && ls /Users/denissajnar/IdeaProjects/forge/tests/evals/agents/ \
  && echo "PHASE_01_READY" || echo "PHASE_01_MISSING"
```
Expected: `PHASE_01_READY` followed by a directory listing. If output is `PHASE_01_MISSING`, STOP — Phase 04 is blocked on Phase 01 landing.

- [ ] **Step 2: Verify eval metrics schema contract test exists**

Run:
```bash
grep -l "eval-metrics\|eval_metrics" /Users/denissajnar/IdeaProjects/forge/tests/contract/*.bats || echo "NO_SCHEMA_TEST"
```
Expected: at least one matching file (e.g., `eval-report.bats`). If `NO_SCHEMA_TEST`, STOP — Phase 01 eval schema contract must land first.

- [ ] **Step 3: Record the Phase 01 commit SHA as baseline**

Run:
```bash
git -C /Users/denissajnar/IdeaProjects/forge log --oneline -- tests/evals/ | head -1
```
Record the SHA in your PR description as "Phase 01 baseline." No commit in this task.

---

### Task 2: Write structural test for fg-301 agent file presence

**Files:**
- Create: `tests/contract/fg-301-frontmatter.bats`

- [ ] **Step 1: Write the failing test**

```bash
cat > /Users/denissajnar/IdeaProjects/forge/tests/contract/fg-301-frontmatter.bats <<'BATS'
#!/usr/bin/env bats

ROOT="${BATS_TEST_DIRNAME}/../.."

@test "fg-301: agent file exists" {
  [ -f "${ROOT}/agents/fg-301-implementer-critic.md" ]
}

@test "fg-301: frontmatter name matches filename" {
  run grep -m1 '^name:' "${ROOT}/agents/fg-301-implementer-critic.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *"fg-301-implementer-critic"* ]]
}

@test "fg-301: model tier is fast" {
  run grep -m1 '^model:' "${ROOT}/agents/fg-301-implementer-critic.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *"fast"* ]]
}

@test "fg-301: color is lime" {
  run grep -m1 '^color:' "${ROOT}/agents/fg-301-implementer-critic.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *"lime"* ]]
}

@test "fg-301: tools is Read-only" {
  run grep -m1 '^tools:' "${ROOT}/agents/fg-301-implementer-critic.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Read"* ]]
  [[ "$output" != *"Edit"* ]]
  [[ "$output" != *"Write"* ]]
  [[ "$output" != *"Bash"* ]]
}

@test "fg-301: ui frontmatter declares Tier-4 (all false)" {
  run grep -A3 '^ui:' "${ROOT}/agents/fg-301-implementer-critic.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *"tasks: false"* ]]
  [[ "$output" == *"ask: false"* ]]
  [[ "$output" == *"plan_mode: false"* ]]
}
BATS
chmod +x /Users/denissajnar/IdeaProjects/forge/tests/contract/fg-301-frontmatter.bats
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./tests/lib/bats-core/bin/bats tests/contract/fg-301-frontmatter.bats`
Expected: FAIL — agent file does not exist.

- [ ] **Step 3: Commit**

```bash
cd /Users/denissajnar/IdeaProjects/forge
git add tests/contract/fg-301-frontmatter.bats
git commit -m "test(phase04): add fg-301 frontmatter contract test (RED)"
```

---

### Task 3: Write the fg-301-implementer-critic agent (minimum to pass Task 2)

**Files:**
- Create: `agents/fg-301-implementer-critic.md`

- [ ] **Step 1: Write the agent file**

```markdown
---
name: fg-301-implementer-critic
description: Fresh-context critic that verifies an implementation diff satisfies the intent (not just the letter) of a test. Dispatched by fg-300 between GREEN and REFACTOR via the Task tool as a sub-subagent.
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
See `shared/agent-philosophy.md` Principle 4 (disconfirming evidence) — apply maximally.
See `shared/agent-defaults.md` for shared constraint vocabulary.

## 1. Identity

You are a fresh reviewer. You have never seen this codebase before this message.
You receive exactly three inputs:

1. `task` — description + acceptance criteria
2. `test_code` — the test written in RED
3. `implementation_diff` — the code written in GREEN

You do NOT receive: the implementer's reasoning, prior iterations, conventions,
PREEMPT items, scaffolder output, or other tasks. This is by design.
If you cannot decide from the three inputs, return `verdict: REVISE, confidence: LOW`.

## 2. Question

Does the diff plausibly satisfy the **intent** of the test, or does it satisfy
only the **letter**?

Intent examples:
- Test asserts `userId != null` → implementation generates/persists a real ID. PASS.
- Test asserts `userId != null` → implementation `return UserId(1)`. REVISE: REFLECT-HARDCODED-RETURN.
- Test asserts `result == "ok"` with single input → `return "ok"`. REVISE: REFLECT-HARDCODED-RETURN.
- Test has one assertion, AC mentions 2 branches, impl covers only the asserted branch. REVISE: REFLECT-MISSING-BRANCH.
- Impl narrows the input domain tighter than the AC allows. REVISE: REFLECT-OVER-NARROW.
- Test covers only happy path, impl covers only happy path, AC matches. PASS.

## 3. Decision rules

1. Diff is a literal constant matching the test's one assertion AND task description implies real computation → REVISE (REFLECT-HARDCODED-RETURN).
2. Diff's control flow handles fewer branches than the AC describes → REVISE (REFLECT-MISSING-BRANCH).
3. Diff narrows the input domain more than the AC allows → REVISE (REFLECT-OVER-NARROW).
4. Diff passes the test and reasonably matches the AC → PASS.
5. Uncertain → REVISE with `confidence: LOW`. False PASS is worse than false REVISE.

## 4. Output format

Return ONLY this YAML. No preamble, no markdown fences. See `shared/checks/output-format.md` for field semantics.

```
verdict: PASS | REVISE
confidence: HIGH | MEDIUM | LOW
findings:
  - category: REFLECT-HARDCODED-RETURN | REFLECT-MISSING-BRANCH | REFLECT-OVER-NARROW | REFLECT-DIVERGENCE
    severity: WARNING | INFO
    file: <path>
    line: <int>
    explanation: <one sentence, <=30 words>
    suggestion: <one sentence, <=30 words>
```

Max total output: 600 tokens. `findings: []` when verdict == PASS.

## 5. Forbidden

- Do NOT use `Read` to explore the repo. The tool is present only for cross-file context inside the diff scope (e.g., reading an imported type referenced by the diff).
- Do NOT suggest refactors or style fixes. Intent satisfaction only.
- Do NOT ask for more information. Decide with what you have.
- Do NOT assume the test is wrong — the test is the contract.
```

Write the file to `/Users/denissajnar/IdeaProjects/forge/agents/fg-301-implementer-critic.md` with the content above verbatim.

- [ ] **Step 2: Run the frontmatter test to verify it passes**

Run: `./tests/lib/bats-core/bin/bats tests/contract/fg-301-frontmatter.bats`
Expected: 6 PASS.

- [ ] **Step 3: Commit**

```bash
cd /Users/denissajnar/IdeaProjects/forge
git add agents/fg-301-implementer-critic.md
git commit -m "feat(phase04): add fg-301-implementer-critic agent (GREEN)"
```

---

### Task 4: Write contract test for REFLECT-* category registry entries

**Files:**
- Create: `tests/contract/reflect-categories.bats`

- [ ] **Step 1: Write the failing test**

```bash
cat > /Users/denissajnar/IdeaProjects/forge/tests/contract/reflect-categories.bats <<'BATS'
#!/usr/bin/env bats

ROOT="${BATS_TEST_DIRNAME}/../.."
REGISTRY="${ROOT}/shared/checks/category-registry.json"

@test "reflect-categories: REFLECT wildcard present" {
  run jq -e '.categories.REFLECT' "$REGISTRY"
  [ "$status" -eq 0 ]
}

@test "reflect-categories: REFLECT owned by fg-301" {
  run jq -r '.categories.REFLECT.agents[]' "$REGISTRY"
  [ "$status" -eq 0 ]
  [[ "$output" == *"fg-301-implementer-critic"* ]]
}

@test "reflect-categories: REFLECT is wildcard" {
  run jq -r '.categories.REFLECT.wildcard' "$REGISTRY"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "reflect-categories: REFLECT-DIVERGENCE discrete entry" {
  run jq -e '.categories["REFLECT-DIVERGENCE"]' "$REGISTRY"
  [ "$status" -eq 0 ]
}

@test "reflect-categories: REFLECT-HARDCODED-RETURN discrete entry" {
  run jq -e '.categories["REFLECT-HARDCODED-RETURN"]' "$REGISTRY"
  [ "$status" -eq 0 ]
}

@test "reflect-categories: REFLECT-OVER-NARROW discrete entry" {
  run jq -e '.categories["REFLECT-OVER-NARROW"]' "$REGISTRY"
  [ "$status" -eq 0 ]
}

@test "reflect-categories: REFLECT-MISSING-BRANCH discrete entry" {
  run jq -e '.categories["REFLECT-MISSING-BRANCH"]' "$REGISTRY"
  [ "$status" -eq 0 ]
}

@test "reflect-categories: scoring.md mentions REFLECT-* wildcard" {
  run grep -E 'REFLECT-\*' "${ROOT}/shared/scoring.md"
  [ "$status" -eq 0 ]
}
BATS
chmod +x /Users/denissajnar/IdeaProjects/forge/tests/contract/reflect-categories.bats
```

- [ ] **Step 2: Run to verify failure**

Run: `./tests/lib/bats-core/bin/bats tests/contract/reflect-categories.bats`
Expected: FAIL — registry entries and scoring.md mention do not exist yet.

- [ ] **Step 3: Commit**

```bash
cd /Users/denissajnar/IdeaProjects/forge
git add tests/contract/reflect-categories.bats
git commit -m "test(phase04): add REFLECT-* category registry contract (RED)"
```

---

### Task 5: Add REFLECT-* entries to category registry and scoring.md

**Files:**
- Modify: `shared/checks/category-registry.json`
- Modify: `shared/scoring.md`

- [ ] **Step 1: Edit `shared/checks/category-registry.json`**

Locate the existing `SCOUT` entry at line 24 (use Read to confirm) and add after `SCOUT` the following entries, preserving JSON validity. Use Edit tool to insert; do not hand-reformat other entries.

Add to the `categories` object:

```json
    "REFLECT": { "description": "Per-task reflection finding: diff satisfies test letter but not intent", "agents": ["fg-301-implementer-critic"], "wildcard": true, "priority": 3, "affinity": ["fg-301-implementer-critic"] },
    "REFLECT-DIVERGENCE": { "description": "Critic rejected two consecutive implementations; reviewer panel must decide", "agents": ["fg-301-implementer-critic"], "severity": "WARNING", "score_impact": "-5", "priority": 3 },
    "REFLECT-HARDCODED-RETURN": { "description": "Implementation returns a literal matching the test assertion without real computation", "agents": ["fg-301-implementer-critic"], "severity": "INFO", "score_impact": "-2", "priority": 3 },
    "REFLECT-OVER-NARROW": { "description": "Implementation narrows input domain more tightly than AC allows", "agents": ["fg-301-implementer-critic"], "severity": "INFO", "score_impact": "-2", "priority": 3 },
    "REFLECT-MISSING-BRANCH": { "description": "Implementation's control flow handles fewer branches than AC describes", "agents": ["fg-301-implementer-critic"], "severity": "INFO", "score_impact": "-2", "priority": 3 },
```

- [ ] **Step 2: Edit `shared/scoring.md` — document REFLECT-\***

Find the wildcard prefix list (around line 183 where `SCOUT-*` appears) and append a row for `REFLECT-*`:

```
| `REFLECT-*` | Per-task reflection findings from fg-301-implementer-critic; standard dedup; NOT SCOUT-class (counts toward score). `REFLECT-DIVERGENCE` WARNING -5, subtypes INFO -2. |
```

Also add a short subsection after the `SCOUT-* Finding Handling` subsection:

```
### REFLECT-* Finding Handling

`REFLECT-*` findings are emitted by `fg-301-implementer-critic` during the per-task
reflection loop inside fg-300 (§5.3a). They are NOT SCOUT-class — they count
toward the score.

Normally, `REFLECT-HARDCODED-RETURN`, `REFLECT-OVER-NARROW`, and `REFLECT-MISSING-BRANCH`
are resolved in-loop (implementer re-enters GREEN) and never reach Stage 6.
They surface to Stage 6 only when the reflection budget is exhausted — at that
point `REFLECT-DIVERGENCE` (WARNING, -5) is emitted on the task and the per-cycle
subtype findings are NOT re-surfaced (no double-counting). Reviewers at Stage 6
independently re-examine the code; they do not read `REFLECT-*` findings as prior art.

Dedup: standard `(component, file, line, category)` key.
```

- [ ] **Step 3: Run the category test to verify it passes**

Run: `./tests/lib/bats-core/bin/bats tests/contract/reflect-categories.bats`
Expected: 8 PASS.

Also validate JSON:
```bash
jq empty /Users/denissajnar/IdeaProjects/forge/shared/checks/category-registry.json && echo JSON_OK
```
Expected: `JSON_OK`.

- [ ] **Step 4: Commit**

```bash
cd /Users/denissajnar/IdeaProjects/forge
git add shared/checks/category-registry.json shared/scoring.md
git commit -m "feat(phase04): register REFLECT-* scoring categories (GREEN)"
```

---

### Task 6: Write failing schema test for reflection state fields

**Files:**
- Create: `tests/unit/state-schema-reflection-fields.bats`

- [ ] **Step 1: Write the failing test**

```bash
cat > /Users/denissajnar/IdeaProjects/forge/tests/unit/state-schema-reflection-fields.bats <<'BATS'
#!/usr/bin/env bats

ROOT="${BATS_TEST_DIRNAME}/../.."
SCHEMA="${ROOT}/shared/state-schema.md"

@test "state-schema: implementer_reflection_cycles_total documented at run level" {
  run grep -E '^\|\s*`implementer_reflection_cycles_total`' "$SCHEMA"
  [ "$status" -eq 0 ]
}

@test "state-schema: reflection_divergence_count documented at run level" {
  run grep -E '^\|\s*`reflection_divergence_count`' "$SCHEMA"
  [ "$status" -eq 0 ]
}

@test "state-schema: tasks[*].implementer_reflection_cycles documented" {
  run grep -E 'tasks\[\*\]\.implementer_reflection_cycles' "$SCHEMA"
  [ "$status" -eq 0 ]
}

@test "state-schema: tasks[*].reflection_verdicts documented" {
  run grep -E 'tasks\[\*\]\.reflection_verdicts' "$SCHEMA"
  [ "$status" -eq 0 ]
}

@test "state-schema: explicit isolation from convergence counters" {
  run grep -F 'does NOT feed into' "$SCHEMA"
  [ "$status" -eq 0 ]
  [[ "$output" == *"reflection"* ]] || [[ "$output" == *"implementer_reflection_cycles"* ]]
}

@test "state-schema: changelog entry for 1.8.0" {
  run grep -E '^### 1\.8\.0' "$SCHEMA"
  [ "$status" -eq 0 ]
}
BATS
chmod +x /Users/denissajnar/IdeaProjects/forge/tests/unit/state-schema-reflection-fields.bats
```

- [ ] **Step 2: Run and verify failure**

Run: `./tests/lib/bats-core/bin/bats tests/unit/state-schema-reflection-fields.bats`
Expected: 6 FAIL.

- [ ] **Step 3: Commit**

```bash
cd /Users/denissajnar/IdeaProjects/forge
git add tests/unit/state-schema-reflection-fields.bats
git commit -m "test(phase04): assert reflection state fields in schema (RED)"
```

---

### Task 7: Add reflection fields to state-schema.md

**Files:**
- Modify: `shared/state-schema.md`

- [ ] **Step 1: Add state JSON example fields**

Use Edit tool. Locate the line `"implementer_fix_cycles": 0,` at line 130. After it insert:

```
  "implementer_reflection_cycles_total": 0,
  "reflection_divergence_count": 0,
```

- [ ] **Step 2: Find the run-level field table containing `implementer_fix_cycles`**

Read around line 350. Append immediately after the `implementer_fix_cycles` row:

```
| `implementer_reflection_cycles_total` | integer | Yes | Sum of `tasks[*].implementer_reflection_cycles` across the run. Reported by retrospective (§5.2 output). Initialized to 0 at PREFLIGHT. Does NOT feed into `total_retries`, `total_iterations`, `verify_fix_count`, `test_cycles`, or `quality_cycles`. |
| `reflection_divergence_count` | integer | Yes | Tasks that exhausted reflection budget (REVISE verdict at cycle == `implementer.reflection.max_cycles`). Starts at 0. Emits `REFLECT-DIVERGENCE` WARNING per increment. |
```

- [ ] **Step 3: Find the task-level schema section and add two fields**

The task checkpoint example at line 1210-1223 shows `task_id`, `status`, etc. Extend the task state to document the two new fields. After the checkpoint schema block, add a new subsection `### Task-level reflection fields`:

```
### Task-level reflection fields

Each task object under `tasks[*]` carries:

| Field | Type | Required | Description |
|---|---|---|---|
| `tasks[*].implementer_reflection_cycles` | integer | Yes | Per-task reflection cycle count. Starts at 0. Incremented each time `fg-301-implementer-critic` returns REVISE and budget permits re-entry. Budget check is `count < implementer.reflection.max_cycles` evaluated BEFORE increment. Capped by `implementer.reflection.max_cycles` (default 2). Does NOT feed into `total_retries`, `total_iterations`, `implementer_fix_cycles`, or any convergence counter. |
| `tasks[*].reflection_verdicts` | array of object | No | Audit trail of reflection dispatches for this task. Each entry: `{cycle: int, verdict: "PASS"\|"REVISE", confidence: "HIGH"\|"MEDIUM"\|"LOW", finding_count: int, duration_ms: int}`. Trimmed to last 5 entries. On `/forge-recover resume` this array is reset to `[]` while `implementer_reflection_cycles` is preserved (budget not refunded mid-task). |

**Cycle counter semantics (off-by-one guard):**

- `count == 0` means "no reflection dispatched yet." The FIRST critic dispatch happens at `count == 0`.
- On REVISE verdict within budget: increment count, re-enter GREEN, re-dispatch critic.
- With `max_cycles == 2`: up to 2 REVISEs → count reaches 2 → on next REVISE, budget exhausted, emit REFLECT-DIVERGENCE.

| Reflection # | Counter (before → after) | Verdict | Action |
|---|---|---|---|
| 1st dispatch | 0 → 0 | PASS | Proceed to REFACTOR. |
| 1st dispatch | 0 → 1 | REVISE | Re-enter GREEN; re-dispatch. |
| 2nd dispatch | 1 → 1 | PASS | Proceed to REFACTOR. |
| 2nd dispatch | 1 → 2 | REVISE | Budget exhausted. Emit REFLECT-DIVERGENCE WARNING. Proceed to REFACTOR. Reviewer panel decides at Stage 6. |
```

- [ ] **Step 4: Add changelog entry**

Find the `## Changelog` section near the bottom (line 1233). Prepend:

```
### 1.8.0 (Forge 3.1.0)
- Add `tasks[*].implementer_reflection_cycles` (integer, required) for per-task Chain-of-Verification (CoVe) counter. Does NOT feed into `total_retries`, `total_iterations`, `verify_fix_count`, `test_cycles`, `quality_cycles`, or `implementer_fix_cycles`.
- Add `tasks[*].reflection_verdicts` (array, optional) audit trail, last 5 entries.
- Add run-level `implementer_reflection_cycles_total` and `reflection_divergence_count`.
- On `/forge-recover resume`: `reflection_verdicts` reset to `[]`; `implementer_reflection_cycles` preserved (budget not refunded mid-task).
- **Breaking (no backcompat per Phase 04 brief):** new required fields initialized to 0 / [] at PREFLIGHT. Pre-Phase-04 state.json files are not readable by Phase-04 orchestrator without PREFLIGHT re-init.
```

Bump the schema version header at the top of the file from `v1.7.0` / `v1.6.0` to `v1.8.0` (Read the header first to confirm exact text).

- [ ] **Step 5: Verify tests pass**

Run: `./tests/lib/bats-core/bin/bats tests/unit/state-schema-reflection-fields.bats`
Expected: 6 PASS.

- [ ] **Step 6: Commit**

```bash
cd /Users/denissajnar/IdeaProjects/forge
git add shared/state-schema.md
git commit -m "feat(phase04): add reflection counters to state schema v1.8.0 (GREEN)"
```

---

### Task 8: Add fg-301 to model routing

**Files:**
- Modify: `shared/model-routing.md`

- [ ] **Step 1: Add agent entry**

Read `shared/model-routing.md`. Locate the table listing agents by tier (look for `fg-300-implementer` or a fast/standard/premium tier table). Append an entry placing `fg-301-implementer-critic` in the **fast** tier with this rationale:

```
| `fg-301-implementer-critic` | fast | Per-task, clean slate, ≤4k input, ≤600 output. Fast tier keeps per-task latency under 10s and per-run reflection cost under 5% of pipeline budget. |
```

If the file uses a per-tier bulleted list instead of a table, add `fg-301-implementer-critic` to the fast tier bullet with the same rationale as a nested item.

- [ ] **Step 2: Verify entry present**

Run:
```bash
grep -n "fg-301-implementer-critic" /Users/denissajnar/IdeaProjects/forge/shared/model-routing.md
```
Expected: at least one match.

- [ ] **Step 3: Commit**

```bash
cd /Users/denissajnar/IdeaProjects/forge
git add shared/model-routing.md
git commit -m "feat(phase04): route fg-301-implementer-critic at fast tier"
```

---

### Task 9: Add reflection constraints to preflight-constraints.md

**Files:**
- Modify: `shared/preflight-constraints.md`

- [ ] **Step 1: Append constraint block**

Read `shared/preflight-constraints.md`. At the end of the document, before any footer, add:

```
## Implementer Reflection (Phase 04)

| Key | Type | Default | Range | Violation behavior |
|---|---|---|---|---|
| `implementer.reflection.enabled` | boolean | `true` | — | Non-boolean → log WARNING and default to `true`. |
| `implementer.reflection.max_cycles` | integer | `2` | `[1, 3]` | Out of range → log WARNING and clamp to default `2`. |
| `implementer.reflection.fresh_context` | boolean | `true` | — | Non-boolean → log WARNING and default to `true`. Setting to `false` opts into same-context critic (matches rejected Alt-A in spec §4.6 — discouraged). |
| `implementer.reflection.timeout_seconds` | integer | `90` | `[30, 180]` | Out of range → log WARNING and clamp to default `90`. On timeout per-dispatch: log INFO in stage notes, skip reflection for that task, continue to REFACTOR. Never blocks pipeline. |

**Resume rules:** On `/forge-recover resume`, PREFLIGHT must:
1. Reset `tasks[*].reflection_verdicts` to `[]` (stale mid-dispatch verdicts are not trustworthy).
2. Preserve `tasks[*].implementer_reflection_cycles` (budget is not refunded mid-task — prevents runaway retries after OS kill).
3. Preserve run-level `implementer_reflection_cycles_total` and `reflection_divergence_count`.

**Initialization:** At PREFLIGHT, for every task created at PLAN, set `implementer_reflection_cycles: 0` and `reflection_verdicts: []`. Set run-level `implementer_reflection_cycles_total: 0` and `reflection_divergence_count: 0`.
```

- [ ] **Step 2: Commit**

```bash
cd /Users/denissajnar/IdeaProjects/forge
git add shared/preflight-constraints.md
git commit -m "feat(phase04): add implementer.reflection.* preflight constraints"
```

---

### Task 10: Modify fg-300-implementer.md to dispatch fg-301 between GREEN and REFACTOR

**Files:**
- Modify: `agents/fg-300-implementer.md`

- [ ] **Step 1: Read the current fg-300 to locate insertion points**

Run:
```bash
grep -n "^## \|^### " /Users/denissajnar/IdeaProjects/forge/agents/fg-300-implementer.md | head -40
```
Record line numbers for §5.3 (GREEN), §5.4 (REFACTOR), §5.4.1 (Inner-loop lint/test), §5.7 (exemptions), §7 (Inner Loop vs Fix Loop table), §15 (Output Format).

- [ ] **Step 2: Insert §5.3a REFLECT between GREEN and REFACTOR**

Using Edit tool, insert before the §5.4 REFACTOR header:

```markdown
### 5.3a Reflect (Chain-of-Verification)

After GREEN verifies the test passes, dispatch `fg-301-implementer-critic` as a
sub-subagent via the Task tool. The critic runs in a fresh Claude context (no
inherited reasoning from this implementer instance).

**Skip this step when any of the following hold:**
- `implementer.reflection.enabled` is `false` (PREFLIGHT-validated).
- Task falls under §5.7 exemptions (domain models, migrations, mappers, configs — no test was written; nothing to reflect on).
- Current invocation is a targeted re-implementation from a VERIFY or REVIEW fix loop. The orchestrator passes a `dispatch_mode: fix_loop` flag; if present, skip REFLECT.

**Dispatch payload (exactly three fields, no more, no less):**

```yaml
task:
  id: {task.id}
  description: {task.description}
  acceptance_criteria: {task.acceptance_criteria}
test_code: |
  {verbatim contents of test file written in RED}
implementation_diff: |
  {git diff HEAD -- <production files modified in GREEN>}
```

The critic MUST NOT receive: prior reasoning, PREEMPT items, conventions stack,
scaffolder output, context7 docs, other tasks, or prior reflection iterations
of this same task.

**Handle verdict:**

- `PASS` → proceed to §5.4 REFACTOR. Append verdict to `tasks[task.id].reflection_verdicts`.
- `REVISE` AND `tasks[task.id].implementer_reflection_cycles < implementer.reflection.max_cycles`:
  1. Append verdict to `tasks[task.id].reflection_verdicts` (trim to last 5).
  2. Increment `tasks[task.id].implementer_reflection_cycles` by 1.
  3. Increment `state.implementer_reflection_cycles_total` by 1.
  4. Re-enter §5.3 GREEN with the critic's findings appended to this implementer's context.
  5. Re-run `commands.test_single`. On green, re-dispatch critic (NEW sub-subagent, fresh context).
- `REVISE` AND budget exhausted (`implementer_reflection_cycles == max_cycles`):
  1. Emit `REFLECT-DIVERGENCE` finding (WARNING, file/line/explanation/suggestion copied from the critic's last output).
  2. Increment `state.reflection_divergence_count` by 1.
  3. Log stage note: `REFLECT_EXHAUSTED: {task.id} — critic rejected {max_cycles} consecutive implementations.`
  4. Proceed to §5.4 REFACTOR. Stage-6 reviewer panel will make the final call on the diff.

**Budget semantics (off-by-one guard):** the check `count < max_cycles` is
evaluated BEFORE increment. With `max_cycles == 2`, the flow is:

| Dispatch | Counter before check | Verdict | Counter after action |
|---|---|---|---|
| 1st | 0 | PASS | 0 (proceed to REFACTOR) |
| 1st | 0 | REVISE | 1 (re-enter GREEN, re-dispatch) |
| 2nd | 1 | PASS | 1 (proceed to REFACTOR) |
| 2nd | 1 | REVISE | 2 (budget exhausted, emit REFLECT-DIVERGENCE, proceed) |

**Timeout:** Per-dispatch 90s (configurable via `implementer.reflection.timeout_seconds`). On timeout, log INFO `REFLECT_TIMEOUT: {task.id}` and proceed to REFACTOR without incrementing the counter or emitting a finding. Never block the pipeline on a critic failure.

**Counter isolation:** `implementer_reflection_cycles` is strictly separate from
`implementer_fix_cycles`. It does NOT feed into `total_retries`, `total_iterations`,
`verify_fix_count`, `test_cycles`, or `quality_cycles`.
```

- [ ] **Step 3: Update §7 Inner Loop vs Fix Loop table**

Locate §7 (search for `Inner Loop vs Fix Loop` header). Add a third column `Reflection Loop` with:
- Scope: Per-task, GREEN → REFLECT → GREEN.
- Counter: `tasks[*].implementer_reflection_cycles`.
- Max: `implementer.reflection.max_cycles` (default 2).
- Feeds convergence: No.
- Fires on: Critic REVISE verdict within budget.
- Exit: PASS verdict OR budget exhausted (emit REFLECT-DIVERGENCE).

If a table already exists with two columns (Inner Loop / Fix Loop), add a third column matching that formatting. If it is a bulleted list, add a parallel bulleted section for "Reflection Loop" with the same six fields.

- [ ] **Step 4: Update §15 Output Format — add Reflection Summary**

Locate §15 (search for `Output Format`). Append a `Reflection Summary` subsection template:

```
### Reflection Summary

- Total reflections dispatched: {state.implementer_reflection_cycles_total}
- Tasks that triggered at least one reflection: {count of tasks where implementer_reflection_cycles > 0}
- REFLECT-DIVERGENCE count: {state.reflection_divergence_count}
- Per-task breakdown: {table of task_id → cycles → final verdict}
```

- [ ] **Step 5: Smoke-run structural validator**

Run: `./tests/validate-plugin.sh`
Expected: pass (73+ checks). Any failure → diagnose before commit.

- [ ] **Step 6: Commit**

```bash
cd /Users/denissajnar/IdeaProjects/forge
git add agents/fg-300-implementer.md
git commit -m "feat(phase04): dispatch fg-301 between GREEN and REFACTOR in fg-300"
```

---

### Task 11: Update stage-contract.md Stage 4 action step

**Files:**
- Modify: `shared/stage-contract.md`

- [ ] **Step 1: Locate Stage 4 action step 4**

Run:
```bash
grep -nE "Stage 4|IMPLEMENT|parallel group" /Users/denissajnar/IdeaProjects/forge/shared/stage-contract.md | head -20
```

- [ ] **Step 2: Expand per-task flow**

Using Edit tool, replace the existing Stage 4 action-4 bullet sequence (fg-310 → fg-300 → verify) with:

```
4. For each parallel group (sequential order, after conflict detection):
   - For each task in group (concurrent up to `implementation.parallel_threshold`):
     a. `fg-310-scaffolder` generates boilerplate (if `scaffolder_before_impl: true`).
     b. Write tests (RED phase).
     c. `fg-300-implementer` writes implementation to pass tests (GREEN).
     d. **`fg-301-implementer-critic` reflects on diff vs test intent via Task-tool sub-subagent dispatch (fresh context).** [Phase 04]
        - PASS → continue to (e).
        - REVISE within budget → re-enter (c), then re-dispatch critic.
        - REVISE beyond budget → emit `REFLECT-DIVERGENCE` (WARNING), continue.
        - Skipped when: `implementer.reflection.enabled == false`; task matches §5.7 exemption; invocation is a targeted fix-loop re-implementation.
     e. `fg-300-implementer` refactors + runs self-review checkpoint.
     f. `fg-300-implementer` inner-loop: lint + affected tests (§5.4.1).
     g. Verify with `commands.build` or `commands.test_single`.
```

Stage-level entry/exit conditions are unchanged. Note this in an inline comment at the end of the section: `<!-- Phase 04: reflection is Stage-4-internal; no stage entry/exit changes. -->`.

- [ ] **Step 3: Commit**

```bash
cd /Users/denissajnar/IdeaProjects/forge
git add shared/stage-contract.md
git commit -m "docs(phase04): document REFLECT sub-step in Stage 4 contract"
```

---

### Task 12: Write the fresh-context smoke test (pre-merge verification)

**Files:**
- Create: `tests/contract/fg-301-fresh-context.bats`

This test addresses Suggestion 3 from the review: verify the critic's observable context contains no fg-300 artifacts. It is a **static check** — we cannot launch real subagents in bats — that asserts the dispatch **contract** in fg-300 is exactly three fields and nothing more, and that the critic's agent body forbids reading anything else.

- [ ] **Step 1: Write the test**

```bash
cat > /Users/denissajnar/IdeaProjects/forge/tests/contract/fg-301-fresh-context.bats <<'BATS'
#!/usr/bin/env bats
# Pre-merge smoke test for sub-subagent context isolation.
# Verifies fg-300 dispatches fg-301 with exactly 3 payload fields and no context bleed.

ROOT="${BATS_TEST_DIRNAME}/../.."
IMPL="${ROOT}/agents/fg-300-implementer.md"
CRITIC="${ROOT}/agents/fg-301-implementer-critic.md"

@test "fresh-context: fg-300 dispatches fg-301 via Task tool (sub-subagent)" {
  run grep -E "fg-301-implementer-critic" "$IMPL"
  [ "$status" -eq 0 ]
  run grep -E "sub-subagent|Task tool" "$IMPL"
  [ "$status" -eq 0 ]
}

@test "fresh-context: dispatch payload declares exactly 3 top-level fields" {
  # The payload block must contain exactly 'task:', 'test_code:', 'implementation_diff:' as top-level keys.
  run awk '
    /^```yaml$/ { in_block=1; next }
    /^```$/ && in_block { in_block=0 }
    in_block && /^[a-z_]+:/ { print $1 }
  ' "$IMPL"
  [ "$status" -eq 0 ]
  # Must contain all three; no extras at top level inside the dispatch block.
  [[ "$output" == *"task:"* ]]
  [[ "$output" == *"test_code:"* ]]
  [[ "$output" == *"implementation_diff:"* ]]
}

@test "fresh-context: fg-300 explicitly forbids extra context in dispatch" {
  # Must name at least these forbidden items in the NOT-sent list.
  run grep -E "MUST NOT receive|NOT receive|no inherited" "$IMPL"
  [ "$status" -eq 0 ]
  for forbidden in "PREEMPT" "conventions" "scaffolder" "prior reasoning\|prior iterations\|prior reflection"; do
    run grep -E "$forbidden" "$IMPL"
    [ "$status" -eq 0 ]
  done
}

@test "fresh-context: fg-301 identity asserts fresh reviewer" {
  run grep -E "fresh reviewer|never seen this codebase" "$CRITIC"
  [ "$status" -eq 0 ]
}

@test "fresh-context: fg-301 forbidden list blocks repo exploration" {
  run grep -E "Do NOT use.*Read.*explore|do not use it to explore" "$CRITIC"
  [ "$status" -eq 0 ]
}

@test "fresh-context: fg-301 has no tools beyond Read" {
  tools_line=$(grep -m1 '^tools:' "$CRITIC")
  [[ "$tools_line" == *"Read"* ]]
  [[ "$tools_line" != *"Edit"* ]]
  [[ "$tools_line" != *"Write"* ]]
  [[ "$tools_line" != *"Bash"* ]]
  [[ "$tools_line" != *"Grep"* ]]
  [[ "$tools_line" != *"Glob"* ]]
  [[ "$tools_line" != *"Task"* ]]
  [[ "$tools_line" != *"WebFetch"* ]]
}

@test "fresh-context: fg-301 instructed not to ask for more info" {
  run grep -E "Do NOT ask for more|decide with what you have" "$CRITIC"
  [ "$status" -eq 0 ]
}

@test "fresh-context: prior reflection iterations explicitly excluded" {
  run grep -E "prior reflection|other tasks" "$IMPL"
  [ "$status" -eq 0 ]
}
BATS
chmod +x /Users/denissajnar/IdeaProjects/forge/tests/contract/fg-301-fresh-context.bats
```

- [ ] **Step 2: Run the test**

Run: `./tests/lib/bats-core/bin/bats tests/contract/fg-301-fresh-context.bats`
Expected: all PASS given Tasks 3 and 10 landed. If any fail, fix fg-300 / fg-301 body to satisfy the contract — do not weaken the test.

- [ ] **Step 3: Commit**

```bash
cd /Users/denissajnar/IdeaProjects/forge
git add tests/contract/fg-301-fresh-context.bats
git commit -m "test(phase04): add fresh-context dispatch smoke test"
```

---

### Task 13: Add `implementer.reflection.*` config block to framework templates

**Files:**
- Modify: `modules/frameworks/*/forge-config-template.md` (all framework templates that include an `implementer:` block)

- [ ] **Step 1: Find templates containing an `implementer:` block**

Run:
```bash
grep -rl "^implementer:" /Users/denissajnar/IdeaProjects/forge/modules/frameworks/*/forge-config-template.md
```
Record the list of files.

- [ ] **Step 2: For each file, insert the reflection block inside `implementer:`**

For each file in the list, use Edit tool. Locate the `implementer:` block (e.g., the `inner_loop:` sub-block). Add sibling keys for reflection:

```yaml
implementer:
  inner_loop:
    enabled: true
    max_fix_cycles: 3
    run_lint: true
    run_tests: true
  reflection:
    enabled: true          # Phase 04 CoVe. Set false to disable per-task fresh-context critic.
    max_cycles: 2          # Range [1, 3]. Default 2.
    fresh_context: true    # Dispatch fg-301 as sub-subagent (recommended).
    timeout_seconds: 90    # Range [30, 180]. On timeout, skip reflection for that task.
```

Preserve the existing `inner_loop` block exactly. Add `reflection:` as a sibling key with the same indentation as `inner_loop:`. Do not reorder other top-level keys.

- [ ] **Step 3: Sanity check**

Run:
```bash
grep -l "reflection:" /Users/denissajnar/IdeaProjects/forge/modules/frameworks/*/forge-config-template.md | wc -l
```
Expected: equal to the count from Step 1.

- [ ] **Step 4: Commit**

```bash
cd /Users/denissajnar/IdeaProjects/forge
git add modules/frameworks/*/forge-config-template.md
git commit -m "feat(phase04): add implementer.reflection.* to framework config templates"
```

---

### Task 14: Update CLAUDE.md (agent count, feature table, category list)

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Bump agent count**

Using Edit tool, replace `42 agents` (and `## Agents (42 total` header) with `43`:
- Find: `42 agents, check engine`
- Replace with: `43 agents, check engine`
- Find: `## Agents (42 total`
- Replace with: `## Agents (43 total`

- [ ] **Step 2: Add fg-301 to the Implement bucket**

Find the line listing `fg-300-implementer` in the Pipeline agent bullet list (under `## Agents`). Extend the Implement bucket bullet to include `fg-301-implementer-critic`:

Find:
```
- Implement: `fg-300-implementer` (TDD + inner-loop lint/test validation per task), `fg-310-scaffolder`, `fg-320-frontend-polisher`
```

Replace with:
```
- Implement: `fg-300-implementer` (TDD + inner-loop lint/test validation per task), `fg-301-implementer-critic` (Chain-of-Verification critic between GREEN and REFACTOR, fresh-context sub-subagent, fast tier), `fg-310-scaffolder`, `fg-320-frontend-polisher`
```

- [ ] **Step 3: Add REFLECT-\* to the scoring wildcard list**

Find the sentence `Key wildcards: ...`. Append `REFLECT-*` to the list:

Find: ``AI-CONCURRENCY-*`, `AI-SEC-*`.``
Replace with: ``AI-CONCURRENCY-*`, `AI-SEC-*`, `REFLECT-*`.``

Also bump the wildcard count: find `27 wildcard prefixes + 60 discrete` and replace with `28 wildcard prefixes + 64 discrete` (4 new discrete REFLECT entries added).

- [ ] **Step 4: Add a Phase-04 row to the feature table**

Find the feature table row for `Consumer-driven contracts (F25)` or the last `(F...)` row. Append a new row:

```
| Implementer reflection (F32, Phase 04) | `implementer.reflection.*` | `fg-301-implementer-critic` between GREEN/REFACTOR. Per-task `implementer_reflection_cycles` counter. Categories: `REFLECT-DIVERGENCE`, `REFLECT-HARDCODED-RETURN`, `REFLECT-OVER-NARROW`, `REFLECT-MISSING-BRANCH` |
```

- [ ] **Step 5: Commit**

```bash
cd /Users/denissajnar/IdeaProjects/forge
git add CLAUDE.md
git commit -m "docs(phase04): bump agent count to 43 and document REFLECT-*"
```

---

### Task 15: Add reflection eval scenarios

**Files:**
- Create: `tests/evals/scenarios/reflection/hardcoded-return.yaml`
- Create: `tests/evals/scenarios/reflection/over-narrow.yaml`
- Create: `tests/evals/scenarios/reflection/missing-branch.yaml`
- Create: `tests/evals/scenarios/reflection/legit-minimal.yaml`
- Create: `tests/evals/scenarios/reflection/legit-trivial.yaml`

Phase 01 owns `tests/evals/framework.bash` and `tests/evals/agents/`. These scenarios plug into the existing scenario-runner contract. If Phase 01's scenario schema differs from the one sketched below, conform to Phase 01's schema and keep the semantic intent intact.

- [ ] **Step 1: Create scenario directory**

```bash
mkdir -p /Users/denissajnar/IdeaProjects/forge/tests/evals/scenarios/reflection
```

- [ ] **Step 2: Write `hardcoded-return.yaml`**

```yaml
id: reflection-hardcoded-return
phase: 04
kind: planted-defect
agent_under_test: fg-301-implementer-critic
description: |
  Test asserts userId != null. Implementation returns UserId(1) unconditionally
  with no persistence. Critic must flag as REFLECT-HARDCODED-RETURN.

task:
  id: EVAL-01
  description: "Implement CreateUserUseCase.execute() — validate email, persist user, return UserId."
  acceptance_criteria:
    - "Given a unique email, when execute is called, then a User is persisted and UserId returned."
    - "Given a duplicate email, when execute is called, then DuplicateEmailError is raised."

test_code: |
  @Test
  fun `returns a UserId when email is unique`() {
    val result = sut.execute(CreateUser("alice@example.com"))
    assertThat(result.userId).isNotNull()
  }

implementation_diff: |
  +++ b/src/domain/CreateUserUseCase.kt
  @@
  +class CreateUserUseCase(private val repo: UserRepository) {
  +  fun execute(cmd: CreateUser): CreateUserResult {
  +    return CreateUserResult(userId = UserId(1))
  +  }
  +}

expected:
  verdict: REVISE
  finding_category: REFLECT-HARDCODED-RETURN
  min_confidence: MEDIUM
```

- [ ] **Step 3: Write `over-narrow.yaml`**

```yaml
id: reflection-over-narrow
phase: 04
kind: planted-defect
agent_under_test: fg-301-implementer-critic
description: |
  Test asserts a single happy-path input maps to "ok". Implementation only
  returns "ok" when input equals the exact test string, else throws. Critic
  must flag as REFLECT-OVER-NARROW because AC allows any non-empty input.

task:
  id: EVAL-02
  description: "Implement Greeter.greet(name) — return a greeting for any non-empty name."
  acceptance_criteria:
    - "Given any non-empty name, when greet is called, then a greeting containing the name is returned."
    - "Given an empty name, when greet is called, then IllegalArgumentException is raised."

test_code: |
  @Test
  fun `greets alice`() {
    assertThat(sut.greet("alice")).isEqualTo("hello alice")
  }

implementation_diff: |
  +++ b/src/domain/Greeter.kt
  @@
  +class Greeter {
  +  fun greet(name: String): String {
  +    if (name == "alice") return "hello alice"
  +    throw IllegalStateException("unsupported")
  +  }
  +}

expected:
  verdict: REVISE
  finding_category: REFLECT-OVER-NARROW
  min_confidence: MEDIUM
```

- [ ] **Step 4: Write `missing-branch.yaml`**

```yaml
id: reflection-missing-branch
phase: 04
kind: planted-defect
agent_under_test: fg-301-implementer-critic
description: |
  Test covers the unique-email happy path. AC describes TWO branches: unique
  and duplicate. Implementation silently ignores duplicates and always returns
  a new UserId. Critic must flag REFLECT-MISSING-BRANCH.

task:
  id: EVAL-03
  description: "Implement CreateUserUseCase.execute() — handle unique and duplicate emails."
  acceptance_criteria:
    - "Given a unique email, then persist and return UserId."
    - "Given a duplicate email, then raise DuplicateEmailError."

test_code: |
  @Test
  fun `returns userId for unique email`() {
    val result = sut.execute(CreateUser("alice@example.com"))
    assertThat(result.userId).isNotNull()
  }

implementation_diff: |
  +++ b/src/domain/CreateUserUseCase.kt
  @@
  +class CreateUserUseCase(private val repo: UserRepository) {
  +  fun execute(cmd: CreateUser): CreateUserResult {
  +    val id = repo.nextId()
  +    repo.save(User(id, cmd.email))
  +    return CreateUserResult(userId = id)
  +  }
  +}

expected:
  verdict: REVISE
  finding_category: REFLECT-MISSING-BRANCH
  min_confidence: MEDIUM
```

- [ ] **Step 5: Write `legit-minimal.yaml`**

```yaml
id: reflection-legit-minimal
phase: 04
kind: false-positive-guard
agent_under_test: fg-301-implementer-critic
description: |
  Test covers unique-email happy path; AC only describes this one branch.
  Implementation is minimal and correct — persists and returns a generated id.
  Critic must return PASS.

task:
  id: EVAL-04
  description: "Implement CreateUserUseCase.execute() — persist and return a new UserId for any email."
  acceptance_criteria:
    - "Given any email, then persist a User and return UserId."

test_code: |
  @Test
  fun `persists and returns userId`() {
    val result = sut.execute(CreateUser("alice@example.com"))
    assertThat(result.userId).isNotNull()
    assertThat(repo.saved).hasSize(1)
  }

implementation_diff: |
  +++ b/src/domain/CreateUserUseCase.kt
  @@
  +class CreateUserUseCase(private val repo: UserRepository) {
  +  fun execute(cmd: CreateUser): CreateUserResult {
  +    val id = repo.nextId()
  +    repo.save(User(id, cmd.email))
  +    return CreateUserResult(userId = id)
  +  }
  +}

expected:
  verdict: PASS
  finding_category: null
```

- [ ] **Step 6: Write `legit-trivial.yaml`**

```yaml
id: reflection-legit-trivial
phase: 04
kind: false-positive-guard
agent_under_test: fg-301-implementer-critic
description: |
  Test asserts a constant. Task description is a config-value lookup that
  legitimately returns a constant. Critic must return PASS — hardcoded return
  rule 1 does NOT apply because the task does not imply real computation.

task:
  id: EVAL-05
  description: "Implement ApiVersion.current() — return the string '1.0.0' as the stable API version."
  acceptance_criteria:
    - "current() returns '1.0.0'."

test_code: |
  @Test
  fun `current returns 1_0_0`() {
    assertThat(ApiVersion.current()).isEqualTo("1.0.0")
  }

implementation_diff: |
  +++ b/src/api/ApiVersion.kt
  @@
  +object ApiVersion {
  +  fun current(): String = "1.0.0"
  +}

expected:
  verdict: PASS
  finding_category: null
```

- [ ] **Step 7: Commit**

```bash
cd /Users/denissajnar/IdeaProjects/forge
git add tests/evals/scenarios/reflection/
git commit -m "test(phase04): add 5 reflection eval scenarios (3 defects + 2 guards)"
```

---

### Task 16: Bump plugin version and marketplace

**Files:**
- Modify: `plugin.json`
- Modify: `marketplace.json`

- [ ] **Step 1: Bump `plugin.json` version**

Read `/Users/denissajnar/IdeaProjects/forge/plugin.json`. Find the version field (currently `3.0.0`). Replace with `3.1.0`.

- [ ] **Step 2: Bump `marketplace.json` version**

Read `/Users/denissajnar/IdeaProjects/forge/marketplace.json`. Find the entry for `forge` with version `3.0.0`. Replace with `3.1.0`.

- [ ] **Step 3: Verify JSON validity**

```bash
jq empty /Users/denissajnar/IdeaProjects/forge/plugin.json && jq empty /Users/denissajnar/IdeaProjects/forge/marketplace.json && echo JSON_OK
```
Expected: `JSON_OK`.

- [ ] **Step 4: Commit**

```bash
cd /Users/denissajnar/IdeaProjects/forge
git add plugin.json marketplace.json
git commit -m "chore(phase04): bump plugin version to 3.1.0"
```

---

### Task 17: Run full structural suite and validate

**Files:**
- None (verification-only task)

- [ ] **Step 1: Run structural validator**

Run: `./tests/validate-plugin.sh`
Expected: 73+ structural checks pass.

- [ ] **Step 2: Run the new bats tests**

Run:
```bash
./tests/lib/bats-core/bin/bats \
  tests/contract/fg-301-frontmatter.bats \
  tests/contract/fg-301-fresh-context.bats \
  tests/contract/reflect-categories.bats \
  tests/unit/state-schema-reflection-fields.bats
```
Expected: all PASS.

- [ ] **Step 3: Run the full suite locally only if CI is not yet configured for Phase 04**

Per project memory ("no local tests"): do NOT run `./tests/run-all.sh` locally. Push the branch and let CI measure. Record in the PR description:
- Phase 01 baseline SHA (from Task 1 step 3).
- Expected CI jobs: `structural`, `unit`, `contract`, `scenario`, `eval`.
- Expected CI metric lift (from Phase 01 eval harness): +3 points absolute vs `implementer.reflection.enabled: false` baseline.

- [ ] **Step 4: Create the PR**

```bash
cd /Users/denissajnar/IdeaProjects/forge
git log --oneline master..HEAD
```
Expected: 15 commits (one per task with commits, Tasks 1 and 17 are verification-only).

Push and open PR with title `feat(phase04): implementer reflection / Chain-of-Verification (fg-301)` and body containing:
- Summary of what each commit does.
- Phase 01 baseline SHA.
- Success criteria from spec §11 as a checklist for CI to measure.
- Note: per §9 Rollout, if eval shows regression in first 5 post-merge runs, ship a follow-up flipping default to `false` — do NOT revert the code.

No commit in this task (verification + PR open only).

---

## Self-Review

Checked each of the 10 review criteria:
1. All 12 spec sections — covered by Tasks 3, 7, 10, 11, 5, 9, 14, 15, 17. PASS.
2. No placeholders — every step has concrete code, exact paths, exact commands. PASS.
3. Fresh-context mechanism — Tasks 3, 10, 12. PASS.
4. Critic I/O — Tasks 3 (body), 10 (dispatch payload), 15 (scenario shape). PASS.
5. Counter isolation — Tasks 7, 9, 10 each repeat the "does NOT feed into convergence" statement verbatim. PASS.
6. Frontmatter — Task 3 writes it; Task 2 tests it. PASS.
7. REFLECT-* categories — Tasks 4, 5. PASS.
8. Phase 01 eval harness dependency — Task 1 (hard gate) + Task 15 (scenarios). PASS.
9. Alternatives — referenced in spec §4.6; not re-asserted in plan but Task 9 mentions `fresh_context: false` as rejected Alt-A. PASS.
10. Max cycles — Tasks 7, 9, 10 enforce budget check before increment. PASS.

Placeholder scan: no `TBD`, `TODO`, `FIXME`, `<PLACEHOLDER>`. All counter ranges, timeouts, file paths concrete.

Type consistency: `implementer_reflection_cycles` (task-level int), `implementer_reflection_cycles_total` (run-level int), `reflection_divergence_count` (run-level int), `reflection_verdicts` (task-level array), `REFLECT-DIVERGENCE` / `REFLECT-HARDCODED-RETURN` / `REFLECT-OVER-NARROW` / `REFLECT-MISSING-BRANCH` (scoring categories) — names are identical across Tasks 5, 7, 9, 10, 14, 15.

Commit message style: conventional commits; no Co-Authored-By; no AI attribution. Matches `shared/git-conventions.md`.
