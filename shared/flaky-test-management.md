# Flaky Test Management

Persistent test result history with algorithmic flaky detection, automatic quarantine, and predictive test selection. Integrated into `fg-500-test-gate` at VERIFY. All computations are algorithmic (no LLM cost).

---

## 1. Test History

Persistent file: `.forge/test-history.json` (survives `/forge-reset`, same lifecycle as `explore-cache.json`). Schema: `shared/schemas/test-history-schema.json`.

The test gate reads the history at the start of every VERIFY pass and writes it at the end. First run with no history file creates an empty one; all features degrade gracefully to existing behavior.

### Test Identifier Format

Fully qualified test name as reported by the test runner, normalized by stripping parameterized suffixes (`[1]`, `(case: "empty")`):

| Framework | Example |
|-----------|---------|
| JUnit/Kotest | `com.example.UserServiceTest#testCreateUser` |
| Jest/Vitest | `UserService > createUser > should return created user` |
| pytest | `tests/test_user_service.py::TestUserService::test_create_user` |
| Go | `TestCreateUser` |

---

## 2. Flaky Detection Algorithm

Computed after each test suite execution. Requires `flaky.min_runs` (default 5) results before producing a score.

### flip_rate (default)

Measures outcome volatility. A test alternating PASS/FAIL every run scores 1.0. A test that fails consistently scores 0.0 (broken, not flaky).

```
flips = 0
FOR i in 1..len(results)-1:
  prev = normalize(results[i-1].outcome)   # PASS|FLAKY|SKIP -> PASS; FAIL|ERROR -> FAIL
  curr = normalize(results[i].outcome)
  IF prev != curr: flips += 1
flaky_score = flips / (len(results) - 1)
```

### failure_rate (alternative)

Simple failure percentage. Not recommended as default because a test that fails 30% due to a genuine bug should not be quarantined.

```
failures = count(r for r in results if r.outcome in [FAIL, ERROR])
total = count(r for r in results if r.outcome not in [SKIP])
flaky_score = failures / total
```

---

## 3. Quarantine Lifecycle

```
  HEALTHY                         flaky_score > threshold
    |                                    |
    +---------> QUARANTINED <------------+
                    |
                    |  consecutive passes >= unquarantine_consecutive_passes
                    v
              OBSERVATION
                    |
         +----pass--+--fail----+
         |                     |
    consecutive_passes         re-quarantine
    >= threshold               (back to QUARANTINED)
         |
         v
      HEALTHY
         (unquarantined)

  QUARANTINED + max_quarantine_days exceeded
    -> WARNING escalation, user decides: fix / keep / delete test
```

### States

| State | `quarantined` | `consecutive_passes_since_unquarantine` | Behavior on FAIL |
|-------|--------------|----------------------------------------|------------------|
| HEALTHY | `false` | `null` | Normal failure (CRITICAL) |
| QUARANTINED | `true` | `null` | `TEST-FLAKY` INFO, non-blocking |
| OBSERVATION | `true` | `integer >= 0` | Re-quarantine, reset counter |

### Quarantine Behavior During Pipeline

| Test Status | Quarantined? | Pipeline Effect |
|-------------|-------------|-----------------|
| PASS | No | Normal pass |
| PASS | Yes | Pass + increment `consecutive_passes_since_unquarantine` |
| FAIL | No | Normal failure, triggers re-run per existing flaky detection |
| FAIL (confirmed) | No | Genuine failure, blocks pipeline |
| FAIL | Yes | `TEST-FLAKY` INFO finding, does NOT block pipeline |
| FAIL (re-run passes) | No | Marked FLAKY in history, pipeline proceeds (existing behavior) |

### Auto-Unquarantine

After `quarantine.unquarantine_consecutive_passes` (default 5) consecutive PASS results while quarantined, the test is automatically unquarantined. A `TEST-QUARANTINE` INFO finding is emitted.

### Force Escalation

If a test remains quarantined longer than `quarantine.max_quarantine_days` (default 30), emit WARNING: "Test {test_id} quarantined for {N} days. Action required: fix the test, remove it, or extend quarantine." Written to `.forge/alerts.json` in background mode.

---

## 4. Finding Categories

| Code | Severity | Meaning |
|------|----------|---------|
| `TEST-FLAKY` | INFO | Quarantined flaky test failed. Non-blocking. Recorded for trend tracking. |
| `TEST-QUARANTINE` | INFO | Test was quarantined or unquarantined during this run. Informational. |

Both are registered in `shared/checks/category-registry.json`. Neither blocks the pipeline. Genuine test failures remain `TEST-FAIL` (CRITICAL).

---

## 5. Predictive Test Selection

Uses file-test associations to identify which tests are relevant to the current change set (target: 15-20% of suite).

### Association Sources

1. **Import analysis**: Parse test file imports to find implementation files (done by test gate at first run).
2. **Explore cache**: `explore-cache.json` file dependencies for entity-to-test relationships.
3. **Historical correlation**: When a test fails and is fixed by changing file X, associate X with the test.
4. **Naming conventions**: `UserServiceTest` is associated with `UserService.kt` by name.

### Association Confidence

```
confidence = 0.0
IF file in test_entry.associated_files: confidence += 0.5    # explicit
IF test_name_matches_file(test_id, file): confidence += 0.3  # naming
co_changes = count_co_changes(file, test_entry.results)
IF co_changes > 0: confidence += min(0.2, co_changes * 0.05) # historical
RETURN min(1.0, confidence)
```

Minimum confidence threshold: `predictive.min_association_confidence` (default 0.5). Package-level matches use 70% of the threshold.

### Selection Algorithm

1. Select tests associated with changed files (direct + package-level).
2. Always include previously failing tests and high flaky-score tests (not quarantined).
3. If targeted set is empty, fall back to full suite.
4. If targeted set exceeds 80% of suite, run full suite instead (prediction not useful).

### Execution Flow

When `predictive.enabled` is `true` and history has 10+ runs:

1. Compute targeted tests from changed files + associations.
2. Apply prioritization to targeted tests.
3. Run targeted tests in priority order.
4. If targeted pass: run remaining tests (full suite minus targeted).
5. If targeted fail: process failures without running remaining tests (faster feedback).

When insufficient history: run full test suite with prioritization applied if any history is available.

---

## 6. Test Prioritization Order

Tests are ordered for fastest feedback. Priority (descending):

| Priority | Weight | Criterion |
|----------|--------|-----------|
| 1 | +50 | Previously failing (last result was FAIL/ERROR) |
| 2 | +30 | Associated with changed files |
| 3 | +20 max | Higher flaky score (flaky_score * 20) |
| 4 | +10 max | Shorter duration (10 - duration_seconds, floor 0) |
| new test | 100 | Unknown tests run first (unknown = risky) |

---

## 7. Prediction Accuracy Tracking

Stored in `test-history.json` under `prediction_accuracy`:

| Field | Description |
|-------|-------------|
| `total_runs` | Pipeline runs with predictive selection active |
| `targeted_caught_all_failures` | Runs where targeted pass caught all failures |
| `remaining_revealed_failures` | Runs where remaining tests found new failures |
| `catch_rate` | `targeted_caught_all_failures / total_runs` (target: >90%) |
| `avg_targeted_pct` | Average percentage of tests in targeted pass (target: <30%) |
| `avg_time_saved_pct` | Average time savings from targeted-first strategy |

If `catch_rate` drops below 80% over 10+ runs, log WARNING: "Predictive test selection catch rate is {rate}%. Consider increasing association confidence or disabling predictive selection."

---

## 8. Integration Points

| System | Integration | Direction |
|--------|-------------|-----------|
| fg-500-test-gate | Core consumer: flaky detection, quarantine, predictive selection | Read + Write |
| fg-100-orchestrator | Provides changed_files list to test gate | Read |
| fg-700-retrospective | Prunes old history entries, reports flaky trends | Read + Write |
| fg-710-post-run | Reports flaky test stats in run recap | Read |
| explore-cache.json | File dependencies for test-code associations | Read |
| category-registry.json | `TEST-FLAKY`, `TEST-QUARANTINE` finding codes | Read |
| state.json | Test cycle counts and convergence data | Read |
| `/forge-insights` | Flaky trends across runs | Read |

### History Pruning (fg-700-retrospective)

During LEARN stage, the retrospective prunes test entries not seen in `max_age_days` (default 90) days. Entries are removed entirely.

---

## 9. Configuration

In `forge-config.md` / `forge-config-template.md`:

```yaml
test_history:
  enabled: true                         # Master toggle (default: true)
  flaky_threshold: 0.2                  # Flip rate to trigger quarantine (default: 0.2)
  quarantine_passes: 5                  # Consecutive passes to unquarantine (default: 5)
  history_window: 10                    # Number of recent results to track (default: 10)
  predictive_selection: true            # Use file associations for test ordering (default: true)
```

### PREFLIGHT Constraints

- `flaky_threshold` must be > 0.0 and < 1.0.
- `quarantine_passes` must be >= 3 and <= 20.
- `history_window` must be >= 5 and <= 100.

---

## 10. Error Handling

| Scenario | Behavior |
|----------|----------|
| `test-history.json` does not exist | First run: create empty history. All features degrade to existing behavior. |
| `test-history.json` is corrupt (invalid JSON) | Rebuild from empty. Log WARNING. |
| Test identifier format changes (test renamed) | Old entry stays until pruned. New entry starts fresh. |
| Test runner output unparseable | Fall back to existing behavior (no history update). Log WARNING. |
| Quarantine accumulates >50 tests | Log WARNING at PREFLIGHT. |
| Predictive selection returns empty targeted set | Fall back to full test suite. Log INFO. |
| Predictive selection returns >80% of tests | Run full suite instead. Log INFO. |
| Sprint mode: parallel tasks sharing test history | Last-write-wins (acceptable, results accumulate over runs). |
| `max_quarantine_days` exceeded | Emit WARNING, include in `alerts.json` for background mode. |

---

## 11. Performance

- **History file size**: ~500 bytes per test with 20 results. 1000 tests = ~500KB, 5000 tests = ~2.5MB.
- **Flaky score computation**: O(n) per test, n = `history_window`. <100ms for 1000 tests.
- **Predictive selection**: O(tests * changed_files). <200ms for 1000 tests and 20 changed files.
- **No LLM cost**: All computations are algorithmic (bash/jq).
