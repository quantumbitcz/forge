# Q04: Test Suite Expansion

## Status
DRAFT — 2026-04-13

## Problem Statement

The test suite scored B- (75/100) — the second weakest dimension. Current inventory:

| Category | Test Files | Test Cases | Quality |
|----------|-----------|------------|---------|
| Unit | 53 files | 639 tests | Good coverage for scripts/adapters, but gaps in dedup algorithm depth and discovery scripts |
| Contract | 78 files | 846 tests | Solid structural validation, but mostly grep-based existence checks |
| Scenario | 29 files | 297 tests | Reasonable state machine coverage, but E2E dry-run is infrastructure-only (no agent simulation) |
| Structural | 1 file | ~51 checks (validate-plugin.sh) | Adequate |
| **Total** | **161 files** | **~1,833 tests** | |

**Critical gaps identified:**

1. **No full E2E pipeline simulation:** `e2e-dry-run.bats` validates infrastructure (config parsing, convention resolution, state init, check engine, kanban) but does NOT simulate agent dispatch or state transitions through the full PREFLIGHT -> VALIDATING flow.
2. **Zero discovery script tests:** `shared/discovery/detect-project-type.sh` (322 lines) and `shared/discovery/discover-projects.sh` (485 lines) have zero unit tests. These scripts determine the entire pipeline's framework/language detection.
3. **Shallow state integrity tests:** Only 3 scenario tests in `state-integrity.bats`. The `shared/state-integrity.sh` script validates 10+ conditions but only 3 are tested.
4. **Dedup tests are decent but incomplete:** `dedup-logic.bats` has 10 tests covering core cases but lacks edge cases (malformed input, very large input, unicode, empty fields).
5. **Zero hook integration tests:** The 4 hooks in `hooks/hooks.json` have unit tests but no integration test verifying they fire in the correct order during simulated tool use.
6. **run-all.sh lacks modern features:** No parallel execution, no timing per suite, no retry logic, no coverage reporting, no pass/fail summary table.
7. **Many assertions are grep-based:** Tests check "does this file contain this string" rather than validating semantic correctness (e.g., "is this a valid JSON state transition" vs "does this file mention state transitions").

## Target

Tests B- (75) --> A (92+), adding ~120 new tests across 8 new test files and expanding 4 existing files.

## Detailed Changes

### 1. Test Expansion Plan (by priority)

#### Critical Priority (Must Have)

##### 1a. Discovery Script Unit Tests — `tests/unit/detect-project-type.bats`

**File:** `tests/unit/detect-project-type.bats`
**Tests to add:** 25+
**Validates:** `shared/discovery/detect-project-type.sh`

Each test creates a minimal project directory with specific marker files, runs the detection script, and validates the JSON output semantically (not just string matching).

```bash
# Fixture strategy: each test creates a temp dir with minimal files

@test "detect: empty directory returns unknown/unknown/unknown"
# mkdir empty-project; run detect; assert JSON fields all "unknown"

@test "detect: package.json alone returns javascript frontend"
# echo '{}' > package.json; assert language=javascript, type=frontend

@test "detect: package.json + tsconfig.json returns typescript frontend"
# touch tsconfig.json; assert language=typescript

@test "detect: package.json + vite.config.ts + react dep returns react frontend"
# echo '{"dependencies":{"react":"^18"}}' > package.json; touch vite.config.ts
# assert framework=react

@test "detect: package.json + next.config.js returns nextjs frontend"
@test "detect: package.json + svelte.config.js returns sveltekit"
@test "detect: package.json + angular.json returns angular with typescript"
@test "detect: package.json + nest-cli.json returns nestjs backend"
@test "detect: package.json + express dep returns express backend"
@test "detect: package.json + vue dep + vite returns vue frontend"
@test "detect: package.json + svelte dep (no sveltekit) returns svelte frontend"

@test "detect: build.gradle.kts + src/main/kotlin returns kotlin backend"
@test "detect: build.gradle.kts + spring dep returns kotlin spring"
@test "detect: build.gradle.kts + src/main/java returns java backend"
@test "detect: build.gradle + src/main/java + spring returns java spring"
@test "detect: build.gradle.kts + src/commonMain returns kotlin-multiplatform"

@test "detect: pom.xml + src/main/java returns java backend"
@test "detect: pom.xml + spring in pom returns java spring"

@test "detect: Cargo.toml returns rust backend"
@test "detect: go.mod returns go backend"
@test "detect: Package.swift returns swift"
@test "detect: requirements.txt returns python backend"
@test "detect: pyproject.toml returns python backend"
@test "detect: pyproject.toml + fastapi dep returns python fastapi"

@test "detect: Dockerfile only returns unknown (no language markers)"
@test "detect: multiple markers (package.json + go.mod) — most specific wins"
```

**Validation approach:** Parse JSON output with `python3 -c "import json; ..."` and assert individual fields.

##### 1b. Discovery Script Unit Tests — `tests/unit/discover-projects.bats`

**File:** `tests/unit/discover-projects.bats`
**Tests to add:** 12+
**Validates:** `shared/discovery/discover-projects.sh`

```bash
@test "discover: single project in root returns 1 project"
@test "discover: monorepo with services/ subdirs returns multiple projects"
@test "discover: nested projects (project inside project) detected correctly"
@test "discover: hidden directories (.hidden/) are skipped"
@test "discover: node_modules/ and vendor/ are skipped"
@test "discover: max depth respected (no projects beyond depth 3)"
@test "discover: empty directory returns 0 projects"
@test "discover: symlinked projects detected (if followed)"
@test "discover: project with .claude/forge.local.md flagged as already configured"
@test "discover: git submodules detected as separate projects"
@test "discover: output is valid JSON array"
@test "discover: each project entry has required fields (path, type, framework, language)"
```

##### 1c. State Integrity Expansion — `tests/unit/state-integrity.bats` (expand existing)

**File:** `tests/unit/state-integrity.bats` (existing, currently 7 tests)
**Tests to add:** 15+ (bringing total to 22+)
**Validates:** `shared/state-integrity.sh`

```bash
# Existing tests cover: valid state, invalid state, counter violations
# New tests:

@test "state-integrity: missing version field reports error"
@test "state-integrity: unsupported version (e.g., 2.0.0) reports warning"
@test "state-integrity: story_state in valid set (all 10 pipeline states + ABORTED + ESCALATED + COMPLETE)"
@test "state-integrity: recovery_budget.total_weight <= max_weight"
@test "state-integrity: recovery_budget negative total_weight rejected"
@test "state-integrity: score_history entries are valid numbers 0-100"
@test "state-integrity: score_history with negative value rejected"
@test "state-integrity: total_iterations >= quality_cycles"
@test "state-integrity: orphaned checkpoint files detected (checkpoint for wrong story_id)"
@test "state-integrity: _seq field is positive integer"
@test "state-integrity: _seq field missing triggers warning (not error)"
@test "state-integrity: concurrent lock file (.forge/.lock) detected as warning"
@test "state-integrity: stale lock file (>24h) detected as error"
@test "state-integrity: empty state.json (0 bytes) detected"
@test "state-integrity: valid state with all optional fields present passes"
```

##### 1d. Dedup Algorithm Expansion — `tests/unit/dedup-logic.bats` (expand existing)

**File:** `tests/unit/dedup-logic.bats` (existing, 10 tests)
**Tests to add:** 8+ (bringing total to 18+)

```bash
@test "dedup: malformed input line (missing fields) is skipped with warning"
@test "dedup: input with unicode characters in description preserved"
@test "dedup: 100+ findings deduplicates correctly (stress test)"
@test "dedup: findings with empty file field handled"
@test "dedup: findings with no line number (file-level) dedup by file+category"
@test "dedup: confidence field preserved through dedup (HIGH wins over LOW)"
@test "dedup: findings from timed-out reviewers (INFO severity) not promoted"
@test "dedup: pipe characters in description field don't break parsing"
```

#### High Priority

##### 2a. Agent Dispatch Simulation — `tests/scenario/agent-dispatch-simulation.bats`

**File:** `tests/scenario/agent-dispatch-simulation.bats`
**Tests to add:** 15+
**Validates:** Orchestrator dispatch decisions are correct given state

This does NOT invoke actual agents (requires Claude Code runtime). Instead, it validates that the orchestrator's dispatch logic in `fg-100-orchestrator.md` maps to the correct agents for each stage by checking the markdown content.

```bash
@test "dispatch-sim: PREFLIGHT dispatches fg-130-docs-discoverer"
@test "dispatch-sim: PREFLIGHT dispatches fg-140-deprecation-refresh when context7 mentioned"
@test "dispatch-sim: PREFLIGHT dispatches fg-135-wiki-generator"
@test "dispatch-sim: EXPLORE references fg-100 inline (no separate agent)"
@test "dispatch-sim: PLAN dispatches fg-200-planner"
@test "dispatch-sim: VALIDATE dispatches fg-210-validator"
@test "dispatch-sim: IMPLEMENT dispatches fg-300-implementer"
@test "dispatch-sim: IMPLEMENT dispatches fg-310-scaffolder when scaffolding needed"
@test "dispatch-sim: VERIFY dispatches fg-500-test-gate"
@test "dispatch-sim: REVIEW dispatches fg-400-quality-gate"
@test "dispatch-sim: DOCUMENTING dispatches fg-350-docs-generator"
@test "dispatch-sim: SHIPPING dispatches fg-600-pr-builder"
@test "dispatch-sim: SHIPPING dispatches fg-590-pre-ship-verifier before PR"
@test "dispatch-sim: LEARNING dispatches fg-700-retrospective"
@test "dispatch-sim: LEARNING dispatches fg-710-post-run"
@test "dispatch-sim: bugfix mode dispatches fg-020-bug-investigator at EXPLORE"
@test "dispatch-sim: migration mode dispatches fg-160-migration-planner at EXPLORE"
```

**Validation approach:** grep the orchestrator for stage sections, verify agent names appear in the correct stage.

##### 2b. Hook Integration Tests — `tests/scenario/hook-integration.bats`

**File:** `tests/scenario/hook-integration.bats`
**Tests to add:** 10+
**Validates:** `hooks/hooks.json` + hook scripts

```bash
@test "hook-integration: hooks.json is valid JSON with 4 hooks"
@test "hook-integration: check-engine hook references correct script path"
@test "hook-integration: check-engine hook triggers on Edit and Write events"
@test "hook-integration: checkpoint hook triggers on Skill event"
@test "hook-integration: feedback hook triggers on Stop event"
@test "hook-integration: compaction hook triggers on Agent event"
@test "hook-integration: all hook scripts referenced in hooks.json exist and are executable"
@test "hook-integration: check-engine hook script has bash 4+ guard"
@test "hook-integration: hook scripts source platform.sh for portability"
@test "hook-integration: hooks.json does not reference any nonexistent scripts"
```

##### 2c. Graph Query Pattern Tests — `tests/unit/query-patterns.bats` (expand existing)

**File:** `tests/unit/query-patterns.bats` (existing)
**Tests to add:** 8+

```bash
@test "graph-queries: bug hotspot query pattern (14) is valid Cypher syntax"
@test "graph-queries: test coverage query pattern (15) references ProjectFunction nodes"
@test "graph-queries: cross-feature overlap query (19) uses project_id scoping"
@test "graph-queries: cross-repo deps query (20) filters by project_id"
@test "graph-queries: all query patterns in schema.md have IDs"
@test "graph-queries: no query uses deprecated Neo4j syntax"
@test "graph-queries: all queries scope by project_id (security)"
@test "graph-queries: query count matches documented count (20)"
```

#### Medium Priority

##### 3a. Full Dry-Run E2E with State Transitions — `tests/scenario/pipeline-dry-run-e2e.bats` (expand existing)

**File:** `tests/scenario/pipeline-dry-run-e2e.bats` (existing, limited)
**Tests to add:** 12+
**Validates:** State machine transitions for a complete dry-run path

```bash
# Setup: create temp project, initialize state.json at PREFLIGHT
# Simulate state transitions using forge-state.sh

@test "pipeline-e2e: state machine transitions PREFLIGHT -> EXPLORING"
# Run: bash forge-state.sh transition EXPLORING
# Assert: state.json.story_state == "EXPLORING"

@test "pipeline-e2e: state machine transitions EXPLORING -> PLANNING"
@test "pipeline-e2e: state machine transitions PLANNING -> VALIDATING"
@test "pipeline-e2e: dry-run stops at VALIDATING (does not enter IMPLEMENTING)"
@test "pipeline-e2e: VALIDATING -> IMPLEMENTING transition works for non-dry-run"
@test "pipeline-e2e: IMPLEMENTING -> VERIFYING transition"
@test "pipeline-e2e: VERIFYING -> REVIEWING transition"
@test "pipeline-e2e: REVIEWING -> DOCUMENTING transition"
@test "pipeline-e2e: DOCUMENTING -> SHIPPING transition"
@test "pipeline-e2e: SHIPPING -> LEARNING transition"
@test "pipeline-e2e: LEARNING -> COMPLETE transition"
@test "pipeline-e2e: invalid transition (PREFLIGHT -> IMPLEMENTING) rejected"
@test "pipeline-e2e: state.json _seq increments on each transition"
@test "pipeline-e2e: state.json previous_state tracks correctly"
```

**Validation approach:** Use `forge-state.sh` directly to test the state machine. Parse `state.json` with python3 after each transition.

##### 3b. Cross-Component Workflow Tests — `tests/scenario/cross-component-workflows.bats`

**File:** `tests/scenario/cross-component-workflows.bats`
**Tests to add:** 8+

```bash
@test "workflow: scoring formula produces correct score from finding counts"
# Create findings, run through dedup, compute score, verify matches formula

@test "workflow: recovery budget exhaustion triggers correct state"
# Initialize state with budget near max, simulate failure, verify ESCALATED

@test "workflow: convergence plateau detection triggers safety gate"
# Create score_history with plateau pattern, verify detection

@test "workflow: kanban ticket lifecycle (create -> in-progress -> review -> done)"
# Use tracking-ops.sh to move ticket through all states

@test "workflow: convention drift detection (hash comparison)"
# Modify a conventions file, verify hash mismatch detected

@test "workflow: lock file acquisition and release"
# Simulate concurrent lock, verify mutual exclusion

@test "workflow: evidence.json staleness check"
# Create evidence older than max_age, verify stale detection

@test "workflow: state WAL recovery after interrupted write"
# Create WAL file, verify recovery produces valid state
```

##### 3c. Performance Tests — `tests/scenario/performance.bats`

**File:** `tests/scenario/performance.bats`
**Tests to add:** 6+

```bash
@test "performance: state.json write completes in under 100ms for 500KB state"
# Create large state.json (500KB), run forge-state-write.sh, time it

@test "performance: check engine completes in under 2s for 50 files"
# Create 50 minimal source files, run engine.sh --verify, time it

@test "performance: detect-project-type.sh completes in under 500ms"
# Run detection on a typical project structure, time it

@test "performance: dedup-helper processes 500 findings in under 1s"
# Generate 500 findings, pipe through dedup, time it

@test "performance: tracking-ops.sh board generation under 500ms for 100 tickets"
# Create 100 kanban tickets, generate board, time it

@test "performance: state-integrity.sh validates in under 200ms"
# Run validator on a complex state.json, time it
```

### 2. run-all.sh Improvements

Rewrite `tests/run-all.sh` to add:

#### Timing per suite:

```bash
run_tier() {
  local name="$1"; shift
  local start_time end_time duration
  start_time=$(date +%s)
  printf '\n%b=== %s ===%b\n' "$BOLD" "$name" "$NC"
  if "$@"; then
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    printf '%b%s: PASSED (%ds)%b\n' "$GREEN" "$name" "$duration" "$NC"
    RESULTS+=("PASS|$name|${duration}s")
  else
    end_time=$(date +%s)
    duration=$((end_time - start_time))
    printf '%b%s: FAILED (%ds)%b\n' "$RED" "$name" "$duration" "$NC"
    RESULTS+=("FAIL|$name|${duration}s")
    FAILURES=$((FAILURES + 1))
  fi
}
```

#### Pass/fail summary table:

```bash
# At end of run:
printf '\n%b=== Summary ===%b\n' "$BOLD" "$NC"
printf '%-12s %-30s %s\n' "Result" "Suite" "Duration"
printf '%-12s %-30s %s\n' "------" "-----" "--------"
for result in "${RESULTS[@]}"; do
  IFS='|' read -r status suite duration <<< "$result"
  if [[ "$status" == "PASS" ]]; then
    printf '%b%-12s%b %-30s %s\n' "$GREEN" "$status" "$NC" "$suite" "$duration"
  else
    printf '%b%-12s%b %-30s %s\n' "$RED" "$status" "$NC" "$suite" "$duration"
  fi
done
printf '\nTotal: %d passed, %d failed\n' "$((${#RESULTS[@]} - FAILURES))" "$FAILURES"
```

#### Parallel execution (optional, --parallel flag):

```bash
case "$TIER" in
  all)
    if [[ "${PARALLEL:-false}" == "true" ]]; then
      # Run unit and contract in parallel (independent)
      run_tier "Structural" bash "$SCRIPT_DIR/validate-plugin.sh"
      run_tier "Unit Tests" "$BATS" "$SCRIPT_DIR"/unit/*.bats &
      PID_UNIT=$!
      run_tier "Contract Tests" "$BATS" "$SCRIPT_DIR"/contract/*.bats &
      PID_CONTRACT=$!
      wait $PID_UNIT || FAILURES=$((FAILURES + 1))
      wait $PID_CONTRACT || FAILURES=$((FAILURES + 1))
      # Scenarios depend on structural integrity, run after
      run_tier "Scenario Tests" "$BATS" "$SCRIPT_DIR"/scenario/*.bats
    else
      # Sequential (current behavior, default)
      run_tier "Structural" bash "$SCRIPT_DIR/validate-plugin.sh"
      run_tier "Unit Tests" "$BATS" "$SCRIPT_DIR"/unit/*.bats
      run_tier "Contract Tests" "$BATS" "$SCRIPT_DIR"/contract/*.bats
      run_tier "Scenario Tests" "$BATS" "$SCRIPT_DIR"/scenario/*.bats
    fi
    ;;
```

#### Don't exit on first failure (--continue-on-failure):

Replace `exit 1` in `run_tier` failure path with counter increment. Report all failures at end.

### 3. Module Count Guards Update

Update `tests/lib/module-lists.bash` to include test count guards:

```bash
# Add to module-lists.bash:
MIN_UNIT_TESTS=53        # Current: 53 files
MIN_CONTRACT_TESTS=78    # Current: 78 files
MIN_SCENARIO_TESTS=29    # Current: 29 files

# After expansion:
# MIN_UNIT_TESTS=56      # +3 new files
# MIN_CONTRACT_TESTS=80  # +2 new files (skill-quality from Q01, agent-description from Q02)
# MIN_SCENARIO_TESTS=33  # +4 new files
```

### 4. Test Summary Table

After all changes, the test inventory should be:

| Category | Current Files | Current Tests | New Files | New Tests | Target Files | Target Tests |
|----------|--------------|---------------|-----------|-----------|-------------|-------------|
| Unit | 53 | 639 | 3 | 45 | 56 | 684 |
| Contract | 78 | 846 | 2* | 22* | 80 | 868 |
| Scenario | 29 | 297 | 4 | 51 | 33 | 348 |
| Structural | 1 | 51 | 0 | 0 | 1 | 51 |
| **Total** | **161** | **1,833** | **9** | **118** | **170** | **1,951** |

*Contract test files from Q01 (`skill-quality.bats`) and Q02 (`agent-description-quality.bats`) — counted here for total but created in those specs.

### 5. New Test File Locations

```
tests/
  unit/
    detect-project-type.bats          # NEW: 25 tests — discovery detection
    discover-projects.bats            # NEW: 12 tests — multi-project discovery
    state-integrity.bats              # EXPAND: +15 tests (7 -> 22)
    dedup-logic.bats                  # EXPAND: +8 tests (10 -> 18)
    query-patterns.bats               # EXPAND: +8 tests
  contract/
    skill-quality.bats                # NEW (from Q01): 12 tests
    agent-description-quality.bats    # NEW (from Q02): 7 tests
  scenario/
    agent-dispatch-simulation.bats    # NEW: 15 tests
    hook-integration.bats             # NEW: 10 tests
    pipeline-dry-run-e2e.bats         # EXPAND: +12 tests
    cross-component-workflows.bats    # NEW: 8 tests
    performance.bats                  # NEW: 6 tests
```

### 6. Test Fixture Strategy

Create `tests/fixtures/` directory with reusable project templates:

```
tests/fixtures/
  projects/
    kotlin-spring/                    # Minimal Kotlin Spring project markers
      build.gradle.kts
      src/main/kotlin/.gitkeep
    react-vite/                       # Minimal React Vite project markers
      package.json
      vite.config.ts
      tsconfig.json
    python-fastapi/                   # Minimal Python FastAPI project markers
      pyproject.toml
      requirements.txt
    go-stdlib/                        # Minimal Go project markers
      go.mod
    empty/                            # Empty directory
      .gitkeep
  state/
    valid-implementing.json           # Valid state at IMPLEMENTING stage
    valid-complete.json               # Valid completed state
    corrupted-counters.json           # State with counter violations
    stale-lock.json                   # State with stale lock
  findings/
    mixed-severity.txt                # 20 findings with mixed severities
    duplicates.txt                    # Findings with intentional duplicates
    malformed.txt                     # Malformed finding lines
```

## Testing Approach

1. Run expanded test suite: `./tests/run-all.sh` must pass
2. Verify test count targets met: `grep -c "^@test" tests/{unit,contract,scenario}/*.bats`
3. Verify timing output in run-all.sh
4. Run individual new test files to validate they work in isolation
5. Check fixture files are correctly referenced (no hardcoded paths)

## Acceptance Criteria

- [ ] 25+ discovery detection tests passing
- [ ] 12+ multi-project discovery tests passing
- [ ] 22+ state integrity tests passing (expanded from 7)
- [ ] 18+ dedup algorithm tests passing (expanded from 10)
- [ ] 15+ agent dispatch simulation tests passing
- [ ] 10+ hook integration tests passing
- [ ] 12+ pipeline E2E state transition tests passing
- [ ] 8+ cross-component workflow tests passing
- [ ] 6+ performance tests passing with timing assertions
- [ ] run-all.sh shows timing per suite and summary table
- [ ] Total test count >= 1,950
- [ ] All existing tests continue to pass (no regressions)
- [ ] Test fixtures created in `tests/fixtures/`
- [ ] `tests/lib/module-lists.bash` updated with test count guards

## Effort Estimate

**XL** (Extra Large) — 9 new test files, 4 expanded files, run-all.sh rewrite, fixture creation. Estimated: 8-12 hours.

## Dependencies

- Q01 creates `tests/contract/skill-quality.bats` (12 tests counted in contract total)
- Q02 creates `tests/contract/agent-description-quality.bats` (7 tests counted in contract total)
- Q03 creates `tests/contract/orchestrator-modular.bats` if modular split proceeds (not counted in totals)
- Discovery script tests depend on `shared/discovery/detect-project-type.sh` and `shared/discovery/discover-projects.sh` remaining stable
