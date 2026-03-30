# Convergence Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace hard-capped fix cycle loops with a convergence-driven two-phase iteration engine that aims for score 100.

**Architecture:** New shared contract (`shared/convergence-engine.md`) referenced by the orchestrator. The orchestrator's VERIFY (Stage 5) and REVIEW (Stage 6) are coordinated by the engine as Phase 1 (correctness) and Phase 2 (perfection) with a final safety gate. No stage renumbering, no new agents.

**Tech Stack:** Markdown contracts, YAML config, BATS tests, Bash validation.

**Spec:** `docs/superpowers/specs/2026-03-30-convergence-engine-design.md`

---

### Task 1: Create the Convergence Engine Contract

**Files:**
- Create: `shared/convergence-engine.md`

- [ ] **Step 1: Create the convergence engine contract document**

```markdown
# Convergence Engine

This document defines the convergence-driven iteration engine that coordinates VERIFY (Stage 5) and REVIEW (Stage 6) as a two-phase loop. The orchestrator calls this engine after every stage dispatch to determine the next action.

## Convergence States

| State | Meaning | Action |
|-------|---------|--------|
| `IMPROVING` | Score increased by > `plateau_threshold` (default: 2) since last cycle | Continue iterating |
| `PLATEAUED` | Score improved by <= `plateau_threshold` for `plateau_patience` (default: 2) consecutive cycles | Declare convergence — stop iterating |
| `REGRESSING` | Score decreased by more than `oscillation_tolerance` (from `scoring:` config) | Escalate immediately |

## Two-Phase Model

| Phase | Loop | Goal | Convergence Signal |
|-------|------|------|--------------------|
| **Phase 1: Correctness** | IMPLEMENT ↔ VERIFY | Tests green | All tests pass (binary — no scoring) |
| **Phase 2: Perfection** | IMPLEMENT ↔ REVIEW | Score = `target_score` | Score = target, OR `PLATEAUED` state reached |
| **Safety Gate** | VERIFY (one shot) | No regressions | Tests still pass after Phase 2 fixes |

Phase 2 skips VERIFY on each iteration — only REVIEW scores. This avoids running the full test suite for every INFO-level finding fix. The safety gate at the end catches regressions introduced during Phase 2.

If the safety gate fails, the engine transitions back to Phase 1 (correctness first, then perfection again). The `phase_history` log records this for retrospective analysis.

## Algorithm

After every VERIFY or REVIEW dispatch returns, the orchestrator calls this decision function:

```
FUNCTION decide_next(state.convergence, verify_result, review_result):

  MATCH phase:

    "correctness":
      IF verify_result.tests_pass AND verify_result.analysis_pass:
        → transition to "perfection"
        → reset phase_iterations to 0
        → append to phase_history: { phase: "correctness", iterations, outcome: "converged", duration_seconds }
      ELSE:
        → increment phase_iterations
        → increment total_iterations
        → IF total_iterations >= max_iterations: ESCALATE to user
        → ELSE: dispatch IMPLEMENT with failure details, then VERIFY again
        (Phase 1 inner cap is max_test_cycles, managed by pl-500 internally.)

    "perfection":
      score = review_result.score
      previous_score = last entry in state.score_history (0 if first cycle)
      delta = score - previous_score

      IF score >= target_score:
        → transition to "safety_gate"

      ELSE IF delta < 0 AND abs(delta) > oscillation_tolerance:
        → set convergence_state = "REGRESSING"
        → ESCALATE to user

      ELSE IF delta <= plateau_threshold:
        → increment plateau_count
        → IF plateau_count >= plateau_patience:
            → set convergence_state = "PLATEAUED"
            → apply score escalation ladder (orchestrator section 9.4)
            → document unfixable findings with rationale
            → transition to "safety_gate"
        → ELSE:
            → dispatch IMPLEMENT with ALL findings, then REVIEW again
            → increment phase_iterations
            → increment total_iterations

      ELSE:
        → reset plateau_count to 0
        → set convergence_state = "IMPROVING"
        → dispatch IMPLEMENT with ALL findings, then REVIEW again
        → increment phase_iterations
        → increment total_iterations

    "safety_gate":
      IF verify_result.tests_pass:
        → set safety_gate_passed = true
        → append to phase_history: { phase: "perfection", iterations, outcome, duration_seconds }
        → CONVERGED — proceed to DOCS (Stage 7)
      ELSE:
        → transition back to "correctness"
        → reset phase_iterations to 0
        → append to phase_history: { phase: "safety_gate", iterations: 1, outcome: "failed", duration_seconds }
```

## Configuration

Read from `pipeline-config.md` (auto-tunable) > `dev-pipeline.local.md` (static) > plugin defaults:

```yaml
convergence:
  max_iterations: 8       # Hard safety valve across both phases (3-20)
  plateau_threshold: 2    # Score improvement <= this = "no meaningful progress" (0-10)
  plateau_patience: 2     # Consecutive plateaued cycles before declaring convergence (1-5)
  target_score: 100       # The score we aim for (80-100, must be >= pass_threshold)
  safety_gate: true       # Run VERIFY after Phase 2 completes
```

`oscillation_tolerance` is read from the existing `scoring:` section — not duplicated here.

## PREFLIGHT Constraints

Validated alongside existing scoring constraints. On violation, log WARNING and use plugin defaults:

- `max_iterations` must be >= 3 and <= 20
- `plateau_threshold` must be >= 0 and <= 10
- `plateau_patience` must be >= 1 and <= 5
- `target_score` must be >= `pass_threshold` and <= 100
- `safety_gate` must be boolean

## Interaction with Existing Config

- `max_review_cycles`: becomes the Phase 2 **inner** cap per convergence iteration (how many review agent re-dispatches within one iteration). Defaults to 1 — the convergence engine handles the outer loop.
- `max_test_cycles`: stays as-is — Phase 1 inner cap managed by pl-500.
- `total_retries_max`: still applies globally. Each convergence iteration increments `total_retries`.

## State Schema

The convergence engine reads and writes `state.json.convergence`:

```json
{
  "convergence": {
    "phase": "correctness",
    "phase_iterations": 0,
    "total_iterations": 0,
    "plateau_count": 0,
    "last_score_delta": 0,
    "convergence_state": "IMPROVING",
    "phase_history": [],
    "safety_gate_passed": false,
    "unfixable_findings": []
  }
}
```

See `state-schema.md` for full field documentation.

## Retrospective Auto-Tuning

The retrospective agent (pl-700) can adjust convergence parameters based on historical patterns:

- If runs consistently plateau at iteration N, lower `max_iterations` toward N+2
- If runs frequently hit 100 on iteration 2, lower `plateau_patience` to 1
- If `plateau_threshold: 2` causes premature convergence (scores that could still improve), raise to 3-4
- Track `avg_iterations_to_converge` in `agent-effectiveness-schema.json`
```

Write this as the file content for `shared/convergence-engine.md`.

- [ ] **Step 2: Verify the file exists and has the expected sections**

Run: `grep -c "^##" shared/convergence-engine.md`
Expected: 8 sections (Convergence States, Two-Phase Model, Algorithm, Configuration, PREFLIGHT Constraints, Interaction with Existing Config, State Schema, Retrospective Auto-Tuning)

- [ ] **Step 3: Commit**

```bash
git add shared/convergence-engine.md
git commit -m "feat: add convergence engine shared contract"
```

---

### Task 2: Extend State Schema

**Files:**
- Modify: `shared/state-schema.md:99` (JSON block — add convergence object after score_history)
- Modify: `shared/state-schema.md:203` (Field Reference table — add convergence fields)

- [ ] **Step 1: Add convergence object to the state.json JSON example**

In `shared/state-schema.md`, after line 99 (`"score_history": [],`), add:

```json
  "convergence": {
    "phase": "correctness",
    "phase_iterations": 0,
    "total_iterations": 0,
    "plateau_count": 0,
    "last_score_delta": 0,
    "convergence_state": "IMPROVING",
    "phase_history": [],
    "safety_gate_passed": false,
    "unfixable_findings": []
  },
```

- [ ] **Step 2: Add convergence field documentation to the Field Reference table**

In `shared/state-schema.md`, after the `score_history` row (line 203), add these rows to the table:

```markdown
| `convergence` | object | Yes | Convergence engine state. Tracks two-phase iteration progress (correctness → perfection → safety gate). See `shared/convergence-engine.md` for full algorithm. Initialized at PREFLIGHT with all counters at 0. |
| `convergence.phase` | string | Yes | Current convergence phase. Valid values: `"correctness"` (Phase 1 — IMPLEMENT ↔ VERIFY), `"perfection"` (Phase 2 — IMPLEMENT ↔ REVIEW), `"safety_gate"` (final VERIFY after Phase 2). Transitions managed by the convergence engine. |
| `convergence.phase_iterations` | integer | Yes | Iteration count within the current phase. Resets to 0 on phase transition. |
| `convergence.total_iterations` | integer | Yes | Cumulative iteration count across all phases. Never resets. Feeds into `total_retries` budget — each increment also increments `total_retries`. |
| `convergence.plateau_count` | integer | Yes | Consecutive Phase 2 cycles where score improved by <= `plateau_threshold`. Resets to 0 on any improvement > `plateau_threshold`. When >= `plateau_patience`, convergence is declared. |
| `convergence.last_score_delta` | integer | Yes | Score change from the previous cycle (`current_score - previous_score`). 0 on first cycle. Used for convergence state classification. |
| `convergence.convergence_state` | string | Yes | Current convergence classification. Valid values: `"IMPROVING"` (score increasing meaningfully), `"PLATEAUED"` (score stalled — convergence declared), `"REGRESSING"` (score dropped beyond tolerance — escalate). |
| `convergence.phase_history` | array | Yes | Append-only log of completed phases. Each entry: `{ "phase": "<name>", "iterations": <int>, "outcome": "converged"\|"failed"\|"escalated", "duration_seconds": <int> }`. Used by retrospective for trend analysis. |
| `convergence.safety_gate_passed` | boolean | Yes | `true` when the final VERIFY after Phase 2 passes. `false` until then. If safety gate fails, phase transitions back to correctness and this resets to `false`. |
| `convergence.unfixable_findings` | array | Yes | Findings that survived all iterations with documented rationale. Each entry: `{ "category": "<CATEGORY-CODE>", "file": "<path>", "line": <int>, "severity": "<CRITICAL\|WARNING\|INFO>", "reason": "<why not fixed>", "options": ["<option1>", "<option2>"] }`. Populated when Phase 2 converges below target. |
```

- [ ] **Step 3: Commit**

```bash
git add shared/state-schema.md
git commit -m "feat: add convergence object to state schema"
```

---

### Task 3: Add Convergence Constraints to Scoring

**Files:**
- Modify: `shared/scoring.md:61` (add convergence constraints after oscillation_tolerance constraint)

- [ ] **Step 1: Add convergence PREFLIGHT constraints**

In `shared/scoring.md`, after line 61 (`- oscillation_tolerance must be >= 0 and <= 20`), add:

```markdown
- `convergence.max_iterations` must be >= 3 and <= 20 (below 3 defeats convergence; above 20 is runaway)
- `convergence.plateau_threshold` must be >= 0 and <= 10 (0 = any improvement counts; 10 = very loose)
- `convergence.plateau_patience` must be >= 1 and <= 5 (1 = stop at first plateau; 5 = very patient)
- `convergence.target_score` must be >= `pass_threshold` and <= 100 (cannot target below the pass bar)
```

- [ ] **Step 2: Update the `max_review_cycles` reference in verdict band derivation**

In `shared/scoring.md`, line 66, change:

```markdown
- FAIL: score < `concerns_threshold` OR any CRITICAL remaining after `max_review_cycles`
```

to:

```markdown
- FAIL: score < `concerns_threshold` OR any CRITICAL remaining after convergence exhaustion (plateau + max_iterations)
```

- [ ] **Step 3: Commit**

```bash
git add shared/scoring.md
git commit -m "feat: add convergence PREFLIGHT constraints to scoring"
```

---

### Task 4: Update Stage Contract

**Files:**
- Modify: `shared/stage-contract.md:221-305` (Stage 5 and Stage 6 sections)

- [ ] **Step 1: Add convergence engine reference to Stage 5 (VERIFY)**

In `shared/stage-contract.md`, after line 256 (`**Exit condition:** Build passes, lint passes, all tests pass.`), add:

```markdown

**Convergence role:** Stage 5 serves as Phase 1 (Correctness) of the convergence engine. The orchestrator enters Phase 1 after IMPLEMENT completes. When VERIFY passes (tests green), the convergence engine transitions to Phase 2 (Perfection → Stage 6). Stage 5 is also the safety gate — re-invoked after Phase 2 converges to catch regressions. See `shared/convergence-engine.md`.
```

- [ ] **Step 2: Update Stage 6 (REVIEW) to reference convergence engine**

In `shared/stage-contract.md`, replace the Stage 6 actions block (lines 278-290) with:

```markdown
**Actions:**
1. For each `quality_gate.batch_N` in config: dispatch all agents in the batch in parallel. Wait for batch completion before starting next batch.
2. Run `quality_gate.inline_checks` (scripts or skills).
3. Deduplicate findings by `(file, line, category)` -- keep highest severity (see `scoring.md`).
4. Score using formula: `max(0, 100 - 20*CRITICAL - 5*WARNING - 2*INFO)`.
5. Return score and findings to the orchestrator. The **convergence engine** decides whether to iterate (see `shared/convergence-engine.md`):
   - Score = `target_score` → transition to safety gate (VERIFY one more time)
   - Score improving → dispatch IMPLEMENT with findings, then REVIEW again
   - Score plateaued → declare convergence, proceed to safety gate with documented unfixables
   - Score regressing beyond `oscillation_tolerance` → escalate to user
6. **Score Oscillation Handling** — integrated into convergence engine's REGRESSING state detection. See `convergence-engine.md` algorithm.
```

- [ ] **Step 3: Update Stage 6 exit conditions**

In `shared/stage-contract.md`, replace lines 298-304 with:

```markdown
**Exit condition (converged at target):** Score = `target_score` (default 100) and safety gate passed. Proceed to Stage 7.

**Exit condition (converged below target):** Score plateaued below target. Apply score escalation ladder: 95-99 proceed quietly, 80-94 proceed with CONCERNS, 60-79 escalate, <60 recommend abort. Safety gate must still pass.

**Exit condition (FAIL):** Any CRITICAL remaining after convergence exhaustion → escalate to user.

**On fix cycle:** Convergence engine dispatches IMPLEMENT with findings, then REVIEW again. Increment `quality_cycles` (inner cap) and `convergence.total_iterations` (outer cap). See `shared/convergence-engine.md`.
```

- [ ] **Step 4: Commit**

```bash
git add shared/stage-contract.md
git commit -m "feat: update stage contract for convergence engine"
```

---

### Task 5: Update Quality Gate Agent

**Files:**
- Modify: `agents/pl-400-quality-gate.md:208-261` (sections 8 and 9)

- [ ] **Step 1: Simplify Section 8 (Aim for 100)**

In `agents/pl-400-quality-gate.md`, replace section 8 (lines 208-237) with:

```markdown
## 8. Aim for 100

The quality gate always returns ALL findings — CRITICALs, WARNINGs, and INFOs — not just blocking issues. The implementer fixes all fixable issues.

The **convergence engine** (`shared/convergence-engine.md`) decides whether to iterate based on score trajectory (improving, plateaued, or regressing). The quality gate does NOT manage fix cycles itself — it scores, returns findings, and the orchestrator's convergence engine determines the next action.

When the convergence engine declares convergence below target (PLATEAUED), document each unfixable finding:

#### Unfixed Finding: {CATEGORY-CODE}

**What:** {description of the issue with file:line reference}
**Why it wasn't fixed:** {specific reason — not "couldn't fix it". Examples: "requires changing port interface (out of scope)", "false positive from pattern matcher", "intentional trade-off documented in conventions"}
**Options:**
1. {Option A} — {trade-offs, estimated effort}
2. {Option B} — {trade-offs, estimated effort}
3. {Accept for now} — {risk assessment at current scale}

**Recommendation:** {which option and why}

For each unfixed finding, determine whether a follow-up Linear ticket should be created:
- Architectural WARNINGs: YES — create follow-up ticket
- Style INFOs: NO — document in recap only
- Performance WARNINGs: YES if in hot path, NO if cold path
```

- [ ] **Step 2: Simplify Section 9 (Fix Cycles)**

In `agents/pl-400-quality-gate.md`, replace section 9 (lines 240-261) with:

```markdown
## 9. Fix Cycles

Fix cycles are managed by the convergence engine (`shared/convergence-engine.md`), not by this agent. When the orchestrator re-invokes this gate after a fix cycle:

1. Re-run from the beginning: dispatch batches, run inline checks, deduplicate, score
2. On re-run, dispatch all batch agents again (not just the ones that found issues). Fixes may introduce new problems that other agents catch.
3. Return the full report to the orchestrator — the convergence engine evaluates the score trajectory and decides whether to iterate again.

The quality gate's `max_review_cycles` config serves as the inner cap per convergence iteration (how many re-dispatches within one iteration). The convergence engine manages the outer loop.
```

- [ ] **Step 3: Commit**

```bash
git add agents/pl-400-quality-gate.md
git commit -m "feat: simplify quality gate to delegate iteration to convergence engine"
```

---

### Task 6: Update Orchestrator — VERIFY and REVIEW Sections

**Files:**
- Modify: `agents/pl-100-orchestrator.md:558-562` (state init)
- Modify: `agents/pl-100-orchestrator.md:1066-1137` (section 8 — VERIFY)
- Modify: `agents/pl-100-orchestrator.md:1138-1257` (section 9 — REVIEW)

- [ ] **Step 1: Add convergence object to state initialization**

In `agents/pl-100-orchestrator.md`, after the existing state init fields (around line 562, after `"total_retries": 0`), add:

```json
  "convergence": {
    "phase": "correctness",
    "phase_iterations": 0,
    "total_iterations": 0,
    "plateau_count": 0,
    "last_score_delta": 0,
    "convergence_state": "IMPROVING",
    "phase_history": [],
    "safety_gate_passed": false,
    "unfixable_findings": []
  },
```

- [ ] **Step 2: Add convergence engine entry point after IMPLEMENT**

In `agents/pl-100-orchestrator.md`, at the end of section 8 (VERIFY), before the `---` delimiter at line 1136, add:

```markdown
### Convergence Engine Integration

After IMPLEMENT completes, the orchestrator enters the convergence loop defined in `shared/convergence-engine.md`. The engine coordinates Stages 5 and 6 as two phases:

1. **Enter Phase 1 (Correctness):** Dispatch VERIFY (this stage). If VERIFY passes, the engine transitions to Phase 2.
2. **Phase 1 failure:** If VERIFY fails, dispatch IMPLEMENT with failure details, then re-dispatch VERIFY. The engine tracks `convergence.phase_iterations` and `convergence.total_iterations`.
3. **Phase transition:** On VERIFY pass, set `convergence.phase = "perfection"`, reset `convergence.phase_iterations = 0`, append to `convergence.phase_history`.

Each Phase 1 iteration increments both `convergence.total_iterations` and `total_retries`. If `total_retries >= total_retries_max`, escalate regardless of convergence state.
```

- [ ] **Step 3: Rewrite section 9.3 (Fix Cycle) to use convergence engine**

In `agents/pl-100-orchestrator.md`, replace section 9.3 (lines 1210-1224) with:

```markdown
### 9.3 Convergence-Driven Fix Cycle

Fix cycles are driven by the convergence engine (`shared/convergence-engine.md`). After scoring:

1. Read `convergence.phase` (must be `"perfection"` — Phase 2)
2. Compute `delta = score - previous_score` (0 if first cycle)
3. Evaluate convergence state:
   - **Score >= `target_score`:** transition to `"safety_gate"`. Dispatch VERIFY (Stage 5) one final time.
   - **IMPROVING** (delta > `plateau_threshold`): reset `plateau_count`, send ALL findings to `pl-300-implementer`, increment `convergence.phase_iterations` and `convergence.total_iterations` and `quality_cycles` and `total_retries`, re-dispatch REVIEW.
   - **PLATEAUED** (`plateau_count >= plateau_patience`): apply score escalation ladder (section 9.4), document unfixable findings in `convergence.unfixable_findings`, transition to `"safety_gate"`.
   - **REGRESSING** (delta < 0, abs(delta) > `oscillation_tolerance`): escalate immediately.
4. On transition to `"safety_gate"`: dispatch VERIFY (Stage 5 — full build + lint + tests). If VERIFY passes, set `convergence.safety_gate_passed = true`, proceed to DOCS. If VERIFY fails, transition back to `"correctness"` (Phase 1) — Phase 2 fixes broke something.

**Pre-dispatch budget check:** Before dispatching implementer, check `total_retries` against `total_retries_max`. If within 1 of max, log WARNING in stage notes.

If convergence exhausted (`total_iterations >= max_iterations`) and score still < target:
> "Pipeline converged at score {score}/{target_score} after {total_iterations} iterations. {unfixable_count} unfixable findings documented. Proceeding per score escalation ladder."
```

- [ ] **Step 4: Rewrite section 9.5 (Oscillation Detection) as convergence reference**

In `agents/pl-100-orchestrator.md`, replace section 9.5 (lines 1237-1251) with:

```markdown
### 9.5 Oscillation Detection (via Convergence Engine)

Oscillation detection is now part of the convergence engine's REGRESSING state (see `shared/convergence-engine.md`). The orchestrator:

1. After each REVIEW scoring, computes `delta = score_current - score_previous` using `score_history[]`
2. If `delta < 0` and `abs(delta) > oscillation_tolerance`: set `convergence.convergence_state = "REGRESSING"`, escalate to user
3. If `delta < 0` and `abs(delta) <= oscillation_tolerance`: allow one more cycle (plateau_count increments). Second consecutive dip escalates.

**Interaction with max_iterations:** Oscillation tolerance does NOT extend beyond `convergence.max_iterations`. If `total_iterations >= max_iterations`, the run ends regardless of oscillation state.

Track convergence state in stage notes: `"Convergence: {state} (iteration {N}/{max}, delta {delta}, plateau {plateau_count}/{patience})"`.
```

- [ ] **Step 5: Update state counters section**

In `agents/pl-100-orchestrator.md`, find the counter increment section (around line 1566-1572 where `total_retries` is incremented). Add after the existing counter list:

```markdown
- Update convergence fields (`convergence.phase_iterations`, `convergence.total_iterations`, `convergence.plateau_count`, `convergence.convergence_state`, `convergence.last_score_delta`)
```

And update the escalation message to include convergence state:

```markdown
> "Pipeline exhausted total retry budget ({total_retries}/{total_retries_max}). Convergence: phase={convergence.phase}, iterations={convergence.total_iterations}, state={convergence.convergence_state}. Individual counters: quality={quality_cycles}, test={test_cycles}, verify={verify_fix_count}, validation={validation_retries}. How should I proceed?"
```

- [ ] **Step 6: Commit**

```bash
git add agents/pl-100-orchestrator.md
git commit -m "feat: integrate convergence engine into orchestrator VERIFY and REVIEW stages"
```

---

### Task 7: Update Test Gate Agent (Minimal)

**Files:**
- Modify: `agents/pl-500-test-gate.md:243-245` (section 7 verdict)

- [ ] **Step 1: Add convergence context note**

In `agents/pl-500-test-gate.md`, after section 8 (Fix Cycles, around line 258), add:

```markdown
### Convergence Engine Context

The test gate operates within Phase 1 (Correctness) of the convergence engine (`shared/convergence-engine.md`). The test gate's PASS/FAIL verdict is consumed by the convergence engine to determine phase transitions:
- **PASS:** Convergence engine transitions from Phase 1 to Phase 2 (perfection)
- **FAIL:** Convergence engine keeps Phase 1 active, dispatches IMPLEMENT for fixes

The test gate's `max_test_cycles` remains the inner cap. The convergence engine manages the outer iteration budget via `convergence.total_iterations`.
```

- [ ] **Step 2: Commit**

```bash
git add agents/pl-500-test-gate.md
git commit -m "feat: add convergence engine context to test gate"
```

---

### Task 8: Add Convergence Config to All 21 Pipeline Config Templates

**Files:**
- Modify: `modules/frameworks/angular/pipeline-config-template.md`
- Modify: `modules/frameworks/aspnet/pipeline-config-template.md`
- Modify: `modules/frameworks/axum/pipeline-config-template.md`
- Modify: `modules/frameworks/django/pipeline-config-template.md`
- Modify: `modules/frameworks/embedded/pipeline-config-template.md`
- Modify: `modules/frameworks/express/pipeline-config-template.md`
- Modify: `modules/frameworks/fastapi/pipeline-config-template.md`
- Modify: `modules/frameworks/gin/pipeline-config-template.md`
- Modify: `modules/frameworks/go-stdlib/pipeline-config-template.md`
- Modify: `modules/frameworks/jetpack-compose/pipeline-config-template.md`
- Modify: `modules/frameworks/k8s/pipeline-config-template.md`
- Modify: `modules/frameworks/kotlin-multiplatform/pipeline-config-template.md`
- Modify: `modules/frameworks/nestjs/pipeline-config-template.md`
- Modify: `modules/frameworks/nextjs/pipeline-config-template.md`
- Modify: `modules/frameworks/react/pipeline-config-template.md`
- Modify: `modules/frameworks/spring/pipeline-config-template.md`
- Modify: `modules/frameworks/svelte/pipeline-config-template.md`
- Modify: `modules/frameworks/sveltekit/pipeline-config-template.md`
- Modify: `modules/frameworks/swiftui/pipeline-config-template.md`
- Modify: `modules/frameworks/vapor/pipeline-config-template.md`
- Modify: `modules/frameworks/vue/pipeline-config-template.md`

- [ ] **Step 1: Add convergence section to all 21 templates**

In each `pipeline-config-template.md`, after the commented-out `# scoring:` section at the end of the file, add:

```markdown
# Convergence engine (defaults work for most projects)
# convergence:
#   max_iterations: 8       # Hard safety valve across both phases (3-20)
#   plateau_threshold: 2    # Score delta <= this = "no progress" (0-10)
#   plateau_patience: 2     # Consecutive plateaus before convergence (1-5)
#   target_score: 100       # Score target (80-100, must be >= pass_threshold)
#   safety_gate: true       # Run VERIFY after Phase 2
```

Use a script to add this to all 21 files at once:

```bash
for f in modules/frameworks/*/pipeline-config-template.md; do
  # Only append if not already present
  if ! grep -q "convergence:" "$f"; then
    printf '\n# Convergence engine (defaults work for most projects)\n# convergence:\n#   max_iterations: 8       # Hard safety valve across both phases (3-20)\n#   plateau_threshold: 2    # Score delta <= this = "no progress" (0-10)\n#   plateau_patience: 2     # Consecutive plateaus before convergence (1-5)\n#   target_score: 100       # Score target (80-100, must be >= pass_threshold)\n#   safety_gate: true       # Run VERIFY after Phase 2\n' >> "$f"
  fi
done
```

- [ ] **Step 2: Verify all 21 templates have the section**

Run: `for f in modules/frameworks/*/pipeline-config-template.md; do grep -q "convergence:" "$f" && echo "OK: $f" || echo "MISSING: $f"; done`
Expected: 21 "OK" lines, 0 "MISSING"

- [ ] **Step 3: Commit**

```bash
git add modules/frameworks/*/pipeline-config-template.md
git commit -m "feat: add convergence config section to all 21 pipeline config templates"
```

---

### Task 9: Update Agent Effectiveness Schema

**Files:**
- Modify: `shared/learnings/agent-effectiveness-schema.json`

- [ ] **Step 1: Add convergence metrics to the schema**

In `shared/learnings/agent-effectiveness-schema.json`, add a new top-level key after `agent_effectiveness`:

```json
  "convergence_metrics": {
    "total_runs_with_convergence": "integer — runs that used the convergence engine",
    "avg_iterations_to_converge": "float — average total_iterations across runs",
    "avg_phase1_iterations": "float — average iterations in correctness phase",
    "avg_phase2_iterations": "float — average iterations in perfection phase",
    "perfect_score_rate": "float — ratio of runs reaching target_score exactly",
    "plateau_rate": "float — ratio of runs that converged via plateau (not target)",
    "safety_gate_failure_rate": "float — ratio of runs where safety gate failed",
    "avg_final_score": "float — average score at convergence"
  },
```

And add a convergence-specific improvement trigger in `_improvement_triggers`:

```json
    "plateau_rate > 0.5 for 5+ runs": "CONVERGENCE-TUNE: raise plateau_patience or lower plateau_threshold",
    "safety_gate_failure_rate > 0.2 for 5+ runs": "CONVERGENCE-TUNE: consider running targeted tests in Phase 2",
    "avg_iterations_to_converge > 6 for 5+ runs": "CONVERGENCE-TUNE: lower max_iterations, investigate recurring findings"
```

- [ ] **Step 2: Commit**

```bash
git add shared/learnings/agent-effectiveness-schema.json
git commit -m "feat: add convergence metrics to agent effectiveness schema"
```

---

### Task 10: Update CLAUDE.md

**Files:**
- Modify: `CLAUDE.md:61-70` (key entry points table)
- Modify: `CLAUDE.md` (key conventions section, PREFLIGHT constraints)

- [ ] **Step 1: Add convergence engine to key entry points table**

In `CLAUDE.md`, after the "Token management" row (line 70), add:

```markdown
| Convergence loop | `shared/convergence-engine.md` (two-phase iteration, plateau detection) |
```

- [ ] **Step 2: Add convergence to PREFLIGHT constraints**

In `CLAUDE.md`, find the PREFLIGHT constraints list (the line that starts with `- PREFLIGHT constraints — scoring:`). Append to the end of that bullet:

Add a new bullet after the scoring constraints:
```markdown
- PREFLIGHT constraints — convergence: `max_iterations` 3-20, `plateau_threshold` 0-10, `plateau_patience` 1-5, `target_score` >= `pass_threshold` and <= 100.
```

- [ ] **Step 3: Update the key conventions mention of fix cycles**

In `CLAUDE.md`, find the scoring description (`**Scoring** (scoring.md)`). Update the `max_review_cycles` mention to reference convergence:

Find:
```
Oscillation tolerance: configurable (default 5 pts).
```

Add after it:
```
Convergence engine: two-phase iteration (correctness → perfection → safety gate) replaces hard-capped fix cycles. See `shared/convergence-engine.md`.
```

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: add convergence engine references to CLAUDE.md"
```

---

### Task 11: Write Contract Tests for Convergence Engine

**Files:**
- Create: `tests/contract/convergence-engine.bats`

- [ ] **Step 1: Write the contract test file**

```bash
#!/usr/bin/env bats
# Contract tests: shared/convergence-engine.md — validates the convergence engine document.

load '../helpers/test-helpers'

ENGINE="$PLUGIN_ROOT/shared/convergence-engine.md"

# ---------------------------------------------------------------------------
# 1. Document exists
# ---------------------------------------------------------------------------
@test "convergence-engine: document exists" {
  [[ -f "$ENGINE" ]]
}

# ---------------------------------------------------------------------------
# 2. Three convergence states documented: IMPROVING, PLATEAUED, REGRESSING
# ---------------------------------------------------------------------------
@test "convergence-engine: three convergence states documented" {
  grep -q "IMPROVING" "$ENGINE" || fail "IMPROVING state not documented"
  grep -q "PLATEAUED" "$ENGINE" || fail "PLATEAUED state not documented"
  grep -q "REGRESSING" "$ENGINE" || fail "REGRESSING state not documented"
}

# ---------------------------------------------------------------------------
# 3. Two-phase model documented: correctness, perfection, safety_gate
# ---------------------------------------------------------------------------
@test "convergence-engine: two-phase model with safety gate documented" {
  grep -q "Phase 1.*Correctness\|Correctness.*Phase 1\|correctness" "$ENGINE" \
    || fail "Phase 1 (Correctness) not documented"
  grep -q "Phase 2.*Perfection\|Perfection.*Phase 2\|perfection" "$ENGINE" \
    || fail "Phase 2 (Perfection) not documented"
  grep -q "safety_gate\|Safety Gate\|safety gate" "$ENGINE" \
    || fail "Safety gate not documented"
}

# ---------------------------------------------------------------------------
# 4. Algorithm documented with decide_next function
# ---------------------------------------------------------------------------
@test "convergence-engine: algorithm documented with decide_next" {
  grep -q "decide_next" "$ENGINE" || fail "decide_next function not documented"
}

# ---------------------------------------------------------------------------
# 5. Configuration section with all 5 parameters
# ---------------------------------------------------------------------------
@test "convergence-engine: configuration documents all 5 parameters" {
  local params=(max_iterations plateau_threshold plateau_patience target_score safety_gate)
  for param in "${params[@]}"; do
    grep -q "$param" "$ENGINE" \
      || fail "Configuration parameter $param not documented"
  done
}

# ---------------------------------------------------------------------------
# 6. PREFLIGHT constraints documented with ranges
# ---------------------------------------------------------------------------
@test "convergence-engine: PREFLIGHT constraints with valid ranges" {
  grep -q "3.*20\|>= 3.*<= 20" "$ENGINE" \
    || fail "max_iterations range 3-20 not documented"
  grep -q "0.*10\|>= 0.*<= 10" "$ENGINE" \
    || fail "plateau_threshold range 0-10 not documented"
  grep -q "1.*5\|>= 1.*<= 5" "$ENGINE" \
    || fail "plateau_patience range 1-5 not documented"
}

# ---------------------------------------------------------------------------
# 7. State schema section references convergence object
# ---------------------------------------------------------------------------
@test "convergence-engine: state schema section documents convergence object" {
  grep -q "state.json.convergence\|state\.json.*convergence\|convergence.*state" "$ENGINE" \
    || fail "State schema convergence object not documented"
}

# ---------------------------------------------------------------------------
# 8. Interaction with existing config documented
# ---------------------------------------------------------------------------
@test "convergence-engine: interaction with max_review_cycles and max_test_cycles documented" {
  grep -q "max_review_cycles" "$ENGINE" \
    || fail "Interaction with max_review_cycles not documented"
  grep -q "max_test_cycles" "$ENGINE" \
    || fail "Interaction with max_test_cycles not documented"
}

# ---------------------------------------------------------------------------
# 9. Phase 2 skips VERIFY explicitly stated
# ---------------------------------------------------------------------------
@test "convergence-engine: Phase 2 skips VERIFY documented" {
  grep -qi "phase 2 skips verify\|skips verify.*iteration\|only review scores" "$ENGINE" \
    || fail "Phase 2 skipping VERIFY not documented"
}

# ---------------------------------------------------------------------------
# 10. Safety gate failure routes back to correctness
# ---------------------------------------------------------------------------
@test "convergence-engine: safety gate failure transitions to correctness" {
  grep -qi "safety.gate.*fail.*correctness\|back to.*correctness\|transition.*back.*correctness" "$ENGINE" \
    || fail "Safety gate failure -> correctness transition not documented"
}
```

- [ ] **Step 2: Run the contract tests**

Run: `./tests/lib/bats-core/bin/bats tests/contract/convergence-engine.bats`
Expected: 10 tests, all passing

- [ ] **Step 3: Commit**

```bash
git add tests/contract/convergence-engine.bats
git commit -m "test: add convergence engine contract tests"
```

---

### Task 12: Write Contract Tests for State Schema Convergence Fields

**Files:**
- Modify: `tests/contract/state-schema.bats` (add convergence field tests)

- [ ] **Step 1: Add convergence field tests to state-schema.bats**

Append to the end of `tests/contract/state-schema.bats`:

```bash
# ---------------------------------------------------------------------------
# N. convergence object documented in state schema
# ---------------------------------------------------------------------------
@test "state-schema: convergence object documented" {
  grep -q '"convergence"' "$STATE_SCHEMA" \
    || fail "convergence object not found in state schema"
}

# ---------------------------------------------------------------------------
# N+1. convergence required fields documented
# ---------------------------------------------------------------------------
@test "state-schema: convergence fields documented (phase phase_iterations total_iterations plateau_count convergence_state)" {
  local fields=(phase phase_iterations total_iterations plateau_count convergence_state safety_gate_passed unfixable_findings)
  for field in "${fields[@]}"; do
    grep -q "convergence\.${field}\|convergence.*${field}" "$STATE_SCHEMA" \
      || fail "convergence field $field not documented in state-schema.md"
  done
}

# ---------------------------------------------------------------------------
# N+2. convergence phase valid values documented
# ---------------------------------------------------------------------------
@test "state-schema: convergence phase valid values correctness perfection safety_gate documented" {
  grep -q '"correctness"' "$STATE_SCHEMA" || fail 'convergence phase "correctness" not documented'
  grep -q '"perfection"' "$STATE_SCHEMA"  || fail 'convergence phase "perfection" not documented'
  grep -q '"safety_gate"' "$STATE_SCHEMA" || fail 'convergence phase "safety_gate" not documented'
}
```

- [ ] **Step 2: Run the state-schema tests**

Run: `./tests/lib/bats-core/bin/bats tests/contract/state-schema.bats`
Expected: All existing tests + 3 new tests pass

- [ ] **Step 3: Commit**

```bash
git add tests/contract/state-schema.bats
git commit -m "test: add convergence fields to state schema contract tests"
```

---

### Task 13: Write Scenario Tests for Convergence Behavior

**Files:**
- Create: `tests/scenario/convergence-engine.bats`

- [ ] **Step 1: Write convergence scenario tests**

```bash
#!/usr/bin/env bats
# Scenario tests: convergence engine behavior in the orchestrator

load '../helpers/test-helpers'

ORCHESTRATOR="$PLUGIN_ROOT/agents/pl-100-orchestrator.md"
ENGINE="$PLUGIN_ROOT/shared/convergence-engine.md"
QUALITY_GATE="$PLUGIN_ROOT/agents/pl-400-quality-gate.md"
TEST_GATE="$PLUGIN_ROOT/agents/pl-500-test-gate.md"
STAGE_CONTRACT="$PLUGIN_ROOT/shared/stage-contract.md"

# ---------------------------------------------------------------------------
# 1. Orchestrator references convergence engine
# ---------------------------------------------------------------------------
@test "convergence-scenario: orchestrator references convergence-engine.md" {
  grep -q "convergence-engine.md" "$ORCHESTRATOR" \
    || fail "Orchestrator does not reference convergence-engine.md"
}

# ---------------------------------------------------------------------------
# 2. Orchestrator initializes convergence state
# ---------------------------------------------------------------------------
@test "convergence-scenario: orchestrator initializes convergence object in state" {
  grep -q '"convergence"' "$ORCHESTRATOR" \
    || fail "Orchestrator does not initialize convergence object"
  grep -q '"phase".*"correctness"' "$ORCHESTRATOR" \
    || fail "Orchestrator does not set initial phase to correctness"
}

# ---------------------------------------------------------------------------
# 3. Quality gate delegates iteration to convergence engine
# ---------------------------------------------------------------------------
@test "convergence-scenario: quality gate delegates fix cycles to convergence engine" {
  grep -q "convergence engine" "$QUALITY_GATE" \
    || fail "Quality gate does not reference convergence engine"
  # Quality gate should NOT manage cycles itself anymore
  ! grep -q "The fix-and-rescore cycle continues until" "$QUALITY_GATE" \
    || fail "Quality gate still contains old fix-cycle management language"
}

# ---------------------------------------------------------------------------
# 4. Test gate documents convergence context
# ---------------------------------------------------------------------------
@test "convergence-scenario: test gate documents Phase 1 convergence role" {
  grep -qi "phase 1\|convergence" "$TEST_GATE" \
    || fail "Test gate does not document its Phase 1 convergence role"
}

# ---------------------------------------------------------------------------
# 5. Stage contract references convergence for both VERIFY and REVIEW
# ---------------------------------------------------------------------------
@test "convergence-scenario: stage contract references convergence in VERIFY and REVIEW" {
  # Check Stage 5 section
  local stage5
  stage5=$(sed -n '/### Stage 5: VERIFY/,/### Stage 6/p' "$STAGE_CONTRACT")
  echo "$stage5" | grep -qi "convergence" \
    || fail "Stage 5 does not reference convergence"

  # Check Stage 6 section
  local stage6
  stage6=$(sed -n '/### Stage 6: REVIEW/,/### Stage 7/p' "$STAGE_CONTRACT")
  echo "$stage6" | grep -qi "convergence" \
    || fail "Stage 6 does not reference convergence"
}

# ---------------------------------------------------------------------------
# 6. Safety gate is documented as re-invoking VERIFY
# ---------------------------------------------------------------------------
@test "convergence-scenario: safety gate re-invokes VERIFY" {
  grep -qi "safety.*gate.*verify\|safety_gate.*verify" "$ENGINE" \
    || fail "Safety gate re-invoking VERIFY not documented"
  grep -qi "safety.*gate.*fail.*correctness\|back to.*correctness" "$ENGINE" \
    || fail "Safety gate failure routing to correctness not documented"
}

# ---------------------------------------------------------------------------
# 7. All 21 pipeline config templates have convergence section
# ---------------------------------------------------------------------------
@test "convergence-scenario: all 21 pipeline config templates have convergence section" {
  local count=0
  local missing=()
  for f in "$PLUGIN_ROOT"/modules/frameworks/*/pipeline-config-template.md; do
    if grep -q "convergence:" "$f"; then
      ((count++))
    else
      missing+=("$(basename "$(dirname "$f")")")
    fi
  done
  [[ ${#missing[@]} -eq 0 ]] \
    || fail "Missing convergence section in: ${missing[*]}"
  [[ $count -ge 21 ]] \
    || fail "Expected >= 21 templates with convergence, got $count"
}

# ---------------------------------------------------------------------------
# 8. Convergence config has all 5 parameters in templates
# ---------------------------------------------------------------------------
@test "convergence-scenario: config templates document all convergence parameters" {
  local params=(max_iterations plateau_threshold plateau_patience target_score safety_gate)
  # Check just one template — Task 8 ensures all 21 are identical
  local template="$PLUGIN_ROOT/modules/frameworks/spring/pipeline-config-template.md"
  for param in "${params[@]}"; do
    grep -q "$param" "$template" \
      || fail "Parameter $param missing from spring pipeline-config-template.md"
  done
}
```

- [ ] **Step 2: Run the scenario tests**

Run: `./tests/lib/bats-core/bin/bats tests/scenario/convergence-engine.bats`
Expected: 8 tests, all passing

- [ ] **Step 3: Commit**

```bash
git add tests/scenario/convergence-engine.bats
git commit -m "test: add convergence engine scenario tests"
```

---

### Task 14: Update Structural Validation

**Files:**
- Modify: `tests/validate-plugin.sh` (add check 33: convergence engine exists with required sections)

- [ ] **Step 1: Add structural check for convergence engine**

In `tests/validate-plugin.sh`, after the last check (check 32), add:

```bash
# ── CONVERGENCE ENGINE ──────────────────────────────────────────────────────
check33_fail=0
if [[ ! -f "$PLUGIN_ROOT/shared/convergence-engine.md" ]]; then
  echo "  FAIL: shared/convergence-engine.md does not exist"
  check33_fail=1
else
  for section in "Convergence States" "Two-Phase Model" "Algorithm" "Configuration" "PREFLIGHT Constraints"; do
    if ! grep -q "$section" "$PLUGIN_ROOT/shared/convergence-engine.md"; then
      echo "  FAIL: convergence-engine.md missing section: $section"
      check33_fail=1
    fi
  done
fi
check "Convergence engine exists with required sections" "$check33_fail"

# ── Check 34: pipeline config templates have convergence ─────────────────
check34_fail=0
for f in "$PLUGIN_ROOT"/modules/frameworks/*/pipeline-config-template.md; do
  if ! grep -q "convergence:" "$f"; then
    echo "  FAIL: $(basename "$(dirname "$f")")/pipeline-config-template.md missing convergence section"
    check34_fail=1
  fi
done
check "All pipeline config templates have convergence section" "$check34_fail"
```

Also update the total check count at the top of the file (increment by 2) and in `CLAUDE.md` (structural check count references). Update the final summary line accordingly.

- [ ] **Step 2: Run structural validation**

Run: `./tests/validate-plugin.sh`
Expected: 34 checks, all passing

- [ ] **Step 3: Commit**

```bash
git add tests/validate-plugin.sh
git commit -m "test: add convergence engine structural validation checks"
```

---

### Task 15: Run Full Test Suite and Fix Any Failures

**Files:**
- Potentially any file modified in previous tasks

- [ ] **Step 1: Run the full test suite**

Run: `./tests/run-all.sh`
Expected: All tests pass (structural 34/34 + unit + contract + scenario)

- [ ] **Step 2: If any tests fail, fix the issues**

Read the failure output, identify the root cause, fix the file, and re-run.

- [ ] **Step 3: Final commit if fixes were needed**

```bash
git add -A
git commit -m "fix: resolve test failures from convergence engine integration"
```

- [ ] **Step 4: Run the full suite one more time to confirm**

Run: `./tests/run-all.sh`
Expected: All tests pass, 0 failures
