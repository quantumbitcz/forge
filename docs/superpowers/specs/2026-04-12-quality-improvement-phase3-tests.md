# Phase 3: Test Coverage

**Parent:** [Umbrella Spec](./2026-04-12-quality-improvement-umbrella-design.md)
**Priority:** Medium — closes the "F" grade gaps in language/testing module validation.
**Approach:** Structural validation matching existing framework test patterns. Uses `module-lists.bash` for dynamic discovery.

## Item 3.1: Language module structural validation

**Rationale:** 15 language modules in `modules/languages/` have zero dedicated tests. If someone introduces a malformed module file, no test catches it.

**Category:** Test coverage gap (F → B+).

**New file:** `tests/contract/language-module-structure.bats`

**Test design:**
```bash
# Sources module-lists.bash for dynamic discovery
# For each language module file in modules/languages/*.md:

@test "language modules: all discovered modules exist and are non-empty" {
  # Uses get_language_modules() from module-lists.bash
  # Asserts file exists and has > 0 bytes
}

@test "language modules: each module contains required sections" {
  # For each module, asserts presence of:
  # - A level-2 heading (## ...) for overview/description
  # - A "Dos" or "Do" section (case-insensitive grep)
  # - A "Don'ts" or "Do not" section (case-insensitive grep)
}

@test "language modules: minimum count guard" {
  # Asserts discovered count >= MIN_LANGUAGES (15)
  # Catches accidental deletions
}
```

**Expected test count:** ~3 test cases (one per assertion type), each iterating 15 modules internally.

## Item 3.2: Testing module structural validation

**Rationale:** 19 testing modules in `modules/testing/` have zero dedicated tests. Same gap as languages.

**Category:** Test coverage gap (F → B+).

**New file:** `tests/contract/testing-module-structure.bats`

**Test design:**
```bash
# Sources module-lists.bash for dynamic discovery
# For each testing module file in modules/testing/*.md:

@test "testing modules: all discovered modules exist and are non-empty" {
  # Uses get_testing_modules() from module-lists.bash
  # Asserts file exists and has > 0 bytes
}

@test "testing modules: each module contains required sections" {
  # For each module, asserts presence of:
  # - A level-2 heading for overview
  # - Convention or integration guidance section
  # - Framework-specific content (not just a placeholder)
}

@test "testing modules: minimum count guard" {
  # Asserts discovered count >= MIN_TESTING (19)
}
```

**Expected test count:** ~3 test cases iterating 19 modules.

## Item 3.3: E2E dry-run pipeline scenario

**Rationale:** No test exercises the state machine progression across multiple stages. The simulation harness (`forge-sim.sh`) exists but isn't tested via BATS.

**Category:** Integration test gap (D → B).

**New file:** `tests/scenario/pipeline-dry-run-e2e.bats`

**Test design:**

`forge-state.sh` uses named events for transitions (verified in source):
- `preflight_complete` → PREFLIGHT → EXPLORING
- `explore_complete` → EXPLORING → PLANNING (when scope < threshold)
- `plan_complete` → PLANNING → VALIDATING
- `validate_complete` → VALIDATING → COMPLETE (when dry_run=true)

```bash
# Uses forge-state.sh for state transitions
# Uses forge-state-write.sh for atomic state updates
# Simulates dry-run: PREFLIGHT → EXPLORING → PLANNING → VALIDATING → COMPLETE

@test "dry-run: initial state is PREFLIGHT" {
  # Creates fresh state.json via forge-state-write.sh with dry_run=true
  # Asserts stage == "PREFLIGHT"
}

@test "dry-run: preflight_complete transitions to EXPLORING" {
  # Calls: forge-state.sh transition preflight_complete
  # Asserts new stage == "EXPLORING"
  # Asserts _seq incremented
}

@test "dry-run: explore_complete transitions to PLANNING" {
  # Calls: forge-state.sh transition explore_complete scope=1 decomposition_threshold=3
  # Asserts new stage == "PLANNING"
}

@test "dry-run: plan_complete transitions to VALIDATING" {
  # Calls: forge-state.sh transition plan_complete
  # Asserts new stage == "VALIDATING"
}

@test "dry-run: validate_complete with dry_run=true transitions to COMPLETE" {
  # Calls: forge-state.sh transition validate_complete
  # Asserts state reflects completion (dry-run stops after validation)
}

@test "dry-run: state file well-formed after each transition" {
  # After full sequence, validates state.json against required fields
  # from state-schema.md: version, stage, mode, _seq, timestamps
}

@test "dry-run: decision log entries written per transition" {
  # Asserts .forge/decisions.jsonl has entries for each stage transition
  # Each entry has required fields: timestamp, agent, decision_type
}

@test "dry-run: invalid event rejected" {
  # From PREFLIGHT, sends explore_complete (wrong event for this state)
  # Asserts transition is rejected by forge-state.sh (non-zero exit)
}
```

**Expected test count:** ~8 test cases.

**Dependencies:** `forge-state.sh` and `forge-state-write.sh` are testable in isolation — they accept `--forge-dir` parameter and operate on arbitrary file paths. Events are named strings passed as arguments to the `transition` subcommand.

## Item 3.4: Scoring formula end-to-end test

**Rationale:** Convergence and recovery arithmetic are tested, but the core quality scoring formula `max(0, 100 - 20*CRITICAL - 5*WARNING - 2*INFO)` and verdict thresholds have no dedicated test.

**Category:** Test coverage gap (C → A).

**New file:** `tests/unit/scoring-formula.bats`

**Test design:**
```bash
# Tests the scoring formula and verdict determination

@test "scoring: clean slate = 100" {
  # 0 CRITICAL, 0 WARNING, 0 INFO → score 100
}

@test "scoring: 1 critical = 80" {
  # 1 CRITICAL → 100 - 20 = 80
}

@test "scoring: 5 criticals floors at 0" {
  # 5 CRITICAL → 100 - 100 = 0, max(0, 0) = 0
}

@test "scoring: 6 criticals still floors at 0" {
  # 6 CRITICAL → 100 - 120 = -20, max(0, -20) = 0
}

@test "scoring: mixed findings" {
  # 1 CRITICAL + 2 WARNING + 3 INFO → 100 - 20 - 10 - 6 = 64
}

@test "scoring: verdict PASS when score >= 80" {
  # Score 80 → PASS
}

@test "scoring: verdict CONCERNS when 60 <= score < 80" {
  # Score 70 → CONCERNS
}

@test "scoring: verdict FAIL when score < 60" {
  # Score 45 → FAIL
}

@test "scoring: verdict FAIL when unresolved CRITICAL regardless of score" {
  # 1 unresolved CRITICAL, score 80 → FAIL (not PASS)
}

@test "scoring: deduplication by (component, file, line, category)" {
  # Two findings with same key → counted once
  # Two findings with different keys → counted separately
}
```

**Expected test count:** ~10 test cases.

**Implementation note:** If scoring logic is embedded in agent prose (not a shell function), tests will implement the formula directly in bash arithmetic and validate against documented examples from `scoring.md`. This creates a "specification test" — the test IS the executable specification.

## Phase 3 Verification Checklist

- [ ] 4 new BATS files created
- [ ] Language module tests cover all 15 modules
- [ ] Testing module tests cover all 19 modules
- [ ] E2E dry-run tests exercise state transitions
- [ ] Scoring formula tests cover formula + verdicts + dedup
- [ ] All new tests passing (green)
- [ ] All existing tests passing (`./tests/run-all.sh`)
- [ ] `/requesting-code-review` passes
