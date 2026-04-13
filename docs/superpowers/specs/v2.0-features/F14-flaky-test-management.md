# F14: Flaky Test Detection, Quarantine, and Predictive Test Selection

## Status
DRAFT -- 2026-04-13

## Problem Statement

Forge's test gate (`fg-500-test-gate`) has basic flaky test handling: on first test failure, it re-runs only the failing tests. If they pass on re-run, they are marked as FLAKY and the pipeline proceeds. If they fail again, they are treated as genuine failures.

This approach has three structural limitations:

1. **No history**: Flaky detection is per-run, with no memory. A test that flips pass/fail across 10 runs is detected as flaky only when it happens to fail in the current run. There is no proactive identification of unreliable tests.
2. **No quarantine**: A known-flaky test that fails blocks the pipeline identically to a genuine regression. The developer must manually decide whether to investigate or re-run. There is no mechanism to quarantine tests that are known-unreliable while still running them for monitoring.
3. **No predictive selection**: The test gate runs the full suite on every VERIFY pass. For projects with 500+ tests, this means running tests unrelated to the current changes. The existing large-suite optimization (run targeted first, then full) uses naming conventions and import analysis but has no historical signal about which tests are actually associated with which code paths.

Research context:
- Google's test infrastructure classifies tests as reliable, flaky, or broken based on multi-run history and automatically quarantines flaky tests from blocking CI.
- Launchable and Trunk achieve 60-80% test suite reduction by using historical test-code associations to predict which tests will fail given a code change.
- Meta's predictive test selection reduces CI pipeline execution from 4 hours to 45 minutes by running only the 15-20% of tests relevant to each commit.

The gap in Forge: the test gate treats every run as independent, discarding valuable signal about test reliability and code-test associations.

## Proposed Solution

Introduce a persistent test result history (`.forge/test-history.json`) that tracks per-test outcomes across pipeline runs. Build three capabilities on this history: (1) algorithmic flaky detection with configurable thresholds, (2) automatic quarantine with self-healing unquarantine, and (3) predictive test selection using code-test association graphs. Integrate all three into `fg-500-test-gate` with minimal changes to the convergence loop.

## Detailed Design

### Architecture

The test history is a persistent JSON file that survives `/forge-reset` (same lifecycle as `explore-cache.json`). The test gate reads and writes this file on every VERIFY pass. Three subsystems consume the history:

```
                         .forge/test-history.json
                                |
          +---------------------+---------------------+
          |                     |                     |
  Flaky Detector        Quarantine Manager    Predictive Selector
          |                     |                     |
          +---------------------+---------------------+
                                |
                        fg-500-test-gate
                     (integrated decisions)
```

#### Component Ownership

| Component | Owner | Responsibility |
|-----------|-------|----------------|
| Test history persistence | fg-500-test-gate | Read/write test-history.json on each VERIFY |
| Flaky detector | fg-500-test-gate | Compute flaky scores from history |
| Quarantine manager | fg-500-test-gate | Decide quarantine/unquarantine |
| Predictive selector | fg-500-test-gate | Select tests for targeted pass |
| History pruning | fg-700-retrospective | Prune old entries during LEARN |

### Schema / Data Model

#### Test History Schema

`.forge/test-history.json`:

```json
{
  "schema_version": "1.0.0",
  "last_updated": "2026-04-13T14:30:00Z",
  "run_count": 42,
  "tests": {
    "com.example.UserServiceTest#testCreateUser": {
      "results": [
        { "run_id": "run-2026-04-13-abc", "outcome": "PASS", "duration_ms": 450, "timestamp": "2026-04-13T14:30:00Z" },
        { "run_id": "run-2026-04-12-def", "outcome": "PASS", "duration_ms": 430, "timestamp": "2026-04-12T10:00:00Z" },
        { "run_id": "run-2026-04-11-ghi", "outcome": "FAIL", "duration_ms": 520, "timestamp": "2026-04-11T16:00:00Z" },
        { "run_id": "run-2026-04-11-jkl", "outcome": "PASS", "duration_ms": 440, "timestamp": "2026-04-11T10:00:00Z" }
      ],
      "flaky_score": 0.17,
      "quarantined": false,
      "quarantine_history": [],
      "avg_duration_ms": 460,
      "associated_files": [
        "src/main/kotlin/com/example/UserService.kt",
        "src/main/kotlin/com/example/UserRepository.kt"
      ],
      "last_failed_at": "2026-04-11T16:00:00Z",
      "last_passed_at": "2026-04-13T14:30:00Z",
      "consecutive_passes_since_unquarantine": null
    },
    "com.example.NotificationServiceTest#testSendAsync": {
      "results": [
        { "run_id": "run-2026-04-13-abc", "outcome": "FAIL", "duration_ms": 3200, "timestamp": "2026-04-13T14:30:00Z" },
        { "run_id": "run-2026-04-12-def", "outcome": "PASS", "duration_ms": 1800, "timestamp": "2026-04-12T10:00:00Z" },
        { "run_id": "run-2026-04-11-ghi", "outcome": "FAIL", "duration_ms": 3500, "timestamp": "2026-04-11T16:00:00Z" },
        { "run_id": "run-2026-04-11-jkl", "outcome": "PASS", "duration_ms": 2100, "timestamp": "2026-04-11T10:00:00Z" }
      ],
      "flaky_score": 0.67,
      "quarantined": true,
      "quarantine_history": [
        { "action": "quarantine", "timestamp": "2026-04-12T10:00:00Z", "reason": "flaky_score 0.67 exceeded threshold 0.3" }
      ],
      "avg_duration_ms": 2650,
      "associated_files": [
        "src/main/kotlin/com/example/NotificationService.kt",
        "src/main/kotlin/com/example/messaging/AsyncSender.kt"
      ],
      "last_failed_at": "2026-04-13T14:30:00Z",
      "last_passed_at": "2026-04-12T10:00:00Z",
      "consecutive_passes_since_unquarantine": null
    }
  }
}
```

| Field | Type | Description |
|-------|------|-------------|
| `schema_version` | string | History format version |
| `last_updated` | string (ISO 8601) | Last write timestamp |
| `run_count` | integer | Total pipeline runs that wrote to this file |
| `tests` | object | Keyed by fully qualified test identifier |
| `tests.*.results` | array | Last N run results (bounded by `max_history_per_test`) |
| `tests.*.results[].run_id` | string | Pipeline run identifier |
| `tests.*.results[].outcome` | enum | `PASS`, `FAIL`, `SKIP`, `ERROR`, `FLAKY` |
| `tests.*.results[].duration_ms` | integer | Test execution time |
| `tests.*.results[].timestamp` | string (ISO 8601) | When the result was recorded |
| `tests.*.flaky_score` | float | Computed flaky score (0.0 = stable, 1.0 = maximally flaky) |
| `tests.*.quarantined` | boolean | Whether the test is currently quarantined |
| `tests.*.quarantine_history` | array | Quarantine/unquarantine events |
| `tests.*.avg_duration_ms` | integer | Rolling average duration |
| `tests.*.associated_files` | string[] | Implementation files associated with this test |
| `tests.*.last_failed_at` | string or null | Timestamp of most recent failure |
| `tests.*.last_passed_at` | string or null | Timestamp of most recent pass |
| `tests.*.consecutive_passes_since_unquarantine` | integer or null | Used to track post-unquarantine stability. `null` when not in unquarantine observation period. |

**Test identifier format:** Fully qualified test name as reported by the test runner. Framework-specific:
- JUnit/Kotest: `com.example.UserServiceTest#testCreateUser`
- Jest/Vitest: `UserService > createUser > should return created user`
- pytest: `tests/test_user_service.py::TestUserService::test_create_user`
- Go: `TestCreateUser`

The test gate normalizes identifiers by stripping parameterized test suffixes (e.g., `[1]`, `(case: "empty")`) to group parameterized test results.

#### Finding Categories

New finding code for quarantined test failures:

```json
{
  "TEST-FLAKY": {
    "description": "Quarantined flaky test failed (non-blocking)",
    "agents": ["fg-500-test-gate"],
    "wildcard": false,
    "priority": 5,
    "affinity": ["fg-500-test-gate", "fg-410-code-reviewer"]
  },
  "TEST-QUARANTINE": {
    "description": "Test quarantine status changed (quarantined or unquarantined)",
    "agents": ["fg-500-test-gate"],
    "wildcard": false,
    "priority": 5,
    "affinity": ["fg-500-test-gate"]
  }
}
```

| Code | Severity | Meaning |
|------|----------|---------|
| `TEST-FLAKY` | INFO | Quarantined test failed. Non-blocking. Recorded for trend tracking. |
| `TEST-QUARANTINE` | INFO | Test was quarantined or unquarantined during this run. Informational. |

These do not block the pipeline. Genuine test failures remain `TEST-FAIL` (CRITICAL) as today.

### Configuration

In `forge-config.md`:

```yaml
test_history:
  enabled: true                         # Master toggle (default: true)
  max_history_per_test: 20              # Keep last N results per test (default: 20)
  max_age_days: 90                      # Prune test entries not seen in N days (default: 90)
  flaky:
    enabled: true                       # Enable flaky detection (default: true)
    threshold: 0.3                      # Flaky score above this = flaky (default: 0.3)
    min_runs: 5                         # Minimum runs before computing flaky score (default: 5)
    algorithm: "flip_rate"              # "flip_rate" or "failure_rate" (default: flip_rate)
  quarantine:
    enabled: true                       # Enable automatic quarantine (default: true)
    auto_quarantine: true               # Automatically quarantine above threshold (default: true)
    auto_unquarantine: true             # Automatically unquarantine when stable (default: true)
    unquarantine_consecutive_passes: 5  # Consecutive passes needed to unquarantine (default: 5)
    max_quarantine_days: 30             # Force-unquarantine after N days (escalate to user) (default: 30)
  predictive:
    enabled: true                       # Enable predictive test selection (default: true)
    targeted_first: true                # Run targeted pass before full pass (default: true)
    min_association_confidence: 0.5     # Minimum confidence for file-test association (default: 0.5)
    track_accuracy: true                # Track prediction accuracy (default: true)
```

Constraints enforced at PREFLIGHT:
- `max_history_per_test` must be >= 5 and <= 100.
- `max_age_days` must be >= 7 and <= 365.
- `flaky.threshold` must be > 0.0 and < 1.0.
- `flaky.min_runs` must be >= 3 and <= 20.
- `flaky.algorithm` must be one of `flip_rate`, `failure_rate`.
- `quarantine.unquarantine_consecutive_passes` must be >= 3 and <= 20.
- `quarantine.max_quarantine_days` must be >= 7 and <= 90.
- `predictive.min_association_confidence` must be > 0.0 and <= 1.0.

### Data Flow

#### Flaky Detection Algorithm

Computed after each test suite execution:

```
FUNCTION compute_flaky_score(test_entry, config):
  results = test_entry.results

  # Guard: minimum run count
  IF len(results) < config.flaky.min_runs:
    RETURN null  # Not enough data

  IF config.flaky.algorithm == "flip_rate":
    # Count outcome transitions (PASS->FAIL or FAIL->PASS)
    flips = 0
    FOR i in range(1, len(results)):
      prev = results[i-1].outcome
      curr = results[i].outcome
      # Normalize: FLAKY counts as PASS (it passed on re-run)
      prev_binary = "PASS" if prev in ["PASS", "FLAKY", "SKIP"] else "FAIL"
      curr_binary = "PASS" if curr in ["PASS", "FLAKY", "SKIP"] else "FAIL"
      IF prev_binary != curr_binary:
        flips += 1
    flaky_score = flips / (len(results) - 1)

  ELIF config.flaky.algorithm == "failure_rate":
    # Simple failure frequency
    failures = count(r for r in results if r.outcome in ["FAIL", "ERROR"])
    total = count(r for r in results if r.outcome not in ["SKIP"])
    flaky_score = failures / total if total > 0 else 0

  RETURN round(flaky_score, 2)
```

**Algorithm choice:**
- `flip_rate` (default): Measures outcome volatility. A test that alternates PASS/FAIL every run scores 1.0. A test that fails consistently scores 0.0 (it is broken, not flaky). This is the correct metric for flakiness because flaky tests are characterized by non-determinism, not failure frequency.
- `failure_rate`: Simple failure percentage. Useful when the distinction between "flaky" and "frequently failing" is less important. Not recommended as default because a test that fails 30% of the time due to a genuine bug should not be quarantined.

#### Quarantine Lifecycle

```
  [STABLE]                    [FLAKY DETECTED]
      |                              |
      |  flaky_score > threshold     |
      +---> [QUARANTINED] ----------+
                |
                |  consecutive_passes >= unquarantine_threshold
                |
                +---> [OBSERVATION PERIOD]
                          |
                          |  consecutive_passes >= unquarantine_consecutive_passes
                          |
                          +---> [STABLE]  (unquarantined)
                          |
                          |  any failure during observation
                          |
                          +---> [QUARANTINED]  (re-quarantined)
                          
  [QUARANTINED] + max_quarantine_days exceeded
      |
      +---> [FORCE ESCALATION] --> user decides: fix, keep quarantined, or delete test
```

**Quarantine behavior during pipeline:**

```
FUNCTION handle_test_result(test_id, outcome, test_entry, config):
  # Update history
  test_entry.results.prepend({run_id, outcome, duration_ms, timestamp})
  IF len(test_entry.results) > config.max_history_per_test:
    test_entry.results.pop()  # Remove oldest

  # Compute flaky score
  test_entry.flaky_score = compute_flaky_score(test_entry, config)

  # Quarantine decision
  IF test_entry.quarantined:
    IF outcome == "PASS":
      IF test_entry.consecutive_passes_since_unquarantine is not null:
        test_entry.consecutive_passes_since_unquarantine += 1
        IF test_entry.consecutive_passes_since_unquarantine >= config.quarantine.unquarantine_consecutive_passes:
          # Unquarantine
          test_entry.quarantined = false
          test_entry.consecutive_passes_since_unquarantine = null
          test_entry.quarantine_history.append({action: "unquarantine", timestamp, reason: "stable for N runs"})
          emit_finding("TEST-QUARANTINE", INFO, "Unquarantined: {test_id} -- stable for {N} consecutive runs")
    ELIF outcome == "FAIL":
      IF test_entry.consecutive_passes_since_unquarantine is not null:
        # Failed during observation -- re-quarantine
        test_entry.consecutive_passes_since_unquarantine = null
      emit_finding("TEST-FLAKY", INFO, "Quarantined flaky test failed: {test_id}")
      RETURN "QUARANTINED_FAIL"  # Non-blocking

  ELIF NOT test_entry.quarantined AND test_entry.flaky_score is not null:
    IF test_entry.flaky_score > config.flaky.threshold AND config.quarantine.auto_quarantine:
      test_entry.quarantined = true
      test_entry.consecutive_passes_since_unquarantine = null
      test_entry.quarantine_history.append({action: "quarantine", timestamp, reason: "flaky_score {score} exceeded threshold {threshold}"})
      emit_finding("TEST-QUARANTINE", INFO, "Quarantined: {test_id} (flaky_score={score})")

  # Duration tracking
  test_entry.avg_duration_ms = rolling_average(test_entry.results.map(r => r.duration_ms))

  IF outcome == "FAIL":
    test_entry.last_failed_at = timestamp
  ELIF outcome == "PASS":
    test_entry.last_passed_at = timestamp

  RETURN outcome
```

**Impact on pipeline verdicts:**

| Test Status | Quarantined? | Pipeline Effect |
|-------------|-------------|-----------------|
| PASS | No | Counts as pass (normal) |
| PASS | Yes | Counts as pass + increments `consecutive_passes_since_unquarantine` |
| FAIL | No | Counts as fail, triggers re-run per existing flaky detection |
| FAIL (confirmed) | No | Genuine failure, blocks pipeline |
| FAIL | Yes | `TEST-FLAKY` INFO finding, does NOT block pipeline |
| FAIL (re-run passes) | No | Marked FLAKY in history, pipeline proceeds (existing behavior) |

#### Predictive Test Selection Algorithm

Used for inner-loop testing and the first VERIFY pass:

```
FUNCTION select_tests(changed_files, test_history, config):
  # 1. Build file-test association map
  associations = {}
  FOR test_id, entry in test_history.tests:
    FOR file in entry.associated_files:
      IF file not in associations:
        associations[file] = []
      associations[file].append({
        test_id: test_id,
        confidence: compute_association_confidence(file, test_id, entry)
      })

  # 2. Select tests associated with changed files
  targeted_tests = set()
  FOR changed_file in changed_files:
    # Direct associations
    IF changed_file in associations:
      FOR assoc in associations[changed_file]:
        IF assoc.confidence >= config.predictive.min_association_confidence:
          targeted_tests.add(assoc.test_id)

    # Package/module-level associations
    package = extract_package(changed_file)
    FOR file, assocs in associations:
      IF extract_package(file) == package:
        FOR assoc in assocs:
          IF assoc.confidence >= config.predictive.min_association_confidence * 0.7:  # Lower bar for package-level
            targeted_tests.add(assoc.test_id)

  # 3. Add priority tests (always included)
  FOR test_id, entry in test_history.tests:
    # Previously failing tests
    IF entry.results and entry.results[0].outcome in ["FAIL", "ERROR"]:
      targeted_tests.add(test_id)

    # High flaky-score tests (if not quarantined)
    IF entry.flaky_score and entry.flaky_score > config.flaky.threshold * 0.5 and not entry.quarantined:
      targeted_tests.add(test_id)

  # 4. Compute remaining tests (full suite minus targeted)
  all_tests = set(test_history.tests.keys())
  remaining_tests = all_tests - targeted_tests

  RETURN {
    targeted: sorted(targeted_tests),
    remaining: sorted(remaining_tests),
    targeted_pct: len(targeted_tests) / len(all_tests) * 100
  }
```

**Association confidence computation:**

```
FUNCTION compute_association_confidence(file, test_id, test_entry):
  confidence = 0.0

  # 1. Explicit association (from explore cache or import analysis)
  IF file in test_entry.associated_files:
    confidence += 0.5

  # 2. Naming convention match
  IF test_name_matches_file(test_id, file):
    confidence += 0.3

  # 3. Historical co-change: test failed when file was changed
  co_changes = count_co_changes(file, test_entry.results)
  IF co_changes > 0:
    confidence += min(0.2, co_changes * 0.05)

  RETURN min(1.0, confidence)
```

The `associated_files` field is populated by:
1. **Import analysis**: Parse test file imports/requires to find implementation files (done by test gate at first run).
2. **Explore cache**: Use `explore-cache.json` file_index dependencies for entity-to-test relationships.
3. **Historical correlation**: When a test fails and is fixed by changing file X, associate X with the test.
4. **Naming conventions**: `UserServiceTest` is associated with `UserService.kt` by name.

#### Test Prioritization

When executing tests (targeted or full), order them for fastest feedback:

```
FUNCTION prioritize_tests(test_ids, test_history):
  scored = []
  FOR test_id in test_ids:
    entry = test_history.tests.get(test_id)
    IF entry is null:
      # New test, no history -- run early (unknown = risky)
      scored.append({test_id, priority: 100})
      CONTINUE

    priority = 0

    # 1. Previously failing (highest priority)
    IF entry.results and entry.results[0].outcome in ["FAIL", "ERROR"]:
      priority += 50

    # 2. Associated with changed files (already selected by predictive)
    IF test_id in targeted_tests:
      priority += 30

    # 3. Higher flaky score = run sooner (catch flakes early)
    IF entry.flaky_score:
      priority += int(entry.flaky_score * 20)

    # 4. Shorter duration = run sooner (faster feedback)
    IF entry.avg_duration_ms:
      # Normalize: 0ms = +10, 10000ms+ = +0
      priority += max(0, 10 - int(entry.avg_duration_ms / 1000))

    scored.append({test_id, priority})

  # Sort descending by priority
  RETURN sorted(scored, key=priority, descending=true)
```

#### Integration with Test Gate Execution Flow

The test gate's existing execution flow (Section 3 of `fg-500-test-gate.md`) is modified:

```
EXISTING FLOW:
  1. Run full test suite
  2. On failure: re-run failing tests (flaky check)
  3. If flaky: proceed. If genuine: report failure.
  4. On success: dispatch analysis agents.

MODIFIED FLOW:
  1. Load test-history.json
  2. IF predictive.enabled AND history has sufficient data (>= 10 runs):
     a. Compute targeted tests from changed files + associations
     b. Apply prioritization to targeted tests
     c. Run targeted tests in priority order
     d. IF targeted pass:
        - Run remaining tests (full suite minus targeted)
        - Track: did any remaining test fail? (prediction accuracy)
     e. IF targeted fail:
        - Process failures (step 3 below) without running remaining tests (faster feedback)
  ELSE:
     a. Run full test suite (existing behavior)
     b. Apply prioritization if history available

  3. For each failing test:
     a. Lookup in test-history
     b. IF quarantined:
        - Emit TEST-FLAKY (INFO)
        - Do NOT count as pipeline failure
     c. ELSE:
        - Re-run failing test (existing flaky detection)
        - IF passes on re-run:
          - Record as FLAKY in history
          - Proceed (existing behavior)
        - IF fails again:
          - Genuine failure, report to orchestrator
          - Update history with FAIL outcome
     d. Update test-history.json with new results

  4. Compute flaky scores for all tests that ran
  5. Apply quarantine/unquarantine decisions
  6. Write test-history.json
  7. On all-pass: dispatch analysis agents (existing behavior)
```

#### Prediction Accuracy Tracking

When predictive selection is active, track how accurate the predictions are:

```json
{
  "prediction_accuracy": {
    "total_runs": 42,
    "targeted_caught_all_failures": 38,
    "remaining_revealed_failures": 4,
    "catch_rate": 0.905,
    "avg_targeted_pct": 18.5,
    "avg_time_saved_pct": 62.3
  }
}
```

Stored in `test-history.json` at the top level. Updated after each predictive run.

- `catch_rate`: Percentage of runs where the targeted pass caught all failures (no surprises in remaining tests). Target: >90%.
- `avg_targeted_pct`: Average percentage of tests in the targeted pass. Target: <30%.
- `avg_time_saved_pct`: Average time savings from running targeted first. Computed as `1 - (targeted_duration / full_duration)`.

If `catch_rate` drops below 80% over 10+ runs, log WARNING: "Predictive test selection catch rate is {rate}%. Consider increasing association confidence or disabling predictive selection."

### Integration Points

| System | Integration | Direction |
|--------|-------------|-----------|
| fg-500-test-gate | Core consumer: flaky detection, quarantine, predictive selection | Read + Write |
| fg-100-orchestrator | Provides changed_files list to test gate | Read |
| fg-700-retrospective | Prunes old history entries, reports flaky trends | Read + Write |
| fg-710-post-run | Reports flaky test stats in run recap | Read |
| explore-cache.json | File dependencies for test-code associations | Read |
| F07 event log | Test result events for causal chain tracking | Write |
| category-registry.json | TEST-FLAKY, TEST-QUARANTINE finding codes | Read |
| state.json | Test cycle counts and convergence data | Read |
| `/forge-insights` | Flaky trends across runs | Read |

### Error Handling

| Scenario | Behavior |
|----------|----------|
| `test-history.json` does not exist | First run: create empty history. All features degrade gracefully to existing behavior (no flaky detection, no quarantine, full test suite). |
| `test-history.json` is corrupt (invalid JSON) | Rebuild from empty. Log WARNING: "Test history corrupt, starting fresh." Analytics lost. |
| Test identifier format changes (test renamed) | Old entry stays in history until pruned by `max_age_days`. New entry starts from scratch. No attempt to match renamed tests. |
| Test runner output unparseable (cannot extract test names) | Fall back to existing behavior (no history update). Log WARNING. |
| Quarantine accumulates >50 tests | Log WARNING at PREFLIGHT: "{N} tests quarantined. Consider running /forge-fix to investigate root causes." |
| Predictive selection returns empty targeted set (no associations for changed files) | Fall back to full test suite. Log INFO: "No test associations found for changed files." |
| Predictive selection returns >80% of tests as targeted | Run full suite instead (prediction not useful). Log INFO: "Targeted set is {N}% of suite, running full suite." |
| Sprint mode: parallel tasks sharing test history | Each task reads at start, writes at end. Last-write-wins for the same test entry (acceptable -- results accumulate over multiple runs). |
| `max_quarantine_days` exceeded for a quarantined test | Emit WARNING: "Test {test_id} quarantined for {N} days. Action required: fix the test, remove it, or extend quarantine." Include in `alerts.json` for background mode. |

## Performance Characteristics

- **History file size**: Each test entry is ~500 bytes with 20 results. At 1000 tests: ~500KB. At 5000 tests: ~2.5MB. Well within JSON parsing limits.
- **Flaky score computation**: O(n) per test where n = `max_history_per_test` (max 100). For 1000 tests: <100ms total.
- **Predictive selection computation**: O(tests * changed_files) for association lookup. At 1000 tests and 20 changed files: <200ms.
- **Test execution savings**: For a 500-test suite with 18% targeted (90 tests), the targeted pass takes ~20% of full suite time. If targeted pass catches all failures (90%+ of the time), the full suite run is deferred until all fixes are complete, saving 3-5 targeted-only iterations.
- **No LLM cost**: All computations are algorithmic (bash/jq). No LLM calls.
- **Convergence loop impact**: Faster test feedback (targeted pass) reduces time-per-iteration in Phase 1 (Correctness). Quarantined tests reduce false failure rate, reducing unnecessary fix iterations.

## Testing Approach

### Structural Tests

1. `TEST-FLAKY` and `TEST-QUARANTINE` categories exist in `category-registry.json`.
2. Test history schema version field is present.
3. `test_history` config key documented in forge-config template.

### Unit Tests

1. **Flaky score (flip_rate)**: Given results [PASS, FAIL, PASS, FAIL, PASS], compute flaky_score = 0.80. Given [PASS, PASS, PASS, FAIL, PASS], compute flaky_score = 0.40. Given [FAIL, FAIL, FAIL, FAIL, FAIL], compute flaky_score = 0.0 (broken, not flaky).
2. **Flaky score (failure_rate)**: Given results with 3 FAIL out of 10, compute flaky_score = 0.30.
3. **Quarantine trigger**: Given flaky_score = 0.35 and threshold = 0.30, verify quarantine is applied. Given flaky_score = 0.25, verify no quarantine.
4. **Unquarantine**: Given a quarantined test with 5 consecutive PASS results and `unquarantine_consecutive_passes: 5`, verify unquarantine is applied.
5. **Re-quarantine**: Given a test in observation period (3 consecutive passes) that fails, verify it is re-quarantined and `consecutive_passes_since_unquarantine` is reset.
6. **Predictive selection**: Given changed files [UserService.kt] and associations {UserService.kt -> [UserServiceTest]}, verify UserServiceTest is in targeted set.
7. **Prioritization**: Given 3 tests (one previously failing, one flaky, one stable), verify priority ordering: failing > flaky > stable.
8. **History pruning**: Given entries last seen 91 days ago and `max_age_days: 90`, verify entries are removed.

### Contract Tests

1. Test gate reads `test-history.json` and correctly identifies quarantined tests from the history.
2. Test gate writes valid `test-history.json` after execution.
3. `TEST-FLAKY` findings emitted for quarantined test failures are valid per `output-format.md`.

### Scenario Tests

1. **Flaky detection**: Run a pipeline 5 times where test X alternates PASS/FAIL. On 6th run, verify test X has flaky_score > 0.5 and is quarantined.
2. **Quarantine non-blocking**: Run a pipeline where quarantined test X fails. Verify the pipeline proceeds (test failure is INFO, not CRITICAL) and the run can reach SHIP.
3. **Unquarantine**: Run a pipeline 5 times where quarantined test X passes each time. On 6th run, verify test X is unquarantined and a `TEST-QUARANTINE` INFO finding is emitted.
4. **Predictive selection**: Run a pipeline with 100 tests, change 2 files associated with 10 tests. Verify the test gate runs 10 targeted tests first, then 90 remaining tests. Check `prediction_accuracy.avg_targeted_pct` is approximately 10%.
5. **Prediction accuracy tracking**: Run 10 pipelines with predictive selection. On run 11, verify `catch_rate` is computed and logged.
6. **Disabled mode**: Run with `test_history.enabled: false`. Verify no test-history.json is created and the test gate behaves identically to v1.20.1.

## Acceptance Criteria

- [AC-001] GIVEN a test X that has alternated PASS/FAIL across its last 6 runs WHEN the flaky score is computed with `algorithm: flip_rate` THEN the flaky_score for X is >= 0.8 (indicating high flakiness).
- [AC-002] GIVEN a test X with flaky_score 0.45 and `quarantine.threshold: 0.3` WHEN the test gate processes results and `auto_quarantine: true` THEN X is quarantined and a `TEST-QUARANTINE` INFO finding is emitted.
- [AC-003] GIVEN a quarantined test X that fails during a VERIFY pass WHEN the test gate evaluates results THEN X's failure produces a `TEST-FLAKY` INFO finding (not CRITICAL) and does NOT block the pipeline from proceeding.
- [AC-004] GIVEN a quarantined test X WHEN X passes in 5 consecutive runs and `unquarantine_consecutive_passes: 5` THEN X is automatically unquarantined and a `TEST-QUARANTINE` INFO finding notes the unquarantine.
- [AC-005] GIVEN a test suite of 500 tests and 15 tests associated with the 3 changed files WHEN `predictive.enabled: true` and sufficient history exists THEN the test gate runs the 15 targeted tests first, and only runs the remaining 485 tests if the targeted pass succeeds.
- [AC-006] GIVEN predictive test selection is active WHEN a failure is found in the remaining (non-targeted) test set THEN `prediction_accuracy.catch_rate` decreases accordingly and if catch_rate falls below 80% over 10+ runs then a WARNING is logged.
- [AC-007] GIVEN `test_history.enabled: true` WHEN a pipeline run completes THEN `.forge/test-history.json` contains updated results for every test that was executed, with `run_id`, `outcome`, `duration_ms`, and `timestamp` fields.
- [AC-008] GIVEN test history entries not seen in 91 days and `max_age_days: 90` WHEN the retrospective runs at LEARN stage THEN those entries are pruned from `test-history.json`.

## Migration Path

1. **v2.0.0**: Ship with `test_history.enabled: true` by default. First run creates the history file. Flaky detection and quarantine require `min_runs` (default 5) runs before activating. Predictive selection requires 10+ runs. All features degrade to existing behavior when history is insufficient.
2. **v2.0.x**: Tune thresholds based on real-world flaky rates. Consider framework-specific test identifier normalization for edge cases.
3. **v2.1.0**: Add `/forge-flaky` skill that reports on test health: most flaky tests, quarantine status, prediction accuracy, and actionable recommendations.
4. **v2.2.0**: Consider integration with CI systems to import test history from external CI runs, seeding the history faster than waiting for N pipeline runs.

## Dependencies

| Dependency | Type | Required? |
|------------|------|-----------|
| fg-500-test-gate modification | Agent modification | Yes |
| category-registry.json update | Shared infrastructure | Yes |
| fg-700-retrospective (history pruning) | Agent modification | Yes |
| fg-710-post-run (flaky reporting) | Agent modification | Yes |
| explore-cache.json (file associations) | Existing system | No (enhances association accuracy) |
| F07 event log (test result events) | Feature dependency | No (graceful: skip event emission if F07 inactive) |
| Test runner output parsing | Existing capability (per framework module) | Yes |
| `jq` availability | External tool | Yes (already required by forge) |
