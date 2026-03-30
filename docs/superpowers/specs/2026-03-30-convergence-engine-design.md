# Convergence Engine Design

**Date:** 2026-03-30
**Status:** Draft
**Author:** Denis Sajnar + Claude

## Summary

Replace the pipeline's hard-capped fix cycle loops (`max_review_cycles`, `max_test_cycles`) with a convergence-driven iteration engine inspired by Ralph Loop's self-referential iteration philosophy. The engine coordinates VERIFY and REVIEW stages as a two-phase convergence loop that aims for a perfect score of 100, stopping only when the score plateaus or the target is reached.

## Motivation

The current pipeline accepts PASS at score >= 80 and moves on, with fix cycles capped at `max_review_cycles: 2`. This exits too early — a score trajectory of 60 → 85 → 92 (clearly improving) hits the same cap as 85 → 86 → 86 (plateaued). The convergence engine replaces hard caps with plateau detection, letting improving runs continue while correctly stopping stalled ones.

Ralph Loop's key insight applies: iterate with the same goal, see previous work, converge toward the target. The literal Ralph mechanism (stop hook + state file) doesn't fit the pipeline's agent dispatch architecture, but the philosophy does.

## Design

### Core Concept

A new shared contract (`shared/convergence-engine.md`) that answers one question after every VERIFY or REVIEW dispatch: **"Should we iterate again, or have we converged?"**

The orchestrator calls the convergence engine after every stage dispatch. The engine evaluates the result and returns the next action.

### Convergence States

| State | Meaning | Action |
|-------|---------|--------|
| `IMPROVING` | Score increased by > `plateau_threshold` | Continue iterating |
| `PLATEAUED` | Score unchanged or improved by <= `plateau_threshold` for `plateau_patience` consecutive cycles | Declare convergence, stop iterating |
| `REGRESSING` | Score decreased beyond `oscillation_tolerance` | Escalate immediately |

### Two-Phase Model

| Phase | Loop | Goal | Convergence signal |
|-------|------|------|--------------------|
| **Phase 1: Correctness** | IMPLEMENT <-> VERIFY | Tests green | All tests pass (binary) |
| **Phase 2: Perfection** | IMPLEMENT <-> REVIEW | Score = `target_score` | Score = target, OR `PLATEAUED` |
| **Safety gate** | VERIFY (one shot) | No regressions | Tests still pass after Phase 2 |

Phase 2 skips VERIFY on each iteration (efficiency win — no test suite overhead for fixing an INFO about a missing docstring). The safety gate at the end catches regressions from Phase 2 fixes.

If the safety gate fails, the engine transitions back to Phase 1 (correctness first, then perfection again).

### Algorithm

```
FUNCTION decide_next(state.convergence, verify_result, review_result):

  MATCH phase:

    "correctness":
      IF verify_result.tests_pass AND verify_result.analysis_pass:
        -> transition to "perfection", reset phase_iterations
      ELSE:
        -> increment phase_iterations, increment total_iterations
        -> IF total_iterations >= max_iterations: ESCALATE
        -> ELSE: dispatch IMPLEMENT with failure details, then VERIFY again
        (Phase 1 inner cap is max_test_cycles, managed by pl-500.
         The convergence engine tracks total_iterations across both phases.)

    "perfection":
      score = review_result.score
      delta = score - previous_score  (0 if first cycle)

      IF score >= target_score:
        -> transition to "safety_gate"

      ELSE IF delta < 0 AND abs(delta) > oscillation_tolerance:
        -> convergence_state = "REGRESSING", ESCALATE

      ELSE IF delta <= plateau_threshold:
        -> plateau_count += 1
        -> IF plateau_count >= plateau_patience:
            convergence_state = "PLATEAUED"
            -> apply score escalation ladder (existing orchestrator 9.4)
            -> proceed to "safety_gate" with documented unfixables
        -> ELSE: dispatch IMPLEMENT with findings, then REVIEW again

      ELSE:
        -> plateau_count = 0, convergence_state = "IMPROVING"
        -> dispatch IMPLEMENT with findings, then REVIEW again

    "safety_gate":
      IF verify_result.tests_pass:
        -> safety_gate_passed = true
        -> CONVERGED, proceed to DOCS
      ELSE:
        -> transition back to "correctness"
```

### Key Behaviors

- **Phase 2 skips VERIFY** per iteration. Only REVIEW scores. The safety gate catches regressions at the end.
- **Plateau detection is cumulative.** Two consecutive "no meaningful improvement" cycles trigger convergence. A meaningful jump resets the counter.
- **Safety gate failure loops to Phase 1**, not Phase 2. If Phase 2 fixes broke tests, correctness must be restored before perfection resumes.
- **Score escalation ladder** (orchestrator 9.4) applies when Phase 2 converges below target. Score 95-99 proceeds quietly; 80-94 proceeds with CONCERNS; below 80 escalates to user.
- **total_retries** increments on every iteration across both phases. The global budget still applies.

## State Schema Extensions

New `convergence` object in `state.json`:

```json
{
  "convergence": {
    "phase": "correctness",
    "phase_iterations": 0,
    "total_iterations": 0,
    "plateau_count": 0,
    "last_score_delta": 0,
    "convergence_state": "IMPROVING",
    "phase_history": [
      {
        "phase": "correctness",
        "iterations": 3,
        "outcome": "converged",
        "duration_seconds": 45
      }
    ],
    "safety_gate_passed": false,
    "unfixable_findings": []
  }
}
```

**Field semantics:**

- `phase`: `"correctness"` | `"perfection"` | `"safety_gate"` — current phase
- `phase_iterations`: resets to 0 on phase transition
- `total_iterations`: never resets, feeds into `total_retries` budget
- `plateau_count`: consecutive cycles with improvement <= `plateau_threshold`. Resets on meaningful improvement.
- `convergence_state`: `"IMPROVING"` | `"PLATEAUED"` | `"REGRESSING"`
- `phase_history`: append-only log for retrospective analysis
- `unfixable_findings`: findings that survived all iterations, each entry: `{ "category": "ARCH-001", "file": "path", "line": 42, "severity": "INFO", "reason": "intentional trade-off — extracting further would scatter related test fixtures", "options": ["accept", "follow-up ticket"] }`

**Relationship to existing counters:** `test_cycles` and `quality_cycles` still exist — used by pl-500 and pl-400 internally. The convergence engine's `total_iterations` is the outer loop counter.

## Configuration

New `convergence:` section in both `pipeline-config.md` and `dev-pipeline.local.md`:

```yaml
convergence:
  max_iterations: 8
  plateau_threshold: 2
  plateau_patience: 2
  target_score: 100
  safety_gate: true
```

**Parameter resolution:** `pipeline-config.md` > `dev-pipeline.local.md` > plugin defaults.

**PREFLIGHT constraints:**

| Parameter | Range | Rationale |
|-----------|-------|-----------|
| `max_iterations` | 3-20 | Below 3 defeats the purpose; above 20 is runaway |
| `plateau_threshold` | 0-10 | 0 = any improvement counts; 10 = very loose |
| `plateau_patience` | 1-5 | 1 = stop at first plateau; 5 = very patient |
| `target_score` | 80-100 | Cannot be below `pass_threshold` |
| `safety_gate` | boolean | — |

**Interaction with existing config:**

- `max_review_cycles` becomes the Phase 2 inner cap per iteration (how many review agent re-dispatches within one convergence iteration). Defaults to 1 when convergence is active — the convergence engine handles the outer loop.
- `max_test_cycles` stays as-is — Phase 1 inner cap.
- `oscillation_tolerance` stays in the existing `scoring:` section of `pipeline-config.md` (not duplicated into `convergence:`). The convergence engine reads it from there.
- `total_retries_max` still applies globally.

**Retrospective auto-tuning:** pl-700 can adjust `plateau_threshold` and `plateau_patience` based on historical convergence patterns.

## File Changes

| File | Change | Scope |
|------|--------|-------|
| `shared/convergence-engine.md` | **NEW** — core contract | ~200 lines |
| `shared/state-schema.md` | Add `convergence` object | ~30 lines |
| `shared/scoring.md` | Add convergence PREFLIGHT constraints | ~10 lines |
| `agents/pl-100-orchestrator.md` | Rewrite sections 8+9 to use convergence engine | ~100 lines changed |
| `agents/pl-400-quality-gate.md` | Simplify section 8 (aim for 100) — gate scores and returns, engine decides whether to iterate | ~30 lines changed |
| `agents/pl-500-test-gate.md` | Minimal — test gate returns PASS/FAIL, engine wraps dispatch | ~5 lines changed |
| `shared/stage-contract.md` | Update Stage 5+6 to reference convergence engine | ~20 lines |
| `modules/frameworks/*/pipeline-config-template.md` | Add `convergence:` section (21 templates) | ~7 lines each |
| `shared/learnings/` schema | Add convergence metrics to `agent-effectiveness-schema.json` | ~15 lines |
| `CLAUDE.md` | Add convergence engine to key entry points, conventions | ~10 lines |
| `tests/` | New test files for convergence logic | ~3 files |

**Files NOT changed:** All 10 review agents, pl-300-implementer, pl-310-scaffolder, pl-350-docs-generator, pl-600-pr-builder, hooks, check engine, skills. They don't know about the convergence engine.

**No stage renumbering. No new agents. No new skills.** The convergence engine is a shared contract that changes how the orchestrator decides, not how agents work.

## Testing Strategy

### Structural Tests
- `convergence-engine.md` exists with required sections
- All 21 `pipeline-config-template.md` files contain `convergence:` section
- `state-schema.md` documents `convergence` object

### Contract Tests
- Convergence state transitions: IMPROVING -> PLATEAUED after `plateau_patience` cycles
- Convergence state transitions: IMPROVING -> REGRESSING on score drop > `oscillation_tolerance`
- Phase transitions: correctness -> perfection on tests pass
- Phase transitions: perfection -> safety_gate on target reached or plateaued
- Safety gate failure routes back to correctness
- PREFLIGHT constraint validation for all convergence parameters

### Scenario Tests
- Full convergence to 100: score trajectory 60 -> 82 -> 94 -> 100
- Plateau at 96: score trajectory 60 -> 85 -> 94 -> 96 -> 96 -> converge
- Regression escalation: score trajectory 60 -> 85 -> 78 -> escalate
- Safety gate failure: Phase 2 fixes break tests -> back to Phase 1 -> re-converge
- Global retry budget exhaustion during convergence
