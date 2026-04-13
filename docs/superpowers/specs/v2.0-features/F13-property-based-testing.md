# F13: Agentic Property-Based Test Generation

## Status
DRAFT — 2026-04-13

## Problem Statement

Research from October 2025 demonstrates that LLM agents can generate property-based tests that find real bugs in production libraries, achieving a 56% validity rate on generated properties. Property-based testing (PBT) discovers edge cases that example-based tests miss — off-by-one errors, overflow conditions, invariant violations, and symmetry breaks that manual test writers rarely cover.

Forge's current test quality system consists of `fg-500-test-gate` (run tests, check coverage) and `fg-510-mutation-analyzer` (generate mutants, verify tests catch them). Mutation testing answers "do your tests catch intentional breakage?" but PBT answers "does your code satisfy its mathematical properties?" — a complementary and deeper form of verification.

**Gap:** No mechanism to automatically infer function properties (invariants, round-trips, idempotence, commutativity) and generate framework-appropriate property-based tests. Teams that want PBT must write properties manually, which requires specialized expertise.

**Competitive context:** No existing AI coding tool combines mutation testing with property-based test generation. This combination — mutation testing to find *test* gaps plus PBT to find *code* gaps — would be the most comprehensive automated test quality system available.

## Proposed Solution

Add an optional agent `fg-515-property-test-generator` dispatched by `fg-500-test-gate` after standard tests pass. The agent analyzes changed functions, infers testable properties, generates framework-appropriate PBT tests, runs them, and reports surviving failures as `TEST-PROPERTY-*` findings.

## Detailed Design

### Architecture

```
fg-500-test-gate
     |
     +-- Step 1: Run test suite (existing)
     +-- Step 2: Dispatch fg-510-mutation-analyzer (existing, if enabled)
     +-- Step 3: Dispatch fg-515-property-test-generator (NEW, if enabled)
     |
     v
fg-515-property-test-generator
     |
     +-- Analyze changed functions
     +-- Infer properties per function
     +-- Select PBT framework for language
     +-- Generate property tests
     +-- Run property tests
     +-- Filter: passing properties = validation, failing = findings
     +-- Report TEST-PROPERTY-* findings
     |
     v
fg-500-test-gate (collects findings, synthesizes verdict)
```

**Dispatch order:** Mutation testing runs first (it is faster and lower-risk). Property test generation runs second. Both are optional and independent.

### Property Categories

| Category | Description | Applicability | Example |
|---|---|---|---|
| `invariant` | Condition that holds for all valid inputs | Any function with preconditions/postconditions | `sort(xs).length == xs.length` |
| `round_trip` | Encoding then decoding produces original input | Serialization, parsing, encryption, compression | `decode(encode(x)) == x` |
| `idempotence` | Applying function twice gives same result as once | Normalization, formatting, caching, state operations | `normalize(normalize(x)) == normalize(x)` |
| `metamorphic` | Known relationship between input changes and output changes | Numeric, search, sorting, filtering | `filter(xs, p).length <= xs.length` |
| `commutativity` | Order of operations does not affect result | Set operations, math, aggregation | `merge(a, b) == merge(b, a)` |
| `monotonicity` | Increasing input leads to non-decreasing output | Pricing, scoring, ranking | `score(x+1) >= score(x)` |

### PBT Framework Selection

| Forge Language | PBT Framework | Import/Dependency | Test Runner |
|---|---|---|---|
| python | Hypothesis | `hypothesis` (pip) | pytest |
| kotlin | jqwik | `net.jqwik:jqwik` (Gradle/Maven) | JUnit Platform |
| java | jqwik | `net.jqwik:jqwik` (Gradle/Maven) | JUnit Platform |
| typescript | fast-check | `fast-check` (npm) | vitest / jest |
| rust | proptest | `proptest` (Cargo) | `cargo test` |
| go | gopter | `github.com/leanovate/gopter` | `go test` |
| swift | SwiftCheck | `SwiftCheck` (SPM) | XCTest |
| scala | ScalaCheck | `org.scalacheck::scalacheck` (sbt) | ScalaTest |
| ruby | Rantly | `rantly` (gem) | RSpec |
| elixir | StreamData | `stream_data` (mix) | ExUnit |

Languages without established PBT frameworks (C, C++, C#, PHP, Dart) are excluded from property generation. The agent silently skips these.

### Schema / Data Model

**Property test output** (in stage notes):

```markdown
### Property Tests: {function_name}

| Property | Category | Status | Shrunk Counterexample |
|---|---|---|---|
| `sort preserves length` | invariant | PASS | — |
| `encode/decode round-trip` | round_trip | FAIL | `input="\x00\xff"` |

**Failing properties indicate real bugs or specification gaps.**
```

**Finding format:**

```
TEST-PROPERTY-INVARIANT: WARNING: src/Sorter.kt:42: Property "sort preserves length" failed — sort drops duplicates but should preserve them. Counterexample: [1, 1, 2]
TEST-PROPERTY-ROUNDTRIP: WARNING: src/Codec.kt:18: Round-trip property failed for encode/decode — null bytes corrupted. Counterexample: "\x00\xff"
TEST-PROPERTY-IDEMPOTENT: INFO: src/Normalizer.kt:30: Idempotence property failed — double normalization changes case. Counterexample: "McDonalds"
```

**State tracking** (new fields in `state.json.test_gate`):

```json
{
  "test_gate": {
    "property_tests": {
      "generated": 0,
      "passed": 0,
      "failed": 0,
      "skipped": 0,
      "frameworks_used": []
    }
  }
}
```

### Configuration

In `forge-config.md`:

```yaml
# Property-based test generation (v2.0+)
property_testing:
  enabled: false                        # Opt-in. Default: false.
  max_properties_per_function: 5        # Cap on properties per analyzed function. Default: 5. Range: 1-20.
  target_modules: []                    # Empty = all changed modules. Or explicit list: [src/core, src/domain]
  categories: [invariant, round_trip, idempotence, metamorphic, commutativity, monotonicity]  # Which categories to attempt.
  keep_passing_tests: false             # If true, commit passing property tests to the codebase. Default: false.
  timeout_per_property_ms: 10000        # Max time per property test run. Default: 10000. Range: 1000-60000.
  max_examples: 100                     # Number of random examples per property. Default: 100. Range: 10-10000.
```

**PREFLIGHT validation constraints:**

| Parameter | Range | Default | Rationale |
|---|---|---|---|
| `property_testing.enabled` | boolean | `false` | Opt-in; adds latency and may add dependency |
| `property_testing.max_properties_per_function` | 1-20 | 5 | Token budget control |
| `property_testing.timeout_per_property_ms` | 1000-60000 | 10000 | Property tests with generators can run long |
| `property_testing.max_examples` | 10-10000 | 100 | Balance between thoroughness and speed |
| `property_testing.keep_passing_tests` | boolean | `false` | Committing generated tests requires team buy-in |

### Data Flow

**Step-by-step:**

1. Test gate runs standard test suite (passes)
2. Test gate dispatches `fg-510-mutation-analyzer` (if enabled)
3. Test gate dispatches `fg-515-property-test-generator` with changed files list
4. Agent reads each changed function and its context (types, docs, callers)
5. For each function, agent infers applicable property categories:
   - Has encode/decode pair? -> `round_trip`
   - Has normalize/clean/format? -> `idempotence`
   - Has sort/filter/map? -> `invariant` + `metamorphic`
   - Has mathematical operations? -> `commutativity` + `monotonicity`
6. Agent generates PBT test code using the language-appropriate framework
7. Agent writes test files to `.forge/worktree/` (temporary, alongside source)
8. Agent runs property tests via the project's test runner
9. Passing properties: logged as validation (optionally kept if `keep_passing_tests`)
10. Failing properties: shrink counterexample, report as `TEST-PROPERTY-*` findings
11. Agent cleans up generated test files (unless `keep_passing_tests`)
12. Test gate collects property findings alongside mutation findings

**Integration with mutation testing:** When both are enabled, property tests also run against surviving mutants. A property that catches a mutant that example-based tests missed demonstrates high-value test coverage.

### Integration Points

| File | Change |
|---|---|
| `agents/fg-515-property-test-generator.md` | NEW — property-based test generation agent |
| `agents/fg-500-test-gate.md` | Add dispatch step for fg-515 after mutation analysis. Add property test findings to verdict synthesis. |
| `shared/checks/category-registry.json` | Add `TEST-PROPERTY-INVARIANT`, `TEST-PROPERTY-ROUNDTRIP`, `TEST-PROPERTY-IDEMPOTENT`, `TEST-PROPERTY-METAMORPHIC`, `TEST-PROPERTY-COMMUTATIVE`, `TEST-PROPERTY-MONOTONIC` |
| `shared/agent-registry.md` | Register `fg-515-property-test-generator` |
| `shared/state-schema.md` | Add `test_gate.property_tests` schema |
| `modules/frameworks/*/forge-config-template.md` | Add `property_testing:` section |
| `shared/learnings/` | Property test effectiveness data per module |
| `CLAUDE.md` | Update test framework count, agent count |

### Error Handling

**Failure mode 1: PBT framework not installed.**
- Detection: Dependency check runs BEFORE any code generation (e.g., `pip show hypothesis`, check `package.json` for `fast-check`, check `build.gradle` for `jqwik`). This check happens in the agent's first step, not after generating test files.
- Behavior: Agent logs INFO finding: "Property testing skipped: {framework} not available for {language}". Skip property generation for that language entirely — no test files are written.
- Impact: Zero disruption. Agent exits cleanly with no findings. No risk of writing imports for unavailable frameworks.

**Failure mode 2: Generated property test has syntax error.**
- Detection: Test runner fails to compile/load the generated test
- Behavior: Agent discards the test, logs internally, moves to next property. Does not report as a finding (this is a generator quality issue, not a codebase issue).
- Mitigation: Agent validates generated code against L0 syntax check (if available) before running.

**Failure mode 3: Property test hangs (infinite generator).**
- Detection: `timeout_per_property_ms` exceeded
- Behavior: Kill test process, report `TEST-PROPERTY-TIMEOUT` (INFO). Move to next property.

**Failure mode 4: All properties pass (no findings).**
- This is a success case. Agent reports summary in stage notes. No findings emitted. The generated tests can optionally be kept as regression tests.

**Failure mode 5: Too many failures indicate flawed property inference.**
- Detection: >80% of generated properties fail
- Behavior: Agent halts early, reports `TEST-PROPERTY-GENERATION-QUALITY` (INFO): "High failure rate suggests property inference quality issues for this codebase. Consider reviewing generated properties."

## Performance Characteristics

**Time budget per function:**

| Step | Duration | Notes |
|---|---|---|
| Analyze function + infer properties | 500-2,000 tokens | LLM inference |
| Generate test code | 300-1,000 tokens | Per property |
| Run property tests (100 examples) | 1-10s | Depends on function complexity |
| Shrink counterexample (on failure) | 1-5s | Framework-native shrinking |
| **Total per function (5 properties)** | **5-50s** | Dominated by test execution |

**Total overhead for a typical run (3 changed functions, 5 properties each):**
- 15-150s of test execution time
- 4,000-15,000 tokens for analysis + generation
- Runs in parallel with or after mutation testing

**Net value:** A single property-discovered bug in production code justifies hundreds of runs of property generation. The 56% validity rate from research suggests roughly 3 out of 5 generated properties will be meaningful.

## Testing Approach

### Structural Tests (`tests/structural/`)

1. **Agent registration:** `fg-515-property-test-generator.md` exists in `agents/`, name matches filename
2. **Category registration:** All `TEST-PROPERTY-*` codes exist in `category-registry.json`
3. **Config template:** All `forge-config-template.md` files include `property_testing:` section
4. **Agent frontmatter:** Tools list, UI tier, description present and valid

### Unit Tests (`tests/unit/`)

1. **`property-test-generation.bats`:**
   - Framework selection: Python -> Hypothesis, Kotlin -> jqwik, TypeScript -> fast-check
   - Category inference: encode/decode pair -> round_trip, sort function -> invariant
   - Config disabled: `property_testing.enabled: false` skips dispatch entirely
   - Language exclusion: C, C++, C#, PHP, Dart -> skip (no PBT framework)
   - `max_properties_per_function` respected
   - Timeout handling: long-running property killed after `timeout_per_property_ms`

### Scenario Tests (`tests/scenario/`)

1. **`property-testing-pipeline.bats`:**
   - Full pipeline with property testing enabled produces `TEST-PROPERTY-*` findings
   - Property tests run in worktree (not user's tree)
   - Generated test files cleaned up after run (unless `keep_passing_tests`)

## Acceptance Criteria

1. `fg-515-property-test-generator` is dispatched by test gate when `property_testing.enabled: true`
2. Agent correctly selects PBT framework per language (10 supported languages)
3. Agent infers at least one property category for functions with clear patterns (sort, encode/decode, normalize)
4. Failing properties produce `TEST-PROPERTY-*` findings with shrunk counterexamples
5. Passing properties are logged but do not produce findings
6. Property tests execute in the worktree, not the user's working tree
7. Generated test files are cleaned up unless `keep_passing_tests: true`
8. Per-property timeout is enforced (`timeout_per_property_ms`)
9. Missing PBT framework causes graceful skip, not pipeline failure
10. Unsupported languages are silently skipped
11. Property test results tracked in `state.json.test_gate.property_tests`

## Migration Path

**From v1.20.1 to v2.0:**

1. **Zero breaking changes.** Feature is opt-in (`enabled: false` default).
2. **New agent:** `fg-515-property-test-generator.md` added to `agents/`. Does not affect existing agent dispatch unless enabled.
3. **Test gate update:** New dispatch step added after mutation analysis. When disabled, the step is skipped entirely (no token cost).
4. **Dependencies:** PBT frameworks are project dependencies, not plugin dependencies. If a project does not have Hypothesis/jqwik/fast-check installed, the agent skips gracefully.
5. **Category registry:** Six new finding codes added. Existing scoring formula unchanged.
6. **Agent registry:** One new agent registered. Agent count goes from 40 to 41.

## Dependencies

**This feature depends on:**
- `fg-500-test-gate` dispatch mechanism (already supports sub-agent dispatch for fg-510)
- Worktree for test file generation (already created at PREFLIGHT)
- Language detection from project config (already available in `state.json`)

**Other features that benefit from this:**
- F12 (Spec Inference): Inferred specifications suggest properties to test
- Mutation testing (existing fg-510): Property tests can run against surviving mutants for combined analysis
- Retrospective learning: Property discovery patterns feed into per-module learnings
