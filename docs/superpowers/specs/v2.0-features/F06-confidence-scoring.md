# F06: Adaptive Confidence Scoring and Pre-Execution Gating

## Status
DRAFT — 2026-04-13

## Problem Statement

Forge proceeds through all 10 pipeline stages without surfacing confidence about its ability to succeed. A vague two-word requirement receives the same treatment as a detailed spec with acceptance criteria. The pipeline discovers failure late — at VERIFY or REVIEW — after consuming significant tokens and time.

Devin provides confidence scores before execution and pauses when confidence is low, asking clarifying questions. OpenHands uses risk-based confirmation with adaptive trust — after repeated successful runs, it proceeds autonomously on similar tasks. Cursor's BugBot learns from corrections to reduce future false positives.

The gap: Forge has `autonomous: true` mode (never pause except safety escalations) and the shaper for vague requirements, but no middle ground. There is no mechanism to say "I am 65% confident this plan will succeed — here is why, and here is the estimated cost. Proceed?" There is no adaptive trust model that learns from user corrections over time.

The existing infrastructure supports this: requirement clarity can be assessed from word count and entity detection (already in `shared/intent-classification.md`), pattern familiarity can be queried from the PREEMPT system and learnings, codebase complexity is available from the knowledge graph (F01) or explore cache, and pipeline run history is in `.forge/reports/`.

## Proposed Solution

Add a confidence scoring system that operates at two levels: (1) pre-execution gating at PLAN to decide whether to proceed, pause for confirmation, or suggest refinement, and (2) per-stage confidence signals throughout the pipeline. Combined with an adaptive trust model that learns from user corrections, the system progressively reduces friction for experienced users on familiar codebases while remaining cautious on novel tasks.

## Detailed Design

### Architecture

```
User Requirement
       |
       v
+------------------+
| Intent Classifier |  (existing: shared/intent-classification.md)
+------------------+
       |
       v
+----------------------------+
| Confidence Estimator       |  (new: shared/confidence-estimator.md)
| - Requirement clarity      |
| - Pattern familiarity      |
| - Codebase complexity      |
| - Historical success rate  |
| - Trust level              |
+----------------------------+
       |
       +-------> confidence_score (0.0 - 1.0)
       |         confidence_level (HIGH / MEDIUM / LOW)
       |         cost_estimate ($X.XX - $Y.YY)
       |         time_estimate (Xm - Ym)
       v
+----------------------------+
| Execution Gate             |
| - HIGH:   proceed          |
| - MEDIUM: confirm + show   |
| - LOW:    suggest /shape   |
+----------------------------+
       |
       v
Pipeline proceeds (or pauses/redirects)
```

### Confidence Calculation Algorithm

The confidence score is a weighted sum of four dimensions, each scored 0.0-1.0:

```
confidence_score = w_clarity * clarity_score
                 + w_familiarity * familiarity_score
                 + w_complexity * complexity_score
                 + w_history * history_score

# Apply trust modifier
effective_confidence = confidence_score * (0.5 + 0.5 * trust_level)
# trust_level: 0.0-1.0, default 0.5
# At trust=0.0: effective = 0.5 * confidence (very conservative)
# At trust=0.5: effective = 0.75 * confidence (balanced)
# At trust=1.0: effective = 1.0 * confidence (full trust)
```

#### Default Weights

| Dimension | Weight | Rationale |
|---|---|---|
| `w_clarity` | 0.30 | Requirement quality is the strongest predictor of pipeline success |
| `w_familiarity` | 0.25 | Known patterns reduce uncertainty |
| `w_complexity` | 0.20 | Simpler changes are more likely to succeed |
| `w_history` | 0.25 | Past performance on similar tasks is a strong signal |

Weights must sum to 1.0. Configurable per project.

#### Dimension: Requirement Clarity (0.0-1.0)

Assessed from the requirement text using existing intent classification signals:

| Signal | Score Contribution | Detection Method |
|---|---|---|
| Word count >= 20 | +0.15 | `wc -w` |
| Contains specific actors (user, admin, system) | +0.15 | Regex match against actor patterns |
| Contains specific entities (nouns matching codebase symbols from explore cache or code graph) | +0.20 | Fuzzy match against `explore-cache.json` `file_index` keys and `code-graph.db` node names |
| Contains surface/endpoint (URL path, UI component, CLI command) | +0.15 | Regex for path patterns, component names |
| Contains acceptance criteria (given/when/then, should, must) | +0.20 | Regex match for BDD/acceptance keywords |
| Contains negative constraints (must not, should not, except) | +0.10 | Regex for constraint language |
| Has attached spec file (`--spec`) | +0.05 | Check `state.json.spec` field |

Score is clamped to [0.0, 1.0]. Maximum achievable: 1.0 (all signals present).

#### Dimension: Pattern Familiarity (0.0-1.0)

Assessed from PREEMPT items and learnings matching the requirement's domain:

| Signal | Score Contribution |
|---|---|
| >= 5 HIGH-confidence PREEMPT items match the domain area | 0.30 |
| >= 3 MEDIUM-confidence PREEMPT items match | 0.20 |
| Cached plan exists in plan-cache with similarity >= 0.7 | 0.25 |
| Previous successful run for the same `domain_area` in `.forge/reports/` | 0.15 |
| Active learned rules (from F09) match the requirement keywords | 0.10 |

Score is the sum of applicable contributions, clamped to [0.0, 1.0].

#### Dimension: Codebase Complexity (0.0-1.0)

Inverted complexity — higher score means simpler change:

| Signal | Score (inverted) |
|---|---|
| Affected files (from blast radius query or estimate) <= 5 | 1.0 |
| Affected files 6-15 | 0.7 |
| Affected files 16-30 | 0.4 |
| Affected files > 30 | 0.2 |
| Cross-component change detected | -0.2 modifier |
| Multiple community boundaries crossed (from F01 community detection) | -0.15 modifier |
| High cyclomatic complexity in affected files (avg > 15, from code graph `properties` field) | -0.1 modifier |

Score is clamped to [0.0, 1.0]. When the code graph is unavailable, affected file count is estimated from keyword matching in explore cache (lower accuracy, but available).

#### Dimension: Historical Success Rate (0.0-1.0)

Assessed from completed pipeline run reports in `.forge/reports/`:

| Signal | Score |
|---|---|
| Last 5 runs for same `domain_area`: all PASS (score >= 80) | 1.0 |
| Last 5 runs: 4 PASS, 1 CONCERNS | 0.8 |
| Last 5 runs: 3+ PASS | 0.6 |
| Last 5 runs: mixed or fewer than 3 runs total | 0.4 |
| Last 5 runs: majority FAIL or CONCERNS | 0.2 |
| No prior runs | 0.3 (neutral — no evidence either way) |

### Pre-Run Cost Estimation

**NOTE:** Cost estimation is owned by F03 (model-routing-default.md) which defines `shared/pricing.json` and the dispatch-count-based estimation algorithm. F06 consumes the cost estimate from F03's infrastructure — it does NOT define its own pricing or estimation logic.

F06's role is to **display** the cost estimate as part of the confidence breakdown and use it as one input to the gating decision. The complexity_factor and mode_factor below influence the confidence score, not the cost estimate itself.

Complexity factor (for confidence, not cost): `1.0` for simple (1-5 files), `1.5` for medium (6-15), `2.0` for complex (16-30), `3.0` for large (30+).

Mode factor (for confidence, not cost): `1.0` for standard, `0.6` for bugfix, `0.7` for bootstrap, `1.3` for migration.

The cost estimate from F03 is presented alongside confidence as: `Estimated cost: $X.XX - $Y.YY`.

#### Time Estimation

Based on historical wall-clock times from `state.json.stage_timestamps` across previous runs:

```
estimated_time = sum(historical_avg_duration[stage] for stage in expected_stages)
```

Present as range: `Xm - Ym`.

### Execution Gate

After computing confidence, the gate decides:

| Effective Confidence | Level | Action |
|---|---|---|
| >= `autonomous_threshold` (default 0.7) | HIGH | Proceed autonomously. Log: `"Confidence: HIGH ({score}). Proceeding."` |
| >= `pause_threshold` (default 0.4) AND < `autonomous_threshold` | MEDIUM | Display plan summary, confidence breakdown, cost estimate, time estimate. Ask for confirmation via `AskUserQuestion`. |
| < `pause_threshold` (default 0.4) | LOW | Display concerns. Suggest `/forge-shape` for requirement refinement. Offer to proceed anyway. |

**MEDIUM confidence display:**

```
Pipeline Confidence: MEDIUM (0.62)

Breakdown:
  Requirement clarity:  0.65 (missing acceptance criteria)
  Pattern familiarity:  0.70 (3 matching PREEMPT items, cached plan found)
  Codebase complexity:  0.50 (12 affected files, crosses 2 module boundaries)
  Historical success:   0.60 (3/5 recent runs passed for domain "billing")

Estimated cost: $0.45 - $1.20
Estimated time: 8m - 22m
Expected stages: PREFLIGHT → EXPLORE → PLAN → VALIDATE → IMPLEMENT → VERIFY → REVIEW → SHIP → LEARN

Proceed? [Yes / Refine requirement / Abort]
```

**LOW confidence display:**

```
Pipeline Confidence: LOW (0.31)

Concerns:
  - Requirement is too vague (12 words, no actors, no acceptance criteria)
  - No prior runs in domain "inventory" — no historical baseline
  - Estimated blast radius: 25+ files across 3 components

Recommendation: Use /forge-shape to refine the requirement first.

[Proceed anyway / Refine with /forge-shape / Abort]
```

### Adaptive Trust Model

Trust starts at `initial_trust` (default 0.5) and adjusts based on user behavior:

#### Trust Increase

| Event | Trust Increase | Condition |
|---|---|---|
| Pipeline run completes with PASS, no user corrections | +0.05 | Score >= 80 AND user did not reject PR or provide feedback |
| User accepts AUTO decision (confidence was MEDIUM, user confirmed) | +0.02 | Confirmation was given without changes |
| 3 consecutive PASS runs without corrections | +0.10 (bonus) | Streak tracking in state |

#### Trust Decrease

| Event | Trust Decrease | Condition |
|---|---|---|
| User rejects PR | -0.10 | `feedback_loop_count` incremented |
| User provides design-level feedback | -0.08 | `feedback_classification == "design"` |
| User provides implementation-level feedback | -0.05 | `feedback_classification == "implementation"` |
| Pipeline FAIL verdict | -0.03 | Score < 60 |
| User aborts pipeline | -0.05 | `/forge-abort` invoked |

#### Trust Decay

To prevent stale trust from old sessions:

```
trust_after_decay = trust_level - trust_decay * runs_since_last_interaction
```

Where `trust_decay` (default 0.05) is applied per run without user correction (natural decay toward caution). Trust is clamped to [0.0, 1.0] and never decays below `initial_trust * 0.5` (floor of 0.25 at default settings).

#### Trust Persistence

Trust level is stored in `.forge/trust.json` (local, NOT committed to git, per-developer). This is deliberate — trust is per-developer, not per-repo. Developer A's trust level should not be overwritten by Developer B's commit.

```json
{
  "trust_level": 0.72,
  "last_updated": "2026-04-13T10:00:00Z",
  "consecutive_passes": 4,
  "total_corrections": 2,
  "total_runs": 15
}
```

The file survives `/forge-reset` (added to the persistence list alongside explore-cache and plan-cache).

### Per-Stage Confidence

Beyond the pre-execution gate, stages can surface confidence:

| Stage | Confidence Signal | Used By |
|---|---|---|
| PLAN | Plan quality assessment (Challenge Brief completeness, story count, domain coverage) | Validator uses to decide APPROVE vs REVISE threshold |
| VALIDATE | Validation confidence (how many concerns remain after 2 passes) | Orchestrator uses to decide whether to add extra validation retry |
| IMPLEMENT | Implementation confidence (how many files touched vs. plan estimate, test coverage of changes) | Verify stage uses to decide thoroughness of verification |
| REVIEW | Finding confidence (existing HIGH/MEDIUM/LOW per finding in `scoring.md`) | Quality gate dispatch routing (LOW findings excluded from fix cycles) |
| SHIP | Evidence freshness and completeness | Pre-ship verifier uses to decide whether evidence needs refresh |

Per-stage confidence is logged to `state.json` but does not gate execution — only PLAN-level confidence gates.

### Schema Additions to state.json

```json
{
  "confidence": {
    "overall_score": 0.62,
    "overall_level": "MEDIUM",
    "dimensions": {
      "clarity": 0.65,
      "familiarity": 0.70,
      "complexity": 0.50,
      "history": 0.60
    },
    "cost_estimate": {
      "low_usd": 0.45,
      "high_usd": 1.20,
      "model_tier": "standard"
    },
    "time_estimate": {
      "low_minutes": 8,
      "high_minutes": 22
    },
    "gate_decision": "confirm",
    "user_response": "proceed",
    "computed_at": "2026-04-13T10:00:00Z"
  },
  "trust": {
    "level": 0.72,
    "consecutive_passes": 4,
    "total_corrections": 2,
    "total_runs": 15,
    "last_updated": "2026-04-13T10:00:00Z"
  }
}
```

### Configuration

In `forge-config.md`:

```yaml
confidence:
  enabled: true
  planning_gate: true
  autonomous_threshold: 0.7
  pause_threshold: 0.4
  initial_trust: 0.5
  trust_decay: 0.05
  weights:
    clarity: 0.30
    familiarity: 0.25
    complexity: 0.20
    history: 0.25
  cost_estimation: true
  time_estimation: true
```

| Parameter | Type | Default | Range | Description |
|---|---|---|---|---|
| `enabled` | boolean | `true` | -- | Master toggle |
| `planning_gate` | boolean | `true` | -- | Enable pre-execution gating at PLAN |
| `autonomous_threshold` | float | `0.7` | 0.3-0.95 | Score above which pipeline proceeds without confirmation |
| `pause_threshold` | float | `0.4` | 0.1-0.7 | Score below which LOW confidence warning is shown |
| `initial_trust` | float | `0.5` | 0.0-1.0 | Starting trust level for new projects |
| `trust_decay` | float | `0.05` | 0.0-0.2 | Trust decay per run without interaction |
| `weights.clarity` | float | `0.30` | 0.0-1.0 | Weight for requirement clarity dimension |
| `weights.familiarity` | float | `0.25` | 0.0-1.0 | Weight for pattern familiarity dimension |
| `weights.complexity` | float | `0.20` | 0.0-1.0 | Weight for codebase complexity dimension |
| `weights.history` | float | `0.25` | 0.0-1.0 | Weight for historical success dimension |
| `cost_estimation` | boolean | `true` | -- | Include cost estimates in confidence display |
| `time_estimation` | boolean | `true` | -- | Include time estimates in confidence display |

**Constraints enforced at PREFLIGHT:**
- `autonomous_threshold` must be > `pause_threshold` (gap >= 0.1)
- All weights must sum to 1.0 (tolerance: +/- 0.01)
- `autonomous_threshold` must be >= 0.3 (never fully bypass confirmation below this)

### Data Flow

#### At PREFLIGHT

1. Load trust level from `.claude/forge-log.md`
2. Apply trust decay based on `runs_since_last_interaction`
3. Store current trust in `state.json.trust`

#### At PLAN (after planner completes, before VALIDATE)

1. Compute clarity score from requirement text
2. Compute familiarity score from PREEMPT items and plan cache
3. Compute complexity score from code graph or explore cache
4. Compute history score from `.forge/reports/`
5. Calculate weighted confidence score
6. Apply trust modifier to get effective confidence
7. Determine gate decision (proceed / confirm / suggest-shape)
8. If MEDIUM: display breakdown via `AskUserQuestion`, wait for response
9. If LOW: display concerns, suggest `/forge-shape`
10. Store confidence data in `state.json.confidence`
11. Log decision to `.forge/decisions.jsonl`

#### After Pipeline Completion (at LEARN)

1. Evaluate outcome: PASS/CONCERNS/FAIL, user corrections, PR acceptance
2. Update trust level per the trust adjustment rules
3. Persist updated trust to `.claude/forge-log.md`
4. Record confidence accuracy: was the confidence prediction correct?
   - HIGH confidence + PASS = calibrated
   - HIGH confidence + FAIL = over-confident (log for trend analysis)
   - LOW confidence + PASS = under-confident (log for trend analysis)

### Integration Points

| Agent / System | Integration | Change Required |
|---|---|---|
| `fg-100-orchestrator` | Invoke confidence estimator after PLAN, before VALIDATE. Gate execution based on result. | Add confidence gate step in orchestrator dispatch flow. |
| `fg-200-planner` | Provide plan quality assessment as input to confidence estimator. | Add plan quality signal to planner output (already partially present in Challenge Brief). |
| `fg-010-shaper` | LOW confidence gate suggests `/forge-shape`. Shaper output re-enters confidence estimation. | No change to shaper — orchestrator routes to shaper based on gate decision. |
| `fg-700-retrospective` | Update trust level based on run outcome. Record confidence prediction accuracy. | Add trust update logic to retrospective agent. |
| `fg-710-post-run` | Include confidence data in pipeline timeline. | Add confidence section to recap report. |
| `shared/intent-classification.md` | Reuse clarity signals (actors, entities, surface, criteria detection). | Reference existing signals; no duplication. |
| `shared/state-schema.md` | Add `confidence` and `trust` sections to state.json schema. | Schema version bump to 1.6.0. |
| Explore cache / Code graph | Query affected file count and complexity for complexity dimension. | Read-only access; no changes to cache/graph. |
| Plan cache | Check for cached plans to boost familiarity dimension. | Read-only access. |

### Error Handling

| Failure Mode | Behavior |
|---|---|
| Code graph unavailable | Complexity dimension falls back to explore-cache file count. If explore cache also missing, use `0.5` (neutral). |
| No pipeline history | History dimension uses `0.3` (neutral-cautious). |
| Trust data missing from forge-log.md | Use `initial_trust` from config. |
| Confidence computation fails (any error) | Log WARNING, set confidence to MEDIUM (0.5), proceed with confirmation gate. Never block pipeline due to confidence failure. |
| User does not respond to MEDIUM gate within 5 minutes (background mode) | Write escalation to `.forge/alerts.json` per background execution protocol. |
| `autonomous: true` mode | Confidence is computed and logged but gates are bypassed. LOW confidence + autonomous mode logs WARNING: "Low confidence ({score}) in autonomous mode — proceeding per autonomous flag." |

## Performance Characteristics

| Operation | Expected Latency | Token Cost |
|---|---|---|
| Clarity scoring | <10ms | 0 tokens (regex-based) |
| Familiarity scoring | <100ms | 0 tokens (reads from forge-log.md and plan-cache/index.json) |
| Complexity scoring | <500ms | 0 tokens (reads from code-graph.db or explore-cache.json) |
| History scoring | <200ms | 0 tokens (reads from .forge/reports/) |
| Confidence computation (total) | <1s | 0 tokens |
| Cost/time estimation | <100ms | 0 tokens |
| Trust update (at LEARN) | <50ms | 0 tokens |

The confidence system adds no token cost — it operates entirely on existing pipeline artifacts (explore cache, plan cache, reports, learnings). The only latency is from local file reads and SQL queries.

## Testing Approach

### Unit Tests (`tests/unit/confidence.bats`)

1. **Clarity scoring:** Test each signal independently with known requirement texts
2. **Familiarity scoring:** Mock forge-log.md and plan-cache, verify scores
3. **Complexity scoring:** Mock explore-cache with known file counts, verify inverted scoring
4. **History scoring:** Mock reports directory with known outcomes, verify score
5. **Weight validation:** Verify weights must sum to 1.0
6. **Trust adjustment:** Verify trust increase/decrease/decay for each event type
7. **Gate decisions:** Verify threshold-based routing (HIGH/MEDIUM/LOW)
8. **Cost estimation:** Verify token-to-cost calculation for each model tier

### Integration Tests (`tests/integration/confidence.bats`)

1. **Full flow:** Run `/forge-run --dry-run` with confidence enabled, verify confidence data in state.json
2. **Trust persistence:** Run two sequential pipeline runs, verify trust level updates in forge-log.md
3. **Autonomous mode bypass:** Run with `autonomous: true`, verify gates are logged but not enforced

### Scenario Tests

1. **HIGH confidence path:** Detailed requirement + rich PREEMPT data + small change + strong history = autonomous proceed
2. **LOW confidence path:** Vague requirement + no history + complex codebase = suggest /forge-shape
3. **Trust escalation:** 5 consecutive PASS runs → trust increases → autonomous threshold reached

## Acceptance Criteria

1. Confidence score is computed as a weighted sum of four dimensions (clarity, familiarity, complexity, history), each scored 0.0-1.0
2. Pre-execution gate at PLAN asks for confirmation when confidence is MEDIUM and suggests `/forge-shape` when confidence is LOW
3. When `autonomous: true`, gates are bypassed but confidence is still logged
4. Trust level persists in `.claude/forge-log.md` across runs and adjusts based on user corrections and pipeline outcomes
5. Cost estimate is displayed with the confidence breakdown, showing a range based on model tier pricing
6. Time estimate is displayed based on historical stage durations
7. Confidence data is recorded in `state.json.confidence` for retrospective analysis
8. Confidence system adds zero token cost (all computation is local)
9. When any confidence data source is unavailable (no graph, no history, no cache), the system degrades gracefully with neutral scores
10. `validate-plugin.sh` passes with the new `shared/confidence-estimator.md` added

## Migration Path

1. **v2.0.0:** Add `shared/confidence-estimator.md` defining the algorithm. Add `confidence:` section to `forge-config-template.md`. Update `fg-100-orchestrator.md` to invoke confidence gate.
2. **v2.0.0:** Add `confidence` and `trust` sections to `state-schema.md` (bump to v1.6.0). The `trust` section in `.claude/forge-log.md` is auto-created on first run.
3. **v2.0.0:** Default `confidence.enabled: true` but `confidence.planning_gate: true` — users get confidence information by default; they can disable the gate with `planning_gate: false`.
4. **v2.0.0:** Existing `autonomous: true` behavior is preserved — confidence gates are bypassed in autonomous mode.
5. **No breaking changes:** All confidence features are additive. Projects without `confidence:` config use defaults. Trust starts at `initial_trust` for all existing projects on first run.

## Dependencies

**Depends on:**
- F01 (Tree-sitter Code Graph): for codebase complexity signals (affected file count, community boundaries, cyclomatic complexity). Falls back to explore cache when F01 is unavailable.
- Existing: `shared/intent-classification.md` (clarity signals), explore cache (file patterns), plan cache (similarity matching), learnings (PREEMPT items), `.forge/reports/` (historical outcomes).

**Depended on by:**
- F09 (Active Knowledge Base): learned rules contribute to the familiarity dimension score.
