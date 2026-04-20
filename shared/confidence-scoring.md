# Confidence Scoring

Adaptive confidence scoring and pre-execution gating for the forge pipeline. Computes a confidence score at PLAN completion to decide whether to proceed autonomously, ask for confirmation, or suggest requirement refinement.

## Algorithm

Confidence is a weighted sum of four dimensions, each scored 0.0-1.0:

```
confidence_score = w_clarity * clarity + w_familiarity * familiarity
                 + w_complexity * complexity + w_history * history

effective_confidence = confidence_score * (0.5 + 0.5 * trust_level)
```

Trust modifier effect: at trust=0.0 the effective score is halved (very conservative); at trust=0.5 (default) it is 75% of raw; at trust=1.0 no dampening.

### Default Weights

| Dimension | Weight | Rationale |
|---|---|---|
| `clarity` | 0.30 | Requirement quality is the strongest predictor of pipeline success |
| `familiarity` | 0.25 | Known patterns reduce uncertainty |
| `complexity` | 0.20 | Simpler changes are more likely to succeed |
| `history` | 0.25 | Past performance on similar tasks is a strong signal |

Weights must sum to 1.0 (tolerance +/- 0.01). Configurable in `forge-config.md` under `confidence.weights`.

## Confidence Levels

| Effective Confidence | Level | Gate Decision |
|---|---|---|
| >= `autonomous_threshold` (default 0.7) | HIGH | `PROCEED` -- proceed autonomously |
| >= `pause_threshold` (default 0.4) | MEDIUM | `ASK` -- display breakdown, ask confirmation via `AskUserQuestion` |
| < `pause_threshold` (default 0.4) | LOW | `SUGGEST_SHAPE` -- suggest `/forge-shape` for requirement refinement |

## Dimension: Requirement Clarity (0.0-1.0)

Assessed from the requirement text using intent classification signals (see `shared/intent-classification.md`).

| Signal | Score Contribution | Detection |
|---|---|---|
| Word count >= 20 | +0.15 | `wc -w` |
| Contains specific actors (user, admin, system) | +0.15 | Regex match against actor patterns |
| Contains entities matching codebase symbols | +0.20 | Fuzzy match against explore cache `file_index` keys and code graph node names |
| Contains surface/endpoint (URL path, UI component, CLI command) | +0.15 | Regex for path patterns, component names |
| Contains acceptance criteria (given/when/then, should, must) | +0.20 | Regex match for BDD/acceptance keywords |
| Contains negative constraints (must not, should not, except) | +0.10 | Regex for constraint language |
| Has attached spec file (`--spec`) | +0.05 | Check `state.json.spec` field |

Clamped to [0.0, 1.0].

## Dimension: Pattern Familiarity (0.0-1.0)

Assessed from PREEMPT items and learnings matching the requirement's domain.

| Signal | Score Contribution |
|---|---|
| >= 5 HIGH-confidence PREEMPT items match the domain area | 0.30 |
| >= 3 MEDIUM-confidence PREEMPT items match | 0.20 |
| Cached plan exists in plan-cache with similarity >= 0.7 | 0.25 |
| Previous successful run for the same `domain_area` in `.forge/reports/` | 0.15 |
| Active learned rules (from F09 active knowledge) match requirement keywords | 0.10 |

Sum of applicable contributions, clamped to [0.0, 1.0].

## Dimension: Codebase Complexity (0.0-1.0)

Inverted complexity -- higher score means simpler change.

| Signal | Score |
|---|---|
| Affected files <= 5 | 1.0 |
| Affected files 6-15 | 0.7 |
| Affected files 16-30 | 0.4 |
| Affected files > 30 | 0.2 |

Modifiers (cumulative, applied after base score):

| Modifier | Adjustment |
|---|---|
| Cross-component change detected | -0.2 |
| Multiple community boundaries crossed (code graph) | -0.15 |
| High cyclomatic complexity in affected files (avg > 15) | -0.1 |

Clamped to [0.0, 1.0]. When code graph is unavailable, affected file count is estimated from explore cache keyword matching. When explore cache is also missing, use 0.5 (neutral).

## Dimension: Historical Success Rate (0.0-1.0)

Assessed from completed pipeline run reports in `.forge/reports/`.

| Signal | Score |
|---|---|
| Last 5 runs for same `domain_area`: all PASS (score >= 80) | 1.0 |
| Last 5 runs: 4 PASS, 1 CONCERNS | 0.8 |
| Last 5 runs: 3+ PASS | 0.6 |
| Last 5 runs: mixed or fewer than 3 runs total | 0.4 |
| Last 5 runs: majority FAIL or CONCERNS | 0.2 |
| No prior runs | 0.3 (neutral -- no evidence) |

---

## Trust Model

Trust represents the pipeline's earned credibility with a specific developer. It modulates the effective confidence score: high trust amplifies confidence, low trust dampens it.

### Trust Storage

Trust is stored in `.forge/trust.json` (local, NOT committed to git). This is deliberate -- trust is per-developer, not per-repo. Developer A's trust level should not be overwritten by Developer B's commit.

```json
{
  "trust_level": 0.72,
  "last_updated": "2026-04-13T10:00:00Z",
  "consecutive_passes": 4,
  "total_corrections": 2,
  "total_runs": 15
}
```

The file survives `/forge-recover reset` (alongside `explore-cache.json`, `plan-cache/`, `code-graph.db`, and `wiki/`).

### Trust Initialization

Starts at `initial_trust` (default 0.5). Clamped to [0.0, 1.0]. Never decays below `initial_trust * 0.5` (floor of 0.25 at default settings).

### Trust Increase

| Event | Increase | Condition |
|---|---|---|
| Pipeline run completes with PASS, no user corrections | +0.05 | Score >= 80 AND user did not reject PR or provide feedback |
| User accepts AUTO decision (MEDIUM confidence, user confirmed) | +0.02 | Confirmation given without changes |
| 3 consecutive PASS runs without corrections | +0.10 (bonus) | Streak tracking via `consecutive_passes` |

### Trust Decrease

| Event | Decrease | Condition |
|---|---|---|
| User rejects PR | -0.10 | `feedback_loop_count` incremented |
| User provides design-level feedback | -0.08 | `feedback_classification == "design"` |
| User provides implementation-level feedback | -0.05 | `feedback_classification == "implementation"` |
| Pipeline FAIL verdict | -0.03 | Score < 60 |
| User aborts pipeline | -0.05 | `/forge-abort` invoked |

### Trust Decay

```
trust_after_decay = trust_level - trust_decay * runs_since_last_interaction
```

Applied per run without user correction (natural decay toward caution). Default `trust_decay`: 0.05. Floor: `initial_trust * 0.5`.

---

## Execution Gate Behavior

### HIGH Confidence (PROCEED)

Pipeline proceeds autonomously. Logged: `"Confidence: HIGH ({score}). Proceeding."`

### MEDIUM Confidence (ASK)

Display plan summary, confidence breakdown, cost estimate (from F03), and time estimate. Ask for confirmation via `AskUserQuestion`.

```
Pipeline Confidence: MEDIUM (0.62)

Breakdown:
  Requirement clarity:  0.65 (missing acceptance criteria)
  Pattern familiarity:  0.70 (3 matching PREEMPT items, cached plan found)
  Codebase complexity:  0.50 (12 affected files, crosses 2 module boundaries)
  Historical success:   0.60 (3/5 recent runs passed for domain "billing")

Estimated cost: $0.45 - $1.20
Estimated time: 8m - 22m

Proceed? [Yes / Refine requirement / Abort]
```

### LOW Confidence (SUGGEST_SHAPE)

Display concerns. Suggest `/forge-shape` for requirement refinement. Offer to proceed anyway.

```
Pipeline Confidence: LOW (0.31)

Concerns:
  - Requirement is too vague (12 words, no actors, no acceptance criteria)
  - No prior runs in domain "inventory" -- no historical baseline
  - Estimated blast radius: 25+ files across 3 components

Recommendation: Use /forge-shape to refine the requirement first.

[Proceed anyway / Refine with /forge-shape / Abort]
```

### Autonomous Mode

When `autonomous: true`, confidence is computed and logged but gates are bypassed. LOW confidence + autonomous mode logs WARNING: `"Low confidence ({score}) in autonomous mode -- proceeding per autonomous flag."`

### Background Mode

If user does not respond to MEDIUM gate within 5 minutes, write escalation to `.forge/alerts.json` per background execution protocol.

---

## Orchestrator Integration

The orchestrator (`fg-100-orchestrator`) uses confidence scoring as follows. This section documents the integration contract; the orchestrator's own `.md` file is not modified.

### At PLAN Completion (before VALIDATE)

1. Compute clarity score from requirement text (regex-based, zero tokens)
2. Compute familiarity score from PREEMPT items and plan cache (file reads)
3. Compute complexity score from code graph or explore cache (local query)
4. Compute history score from `.forge/reports/` (file reads)
5. Calculate weighted confidence score
6. Apply trust modifier to get effective confidence
7. Determine gate decision: `PROCEED` / `ASK` / `SUGGEST_SHAPE`
8. If `ASK`: display breakdown via `AskUserQuestion`, wait for response
9. If `SUGGEST_SHAPE`: display concerns, suggest `/forge-shape`
10. Store confidence data in `state.json.confidence`
11. Log decision to `.forge/decisions.jsonl` per `shared/decision-log.md`

### At LEARN (after pipeline completion)

1. Evaluate outcome: PASS/CONCERNS/FAIL, user corrections, PR acceptance
2. Update trust level per trust adjustment rules
3. Persist updated trust to `.forge/trust.json`
4. Record confidence accuracy for calibration tracking:
   - HIGH confidence + PASS = calibrated
   - HIGH confidence + FAIL = over-confident (trend warning)
   - LOW confidence + PASS = under-confident (trend warning)

### Per-Stage Confidence (informational, non-gating)

| Stage | Confidence Signal | Consumer |
|---|---|---|
| PLAN | Plan quality assessment (Challenge Brief completeness, story count, domain coverage) | Validator uses to decide APPROVE vs REVISE threshold |
| VALIDATE | Validation confidence (concerns remaining after 2 passes) | Orchestrator uses to decide extra validation retry |
| IMPLEMENT | Implementation confidence (files touched vs plan estimate, test coverage) | Verify stage uses to decide verification thoroughness |
| REVIEW | Finding confidence (existing HIGH/MEDIUM/LOW per `scoring.md`) | Quality gate dispatch routing |
| SHIP | Evidence freshness and completeness | Pre-ship verifier uses to decide evidence refresh |

---

## Error Handling

| Failure Mode | Behavior |
|---|---|
| Code graph unavailable | Complexity dimension falls back to explore-cache file count. If explore cache also missing, use 0.5 (neutral). |
| No pipeline history | History dimension uses 0.3 (neutral-cautious). |
| Trust data missing from `.forge/trust.json` | Use `initial_trust` from config (default 0.5). |
| Confidence computation fails (any error) | Log WARNING, set confidence to MEDIUM (0.5), proceed with confirmation gate. Never block pipeline due to confidence failure. |
| User does not respond to MEDIUM gate within 5 minutes (background mode) | Write escalation to `.forge/alerts.json`. |
| `autonomous: true` mode | Gates bypassed, confidence still logged. |

## Performance

| Operation | Latency | Token Cost |
|---|---|---|
| Clarity scoring | <10ms | 0 (regex) |
| Familiarity scoring | <100ms | 0 (file reads) |
| Complexity scoring | <500ms | 0 (local query) |
| History scoring | <200ms | 0 (file reads) |
| Trust update | <50ms | 0 (file write) |
| **Total** | **<1s** | **0 tokens** |

## Configuration

In `forge-config.md`:

```yaml
confidence:
  planning_gate: true              # Enable pre-execution gating at PLAN
  autonomous_threshold: 0.7        # HIGH confidence threshold (0.3-0.95)
  pause_threshold: 0.4             # MEDIUM/LOW boundary (0.1-0.7)
  initial_trust: 0.5               # Starting trust level (0.0-1.0)
  trust_decay: 0.05                # Trust decay per run without interaction (0.0-0.2)
```

### PREFLIGHT Constraints

- `autonomous_threshold` must be > `pause_threshold` (gap >= 0.1)
- All weights must sum to 1.0 (tolerance +/- 0.01)
- `autonomous_threshold` >= 0.3
- `pause_threshold` >= 0.1
- `initial_trust` in [0.0, 1.0]
- `trust_decay` in [0.0, 0.2]

### Interaction with Phase 12 Speculation

MEDIUM-confidence requirements with ambiguity signals trigger speculative parallel plan branches. See `shared/speculation.md §Trigger Logic` for the exact predicate. HIGH and LOW bands are unaffected: HIGH proceeds single-plan, LOW routes to `/forge-shape`.
