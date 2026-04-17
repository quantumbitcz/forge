# Developer Experience Metrics

Aggregates developer-facing metrics across pipeline runs to answer: "Is the pipeline getting better at helping me?" Stored in `.forge/dx-metrics.json` and surfaced via `/forge-insights`.

## Overview

Pipeline telemetry (tokens, findings, iterations) is available in `state.json` but not aggregated into actionable DX metrics across runs. This system computes 10 developer-impact metrics from existing state data and tracks trends over time.

**Feature flag:** `dx_metrics.enabled` (default: `true`). Minimal overhead since all source data already exists in `state.json`.

## Metrics Definitions

| # | Metric | Definition | Source | Unit |
|---|--------|-----------|--------|------|
| 1 | `cycle_time_minutes` | Time from PREFLIGHT start to SHIPPING end (or pipeline end) | `state.json` stage timestamps | minutes |
| 2 | `first_attempt_success` | Pipeline shipped without safety gate restart or stage rollback | `state.json` `phase_iterations`, `total_iterations` | boolean |
| 3 | `cost_usd` | Estimated token cost for the entire run | `state.json` `tokens.cost.estimated_cost_usd` | USD |
| 4 | `cost_per_outcome` | Cost categorized by pipeline mode (feature, bugfix, migration, bootstrap) | `state.json` `mode` + `tokens.cost` | USD |
| 5 | `convergence_efficiency` | `1 - (iterations_used / max_iterations)` -- budget remaining | `state.json` iteration counters + config max | ratio 0-1 |
| 6 | `review_efficiency` | Findings resolved per iteration (higher = better) | `state.json` finding counts, iteration counts | findings/iteration |
| 7 | `human_interventions` | Number of `AskUserQuestion` invocations during the run | Stage notes | count |
| 8 | `autonomy_rate` | `1 - (human_interventions / total_agent_dispatches)` | Computed | ratio 0-1 |
| 9 | `stage_durations` | Per-stage wall-clock time breakdown | `state.json` stage timestamps | object (stage -> minutes) |
| 10 | `finding_density` | Findings per 1,000 lines changed | Finding count / changed lines | findings/KLOC |

### Additional Per-Run Fields

| Field | Description |
|-------|-------------|
| `lines_changed` | Total lines added + modified |
| `files_changed` | Number of files created or modified |
| `test_count_added` | Number of tests written in this run |
| `findings_total` | Total findings emitted by reviewers |
| `findings_resolved` | Findings fixed during convergence |

## DX Metrics Store

**Location:** `.forge/dx-metrics.json`

**Lifecycle:**
- Created on first pipeline run with `dx_metrics.enabled: true`
- Appended after each run by `fg-710-post-run`
- Aggregates recomputed on each append
- Survives `/forge-recover reset` (alongside benchmarks, explore-cache, plan-cache)
- Maximum `retention_runs` entries retained (default: 100, oldest trimmed)

**Schema:** See `shared/schemas/dx-metrics-schema.json`.

## Aggregate Metrics

Recomputed after each run append:

| Aggregate | Description |
|-----------|-------------|
| `total_runs` | Count of all tracked runs |
| `avg_cycle_time_minutes` | Mean cycle time |
| `first_attempt_success_rate` | Ratio of first-attempt successes (excludes incomplete runs) |
| `avg_cost_usd` | Mean cost per run |
| `avg_cost_per_feature_usd` | Mean cost for `mode: standard` runs |
| `avg_cost_per_bugfix_usd` | Mean cost for `mode: bugfix` runs |
| `avg_convergence_efficiency` | Mean convergence efficiency |
| `avg_autonomy_rate` | Mean autonomy rate |
| `slowest_stage` | Stage with highest average duration |
| `most_common_mode` | Most frequently used pipeline mode |

## Recap Integration

When `dx_metrics.include_in_recap: true`, a DX summary table is appended to the post-run recap:

```markdown
## Run Metrics

| Metric | This Run | Average (last N runs) | Trend |
|--------|----------|-----------------------|-------|
| Cycle time | 18.5 min | 22.3 min | Improving |
| First attempt | Yes | 72% | -- |
| Cost | $0.42 | $0.38 | Slightly above |
| Convergence efficiency | 85% | 78% | Improving |
| Autonomy rate | 97% | 94% | Improving |
```

**Trend computation:**
- `Improving`: current value is better than average by >5%
- `Stable`: current value is within 5% of average
- `Degrading`: current value is worse than average by >5%
- For `first_attempt_success` (boolean): no trend, just current value vs historical rate

## Sprint Burndown

When `mode == sprint` and `dx_metrics.sprint_burndown: true`:

1. Sprint orchestrator tracks feature completion times
2. Post-run agent plots completed vs planned over sprint duration
3. Burndown data stored under `sprint` key in `dx-metrics.json`:

```json
{
  "sprint": {
    "sprint_id": "sprint-42",
    "planned_features": 5,
    "completed_features": 3,
    "burndown": [
      { "timestamp": "2026-04-13T09:00:00Z", "completed": 0, "remaining": 5 },
      { "timestamp": "2026-04-13T10:30:00Z", "completed": 1, "remaining": 4 },
      { "timestamp": "2026-04-13T12:00:00Z", "completed": 3, "remaining": 2 }
    ]
  }
}
```

## Configuration

```yaml
dx_metrics:
  enabled: true                # Enable DX metric tracking. Default: true.
  retention_runs: 100          # Max run entries. Default: 100. Range: 10-500.
  include_in_recap: true       # Include DX summary in post-run recap. Default: true.
  sprint_burndown: true        # Track sprint burndown. Default: true.
```

## Computation Details

### cycle_time_minutes

```
end_time = state.json stage timestamps for SHIPPING (or last completed stage)
start_time = state.json stage timestamps for PREFLIGHT
cycle_time_minutes = (end_time - start_time) / 60000
```

### first_attempt_success

```
success = true if:
  - All phase_iterations == 1
  - No safety gate restarts logged
  - Pipeline reached SHIPPING stage
```

### convergence_efficiency

```
convergence_efficiency = 1 - (total_iterations / config.convergence.max_iterations)
```

Clamped to [0, 1]. Higher is better (more budget remaining).

### review_efficiency

```
review_efficiency = findings_resolved / max(quality_cycles, 1)
```

Higher means more findings resolved per iteration.

### autonomy_rate

```
autonomy_rate = 1 - (human_interventions / max(total_agent_dispatches, 1))
```

Clamped to [0, 1]. Higher means less human intervention.

### finding_density

```
finding_density = (findings_total / max(lines_changed, 1)) * 1000
```

## Data Flow

```
Stage 9 (LEARN)
  fg-710-post-run
    Part A: Feedback Capture (existing)
    Part B: Recap Generation (existing)
    Part C: Pipeline Timeline (existing)
    Part D: Next-Task Prediction (F18)
    Part E: DX Metrics (NEW)
      1. Read state.json for timestamps, counters, costs, mode
      2. Read stage notes for finding counts, resolution data
      3. Compute all 10 metrics
      4. Write to .forge/dx-metrics.json
      5. Recompute aggregates
      6. If include_in_recap: append DX summary to recap
```

## Integration Points

| File | Change |
|------|--------|
| `agents/fg-710-post-run.md` | Add Part E: DX Metrics computation and recap integration |
| `skills/forge-insights/SKILL.md` | Add "Developer Impact" dashboard section |
| `agents/fg-090-sprint-orchestrator.md` | Pass sprint metadata for burndown tracking |
| `modules/frameworks/*/forge-config-template.md` | Add `dx_metrics:` section |

## Error Handling

| Failure Mode | Detection | Behavior |
|-------------|-----------|----------|
| Missing stage timestamps | `state.json` timestamps null | Skip `cycle_time_minutes` and `stage_durations`. Other metrics still computed. |
| Token cost not tracked | `estimated_cost_usd` is null or 0 | Set `cost_usd: null`. Excluded from cost averages. |
| Pipeline aborted | Stage < SHIPPING | Record with `completed: false`. Excluded from `first_attempt_success_rate`. |
| `dx-metrics.json` corrupted | JSON parse failure | Back up to `.forge/dx-metrics.json.bak`, create fresh file. Log WARNING. |
