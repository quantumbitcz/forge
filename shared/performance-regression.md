# Performance Regression Tracking

Detects build time, test duration, bundle size, and custom metric regressions across pipeline runs by comparing current values against a rolling average of recent runs.

## Overview

Performance regressions -- changes that silently degrade build time, test duration, or artifact size -- are invisible to quality findings. This system records key metrics per pipeline run in `.forge/benchmarks.json` and compares against a rolling average at REVIEW stage.

**Feature flag:** `performance_tracking.enabled` (default: `false`, opt-in).

## Benchmark Store

**Location:** `.forge/benchmarks.json`

**Lifecycle:**
- Created on first pipeline run with `performance_tracking.enabled: true`
- Appended after each run (rolling window of last N runs, default 10)
- Survives `/forge-admin recover reset` (like explore-cache and plan-cache)
- Only manual `rm -rf .forge/` removes it
- Trimmed to `rolling_window * 2` entries when file exceeds 1MB

**Schema:** See `shared/schemas/benchmarks-schema.json`.

## Metrics Tracked

| Metric | Source | Collected By | Notes |
|--------|--------|-------------|-------|
| `build_time_ms` | Wall-clock timing of build command | `fg-505-build-verifier` | Written to `.forge/.build-metrics.json` |
| `lint_time_ms` | Wall-clock timing of lint command | `fg-505-build-verifier` | Written to `.forge/.build-metrics.json` |
| `test_duration_ms` | Wall-clock timing of test suite | `fg-500-test-gate` | Written to `.forge/.test-metrics.json` |
| `test_count` | Number of tests executed | `fg-500-test-gate` | Written to `.forge/.test-metrics.json` |
| `bundle_size_bytes` | Sum of frontend output directory | `fg-505-build-verifier` | `dist/`, `build/`, `.next/` |
| `binary_size_bytes` | Backend binary size | `fg-505-build-verifier` | `build/libs/`, `target/`, `bin/` |
| `artifact_sizes` | Individual artifact file sizes | `fg-505-build-verifier` | Only when `collect.artifact_sizes: true` |
| `custom` | User-defined metrics via regex patterns | `fg-500-test-gate` | See Custom Metrics below |

## Regression Detection Algorithm

Detection runs at REVIEW stage in `fg-400-quality-gate`.

### Step 1: Read Metrics

1. Read `.forge/.build-metrics.json` (temporary, written by build verifier)
2. Read `.forge/.test-metrics.json` (temporary, written by test gate)
3. Read `.forge/benchmarks.json` for rolling average

### Step 2: Compute Change

For each metric:

```
change_pct = ((current - rolling_average) / rolling_average) * 100
```

### Step 3: Compare Against Thresholds

| Condition | Action |
|-----------|--------|
| `change_pct > threshold` | Emit `PERF-REGRESSION-*` finding at WARNING |
| `change_pct > 2 * threshold` | Escalate to severity per `severity_escalation.double_threshold` (default: CRITICAL) |
| `change_pct <= threshold` | No finding |

### Step 4: Append and Update

1. Append current metrics to `.forge/benchmarks.json`
2. Recompute rolling average (trim to `rolling_window` size)
3. Clean up temporary `.forge/.build-metrics.json` and `.forge/.test-metrics.json`

## Thresholds

| Metric | Default Threshold | Config Key | Range |
|--------|-------------------|-----------|-------|
| Build time | 20% increase | `performance_tracking.thresholds.build_time_pct` | 5-100 |
| Test duration | 30% increase | `performance_tracking.thresholds.test_duration_pct` | 5-100 |
| Bundle/artifact size | 10% increase | `performance_tracking.thresholds.bundle_size_pct` | 5-100 |
| Test count decrease | 10% decrease | `performance_tracking.thresholds.test_count_decrease_pct` | 5-50 |
| Custom metrics | Per-metric | `performance_tracking.custom_metrics[].threshold_pct` | 5-100 |

**Insufficient baseline:** When `benchmarks.json` has fewer runs than `rolling_window / 2`, thresholds are widened by 50% to account for low sample size.

## Finding Categories

| Category | Severity | Trigger |
|----------|----------|---------|
| `PERF-REGRESSION-BUILD` | WARNING (CRITICAL at 2x) | Build time exceeds threshold |
| `PERF-REGRESSION-TEST` | WARNING (CRITICAL at 2x) | Test duration exceeds threshold |
| `PERF-REGRESSION-BUNDLE` | WARNING (CRITICAL at 2x) | Bundle/artifact size exceeds threshold |
| `PERF-REGRESSION-CUSTOM` | Configurable per metric | Custom metric exceeds threshold |

All categories registered in `shared/checks/category-registry.json`.

## Custom Metrics

Users define custom metrics extracted from test or build output:

```yaml
performance_tracking:
  custom_metrics:
    - name: api_response_p95_ms
      pattern: "p95 response time: (\\d+)ms"
      source: test_output
      threshold_pct: 25
      severity: WARNING
    - name: db_query_count
      pattern: "Total queries: (\\d+)"
      source: test_output
      threshold_pct: 50
      severity: WARNING
```

After test gate runs, scan test output for custom metric patterns. Apply regex capture group to extract numeric value. Store in `metrics.custom.{name}`. Compare against custom threshold at REVIEW.

## Configuration

```yaml
performance_tracking:
  enabled: false                          # Opt-in. Default: false.
  rolling_window: 10                      # Recent runs to average. Default: 10. Range: 3-50.
  thresholds:
    build_time_pct: 20                    # Build time increase %. Default: 20. Range: 5-100.
    test_duration_pct: 30                 # Test duration increase %. Default: 30. Range: 5-100.
    bundle_size_pct: 10                   # Bundle/artifact size increase %. Default: 10. Range: 5-100.
    test_count_decrease_pct: 10           # Test count decrease %. Default: 10. Range: 5-50.
  severity_escalation:
    double_threshold: CRITICAL            # Severity when metric exceeds 2x threshold. Default: CRITICAL.
  collect:
    build_time: true
    test_duration: true
    bundle_size: true
    artifact_sizes: false
  custom_metrics: []
```

## Error Handling

| Failure Mode | Detection | Behavior |
|-------------|-----------|----------|
| No baseline data (first run) | `.forge/benchmarks.json` missing or 0 runs | Record metrics as first data point. No findings emitted. Log INFO. |
| Insufficient baseline | Fewer runs than `rolling_window / 2` | Use available data with thresholds widened by 50%. Log INFO. |
| Build/test metrics not available | `.forge/.build-metrics.json` or `.forge/.test-metrics.json` missing | Skip corresponding regression check. Occurs in dry-run or skipped stages. |
| Metric spike (environmental) | N/A | Rolling average smooths single-run anomalies. Users can prune outliers from `benchmarks.json`. |
| `benchmarks.json` too large | File exceeds 1MB | Trim to `rolling_window * 2` most recent runs. Log INFO. |

## Data Flow Diagram

```
Stage 5 (VERIFY)
  fg-505-build-verifier  -->  .forge/.build-metrics.json
  fg-500-test-gate       -->  .forge/.test-metrics.json

Stage 6 (REVIEW)
  fg-400-quality-gate
    1. Read .build-metrics.json + .test-metrics.json
    2. Read .forge/benchmarks.json (rolling average)
    3. Compare current vs average per metric
    4. Emit PERF-REGRESSION-* findings if threshold exceeded
    5. Append current to benchmarks.json
    6. Recompute rolling average
```

## Integration Points

| File | Change |
|------|--------|
| `agents/fg-505-build-verifier.md` | Record build_time_ms, artifact sizes to `.forge/.build-metrics.json` |
| `agents/fg-500-test-gate.md` | Record test_duration_ms, test_count to `.forge/.test-metrics.json` |
| `agents/fg-400-quality-gate.md` | Regression detection before review dispatch |
| `shared/checks/category-registry.json` | 4 new `PERF-REGRESSION-*` categories |
| `modules/frameworks/*/forge-config-template.md` | `performance_tracking:` section |
| `skills/forge-ask/SKILL.md` §Subcommand: insights | Performance Trends dashboard section |
