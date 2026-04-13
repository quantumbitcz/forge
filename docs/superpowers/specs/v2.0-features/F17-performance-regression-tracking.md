# F17: Performance Regression Tracking Across Runs

## Status
DRAFT — 2026-04-13

## Problem Statement

Forge tracks quality scores, finding counts, and convergence patterns across pipeline runs. It supports K6 for load testing via the testing modules. However, there is no mechanism to detect *performance regressions* — changes that silently degrade build time, test duration, or artifact size without triggering any quality finding.

**Common regression scenarios:**
- A new dependency adds 8 seconds to build time (20% increase) — noticed only when CI becomes "slow"
- A frontend change adds 150KB to the production bundle — noticed only when Lighthouse scores drop
- A test helper change doubles test suite duration — noticed only when developers start skipping tests
- A binary size increase pushes a mobile app over the 200MB App Store warning threshold

These regressions are invisible to the current pipeline because no agent measures, stores, or compares performance metrics across runs. Each run is evaluated in isolation.

**Competitive context:** Nx and Turborepo track build cache hit rates. Lighthouse CI tracks web performance scores. Datadog CI Visibility tracks test duration. No AI coding tool integrates all of these into a single regression detection system within the development pipeline.

## Proposed Solution

Add a performance benchmark store (`.forge/benchmarks.json`) that records key metrics per pipeline run. Build verifier and test gate record metrics. A new check at REVIEW stage compares current metrics against the rolling average and emits `PERF-REGRESSION-*` findings when thresholds are exceeded.

## Detailed Design

### Architecture

```
Pipeline Stage 5 (VERIFY)
     |
     +-- fg-505-build-verifier
     |     +-- Record: build_time_ms, artifact_size_bytes (NEW)
     |
     +-- fg-500-test-gate
     |     +-- Record: test_duration_ms, test_count (NEW)
     |
     v
.forge/benchmarks.json (append per run)
     |
     v
Pipeline Stage 6 (REVIEW)
     |
     +-- fg-400-quality-gate
           +-- Compare current vs rolling average (NEW)
           +-- Emit PERF-REGRESSION-* findings if thresholds exceeded
```

**Key principle:** Metrics are collected passively during normal pipeline operations (build, test). No additional commands or tools are needed. Regression detection happens at REVIEW, after all metrics are captured.

### Schema / Data Model

**`.forge/benchmarks.json`:**

```json
{
  "version": "1.0.0",
  "runs": [
    {
      "run_id": "story-id-or-timestamp",
      "timestamp": "2026-04-13T10:30:00Z",
      "branch": "feat/user-auth",
      "mode": "standard",
      "metrics": {
        "build_time_ms": 12500,
        "lint_time_ms": 3200,
        "test_duration_ms": 45000,
        "test_count": 342,
        "bundle_size_bytes": 1048576,
        "binary_size_bytes": null,
        "artifact_sizes": {
          "dist/main.js": 524288,
          "dist/vendor.js": 412672
        },
        "custom": {}
      }
    }
  ],
  "rolling_average": {
    "window_size": 10,
    "build_time_ms": 10800,
    "lint_time_ms": 2900,
    "test_duration_ms": 38000,
    "test_count": 335,
    "bundle_size_bytes": 950000
  }
}
```

**Lifecycle:**
- Created on first pipeline run with `performance_tracking.enabled: true`
- Appended after each run (rolling window of last N runs, default 10)
- Survives `/forge-reset` (like explore-cache and plan-cache)
- Only manual `rm -rf .forge/` removes it

**Custom metrics format:**

Users can define custom metrics extracted from test or build output:

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

### Finding Categories

```json
{
  "PERF-REGRESSION-BUILD": { "description": "Build time regression exceeding configured threshold", "agents": ["fg-400-quality-gate"], "wildcard": false, "priority": 4, "affinity": ["fg-416-backend-performance-reviewer"] },
  "PERF-REGRESSION-TEST": { "description": "Test suite duration regression exceeding configured threshold", "agents": ["fg-400-quality-gate"], "wildcard": false, "priority": 4, "affinity": ["fg-410-code-reviewer"] },
  "PERF-REGRESSION-BUNDLE": { "description": "Bundle/artifact size regression exceeding configured threshold", "agents": ["fg-400-quality-gate"], "wildcard": false, "priority": 4, "affinity": ["fg-413-frontend-reviewer"] },
  "PERF-REGRESSION-CUSTOM": { "description": "Custom performance metric regression", "agents": ["fg-400-quality-gate"], "wildcard": false, "priority": 4, "affinity": [] }
}
```

### Configuration

In `forge-config.md`:

```yaml
# Performance regression tracking (v2.0+)
performance_tracking:
  enabled: false                          # Opt-in. Default: false.
  rolling_window: 10                      # Number of recent runs to average. Default: 10. Range: 3-50.
  thresholds:
    build_time_pct: 20                    # Build time increase % to trigger WARNING. Default: 20. Range: 5-100.
    test_duration_pct: 30                 # Test duration increase % to trigger WARNING. Default: 30. Range: 5-100.
    bundle_size_pct: 10                   # Bundle/artifact size increase % to trigger WARNING. Default: 10. Range: 5-100.
    test_count_decrease_pct: 10           # Test count decrease % to trigger WARNING (tests deleted). Default: 10. Range: 5-50.
  severity_escalation:
    double_threshold: CRITICAL            # If metric exceeds 2x the configured threshold, escalate to CRITICAL. Default: CRITICAL.
  collect:
    build_time: true                      # Track build duration. Default: true.
    test_duration: true                   # Track test suite duration. Default: true.
    bundle_size: true                     # Track frontend bundle size. Default: true.
    artifact_sizes: false                 # Track individual artifact sizes. Default: false.
  custom_metrics: []                      # List of custom metric definitions (see schema above).
```

**PREFLIGHT validation constraints:**

| Parameter | Range | Default | Rationale |
|---|---|---|---|
| `performance_tracking.enabled` | boolean | `false` | Requires baseline data; opt-in |
| `performance_tracking.rolling_window` | 3-50 | 10 | <3 is too volatile, >50 dilutes signal |
| `performance_tracking.thresholds.build_time_pct` | 5-100 | 20 | Below 5% is noise; above 100% is too lenient |
| `performance_tracking.thresholds.bundle_size_pct` | 5-100 | 10 | Frontend bundles are sensitive to size increases |
| `performance_tracking.severity_escalation.double_threshold` | `CRITICAL`, `WARNING`, `INFO` | `CRITICAL` | Double the threshold is a serious regression |

### Data Flow

**Metric collection (Stage 5 — VERIFY):**

1. Build verifier (`fg-505`) runs build command and records wall-clock time
2. Build verifier checks for bundle/artifact outputs:
   - Frontend: `dist/`, `build/`, `.next/` directories — sum file sizes
   - Backend: `build/libs/`, `target/`, `bin/` — binary size
3. Build verifier writes metrics to `.forge/.build-metrics.json` (temporary)
4. Test gate (`fg-500`) runs test suite and records wall-clock time + test count
5. Test gate writes metrics to `.forge/.test-metrics.json` (temporary)

**Regression detection (Stage 6 — REVIEW):**

1. Quality gate reads `.forge/.build-metrics.json` and `.forge/.test-metrics.json`
2. Quality gate reads `.forge/benchmarks.json` for rolling average
3. For each metric, compute: `change_pct = ((current - average) / average) * 100`
4. If `change_pct > threshold`: emit `PERF-REGRESSION-*` finding
5. If `change_pct > 2 * threshold`: escalate severity per `severity_escalation`
6. Append current metrics to `.forge/benchmarks.json`
7. Recompute rolling average (trim to `rolling_window` size)

**Custom metric extraction:**

1. After test gate runs, scan test output for custom metric patterns
2. Apply regex capture group to extract numeric value
3. Store in `metrics.custom.{name}`
4. Compare against custom threshold at REVIEW

### Integration Points

| File | Change |
|---|---|
| `agents/fg-505-build-verifier.md` | Add metric recording step after successful build. Write build time and artifact sizes to `.forge/.build-metrics.json`. |
| `agents/fg-500-test-gate.md` | Add metric recording step after test suite completes. Write test duration, test count to `.forge/.test-metrics.json`. |
| `agents/fg-400-quality-gate.md` | Add regression detection step before review agent dispatch. Read metrics, compare against rolling average, emit findings. |
| `shared/checks/category-registry.json` | Add 4 new `PERF-REGRESSION-*` categories |
| `shared/state-schema.md` | Document `.forge/benchmarks.json` schema and lifecycle |
| `skills/forge-insights/SKILL.md` | Add "Performance Trends" section showing metric history |
| `modules/frameworks/*/forge-config-template.md` | Add `performance_tracking:` section |

### Error Handling

**Failure mode 1: No baseline data (first run).**
- Detection: `.forge/benchmarks.json` does not exist or has 0 runs
- Behavior: Record current metrics as the first data point. No regression findings emitted. Log INFO: "Performance baseline established. Regression detection starts from next run."

**Failure mode 2: Insufficient baseline data.**
- Detection: `benchmarks.json` has fewer runs than `rolling_window / 2`
- Behavior: Use available data for comparison but widen thresholds by 50% to account for low sample size. Log INFO: "Performance tracking: {N}/{window} baseline runs collected. Thresholds widened."

**Failure mode 3: Build/test metrics not available.**
- Detection: `.forge/.build-metrics.json` or `.forge/.test-metrics.json` missing
- Behavior: Skip corresponding regression check. May occur in dry-run mode or when build/test stages are skipped.

**Failure mode 4: Metric spike due to environmental factors.**
- Mitigation: Rolling average smooths out single-run anomalies. The window of 10 runs means one bad run shifts the average by only 10%. For known environmental issues, users can manually prune outliers from `benchmarks.json`.

**Failure mode 5: `benchmarks.json` grows too large.**
- Detection: File exceeds 1MB
- Behavior: Trim to `rolling_window * 2` most recent runs (keep extra for trend analysis). Log INFO: "Performance benchmark history trimmed to {N} runs."

## Performance Characteristics

**Collection overhead:**

| Metric | Collection Cost | Notes |
|---|---|---|
| Build time | ~0ms | Wall-clock timing of existing build command |
| Test duration | ~0ms | Wall-clock timing of existing test command |
| Bundle/artifact size | 10-50ms | `du -sb` or `stat` on output directories |
| Custom metrics | 5-20ms | Regex scan of test/build output |
| **Total** | **15-70ms** | Negligible |

**Regression detection:**

| Step | Duration | Notes |
|---|---|---|
| Read benchmarks.json | 1-5ms | JSON parse |
| Compute comparisons | <1ms | Arithmetic |
| Write updated benchmarks | 1-5ms | JSON serialize |
| **Total** | **2-11ms** | Negligible |

**Storage:** ~500 bytes per run entry. At 10-run window: ~5KB. At 50-run window: ~25KB. Negligible.

## Testing Approach

### Structural Tests (`tests/structural/`)

1. **Category registration:** All 4 `PERF-REGRESSION-*` codes exist in `category-registry.json`
2. **Config template:** All `forge-config-template.md` files include `performance_tracking:` section
3. **State schema:** `benchmarks.json` schema documented in `state-schema.md`

### Unit Tests (`tests/unit/`)

1. **`performance-tracking.bats`:**
   - Regression detected: build time 25% above average (threshold 20%) produces WARNING
   - No regression: build time 15% above average (threshold 20%) produces no finding
   - Severity escalation: build time 45% above average (2x threshold) produces CRITICAL
   - First run: no regression findings, baseline recorded
   - Test count decrease: 15% fewer tests than average produces WARNING
   - Custom metric: pattern matched, threshold exceeded, finding emitted
   - Config disabled: `performance_tracking.enabled: false` skips all tracking

2. **`benchmarks-json.bats`:**
   - Rolling window enforced: runs beyond window trimmed
   - Rolling average computed correctly
   - File creation on first run

## Acceptance Criteria

1. Build time, test duration, and bundle size recorded per pipeline run
2. `.forge/benchmarks.json` maintains a rolling window of recent runs
3. Regression detection compares current metrics against rolling average
4. Configured thresholds trigger `PERF-REGRESSION-*` findings at appropriate severity
5. Double-threshold violations escalate to CRITICAL
6. First run establishes baseline without false positives
7. Custom metrics extracted from test/build output via configurable patterns
8. `/forge-insights` displays performance trends across runs
9. `benchmarks.json` survives `/forge-reset`
10. Collection overhead is under 100ms per metric

## Migration Path

**From v1.20.1 to v2.0:**

1. **Zero breaking changes.** Feature is opt-in (`enabled: false` default).
2. **Agent updates:** Build verifier and test gate gain metric recording steps. These are no-ops when `performance_tracking.enabled: false`.
3. **Quality gate update:** Regression detection step added. Skipped when no benchmarks data exists.
4. **New file:** `.forge/benchmarks.json` created on first tracked run.
5. **Category registry:** Four new codes. Existing scoring unchanged.
6. **No new dependencies.** Uses built-in timing and file size commands.

## Dependencies

**This feature depends on:**
- `fg-505-build-verifier` for build time and artifact size collection
- `fg-500-test-gate` for test duration and test count collection
- `fg-400-quality-gate` for regression detection during REVIEW
- `.forge/` directory structure (already established)

**Other features that benefit from this:**
- F19 (DX Metrics): Performance metrics feed into cycle time and efficiency calculations
- F20 (Monorepo Tooling): Nx/Turborepo affected detection can scope metrics to changed packages
- `/forge-insights`: Performance trends become a new dashboard section
