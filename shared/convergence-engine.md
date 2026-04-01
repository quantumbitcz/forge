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

- **`analysis_pass` definition:** The `verify_result.analysis_pass` boolean is `true` when all Phase B analysis agents dispatched by `pl-500-test-gate` (e.g., coverage analysis, quality heuristics) return without CRITICAL findings AND the overall analysis verdict is not FAIL. If no analysis agents are configured, `analysis_pass` defaults to `true`.
- **Phase 2 skips VERIFY** per iteration. Only REVIEW scores matter. The safety gate at the end catches regressions from Phase 2 fixes.
- **Safety gate failure routes to Phase 1**, not Phase 2. If Phase 2 fixes broke tests, correctness must be restored before perfection resumes.
- **Phase 1 inner caps:** Test failures use `max_test_cycles` (see algorithm ELSE branch). Build/lint failures use `max_fix_loops` from `implementation.max_fix_loops` config (default: 3). When tests fail, the convergence engine checks `phase_iterations >= max_test_cycles`. When build/lint fails (PHASE_A_FAILURE), the convergence engine checks `verify_fix_count >= max_fix_loops` first, then the global `max_iterations` cap. Build failures typically resolve in 1-2 attempts, but the inner cap prevents unbounded retries if they don't. `pl-500-test-gate` manages `test_cycles` internally for its own bookkeeping. The convergence engine also tracks `total_iterations` across both phases.
- **Phase 2 inner cap** is `max_review_cycles`, managed by `pl-400-quality-gate`. When convergence is active, `max_review_cycles` defaults to 1 per convergence iteration -- the convergence engine handles the outer loop.

## Algorithm

```
FUNCTION decide_next(state.convergence, verify_result, review_result):

  MATCH phase:

    "correctness":
      IF verify_result is PHASE_A_FAILURE (build/lint failed before tests ran):
        -> increment verify_fix_count, increment phase_iterations, increment total_iterations
        -> IF verify_fix_count >= max_fix_loops: ESCALATE
           (Phase A inner cap — prevents unbounded build/lint fix loops,
            consistent with stage-contract.md escalation rules)
        -> ELSE IF total_iterations >= max_iterations: ESCALATE
        -> ELSE: dispatch IMPLEMENT with build/lint errors, then VERIFY again
        (analysis_pass is not evaluated — Phase B did not run)

      ELSE IF verify_result.tests_pass AND verify_result.analysis_pass:
        -> transition to "perfection", reset phase_iterations to 0
      ELSE:
        -> increment phase_iterations, increment total_iterations
        -> IF phase_iterations >= max_test_cycles: ESCALATE
           (Phase 1 inner cap — prevents unbounded test-fix loops
            within a single correctness phase, independent of total budget)
        -> ELSE IF total_iterations >= max_iterations: ESCALATE
        -> ELSE: dispatch IMPLEMENT with failure details, then VERIFY again

    "perfection":
      score = review_result.score
      delta = score - previous_score  (0 if first perfection cycle)

      IF score >= target_score:
        -> transition to "safety_gate"

      ELSE IF total_iterations >= max_iterations:
        -> ESCALATE (global cap applies to perfection phase too)

      ELSE IF delta < 0 AND abs(delta) > oscillation_tolerance:
        -> convergence_state = "REGRESSING", ESCALATE

      ELSE IF delta <= plateau_threshold AND phase_iterations > 0:
        // Note: phase_iterations > 0 prevents the very first perfection cycle
        // from counting toward plateau (delta is hardcoded to 0 on first cycle)
        -> plateau_count += 1
        -> IF plateau_count >= plateau_patience:
            convergence_state = "PLATEAUED"
            -> apply score escalation ladder (existing scoring sub-bands):
               - score >= pass_threshold: transition directly to "safety_gate"
                 (do NOT dispatch another IMPLEMENT — the score is acceptable)
               - score >= concerns_threshold AND < pass_threshold: ESCALATE to user
                 with CONCERNS verdict before transitioning to safety_gate
                 (user may choose to accept, guide further fixes, or abort)
               - score < concerns_threshold: ESCALATE to user with FAIL verdict
                 (recommend abort or replan — do NOT proceed to safety_gate)
            -> document unfixable findings in convergence.unfixable_findings
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
        -> safety_gate_failures += 1
        -> IF safety_gate_failures >= 2: ESCALATE (cross-phase oscillation detected)
        -> ELSE:
           -> transition back to "correctness"
           -> reset phase_iterations to 0
           -> reset plateau_count to 0
           -> reset last_score_delta to 0
           -> reset convergence_state to "IMPROVING"
           -> append phase_history entry: { phase: "safety_gate", outcome: "restarted" }
           -> NOTE: score_history is NOT cleared — it carries across phases for
              retrospective analysis. The perfection phase uses last_score_delta
              (reset to 0) for its own delta calculations, not score_history.
           -> NOTE: total_iterations is NOT reset — it counts across all phases
              including restarts. The global cap (max_iterations) applies cumulatively.
        -> increment total_iterations
```

**Global budget interaction:** Every `total_iterations` increment also increments `state.json.total_retries`. When `total_retries >= total_retries_max`, the orchestrator escalates regardless of convergence state.

**Phase timeout:** Individual phases do not have explicit time limits — the convergence engine relies on iteration caps (`max_test_cycles` for Phase 1, `max_review_cycles` for Phase 2, `max_iterations` globally) and the global retry budget (`total_retries_max`) to bound execution. Wall-clock time is tracked in `state.json.cost.wall_time_seconds` for retrospective analysis but is not used as a termination condition. If the orchestrator detects no progress (e.g., identical errors across 3 consecutive iterations), it should escalate without waiting for budget exhaustion.

**Consecutive Dip Rule interaction:** The quality gate's per-cycle Consecutive Dip Rule (see `scoring.md`) operates within a single convergence iteration. If two consecutive inner cycles show score dips, the quality gate escalates *within* that iteration. The convergence engine's `REGRESSING` state detects dips *across* iterations (via `oscillation_tolerance`). Both mechanisms are complementary: the inner rule catches intra-iteration oscillation, the outer state catches inter-iteration regression.

**Score escalation ladder** (applies when Phase 2 converges below target via PLATEAUED):
- Score >= `pass_threshold` (default 80): proceed to safety gate with PASS verdict. Findings preserved in stage notes. Sub-band guidance: 95-99 = no follow-up tickets; 80-94 = architectural WARNINGs get follow-up tickets.
- Score >= `concerns_threshold` AND < `pass_threshold` (default 60-79): CONCERNS verdict. Full findings posted. Escalate to user for guidance before proceeding.
- Score < `concerns_threshold` (default < 60): FAIL verdict. Escalate to user. Recommend abort or replan.

**Precedence between oscillation detection and score escalation ladder:**
The REGRESSING state and the score escalation ladder serve different purposes and do NOT conflict:
- **REGRESSING** (oscillation_tolerance check) fires on score *drops between iterations* that exceed tolerance — this is a **trajectory signal** meaning "we're going backwards." It triggers immediately, regardless of absolute score.
- **Score escalation ladder** fires when convergence reaches **PLATEAUED** — this is a **terminal verdict** meaning "we've stopped improving." It determines what happens next based on absolute score.
- If a single iteration shows both a drop exceeding tolerance AND would trigger plateau (e.g., score oscillating around threshold), **REGRESSING takes priority** — it is checked first in the algorithm (line `ELSE IF delta < 0 AND abs(delta) > oscillation_tolerance` precedes the plateau check). This prevents the pipeline from declaring "plateau" when the score is actually declining.

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
    "safety_gate_failures": 0,
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
| `last_score_delta` | number | Score change from previous perfection cycle (0 if first cycle). May be non-integer with custom scoring weights. |
| `convergence_state` | `"IMPROVING"` \| `"PLATEAUED"` \| `"REGRESSING"` | Current convergence state |
| `phase_history` | array | Append-only log of completed phases for retrospective analysis. Each entry has `outcome`: `"converged"` (target reached or plateau accepted), `"escalated"` (cap hit, regression, or user escalation), or `"restarted"` (safety gate failure triggered correctness restart). Capped at 50 entries per run. Resets to `[]` at PREFLIGHT for each new run. |
| `safety_gate_passed` | boolean | Whether the final VERIFY after Phase 2 succeeded |
| `safety_gate_failures` | integer | Consecutive safety gate failures. Escalate at >= 2 (cross-phase oscillation). Resets to 0 on safety gate pass. |
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
