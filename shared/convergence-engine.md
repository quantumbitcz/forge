# Convergence Engine

This document defines the convergence-driven iteration engine that replaces hard-capped fix cycle loops with plateau detection. The orchestrator (`fg-100-orchestrator`) calls the convergence engine after every VERIFY or REVIEW dispatch to decide: **iterate again, or declare convergence?**

The engine coordinates Stages 4-6 (IMPLEMENT, VERIFY, REVIEW) as a three-phase convergence loop (correctness, perfection, evidence) targeting a score of `target_score` (default 90) with verified shipping evidence, stopping when the target is reached and evidence passes or the score plateaus.

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

## Phase Model

| Phase | Loop | Goal | Convergence Signal |
|-------|------|------|--------------------|
| **Phase 1: Correctness** | IMPLEMENT <-> VERIFY | Tests green | All tests pass (binary) |
| **Phase 2: Perfection** | IMPLEMENT <-> REVIEW | Score = `target_score` | Score = target, OR `PLATEAUED` |
| **Safety Gate** | VERIFY (one shot) | No regressions | Tests still pass after Phase 2 |
| **Phase 3: Evidence** | DOCS → fg-590 | Ship-ready proof | `verdict = SHIP` in `.forge/evidence.json` |

Key behaviors:

- **Phase A / Phase B within VERIFY:** Phase A is build + lint. Phase B is tests + analysis. **If Phase A fails, Phase B is skipped entirely** — `tests_pass` and `analysis_pass` are not meaningful when `is_phase_a_failure` is true. The convergence engine must check `is_phase_a_failure` first before evaluating Phase B results.
- **`analysis_pass` definition:** The `verify_result.analysis_pass` boolean is `true` when all Phase B analysis agents dispatched by `fg-500-test-gate` (e.g., coverage analysis, quality heuristics) return without CRITICAL findings AND the overall analysis verdict is not FAIL. If no analysis agents are configured, `analysis_pass` defaults to `true`.
- **Phase 2 skips VERIFY** per iteration. Only REVIEW scores matter. The safety gate at the end catches regressions from Phase 2 fixes.
- **Safety gate failure routes to Phase 1**, not Phase 2. If Phase 2 fixes broke tests, correctness must be restored before perfection resumes.
- **Phase 1 inner caps:** Test failures use `max_test_cycles` (see algorithm ELSE branch). Build/lint failures use `max_fix_loops` from `implementation.max_fix_loops` config (default: 3). The global `max_iterations` cap is always checked first (takes precedence over inner caps). When tests fail, the convergence engine checks `total_iterations >= max_iterations`, then `phase_iterations >= max_test_cycles`. When build/lint fails (PHASE_A_FAILURE), the convergence engine checks `total_iterations >= max_iterations`, then `verify_fix_count >= max_fix_loops`. Build failures typically resolve in 1-2 attempts, but the inner cap prevents unbounded retries if they don't. `fg-500-test-gate` manages `test_cycles` internally for its own bookkeeping. The convergence engine also tracks `total_iterations` across both phases.
- **Phase 2 inner cap** is `max_review_cycles`, managed by `fg-400-quality-gate`. When convergence is active, `max_review_cycles` defaults to 1 per convergence iteration -- the convergence engine handles the outer loop.

## Input Contracts

The convergence engine receives two structured inputs from the orchestrator:

**`verify_result`** (from Stage 5 — VERIFY):
- `tests_pass` (boolean): `true` when all tests pass in Phase B
- `analysis_pass` (boolean): `true` when all Phase B analysis agents return without CRITICAL findings and the overall analysis verdict is not FAIL. Defaults to `true` if no analysis agents configured. Not evaluated on PHASE_A_FAILURE.
- `is_phase_a_failure` (boolean): `true` when build or lint failed before tests ran (Phase A failure). When true, `tests_pass` and `analysis_pass` are not meaningful.

**PHASE_A_FAILURE field values:** When `is_phase_a_failure` is `true`, `fg-500-test-gate` MUST set `tests_pass: false` and `analysis_pass: false` (not `null` or omitted). The convergence engine checks `is_phase_a_failure` first and short-circuits — but defensive `false` values prevent crashes if the check is accidentally bypassed or the struct is accessed directly by other consumers.

**`review_result`** (from Stage 6 — REVIEW):
- `score` (number): Quality score from the quality gate (0-100)
- `findings` (array): Deduplicated findings list (SCOUT-* already filtered out before dispatch to implementer)

## State Machine Reference

The convergence phase transitions follow the formal table in `shared/state-transitions.md` (section "Convergence Phase Transitions"). This algorithm section describes the *implementation* of those transitions — the table is the *specification*.

On every convergence evaluation (IMPROVING, PLATEAUED, REGRESSING) and phase transition, emit a decision log entry per `shared/decision-log.md` with decision type `convergence_evaluation` or `convergence_phase_transition`.

## Algorithm

```
FUNCTION decide_next(state.convergence, verify_result, review_result):

  MATCH phase:

    "correctness":
      IF verify_result.is_phase_a_failure (build/lint failed before tests ran):
        -> increment verify_fix_count, increment phase_iterations, increment total_iterations
        -> IF total_iterations >= max_iterations: ESCALATE
           (Global cap always checked first — takes precedence over inner caps)
        -> ELSE IF verify_fix_count >= max_fix_loops: ESCALATE
           (Phase A inner cap — prevents unbounded build/lint fix loops,
            consistent with stage-contract.md escalation rules)
        -> ELSE: dispatch IMPLEMENT with build/lint errors, then VERIFY again
        (analysis_pass is not evaluated — Phase B did not run)

      ELSE IF verify_result.tests_pass AND verify_result.analysis_pass:
        -> transition to "perfection", reset phase_iterations to 0
      ELSE:
        -> increment phase_iterations, increment total_iterations
        -> IF total_iterations >= max_iterations: ESCALATE
           (Global cap always checked first — takes precedence over inner caps)
        -> ELSE IF phase_iterations >= max_test_cycles: ESCALATE
           (Phase 1 inner cap — prevents unbounded test-fix loops
            within a single correctness phase, independent of total budget)
        -> ELSE: dispatch IMPLEMENT with failure details, then VERIFY again

    "perfection":
      score = review_result.score
      delta = score - previous_score  (0 if first perfection cycle)
      smoothed_delta = compute_smoothed_delta(score_history)

      IF score >= target_score:
        -> transition to "safety_gate"

      ELSE IF total_iterations >= max_iterations:
        -> ESCALATE (global cap applies to perfection phase too)

      ELSE IF delta < 0 AND abs(delta) > oscillation_tolerance:
        // REGRESSING detection uses raw delta (not smoothed) for responsiveness
        -> convergence_state = "REGRESSING", ESCALATE

      ELSE IF smoothed_delta <= plateau_threshold AND phase_iterations >= 2:
        // Note: phase_iterations >= 2 ensures at least 2 cycles of data before
        // plateau detection activates. The first 2 cycles always count as IMPROVING.
        // smoothed_delta filters LLM sampling noise via weighted moving average.
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
           -> NOTE: When computing `smoothed_delta` after a safety gate restart,
              use only scores from the CURRENT phase. Implementation: smoothed_delta
              is computed from the last `min(3, phase_iterations)` entries in score_history,
              NOT the full history. Since phase_iterations resets to 0, the first cycle
              has no delta data (smoothed_delta = 0, treated as IMPROVING). This prevents
              pre-restart perfection scores from contaminating post-restart delta calculations.
           -> NOTE: total_iterations is NOT reset — it counts across all phases
              including restarts. The global cap (max_iterations) applies cumulatively.
           -> NOTE: After restart, the first perfection cycle will have phase_iterations = 0
              and last_score_delta = 0. Per the plateau detection logic (phase_iterations >= 2
              guard), the first two cycles are exempt from plateau counting — they establish
              a new baseline with enough data for the smoothed delta. This is correct and intentional.
        -> increment total_iterations

FUNCTION compute_smoothed_delta(score_history):
  IF len(score_history) < 2: return 0
  IF len(score_history) == 2:
    # Only 1 delta available — use raw delta
    return score_history[-1] - score_history[-2]
  IF len(score_history) == 3:
    # Only 2 deltas available — use 2-point weighted average
    d1 = score_history[-1] - score_history[-2]  # most recent
    d2 = score_history[-2] - score_history[-3]  # previous
    return d1 * 0.6 + d2 * 0.4
  # 4+ scores: 3-point weighted average of most recent 3 deltas
  d1 = score_history[-1] - score_history[-2]
  d2 = score_history[-2] - score_history[-3]
  d3 = score_history[-3] - score_history[-4]
  return d1 * 0.5 + d2 * 0.3 + d3 * 0.2
```

### Phase 3: Evidence

After the safety gate passes and DOCS (Stage 7) completes, the orchestrator dispatches `fg-590-pre-ship-verifier`. This is a checkpoint, not a loop — it runs once and produces a verdict.

On `verdict: "SHIP"`: proceed to Stage 8 (SHIP).

On `verdict: "BLOCK"`: the orchestrator routes back based on `block_reasons`:
- `build`, `lint`, or `test` failure → transition to Phase 1 (correctness): re-enter IMPLEMENT → VERIFY loop
- `review` Critical/Important issues → transition to Phase 2 (perfection): re-enter IMPLEMENT → REVIEW loop
- `score` below `shipping.min_score` → transition to Phase 2 (perfection): re-enter IMPLEMENT → REVIEW loop

After the fix loop completes, DOCS re-runs (incremental), then fg-590 runs again. This uses the same `total_iterations` counter — the global cap applies.

See `shared/verification-evidence.md` for the evidence artifact schema.

**Global budget interaction:** Every `total_iterations` increment also increments `state.json.total_retries`. When `total_retries >= total_retries_max`, the orchestrator escalates regardless of convergence state.

**SCOUT-* finding filtering:** SCOUT-* findings are filtered at two points:

1. **Quality gate (`fg-400`)** excludes SCOUT-* from score calculation (0-point deduction). SCOUT findings are still included in the quality gate's full findings list returned to the orchestrator.
2. **Orchestrator (`fg-100`)** strips SCOUT-* findings from the list before dispatching to the implementer (`fg-300`). This is the definitive filtering point — the orchestrator owns the dispatch decision.

SCOUT items represent improvements already made — they do not affect the score and should not be re-sent as "fixes to make." SCOUT findings are preserved in stage notes for recap and retrospective purposes only.

**Phase timeout:** Individual phases do not have explicit time limits — the convergence engine relies on iteration caps (`max_test_cycles` for Phase 1, `max_review_cycles` for Phase 2, `max_iterations` globally) and the global retry budget (`total_retries_max`) to bound execution. Wall-clock time is tracked in `state.json.cost.wall_time_seconds` for retrospective analysis but is not used as a termination condition. If the orchestrator detects no progress (e.g., identical errors across 3 consecutive iterations), it should escalate without waiting for budget exhaustion.

**Consecutive Dip Rule interaction:** The quality gate's per-cycle Consecutive Dip Rule (see `scoring.md`) operates within a single convergence iteration. If two consecutive inner cycles show score dips, the quality gate escalates *within* that iteration. The convergence engine's `REGRESSING` state detects dips *across* iterations (via `oscillation_tolerance`). Both mechanisms are complementary: the inner rule catches intra-iteration oscillation, the outer state catches inter-iteration regression.

**Score escalation ladder** (applies when Phase 2 converges below target via PLATEAUED):
- Score >= `shipping.min_score` (default 90): proceed to safety gate. Findings preserved in stage notes.
- Score >= `pass_threshold` AND < `shipping.min_score`: proceed to safety gate. Remaining findings documented as follow-up tickets if Linear enabled. Sub-band guidance: 95-99 = no follow-up tickets; 80-94 = architectural WARNINGs get follow-up tickets.
- Score < `pass_threshold` AND >= `concerns_threshold` (default 60-79): escalate to user with 3 options:
  1. **"Keep trying"** — reset `plateau_count` to 0, `convergence_state` to `"IMPROVING"`, continue iterating (`total_iterations` NOT reset — global cap still applies)
  2. **"Fix manually"** — pause pipeline, user fixes outside forge, resume from VERIFY
  3. **"Abort"** — stop pipeline, no PR
- Score < `concerns_threshold` (default < 60): escalate to user. Recommend abort. Same 3 options as above.

**No "Continue anyway" or "Accept and ship" option exists.** The pipeline never offers to ship below `shipping.min_score`.

**Autonomous mode:** On plateau below `shipping.min_score`, auto-select option 1 ("Keep trying"). On `max_iterations` exhausted, hard abort — write `.forge/abort-report.md` with final score, remaining findings, last evidence, iteration history. Never auto-ship below `shipping.min_score`.

**Precedence between oscillation detection and score escalation ladder:**
The REGRESSING state and the score escalation ladder serve different purposes and do NOT conflict:
- **REGRESSING** (oscillation_tolerance check) fires on score *drops between iterations* that exceed tolerance — this is a **trajectory signal** meaning "we're going backwards." It triggers immediately, regardless of absolute score.
- **Score escalation ladder** fires when convergence reaches **PLATEAUED** — this is a **terminal verdict** meaning "we've stopped improving." It determines what happens next based on absolute score.
- If a single iteration shows both a drop exceeding tolerance AND would trigger plateau (e.g., score oscillating around threshold), **REGRESSING takes priority** — it is checked first in the algorithm (line `ELSE IF delta < 0 AND abs(delta) > oscillation_tolerance` precedes the plateau check). This prevents the pipeline from declaring "plateau" when the score is actually declining.

### Diminishing Returns Detection

After each convergence iteration in Phase 2 (perfection), check for diminishing returns:

1. Compute `gain = score_current - score_previous`
2. If `gain > 0 AND gain <= 2 AND score_current >= pass_threshold`:
   - This is a diminishing returns cycle — progress is real but minimal
   - Increment `convergence.diminishing_count` (default 0)
   - If `diminishing_count >= 2`: treat as PLATEAUED — apply score escalation ladder
   - Log: "Diminishing returns: gained {gain} points in last {diminishing_count} iterations"
3. If `gain > 2`: reset `diminishing_count = 0`

This prevents the pipeline from spending 3-4 iterations to squeeze out the last 2-3 INFO fixes when the score is already above pass_threshold.

The `score_diminishing` event is Row 50 in the transition table (`shared/state-transitions.md`).

### Unfixable INFO Tracking

In Phase 2 iterations after the first:
1. Compare current findings with previous cycle's findings
2. INFO findings that persist across 2+ cycles without being fixed: increment `convergence.unfixable_info_count`
3. Compute `effective_target = max(pass_threshold, min(target_score, 100 - 2 * unfixable_info_count))`
   This floor ensures the target never drops below `pass_threshold`, preventing technical debt accumulation where persistent INFOs lower the bar to unacceptable levels.
4. Use `effective_target` instead of `target_score` for convergence decisions

The `unfixable_info_count` field is already added to the state schema (v1.5.0). It resets to 0 at the start of each run.

## Configuration

New `convergence:` section in both `forge-config.md` and `forge.local.md`:

```yaml
convergence:
  max_iterations: 8        # Total iterations across both phases
  plateau_threshold: 2     # Minimum score improvement to count as progress
  plateau_patience: 2      # Consecutive sub-threshold cycles before declaring plateau
  target_score: 90         # Score to aim for (convergence target). Default 90.
  safety_gate: true        # Run VERIFY after Phase 2 to catch regressions

shipping:
  min_score: 90                   # Minimum score to create PR. Range: pass_threshold-100. Default: 90.
  require_evidence: true          # Always true. Not user-configurable. Documented for visibility.
  evidence_review: true           # Dispatch code reviewer in fg-590. Default: true. Set false to skip.
  evidence_max_age_minutes: 30    # Evidence staleness threshold. Range: 5-60. Default: 30.
```

**Parameter resolution:** `forge-config.md` > `forge.local.md` > plugin defaults (values shown above).

## PREFLIGHT Constraints

These constraints are enforced at PREFLIGHT. If violated, log WARNING and use plugin defaults:

| Parameter | Range | Rationale |
|-----------|-------|-----------|
| `max_iterations` | 3-20 | Below 3 defeats the purpose; above 20 is runaway |
| `plateau_threshold` | 0-10 | 0 = any improvement counts; 10 = very loose. Note: 0 means even a 0.1-point improvement resets plateau count. |
| `plateau_patience` | 1-5 | 1 = stop at first plateau; 5 = very patient |
| `target_score` | >= `pass_threshold` AND <= 100 | Cannot be below the passing score |
| `safety_gate` | boolean | No range constraint |
| `shipping.min_score` | >= `pass_threshold` AND <= 100 | Cannot ship below passing score; 100 is maximum |
| `shipping.evidence_max_age_minutes` | 5-60 | Below 5 is impractical; above 60 risks stale evidence |

## Interaction with Existing Config

The convergence engine reads from and interacts with existing pipeline configuration parameters. It does not duplicate them.

| Existing Parameter | Location | Convergence Interaction |
|--------------------|----------|------------------------|
| `max_review_cycles` | `quality_gate:` in `forge-config.md` | Becomes Phase 2 inner cap per convergence iteration. Defaults to 1 when convergence is active -- the convergence engine handles the outer loop. |
| `max_test_cycles` | `test_gate:` in `forge-config.md` | Stays as-is. Phase 1 inner cap, managed by `fg-500-test-gate`. |
| `oscillation_tolerance` | `scoring:` in `forge-config.md` | Read from scoring section. **NOT** duplicated into `convergence:` config. Used by the perfection phase for regression detection. |
| `implementation.max_fix_loops` | `forge-config.md` implementation section | Phase A (build/lint) inner cap. Prevents unbounded build/lint fix loops within VERIFY. Default: 3. |
| `total_retries_max` | `forge-config.md` top-level | Still applies globally. Every convergence iteration increments `total_retries`. |

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
| `phase_history` | array | Append-only log of completed phases for retrospective analysis. Each entry has `outcome`: `"converged"` (target reached or plateau accepted), `"escalated"` (cap hit, regression, or user escalation), or `"restarted"` (safety gate failure triggered correctness restart). Capped at 50 entries per run — when the cap is reached, the oldest entry is evicted (FIFO). Resets to `[]` at PREFLIGHT for each new run. |
| `safety_gate_passed` | boolean | Whether the final VERIFY after Phase 2 succeeded |
| `safety_gate_failures` | integer | Consecutive safety gate failures. Incremented when `verify_result.tests_pass` is `false` during the safety gate phase. Escalate at >= 2 (cross-phase oscillation). Resets to 0 on safety gate pass. |
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

**Relationship to existing counters:** The pipeline uses five iteration counters at different scopes:

| Counter | Scope | Managed By | Resets | Feeds Into |
|---------|-------|-----------|--------|------------|
| `verify_fix_count` | Phase A (build/lint) inner cap | Orchestrator | Per-run only (not per-phase, not on safety gate restart) | `total_retries` |
| `test_cycles` | Phase 1B (test gate) inner cap | `fg-500-test-gate` | Per-run only (not per-phase, not on safety gate restart) | `total_retries` |
| `quality_cycles` | Phase 2 (review) inner cap | `fg-400-quality-gate` | Per-run only (not per-phase, not on safety gate restart) | `total_retries` |
| `phase_iterations` | Current convergence phase | Convergence engine | On phase transition (including safety gate restart) | — |
| `total_iterations` | Entire convergence lifecycle | Convergence engine | Never | `total_retries` |

**Key relationships:**
- `quality_cycles` and `test_cycles` are **inner-loop** counters — they track retries within a single convergence iteration. When convergence is active, `max_review_cycles` defaults to 1, so the quality gate runs once per convergence iteration.
- `phase_iterations` is the **mid-loop** counter — it tracks how many convergence iterations have occurred in the current phase. It resets on phase transitions (correctness → perfection, or safety gate restart → correctness).
- `total_iterations` is the **outer-loop** counter — cumulative across all phases and restarts. It is the primary budget enforcement counter alongside `total_retries`.
- Every increment of `total_iterations` also increments `total_retries`. Inner counters (`verify_fix_count`, `test_cycles`, `quality_cycles`) independently increment `total_retries` as well.

**Safety gate restart and inner counters:** When the safety gate fails and restarts the correctness phase, inner counters (`verify_fix_count`, `test_cycles`, `quality_cycles`) are intentionally NOT reset. This is cross-phase budget sharing: the total budget for build/lint fixes, test cycles, and review cycles is finite across the entire run. If a project consumed 3 build fix loops before Phase 2, those are spent — a safety gate restart does not grant 3 more. The orchestrator should check remaining budget and escalate immediately if inner caps are already exhausted upon re-entry.

**Global budget enforcement in convergence algorithm:** The `total_retries_max` check is performed by the orchestrator *before* each convergence engine call, not within the convergence algorithm itself. The orchestrator MUST check `total_retries >= total_retries_max` before dispatching any stage — if exhausted, escalate regardless of convergence state. This ensures no dispatch occurs after the global budget is exhausted, even if the convergence engine's `max_iterations` cap has not been reached.

**`oscillation_tolerance` = 0 note:** Setting `oscillation_tolerance` to 0 means ANY score decrease triggers REGRESSING escalation. This is intentionally allowed but aggressive — even a 1-point drop from findings being reclassified would escalate. PREFLIGHT logs a WARNING when `oscillation_tolerance` is 0 to alert users that this configuration is very strict.

## Retrospective Auto-Tuning

`fg-700-retrospective` can adjust convergence parameters based on historical patterns:

| Pattern | Adjustment |
|---------|------------|
| Score consistently plateaus early (plateau at iteration 2-3 for 3+ runs) | Decrease `plateau_patience` by 1 (min: 1) |
| Score consistently reaches target (100 for 3+ runs) | Decrease `max_iterations` by 1 (min: 3) |
| Score trajectory shows steady improvement cut short by `max_iterations` | Increase `max_iterations` by 1 (max: 20) |
| Plateau threshold too sensitive (frequent false plateaus followed by improvement in next run) | Increase `plateau_threshold` by 1 (max: 10) |

**Constraints:**
- Auto-tuning respects the PREFLIGHT constraint ranges (no parameter can be tuned outside its valid range).
- At most one parameter is adjusted per run (prevent cascading changes).
- Adjustments are logged in `forge-log.md` with rationale.
- `target_score` and `safety_gate` are never auto-tuned -- these are intentional project decisions.
