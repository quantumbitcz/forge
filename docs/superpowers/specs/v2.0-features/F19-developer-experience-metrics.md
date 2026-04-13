# F19: Developer Experience Metrics Dashboard

## Status
DRAFT — 2026-04-13

## Problem Statement

Forge tracks pipeline telemetry: token usage per stage/agent, finding counts, convergence iterations, and quality scores. The retrospective (`fg-700`) auto-tunes scoring parameters and extracts PREEMPT learnings. The insights skill (`/forge-insights`) shows quality trends and cost analysis.

However, none of these metrics answer the questions developers and engineering managers actually care about:

- **How long does it take to go from requirement to PR?** (Cycle time)
- **How often does the pipeline succeed on the first attempt?** (First-attempt success rate)
- **How much does it cost to build a feature vs fix a bug?** (Cost-per-outcome)
- **How efficient is the pipeline at converging?** (Iterations used vs budgeted)
- **How often does the pipeline need human intervention?** (Autonomy rate)

These are *developer experience* metrics, not pipeline performance metrics. They measure the impact on the human developer, not the internal mechanics of the pipeline.

**Gap:** Pipeline telemetry is available in `state.json` but not aggregated across runs into actionable DX metrics. A developer cannot currently answer "Is the pipeline getting better at helping me?" without manually correlating data from multiple state files and reports.

**Competitive context:** Jellyfish, LinearB, and Pluralsight Flow track DORA-style metrics (lead time, deployment frequency, MTTR, change failure rate). These tools instrument CI/CD pipelines but not AI coding assistants. Forge is uniquely positioned to track AI-assisted development metrics.

## Proposed Solution

Add a DX metrics store (`.forge/dx-metrics.json`) that aggregates developer-facing metrics across pipeline runs. Integrate with `/forge-insights` to display a "Developer Impact" dashboard section. Default-on with minimal overhead since all source data already exists in `state.json`.

## Detailed Design

### Architecture

```
Pipeline completion (Stage 9 — LEARN)
     |
     +-- fg-700-retrospective (existing)
     |     +-- Collect raw telemetry from state.json
     |
     +-- fg-710-post-run (existing)
     |     +-- After recap, compute DX metrics (NEW)
     |     +-- Append to .forge/dx-metrics.json
     |
     v
.forge/dx-metrics.json (append per run)
     |
     v
/forge-insights (enhanced)
     +-- Quality Trends (existing)
     +-- Cost Analysis (existing)
     +-- Convergence Patterns (existing)
     +-- Memory Health (existing)
     +-- Developer Impact (NEW)
           +-- Cycle time trends
           +-- First-attempt success rate
           +-- Cost-per-outcome breakdown
           +-- Autonomy rate
           +-- Sprint burndown (when applicable)
```

### Metrics Definitions

| Metric | Definition | Source | Unit |
|---|---|---|---|
| `cycle_time_minutes` | Time from pipeline start (PREFLIGHT) to PR creation (SHIPPING) or pipeline end | `state.json` stage timestamps | minutes |
| `first_attempt_success` | Pipeline shipped without any convergence restart (safety gate restart) or stage rollback | `state.json` `phase_iterations`, `total_iterations` | boolean |
| `cost_usd` | Estimated token cost for the entire run | `state.json` `tokens.cost.estimated_cost_usd` | USD |
| `cost_per_outcome` | Cost categorized by pipeline mode (feature, bugfix, migration, bootstrap) | `state.json` `mode` + `tokens.cost` | USD |
| `convergence_efficiency` | `1 - (iterations_used / max_iterations)` — how much budget was left | `state.json` iteration counters + config max | ratio 0-1 |
| `review_efficiency` | Findings resolved per iteration (higher = better) | `state.json` finding counts, iteration counts | findings/iteration |
| `human_interventions` | Number of `AskUserQuestion` invocations during the run | `state.json` or stage notes | count |
| `autonomy_rate` | `1 - (human_interventions / total_agent_dispatches)` | Computed | ratio 0-1 |
| `stage_durations` | Per-stage wall-clock time breakdown | `state.json` stage timestamps | object (stage -> minutes) |
| `finding_density` | Findings per 1,000 lines changed | Finding count / changed lines | findings/KLOC |

### Schema / Data Model

**`.forge/dx-metrics.json`:**

```json
{
  "version": "1.0.0",
  "runs": [
    {
      "run_id": "story-123",
      "timestamp": "2026-04-13T10:30:00Z",
      "mode": "standard",
      "branch": "feat/user-auth",
      "requirement_summary": "Add user authentication with JWT",
      "metrics": {
        "cycle_time_minutes": 18.5,
        "first_attempt_success": true,
        "cost_usd": 0.42,
        "convergence_efficiency": 0.85,
        "review_efficiency": 3.2,
        "human_interventions": 1,
        "autonomy_rate": 0.97,
        "finding_density": 12.5,
        "stage_durations": {
          "PREFLIGHT": 0.5,
          "EXPLORING": 1.2,
          "PLANNING": 2.1,
          "VALIDATING": 0.8,
          "IMPLEMENTING": 6.3,
          "VERIFYING": 3.5,
          "REVIEWING": 2.8,
          "DOCUMENTING": 0.5,
          "SHIPPING": 0.3,
          "LEARNING": 0.5
        },
        "lines_changed": 480,
        "files_changed": 12,
        "test_count_added": 8,
        "findings_total": 6,
        "findings_resolved": 6
      }
    }
  ],
  "aggregates": {
    "total_runs": 25,
    "avg_cycle_time_minutes": 22.3,
    "first_attempt_success_rate": 0.72,
    "avg_cost_usd": 0.38,
    "avg_cost_per_feature_usd": 0.45,
    "avg_cost_per_bugfix_usd": 0.22,
    "avg_convergence_efficiency": 0.78,
    "avg_autonomy_rate": 0.94,
    "slowest_stage": "IMPLEMENTING",
    "most_common_mode": "standard"
  }
}
```

**Lifecycle:**
- Created on first pipeline run with `dx_metrics.enabled: true`
- Appended after each run by `fg-710-post-run`
- Aggregates recomputed on each append
- Survives `/forge-reset` (alongside benchmarks, explore-cache, plan-cache)
- Maximum 100 run entries retained (oldest trimmed)

### Configuration

In `forge-config.md`:

```yaml
# Developer experience metrics (v2.0+)
dx_metrics:
  enabled: true                # Enable DX metric tracking. Default: true. Minimal overhead.
  retention_runs: 100          # Max run entries to retain. Default: 100. Range: 10-500.
  include_in_recap: true       # Include DX summary in post-run recap. Default: true.
  sprint_burndown: true        # Track sprint burndown when in sprint mode. Default: true.
```

**PREFLIGHT validation constraints:**

| Parameter | Range | Default | Rationale |
|---|---|---|---|
| `dx_metrics.enabled` | boolean | `true` | Zero overhead from source data; aggregation is <50ms |
| `dx_metrics.retention_runs` | 10-500 | 100 | <10 provides insufficient trend data; >500 wastes storage |
| `dx_metrics.include_in_recap` | boolean | `true` | Developers want to see DX stats after each run |

### Data Flow

**Metric collection (Stage 9 — LEARN):**

1. Post-run agent (`fg-710`) completes Parts A and B
2. Part C (or after Part C if F18 predictions also enabled):
   a. Read `state.json` for stage timestamps, iteration counters, token costs, mode
   b. Read stage notes for finding counts and resolution data
   c. Compute derived metrics:
      - `cycle_time_minutes`: diff between PREFLIGHT start and SHIPPING end (or LEARNING end)
      - `first_attempt_success`: `phase_iterations` for all stages == 1 AND no safety gate restarts
      - `convergence_efficiency`: `1 - (total_iterations / config.convergence.max_iterations)`
      - `review_efficiency`: `findings_resolved / quality_cycles`
      - `human_interventions`: count of `AskUserQuestion` tool uses in stage notes
      - `autonomy_rate`: `1 - (human_interventions / total_agent_dispatches)`
   d. Write metrics to `.forge/dx-metrics.json`
   e. Recompute aggregates
3. If `include_in_recap: true`, append DX summary to recap:

```markdown
## Run Metrics

| Metric | This Run | Average (last 25 runs) | Trend |
|---|---|---|---|
| Cycle time | 18.5 min | 22.3 min | Improving |
| First attempt | Yes | 72% | — |
| Cost | $0.42 | $0.38 | Slightly above |
| Convergence efficiency | 85% | 78% | Improving |
| Autonomy rate | 97% | 94% | Improving |
```

**Sprint burndown** (when `mode == sprint`):

1. Sprint orchestrator tracks feature completion times
2. Post-run agent plots completed vs planned over the sprint duration
3. Burndown data stored in `dx-metrics.json` under a `sprint` key:

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

### Integration Points

| File | Change |
|---|---|
| `agents/fg-710-post-run.md` | Add DX metric computation after recap. New section computing all metrics from state.json. Append DX summary to recap markdown. |
| `skills/forge-insights/SKILL.md` | Add "Developer Impact" section. Read `.forge/dx-metrics.json`. Display trends, comparisons, and breakdowns. |
| `shared/state-schema.md` | Document `.forge/dx-metrics.json` schema, lifecycle, and retention policy. |
| `agents/fg-090-sprint-orchestrator.md` | Pass sprint metadata (planned features, sprint ID) for burndown tracking. |
| `modules/frameworks/*/forge-config-template.md` | Add `dx_metrics:` section. |

### Error Handling

**Failure mode 1: `state.json` missing stage timestamps.**
- Detection: Stage timestamps are null or missing
- Behavior: Skip `cycle_time_minutes` and `stage_durations`. Other metrics still computed from available data. Log INFO: "Cycle time unavailable: stage timestamps missing."

**Failure mode 2: Token cost not tracked.**
- Detection: `tokens.cost.estimated_cost_usd` is null or 0
- Behavior: Set `cost_usd: null`. Aggregates exclude null entries from cost averages.

**Failure mode 3: Pipeline aborted mid-run.**
- Detection: State shows stage < SHIPPING
- Behavior: Record partial metrics with `completed: false` flag. Exclude from `first_attempt_success_rate` calculation but include in cycle time trends (as an outlier indicator).

**Failure mode 4: `dx-metrics.json` corrupted.**
- Detection: JSON parse failure
- Behavior: Back up corrupted file to `.forge/dx-metrics.json.bak`, create fresh file. Log WARNING: "DX metrics history reset due to corruption."

## Performance Characteristics

| Step | Duration | Token Cost | Notes |
|---|---|---|---|
| Read state.json | 1-5ms | 0 | File read |
| Compute metrics | <1ms | 0 | Arithmetic |
| Read dx-metrics.json | 1-5ms | 0 | File read |
| Append + recompute aggregates | 5-20ms | 0 | JSON parse + write |
| Format recap section | 100-200 tokens | N/A | LLM formatting |
| **Total** | **8-31ms + 200 tokens** | | Negligible |

**Storage:** ~300 bytes per run entry. At 100-run retention: ~30KB. Negligible.

## Testing Approach

### Structural Tests (`tests/structural/`)

1. **Agent update:** `fg-710-post-run.md` contains DX metrics computation section
2. **Config template:** All `forge-config-template.md` files include `dx_metrics:` section
3. **State schema:** `dx-metrics.json` documented in `state-schema.md`

### Unit Tests (`tests/unit/`)

1. **`dx-metrics.bats`:**
   - Cycle time computed correctly from stage timestamps
   - First attempt success: true when no safety gate restarts
   - First attempt success: false when phase_iterations > 1
   - Convergence efficiency: 0.85 when 3/20 iterations used
   - Autonomy rate: computed correctly from intervention count
   - Aggregates recomputed on append
   - Retention enforced: oldest runs trimmed at `retention_runs`
   - Config disabled: `dx_metrics.enabled: false` skips computation
   - Partial run: `completed: false` flag set

2. **`dx-metrics-insights.bats`:**
   - `/forge-insights` displays "Developer Impact" section
   - Trend direction computed correctly (improving/stable/degrading)

## Acceptance Criteria

1. All 10 defined metrics are computed and stored after each pipeline run
2. `.forge/dx-metrics.json` maintains history with configurable retention
3. Aggregates are recomputed after each run (averages, rates, trends)
4. Post-run recap includes DX summary table when `include_in_recap: true`
5. `/forge-insights` displays "Developer Impact" section with trends
6. Sprint burndown tracks completed vs planned features over time
7. Aborted runs are recorded with `completed: false` and excluded from success rate
8. Feature is default-on with negligible overhead (<50ms, <200 tokens)
9. `dx-metrics.json` survives `/forge-reset`
10. Corrupted metrics file is backed up and recreated

## Migration Path

**From v1.20.1 to v2.0:**

1. **Zero breaking changes.** DX metrics are computed from existing state.json data. No new collection mechanisms required.
2. **Post-run agent update:** New computation section added after existing Part B (and Part C if F18 is also enabled). Execution order: A -> B -> (C predictions) -> (D dx-metrics).
3. **Config:** `dx_metrics.enabled: true` by default. No action needed for existing projects.
4. **New file:** `.forge/dx-metrics.json` created on first tracked run.
5. **Insights skill:** New dashboard section added. Existing sections unchanged.
6. **No new dependencies.** All data sourced from existing `state.json` fields.

## Dependencies

**This feature depends on:**
- `state.json` stage timestamps and token tracking (already tracked by orchestrator)
- `fg-710-post-run` recap generation (metrics appended to recap)
- `/forge-insights` skill (for dashboard display)

**Other features that depend on this:**
- F17 (Performance Tracking): performance metrics complement DX metrics in the insights dashboard
- F18 (Next-Task Prediction): prediction accuracy rate becomes a DX metric

**Other features that benefit from this:**
- Sprint orchestration: burndown tracking provides visibility into multi-feature progress
- Retrospective: DX metric trends inform auto-tuning decisions (e.g., if autonomy rate is low, suggest raising `autonomous: true`)
