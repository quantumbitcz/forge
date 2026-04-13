# F04: Inner-Loop Lint+Test at Implementer Level

## Status
DRAFT — 2026-04-13

## Problem Statement

Forge separates IMPLEMENT (Stage 4) from VERIFY (Stage 5). The implementer (`fg-300-implementer`) writes code following the TDD cycle (RED/GREEN/REFACTOR), then control returns to the orchestrator, which dispatches the full VERIFY stage (`fg-500-test-gate` with `fg-505-build-verifier` and `fg-510-mutation-analyzer`). If tests fail, the orchestrator dispatches the implementer again with failure context. Each round-trip through the convergence engine costs: orchestrator dispatch overhead (~500 tokens), test-gate agent setup (~1,000 tokens), build-verifier setup (~500 tokens), plus the implementer re-dispatch (~1,500 tokens system prompt). A single fix cycle costs 3,000-5,000 tokens in overhead alone.

**Measured impact:** In forge pipeline runs, 30-40% of Stage 5 failures are "obvious" breaks: syntax errors, import failures, type mismatches, failing tests in the same module as the changed code. These could have been caught by the implementer itself before returning to the orchestrator.

**Competitive validation:**
- **Aider:** Runs lint+test after every single edit. Auto-fixes lint errors and re-runs. Achieves faster task completion by catching obvious breaks immediately.
- **Junie (JetBrains):** Uses IDE inspections after every change, catching compilation errors and style violations in real-time. Reports 30% faster task completion.
- **SWE-Agent:** Runs test suites as part of the edit-observe-act loop, not as a separate stage.
- **OpenHands:** Runs affected tests in the same action loop as implementation.

**Gap:** The implementer already runs `commands.test_single` per step (section 5.5 "Verify Step") and has a fix loop (section 5.6 "Handle Failures"). But it does NOT run the project's lint command, does NOT run dependent tests (only the test for the specific step), and its fix loop budget is separate from the convergence engine. The current "Self-Review Before Completion" checklist (section 5.4) instructs the implementer to run lint and full test suite, but this happens ONCE at the end of all tasks, not incrementally after each TDD cycle.

## Proposed Solution

Enhance `fg-300-implementer` with a tight inner feedback loop that runs after completing each TDD cycle (after GREEN+REFACTOR, before moving to the next task). The inner loop executes:

1. L0 syntax check (from F02) -- already handled by PreToolUse hook, but verified here for completeness
2. Quick lint on changed files only
3. Affected tests (tests in changed files + direct dependents)
4. If any check fails, fix immediately within a separate budget (`implementer_fix_cycles`)

This catches 80%+ of issues that would otherwise require a full Stage 4 -> Stage 5 round-trip.

## Detailed Design

### Architecture

```
fg-300-implementer: TDD Loop (per task)
     |
     +-- 5.2 RED:   Write failing test
     +-- 5.3 GREEN: Implement to pass
     +-- 5.4 REFACTOR
     |
     +-- NEW: Inner Loop Validation
     |   |
     |   +-- Step 1: Quick Lint (changed files only)
     |   |   +-- Run: {commands.lint} --files {changed_files}
     |   |   +-- If lint fails: fix, re-lint (budget: implementer_fix_cycles)
     |   |
     |   +-- Step 2: Affected Test Execution
     |   |   +-- Detect affected tests (explore cache / graph / directory heuristic)
     |   |   +-- Run: {commands.test_single} {affected_test_files}
     |   |   +-- If tests fail: fix, re-test (budget: implementer_fix_cycles)
     |   |
     |   +-- Inner loop PASS: proceed to next task
     |   +-- Inner loop EXHAUSTED: report remaining failures, proceed to next task
     |
     +-- Next task...
     |
     +-- Self-Review Before Completion (existing section 5.4)
     |   +-- Full test suite: {commands.test}
     |   +-- Full lint: {commands.lint}
     |   +-- (This catches issues missed by the per-task inner loop)
     |
     +-- Return Implementation Summary to orchestrator
```

**Key principle:** The inner loop is a **fast filter**, not a replacement for VERIFY. It catches the obvious breaks (syntax errors, lint violations, broken tests in the same module). The full VERIFY stage still runs the complete test suite, mutation testing, coverage analysis, and cross-module verification.

### Inner Loop Algorithm

```
FUNCTION inner_loop_validate(task, changed_files, config):

  IF NOT config.implementer.inner_loop.enabled:
    RETURN  # Skip inner loop entirely

  fix_cycles_used = 0
  max_cycles = config.implementer.inner_loop.max_fix_cycles  # default: 3

  # --- Step 1: Quick Lint ---
  IF config.implementer.inner_loop.run_lint AND commands.lint EXISTS:
    lint_files = filter_lintable(changed_files)
    IF lint_files is not empty:
      lint_result = run_lint(commands.lint, lint_files)

      WHILE lint_result.has_errors AND fix_cycles_used < max_cycles:
        fix_cycles_used += 1
        apply_lint_fixes(lint_result.errors)  # Fix in-place
        lint_result = run_lint(commands.lint, lint_files)

      IF lint_result.has_errors:
        log_stage_note("INNER_LOOP_LINT_REMAINING: {count} lint errors after {fix_cycles_used} fix cycles")

  # --- Step 2: Affected Tests ---
  IF config.implementer.inner_loop.run_tests:
    affected_tests = detect_affected_tests(changed_files, task)

    IF affected_tests is not empty:
      test_result = run_affected_tests(commands.test_single, affected_tests)

      WHILE test_result.has_failures AND fix_cycles_used < max_cycles:
        fix_cycles_used += 1
        fix_test_failures(test_result.failures, changed_files)
        test_result = run_affected_tests(commands.test_single, affected_tests)

      IF test_result.has_failures:
        log_stage_note("INNER_LOOP_TEST_REMAINING: {count} test failures after {fix_cycles_used} fix cycles")

  # --- Record metrics ---
  log_stage_note("INNER_LOOP: task={task.name} fix_cycles={fix_cycles_used}/{max_cycles} lint={lint_pass} tests={tests_pass}")
  increment_state("implementer_fix_cycles", fix_cycles_used)
```

### Affected Test Detection Algorithm

The implementer uses a multi-strategy approach to identify which tests to run after each TDD cycle:

**Strategy 1: Explore Cache (preferred)**

If `.forge/explore-cache.json` exists and contains dependency information:

```
affected_tests = []
for file in changed_files:
  # Find test files that import or reference the changed file
  dependents = explore_cache.get_dependents(file)
  test_dependents = filter(dependents, is_test_file)
  affected_tests.extend(test_dependents)
```

The explore cache is populated during EXPLORE (Stage 1) and contains file dependency edges. This is the most accurate strategy.

**Strategy 2: Knowledge Graph (if Neo4j available)**

```cypher
MATCH (changed:File {path: $changed_file_path})<-[:IMPORTS|REFERENCES]-(test:File)
WHERE test.path CONTAINS '/test/' OR test.path CONTAINS '/spec/' OR test.path CONTAINS 'Test.'
RETURN test.path
```

This leverages the codebase graph built by `graph-init` / `graph-rebuild`. Most accurate for cross-module dependencies.

**Strategy 3: Directory Heuristic (fallback)**

When neither explore cache nor graph is available:

```
affected_tests = []
for file in changed_files:
  # Strategy 3a: Mirror path convention
  # src/main/kotlin/com/example/UserService.kt -> src/test/kotlin/com/example/UserServiceTest.kt
  test_mirror = compute_test_mirror(file)
  if exists(test_mirror): affected_tests.append(test_mirror)

  # Strategy 3b: Same directory test files
  dir = dirname(file)
  test_dir = find_test_directory(dir)  # Look for test/, __tests__/, spec/ sibling
  if test_dir exists:
    test_files = glob(test_dir + "/*Test*") + glob(test_dir + "/*Spec*") + glob(test_dir + "/*.test.*")
    affected_tests.extend(test_files)

  # Strategy 3c: Test files importing the changed module (grep-based)
  module_name = extract_module_name(file)
  test_files_importing = grep("import.*{module_name}", test_directories)
  affected_tests.extend(test_files_importing)
```

**Test mirror path conventions by language:**

| Language | Source Pattern | Test Pattern |
|---|---|---|
| Kotlin/Java | `src/main/kotlin/pkg/Foo.kt` | `src/test/kotlin/pkg/FooTest.kt` |
| TypeScript | `src/components/Foo.tsx` | `src/__tests__/Foo.test.tsx` or `src/components/Foo.test.tsx` |
| Python | `src/foo/bar.py` | `tests/foo/test_bar.py` or `tests/test_bar.py` |
| Go | `pkg/foo/bar.go` | `pkg/foo/bar_test.go` (same directory) |
| Rust | `src/foo/bar.rs` | `src/foo/bar.rs` (inline `#[cfg(test)]`) or `tests/bar.rs` |
| Swift | `Sources/Foo/Bar.swift` | `Tests/FooTests/BarTests.swift` |
| C/C++ | `src/foo.c` | `test/test_foo.c` or `tests/foo_test.cpp` |
| Ruby | `lib/foo/bar.rb` | `spec/foo/bar_spec.rb` or `test/foo/bar_test.rb` |
| PHP | `src/Foo/Bar.php` | `tests/Foo/BarTest.php` |
| Dart | `lib/foo/bar.dart` | `test/foo/bar_test.dart` |
| Elixir | `lib/foo/bar.ex` | `test/foo/bar_test.exs` |
| Scala | `src/main/scala/pkg/Foo.scala` | `src/test/scala/pkg/FooSpec.scala` |

**Strategy selection order:** explore cache -> graph -> directory heuristic. The implementer uses the first strategy that produces results. If all strategies return empty, the inner loop skips test execution for that task (the full test suite at Self-Review Before Completion will catch any issues).

**Affected test cap:** Maximum 20 test files per inner loop invocation. If more are detected, run only the 20 most directly related (by import distance). This prevents the inner loop from becoming a full test suite run.

### Interaction with Convergence Engine Counters

The inner loop operates WITHIN the implementer's context, completely independent of the convergence engine's counters:

| Counter | Scope | Inner Loop Impact |
|---|---|---|
| `verify_fix_count` | Phase A (build/lint) at Stage 5 | NOT incremented by inner loop. The inner loop's lint fixes are invisible to the convergence engine. |
| `test_cycles` | Phase 1B (test gate) at Stage 5 | NOT incremented by inner loop. The inner loop's test fixes are pre-VERIFY corrections. |
| `quality_cycles` | Phase 2 (review) at Stage 6 | NOT incremented by inner loop. Inner loop does not run reviews. |
| `phase_iterations` | Convergence phase | NOT incremented by inner loop. |
| `total_iterations` | Convergence lifecycle | NOT incremented by inner loop. |
| `total_retries` | Global retry budget | NOT incremented by inner loop. |
| **`implementer_fix_cycles`** (NEW) | Per-task inner loop | NEW counter, tracked separately in `state.json.implementer_fix_cycles`. Does NOT feed into `total_retries`. |

**Rationale:** The inner loop catches "easy" issues (syntax, lint, obvious test breaks) that the implementer can fix in-context without orchestrator involvement. These fixes should not consume the global retry budget because they are the implementer doing its job well, not the pipeline retrying a failed stage.

**What the convergence engine sees:** When the implementer returns, the code has already passed the inner loop's lint and affected test checks. The VERIFY stage then runs the FULL test suite. If the full suite passes (which is more likely because the inner loop caught per-module breaks), the convergence engine transitions directly to Phase 2 (perfection). If it fails, the convergence engine handles it normally -- but with fewer iterations because the obvious breaks were already fixed.

**Expected convergence improvement:** Inner loop validation should reduce the average number of correctness-phase iterations from 2.5 to 1.5 (based on the 30-40% of Stage 5 failures being "obvious" breaks).

### Changes to fg-300-implementer.md

The following sections of `agents/fg-300-implementer.md` require modification:

**Section 2 (Input) — add new input fields:**

```markdown
8. **PREEMPT checklist** -- proactive checks from previous pipeline runs to apply before each step
9. **`max_fix_loops`** -- maximum fix attempts before reporting failure (from config)
10. **`inner_loop` config** -- inner loop settings (NEW):
    - `enabled` (boolean): whether to run inner loop validation after each TDD cycle
    - `max_fix_cycles` (integer): max fix attempts within the inner loop per task
    - `run_lint` (boolean): whether to run lint on changed files
    - `run_tests` (boolean): whether to run affected tests
```

**Section 5 (TDD Loop) — add section 5.4.1 after existing 5.4 (Refactor):**

```markdown
### 5.4.1 Inner Loop Validation (after REFACTOR, before next task)

After the REFACTOR step passes and the self-review checkpoint is complete, run
the inner loop validation. This catches lint violations and broken affected tests
before moving to the next task, preventing issues that would otherwise require
a full Stage 5 round-trip.

**When to run:** After completing a RED-GREEN-REFACTOR cycle for a task. NOT after
every individual edit (that would be too expensive). NOT for tasks without tests
(domain models, migrations — section 5.7 exemptions).

**Step 1: Quick Lint**
1. Identify changed files from this task (files created + files modified)
2. Run `{commands.lint} {changed_files}` (file-scoped lint, not full codebase)
   - If the project's lint command doesn't support file arguments, skip to Step 2
3. If lint errors found:
   a. Fix the errors (same approach as section 5.6 Handle Failures)
   b. Re-run lint on changed files
   c. Track fix attempts against `implementer_fix_cycles` budget
   d. If budget exhausted: log remaining lint errors in stage notes, proceed

**Step 2: Affected Tests**
1. Detect affected tests using explore cache, graph, or directory heuristic
   (see Affected Test Detection Algorithm in the spec)
2. Run affected tests via `{commands.test_single} {test_files}`
   - Cap at 20 test files per invocation
3. If tests fail:
   a. Analyze failure (same approach as section 5.6)
   b. Fix the failing code (NOT the test — same rules as section 2.1)
   c. Re-run affected tests
   d. Track fix attempts against remaining `implementer_fix_cycles` budget
   e. If budget exhausted: log remaining test failures in stage notes, proceed

**Budget:** Inner loop fix cycles are tracked separately as `implementer_fix_cycles`.
They do NOT count against `max_fix_loops` (the per-step fix budget) or any
convergence engine counter. Default: 3 per task. Configurable via
`implementer.inner_loop.max_fix_cycles`.

**Output:** Log inner loop results in stage notes:
```
INNER_LOOP: task=CreateUserUseCase fix_cycles=1/3 lint=PASS tests=PASS
INNER_LOOP: task=UserController fix_cycles=2/3 lint=PASS tests=PASS (1 fixed)
INNER_LOOP: task=UserRepository fix_cycles=0/3 lint=PASS tests=SKIP (no affected tests found)
```
```

**Section 13 (Fix Loop) — add clarification:**

```markdown
### Inner Loop vs Fix Loop

The inner loop (section 5.4.1) and the fix loop (this section) serve different purposes:

| Aspect | Inner Loop (5.4.1) | Fix Loop (13) |
|---|---|---|
| When | After each TDD cycle, before next task | When a step fails during implementation |
| What | Lint + affected tests | Build + test for the specific step |
| Budget | `implementer_fix_cycles` (default 3/task) | `max_fix_loops` (default 3/step) |
| Scope | Changed files + dependents | The specific failing step |
| Counter | `state.json.implementer_fix_cycles` | `state.json.verify_fix_count` |

Both budgets are independent. A task could use 2 inner loop fix cycles (catching
lint issues) and still have its full `max_fix_loops` budget for step-level failures.
```

**Section 15 (Output Format) — add inner loop summary:**

```markdown
### Inner Loop Summary
- Total inner loop fix cycles: [N] across [M] tasks
- Tasks with inner loop fixes: [list]
- Remaining inner loop issues: [list or "none"]
```

### Configuration Schema

In `forge-config.md` (new section):

```yaml
# Inner Loop Validation (v2.0+)
implementer:
  inner_loop:
    enabled: true           # Enable/disable inner loop validation. Default: true.
    max_fix_cycles: 3       # Max fix attempts per task within the inner loop. Default: 3. Range: 1-5.
    run_lint: true          # Run lint on changed files after each TDD cycle. Default: true.
    run_tests: true         # Run affected tests after each TDD cycle. Default: true.
    affected_test_cap: 20   # Max test files to run per inner loop invocation. Default: 20. Range: 5-50.
    affected_test_strategy: auto  # Test detection: auto (explore cache -> graph -> directory), explore, graph, directory. Default: auto.
```

**PREFLIGHT validation constraints:**

| Parameter | Range | Default | Rationale |
|---|---|---|---|
| `implementer.inner_loop.enabled` | boolean | `true` | Opt-out for projects where inner loop adds overhead |
| `implementer.inner_loop.max_fix_cycles` | 1-5 | 3 | Below 1 means no fixing; above 5 is too expensive for an inner loop |
| `implementer.inner_loop.run_lint` | boolean | `true` | Disable if lint is slow or unreliable |
| `implementer.inner_loop.run_tests` | boolean | `true` | Disable if test detection is unreliable |
| `implementer.inner_loop.affected_test_cap` | 5-50 | 20 | Below 5 misses too many; above 50 becomes a full suite run |
| `implementer.inner_loop.affected_test_strategy` | `auto`, `explore`, `graph`, `directory` | `auto` | Force a specific strategy if auto-detection picks poorly |

### State Schema Changes

New fields in `state.json`:

```json
{
  "implementer_fix_cycles": 0,
  "inner_loop": {
    "total_fix_cycles": 0,
    "tasks_with_fixes": 0,
    "tasks_total": 0,
    "lint_fixes": 0,
    "test_fixes": 0,
    "remaining_issues": []
  }
}
```

| Field | Type | Description |
|---|---|---|
| `implementer_fix_cycles` | integer | Total inner loop fix cycles across all tasks in this run |
| `inner_loop.total_fix_cycles` | integer | Same as above (explicit in inner_loop object for clarity) |
| `inner_loop.tasks_with_fixes` | integer | Number of tasks that required inner loop fixes |
| `inner_loop.tasks_total` | integer | Total tasks processed through the inner loop |
| `inner_loop.lint_fixes` | integer | Fix cycles spent on lint issues |
| `inner_loop.test_fixes` | integer | Fix cycles spent on test failures |
| `inner_loop.remaining_issues` | array | Issues that exhausted the inner loop budget (passed to VERIFY) |

### Integration Points

| File | Change |
|---|---|
| `agents/fg-300-implementer.md` | Add section 5.4.1 (Inner Loop Validation). Update section 2 (Input) with inner_loop config. Update section 13 (Fix Loop) with clarification. Update section 15 (Output Format) with inner loop summary. |
| `agents/fg-100-orchestrator.md` | Pass `inner_loop` config to implementer dispatch. Read `inner_loop` results from implementer output. Log inner loop metrics in stage notes. |
| `shared/state-schema.md` | Add `implementer_fix_cycles` and `inner_loop` object to state.json schema. |
| `shared/state-schema.json` | Add JSON schema definitions for new fields. |
| `shared/convergence-engine.md` | Add note clarifying that `implementer_fix_cycles` is NOT part of the convergence counter system. Add reference to inner loop reducing correctness-phase iterations. |
| `modules/frameworks/*/forge-config-template.md` | Add `implementer:` section with inner_loop defaults. |
| `shared/scoring.md` | No changes. Inner loop findings are NOT scored (they are internal to the implementer). |
| `CLAUDE.md` | Update implementer description to mention inner loop. Update iteration counter table. |
| `agents/fg-700-retrospective.md` | Add analysis of inner loop effectiveness: ratio of issues caught by inner loop vs VERIFY. Suggest `max_fix_cycles` adjustments. |
| `agents/fg-500-test-gate.md` | No changes. VERIFY still runs full suite. The inner loop reduces failures VERIFY encounters, but VERIFY's behavior is unchanged. |
| `shared/stage-contract.md` | Note that IMPLEMENT now includes internal validation (inner loop) but the contract with VERIFY is unchanged. |

### Data Flow

**Step-by-step for a typical task:**

1. Orchestrator dispatches `fg-300-implementer` with task spec + inner_loop config
2. Implementer starts TDD cycle for Task 1:
   - RED: writes failing test for `CreateUserUseCase`
   - GREEN: implements `CreateUserUseCase`, test passes
   - REFACTOR: extracts helper method, test still passes
   - Self-review checkpoint: "clean"
3. **Inner Loop starts for Task 1:**
   - Step 1 (Lint): Runs `./gradlew ktlintCheck --files src/main/kotlin/com/example/CreateUserUseCase.kt`
     - Result: 1 lint error (unused import)
     - Fix: Remove unused import (fix_cycles: 1)
     - Re-lint: PASS
   - Step 2 (Affected Tests): Detects `CreateUserUseCaseTest.kt` (from explore cache) + `UserControllerTest.kt` (depends on CreateUserUseCase)
     - Runs: `./gradlew test --tests "com.example.CreateUserUseCaseTest" --tests "com.example.UserControllerTest"`
     - Result: PASS (both test files pass)
   - Log: `INNER_LOOP: task=CreateUserUseCase fix_cycles=1/3 lint=PASS tests=PASS`
4. Implementer proceeds to Task 2...
5. After all tasks, runs Self-Review Before Completion (full test suite + full lint)
6. Returns Implementation Summary with Inner Loop Summary

**Step-by-step for an inner loop failure that exhausts budget:**

1. Implementer completes TDD cycle for Task 3 (UserController)
2. Inner Loop starts:
   - Step 1 (Lint): PASS
   - Step 2 (Affected Tests): Detects `UserControllerTest.kt` + `UserIntegrationTest.kt`
     - Run 1: `UserIntegrationTest.testCreateUser` FAILS (missing database migration)
     - Fix attempt 1: Adds migration file (fix_cycles: 1)
     - Run 2: Same test FAILS (migration syntax error)
     - Fix attempt 2: Fixes migration syntax (fix_cycles: 2)
     - Run 3: Same test FAILS (foreign key constraint)
     - Fix attempt 3: Fixes foreign key (fix_cycles: 3)
     - Budget exhausted (3/3)
   - Log: `INNER_LOOP: task=UserController fix_cycles=3/3 lint=PASS tests=FAIL (1 remaining: UserIntegrationTest.testCreateUser)`
3. Implementer proceeds to Task 4 (inner loop budget resets for next task)
4. Remaining failure is reported in Implementation Summary
5. VERIFY (Stage 5) catches the integration test failure and routes through the convergence engine's normal Phase 1 fix loop

### Error Handling

**Failure mode 1: Lint command does not support file arguments.**
- Detection: `commands.lint` execution with file arguments fails with "unrecognized argument" or similar
- Behavior: Skip lint step for this run. Log WARNING: `"INNER_LOOP: lint command does not support file arguments, skipping lint step"`
- Mitigation: VERIFY Stage 5 still runs full lint

**Failure mode 2: No affected tests found.**
- Detection: All three strategies return empty results
- Behavior: Skip test step. Log: `"INNER_LOOP: task={name} tests=SKIP (no affected tests found)"`
- Mitigation: Self-Review Before Completion runs full test suite. VERIFY catches any breaks.

**Failure mode 3: Affected test detection finds too many tests.**
- Detection: More than `affected_test_cap` (default 20) test files detected
- Behavior: Run only the top 20 by relevance (direct imports > same directory > transitive imports). Log WARNING: `"INNER_LOOP: {N} affected tests detected, capped at {affected_test_cap}"`

**Failure mode 4: Test execution hangs.**
- Detection: `commands.test_single` does not return within the step's time budget (5 minutes per fix attempt, inherited from section 5.6)
- Behavior: Kill the test process. Log: `"INNER_LOOP: test execution timed out"`. Skip remaining test fixes. Proceed to next task.

**Failure mode 5: Inner loop config not provided in dispatch.**
- Detection: `inner_loop` not present in dispatch prompt
- Behavior: Use defaults: `enabled: true`, `max_fix_cycles: 3`, `run_lint: true`, `run_tests: true`
- Rationale: The implementer should not fail because the orchestrator forgot to include config. Sensible defaults preserve backward compatibility.

**Failure mode 6: Explore cache / graph unavailable for test detection.**
- Detection: Strategy returns error or empty results
- Behavior: Fall through to next strategy (explore cache -> graph -> directory heuristic). If all fail, skip test step.

### Interaction with Full VERIFY Stage

| Aspect | Inner Loop | VERIFY (Stage 5) |
|---|---|---|
| Test scope | Changed files + dependents (max 20) | Full test suite |
| Lint scope | Changed files only | Full codebase |
| Mutation testing | No | Yes (if enabled) |
| Coverage analysis | No | Yes |
| Build verification | No (handled by L0/L1 hooks) | Yes (Phase A) |
| Counter impact | `implementer_fix_cycles` only | `verify_fix_count`, `test_cycles`, `total_iterations` |
| Score impact | None | Feeds into convergence engine |
| Agent dispatch | None (runs within fg-300) | fg-500 dispatches fg-505, fg-510 |

The inner loop is intentionally limited in scope. It is NOT a replacement for VERIFY. The full VERIFY stage provides:
- Cross-module test execution (the inner loop only runs per-task affected tests)
- Mutation testing (detects tests that pass but don't actually verify behavior)
- Coverage analysis (ensures sufficient branch coverage)
- Build verification (ensures the full project compiles, not just the changed files)

## Performance Characteristics

**Time impact per task:**

| Component | Expected Time | Notes |
|---|---|---|
| Lint (file-scoped) | 2-10s | Depends on linter; file-scoped is much faster than full codebase |
| Affected test detection | 0.1-2s | Explore cache lookup is instant; grep-based fallback takes 1-2s |
| Affected test execution | 5-30s | Depends on test count and complexity; capped at 20 files |
| Fix cycle (if needed) | 10-60s | Depends on issue complexity |
| **Total per task (no fixes)** | **7-42s** | Acceptable for the token savings |
| **Total per task (with 1 fix)** | **17-102s** | Still cheaper than a full Stage 5 round-trip |

**Token impact:**

| Scenario | Without Inner Loop | With Inner Loop | Savings |
|---|---|---|---|
| 5-task run, 0 Stage 5 failures | Same | +500 tokens (inner loop overhead) | -500 tokens (overhead cost) |
| 5-task run, 2 Stage 5 failures | +6,000-10,000 tokens (2 fix loops) | +1,000 tokens (inner loop caught both) | 5,000-9,000 tokens saved |
| 8-task run, 3 Stage 5 failures | +9,000-15,000 tokens (3 fix loops) | +1,500 tokens (inner loop caught 2, 1 goes to Stage 5) | 4,500-10,500 tokens saved |

**Net assessment:** Inner loop adds 500-1,500 tokens of overhead but saves 5,000-15,000 tokens by preventing Stage 5 fix loops. The breakeven point is approximately 1 prevented Stage 5 fix loop per 5 tasks — well within the observed 30-40% failure rate.

**Wall-clock time impact:** Inner loop adds 7-42s per task (no fixes) or 17-102s (with fixes). A Stage 5 round-trip takes 60-180s. Preventing one Stage 5 round-trip saves more time than the inner loop costs across all tasks.

## Testing Approach

### Structural Tests (`tests/structural/`)

1. **Config template:** All `forge-config-template.md` files include `implementer:` section with `inner_loop` defaults
2. **State schema:** `state-schema.md` and `state-schema.json` include `implementer_fix_cycles` and `inner_loop` fields
3. **Implementer agent:** `fg-300-implementer.md` contains section 5.4.1 (Inner Loop Validation)

### Unit Tests (`tests/unit/`)

1. **`inner-loop.bats`:**
   - Inner loop skipped when `enabled: false`
   - Lint step skipped when `run_lint: false`
   - Test step skipped when `run_tests: false`
   - Fix cycles capped at `max_fix_cycles`
   - Affected test cap enforced
   - Fix cycles counter incremented correctly
   - Inner loop does NOT increment convergence counters

2. **`affected-test-detection.bats`:**
   - Explore cache strategy finds correct test files
   - Directory heuristic finds mirror path tests (per language)
   - Grep-based fallback finds importing test files
   - Strategy auto-selection falls through correctly
   - Cap at `affected_test_cap` respects relevance ordering

### Scenario Tests (`tests/scenario/`)

1. **`inner-loop-integration.bats`:**
   - Full TDD cycle with inner loop catching a lint error
   - Full TDD cycle with inner loop catching a broken affected test
   - Inner loop budget exhausted, remaining failures reported
   - VERIFY still runs after inner loop and catches cross-module issues
   - Inner loop metrics appear in state.json and Implementation Summary

## Acceptance Criteria

1. After each TDD cycle (RED-GREEN-REFACTOR), the implementer runs lint on changed files and executes affected tests
2. Lint and test failures within the inner loop are fixed using `implementer_fix_cycles` budget (default 3 per task)
3. `implementer_fix_cycles` is tracked in `state.json` and does NOT increment convergence engine counters (`verify_fix_count`, `test_cycles`, `quality_cycles`, `total_iterations`, `total_retries`)
4. The inner loop can be disabled per-project via `implementer.inner_loop.enabled: false`
5. The full VERIFY stage (Stage 5) still runs after implementation completes, with unchanged behavior
6. Affected test detection uses explore cache, graph, or directory heuristic (in that priority order)
7. Affected tests are capped at `affected_test_cap` (default 20) per inner loop invocation
8. Inner loop results are logged in stage notes and included in the Implementation Summary
9. The Self-Review Before Completion checklist (existing section 5.4 of fg-300) still runs the full test suite and full lint as the final gate
10. `./tests/validate-plugin.sh` passes with new configuration and state schema fields

## Migration Path

**From v1.20.1 to v2.0:**

1. **Zero breaking changes.** The inner loop is additive. If `inner_loop.enabled: false`, the implementer behaves exactly as v1.20.1.

2. **Default behavior change:** The implementer now runs lint and affected tests after each TDD cycle by default. This adds 7-42s per task but reduces Stage 5 fix loops. Projects that do not want this can set `inner_loop.enabled: false`.

3. **State schema extension:** `implementer_fix_cycles` and `inner_loop` added to `state.json`. Old state files without these fields are handled gracefully (default to 0/empty).

4. **Config template extension:** `implementer:` section added to `forge-config-template.md`. Existing projects without this section use plugin defaults.

5. **Implementer agent update:** Section 5.4.1 added. Existing behavior (sections 5.2-5.6) is unchanged. The inner loop is an additional step between REFACTOR (5.4) and the next task.

6. **Orchestrator dispatch update:** Orchestrator passes `inner_loop` config to implementer. If the config is missing from the dispatch (older orchestrator version), the implementer uses defaults.

## Dependencies

**This feature depends on:**
- `commands.lint` in project config (for lint step; gracefully skipped if absent)
- `commands.test_single` in project config (for test step; already required by fg-300)
- `.forge/explore-cache.json` (for affected test detection; gracefully falls back to directory heuristic)
- F02 (Linter-Gated Editing): L0 syntax validation runs before edits reach the inner loop, reducing the number of syntax-related inner loop failures. F04 does not hard-depend on F02 but benefits from it.

**Other features that depend on this:**
- None directly. The inner loop is self-contained within the implementer.

**Other features that benefit from this (no hard dependency):**
- F03 (Model Routing): Inner loop reduces Stage 5 round-trips, which are expensive when premium-tier agents are involved. Combined with model routing, the savings compound.
- Convergence engine: Fewer correctness-phase iterations means faster convergence to the perfection phase.
