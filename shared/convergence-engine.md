# Convergence Engine

This document defines the convergence-driven iteration engine that replaces hard-capped fix cycle loops with plateau detection. The orchestrator (`pl-100-orchestrator`) calls the convergence engine after every VERIFY or REVIEW dispatch to decide: **iterate again, or declare convergence?**

The engine coordinates Stages 4-6 (IMPLEMENT, VERIFY, REVIEW) as a two-phase convergence loop targeting a perfect score of 100, stopping when the target is reached or the score plateaus.

## Convergence States

| State | Meaning | Action |
|-------|---------|--------|
| `IMPROVING` | Score increased by > `plateau_threshold` | Continue iterating |
| `PLATEAUED` | Score unchanged or improved by <= `plateau_threshold` for `plateau_patience` consecutive cycles | Declare convergence, stop iterating |
| `REGRESSING` | Score decreased beyond `oscillation_tolerance` | Escalate immediately |

State transitions:
- `IMPROVING` -> `IMPROVING`: meaningful improvement continues
- `IMPROVING` -> `PLATEAUED`: `plateau_patience` consecutive sub-threshold cycles
- `IMPROVING` -> `REGRESSING`: score drop exceeds `oscillation_tolerance`
- `PLATEAUED` is terminal for the current phase (proceeds to safety gate or exits)
- `REGRESSING` is terminal (escalates to user)

## Two-Phase Model

| Phase | Loop | Goal | Convergence Signal |
|-------|------|------|--------------------|
| **Phase 1: Correctness** | IMPLEMENT <-> VERIFY | Tests green | All tests pass (binary) |
| **Phase 2: Perfection** | IMPLEMENT <-> REVIEW | Score = `target_score` | Score = target, OR `PLATEAUED` |
| **Safety Gate** | VERIFY (one shot) | No regressions | Tests still pass after Phase 2 |

Key behaviors:

- **Phase 2 skips VERIFY** per iteration. Only REVIEW scores matter. The safety gate at the end catches regressions from Phase 2 fixes.
- **Safety gate failure routes to Phase 1**, not Phase 2. If Phase 2 fixes broke tests, correctness must be restored before perfection resumes.
- **Phase 1 inner cap** is `max_test_cycles`, managed by `pl-500-test-gate`. The convergence engine tracks `total_iterations` across both phases.
- **Phase 2 inner cap** is `max_review_cycles`, managed by `pl-400-quality-gate`. When convergence is active, `max_review_cycles` defaults to 1 per convergence iteration -- the convergence engine handles the outer loop.

## Algorithm

```
FUNCTION decide_next(state.convergence, verify_result, review_result):

  MATCH phase:

    "correctness":
      IF verify_result.tests_pass AND verify_result.analysis_pass:
        -> transition to "perfection", reset phase_iterations to 0
      ELSE:
        -> increment phase_iterations, increment total_iterations
        -> IF total_iterations >= max_iterations: ESCALATE
        -> ELSE: dispatch IMPLEMENT with failure details, then VERIFY again
        (Phase 1 inner cap is max_test_cycles, managed by pl-500.
         The convergence engine tracks total_iterations across both phases.)

    "perfection":
      score = review_result.score
      delta = score - previous_score  (0 if first perfection cycle)

      IF score >= target_score:
        -> transition to "safety_gate"

      ELSE IF delta < 0 AND abs(delta) > oscillation_tolerance:
        -> convergence_state = "REGRESSING", ESCALATE

      ELSE IF delta <= plateau_threshold:
        -> plateau_count += 1
        -> IF plateau_count >= plateau_patience:
            convergence_state = "PLATEAUED"
            -> apply score escalation ladder (existing scoring sub-bands)
            -> proceed to "safety_gate" with documented unfixables
        -> ELSE:
            -> increment phase_iterations, increment total_iterations
            -> dispatch IMPLEMENT with findings, then REVIEW again

      ELSE:
        -> plateau_count = 0, convergence_state = "IMPROVING"
        -> increment phase_iterations, increment total_iterations
        -> dispatch IMPLEMENT with findings, then REVIEW again

    "safety_gate":
      IF verify_result.tests_pass:
        -> safety_gate_passed = true
        -> CONVERGED, proceed to DOCS (Stage 7)
      ELSE:
        -> transition back to "correctness", reset phase_iterations to 0
        -> increment total_iterations
```

**Global budget interaction:** Every `total_iterations` increment also increments `state.json.total_retries`. When `total_retries >= total_retries_max`, the orchestrator escalates regardless of convergence state.

**Score escalation ladder** (applies when Phase 2 converges below target):
- Score 95-99: proceed quietly to safety gate
- Score 80-94: proceed with CONCERNS verdict, findings preserved in stage notes
- Score < 80: escalate to user

## Configuration

New `convergence:` section in both `pipeline-config.md` and `dev-pipeline.local.md`:

```yaml
convergence:
  max_iterations: 8        # Total iterations across both phases
  plateau_threshold: 2     # Minimum score improvement to count as progress
  plateau_patience: 2      # Consecutive sub-threshold cycles before declaring plateau
  target_score: 100        # Score to aim for (convergence target)
  safety_gate: true        # Run VERIFY after Phase 2 to catch regressions
```

**Parameter resolution:** `pipeline-config.md` > `dev-pipeline.local.md` > plugin defaults (values shown above).

## PREFLIGHT Constraints

These constraints are enforced at PREFLIGHT. If violated, log WARNING and use plugin defaults:

| Parameter | Range | Rationale |
|-----------|-------|-----------|
| `max_iterations` | 3-20 | Below 3 defeats the purpose; above 20 is runaway |
| `plateau_threshold` | 0-10 | 0 = any improvement counts; 10 = very loose |
| `plateau_patience` | 1-5 | 1 = stop at first plateau; 5 = very patient |
| `target_score` | >= `pass_threshold` AND <= 100 | Cannot be below the passing score |
| `safety_gate` | boolean | No range constraint |

## Interaction with Existing Config

The convergence engine reads from and interacts with existing pipeline configuration parameters. It does not duplicate them.

| Existing Parameter | Location | Convergence Interaction |
|--------------------|----------|------------------------|
| `max_review_cycles` | `quality_gate:` in `pipeline-config.md` | Becomes Phase 2 inner cap per convergence iteration. Defaults to 1 when convergence is active -- the convergence engine handles the outer loop. |
| `max_test_cycles` | `test_gate:` in `pipeline-config.md` | Stays as-is. Phase 1 inner cap, managed by `pl-500-test-gate`. |
| `oscillation_tolerance` | `scoring:` in `pipeline-config.md` | Read from scoring section. **NOT** duplicated into `convergence:` config. Used by the perfection phase for regression detection. |
| `total_retries_max` | `pipeline-config.md` top-level | Still applies globally. Every convergence iteration increments `total_retries`. |

## State Schema

New `convergence` object in `state.json` (see `state-schema.md` for the full schema):

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

| Field | Type | Description |
|-------|------|-------------|
| `phase` | `"correctness"` \| `"perfection"` \| `"safety_gate"` | Current convergence phase |
| `phase_iterations` | integer | Iterations in current phase; resets to 0 on phase transition |
| `total_iterations` | integer | Cumulative iterations across all phases; never resets; feeds into `total_retries` |
| `plateau_count` | integer | Consecutive cycles with improvement <= `plateau_threshold`; resets on meaningful improvement |
| `last_score_delta` | integer | Score change from previous perfection cycle (0 if first cycle) |
| `convergence_state` | `"IMPROVING"` \| `"PLATEAUED"` \| `"REGRESSING"` | Current convergence state |
| `phase_history` | array | Append-only log of completed phases for retrospective analysis |
| `safety_gate_passed` | boolean | Whether the final VERIFY after Phase 2 succeeded |
| `unfixable_findings` | array | Findings that survived all iterations (see format below) |

**Unfixable finding format:**

```json
{
  "category": "ARCH-001",
  "file": "src/domain/Plan.kt",
  "line": 42,
  "severity": "INFO",
  "reason": "intentional trade-off — extracting further would scatter related test fixtures",
  "options": ["accept", "follow-up ticket"]
}
```

**Relationship to existing counters:** `test_cycles` and `quality_cycles` still exist -- used by `pl-500` and `pl-400` internally. The convergence engine's `total_iterations` is the outer loop counter.

## Retrospective Auto-Tuning

`pl-700-retrospective` can adjust convergence parameters based on historical patterns:

| Pattern | Adjustment |
|---------|------------|
| Score consistently plateaus early (plateau at iteration 2-3 for 3+ runs) | Decrease `plateau_patience` by 1 (min: 1) |
| Score consistently reaches target (100 for 3+ runs) | Decrease `max_iterations` by 1 (min: 3) |
| Score trajectory shows steady improvement cut short by `max_iterations` | Increase `max_iterations` by 1 (max: 20) |
| Plateau threshold too sensitive (frequent false plateaus followed by improvement in next run) | Increase `plateau_threshold` by 1 (max: 10) |

**Constraints:**
- Auto-tuning respects the PREFLIGHT constraint ranges (no parameter can be tuned outside its valid range).
- At most one parameter is adjusted per run (prevent cascading changes).
- Adjustments are logged in `pipeline-log.md` with rationale.
- `target_score` and `safety_gate` are never auto-tuned -- these are intentional project decisions.
