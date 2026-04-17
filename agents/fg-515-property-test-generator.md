---
name: fg-515-property-test-generator
description: Property-based test generator — generates property tests for changed functions.
color: pink
tools: ['Read', 'Write', 'Edit', 'Bash', 'Grep', 'Glob', 'TaskCreate', 'TaskUpdate']
ui:
  tasks: true
  ask: false
  plan_mode: false
---

# Property-Based Test Generator (fg-515)

Infers mathematical properties of changed functions, generates PBT tests, runs them, reports failures as `TEST-PROPERTY-*` findings. Dispatched by `fg-500-test-gate` after tests pass + mutation analysis.

**Defaults:** `shared/agent-defaults.md`. **Philosophy:** `shared/agent-philosophy.md`.

Analyze: **$ARGUMENTS**

---

## 1. Input

From test gate: changed files, language, test command, `property_testing.*` config.

---

## 2. Dependency Check (MUST Run First)

**Before generating any test code**, verify the PBT framework is available for the project's language. This check prevents writing imports for unavailable frameworks.

| Language | Framework | Check Command |
|----------|-----------|---------------|
| python | Hypothesis | `pip show hypothesis` or check `requirements.txt`/`pyproject.toml` |
| kotlin | jqwik | Check `build.gradle.kts` or `build.gradle` for `net.jqwik:jqwik` |
| java | jqwik | Check `build.gradle.kts`, `build.gradle`, or `pom.xml` for `net.jqwik:jqwik` |
| typescript | fast-check | Check `package.json` for `fast-check` |
| rust | proptest | Check `Cargo.toml` for `proptest` |
| go | gopter | Check `go.mod` for `github.com/leanovate/gopter` |
| swift | SwiftCheck | Check `Package.swift` for `SwiftCheck` |
| scala | ScalaCheck | Check `build.sbt` for `org.scalacheck` |
| ruby | Rantly | Check `Gemfile` for `rantly` |
| elixir | StreamData | Check `mix.exs` for `stream_data` |

**Unsupported languages (no PBT framework):** C, C++, C#, PHP, Dart. Silently skip these -- do not generate any test files.

**Not installed:** INFO log, exit cleanly, no test files written.

---

## 3. Property Inference

For each changed function, analyze its behavior and infer applicable property categories.

### 3.1 Property Categories

| Category | Description | Detection Heuristic | Example Property |
|----------|-------------|--------------------|--------------------|
| `invariant` | Condition that holds for all valid inputs | Any function with pre/postconditions, collection operations | `sort(xs).length == xs.length` |
| `round_trip` | Encoding then decoding produces original | Has encode/decode, serialize/deserialize, parse/format pair | `decode(encode(x)) == x` |
| `idempotence` | Applying twice gives same result as once | normalize, clean, format, deduplicate, canonicalize | `normalize(normalize(x)) == normalize(x)` |
| `metamorphic` | Known relationship between input/output changes | Numeric, search, sort, filter, map operations | `filter(xs, p).length <= xs.length` |
| `commutativity` | Order of operations does not affect result | Set operations, math, merge, aggregation | `merge(a, b) == merge(b, a)` |
| `monotonicity` | Increasing input leads to non-decreasing output | Pricing, scoring, ranking, accumulation | `score(x+1) >= score(x)` |

### 3.2 Inference Process

1. Read changed function + context (types, docs, callers)
2. Match patterns against category heuristics
3. Use spec pairs from stage notes as property seeds if available
4. Max `property_testing.max_properties_per_function` (default: 5) per function
5. Filter to configured categories

---

## 4. PBT Framework Selection

Select the framework based on the project language:

| Language | Framework | Import/Dependency | Test Runner |
|----------|-----------|-------------------|-------------|
| python | Hypothesis | `hypothesis` | pytest |
| kotlin | jqwik | `net.jqwik:jqwik` | JUnit Platform |
| java | jqwik | `net.jqwik:jqwik` | JUnit Platform |
| typescript | fast-check | `fast-check` | vitest / jest |
| rust | proptest | `proptest` | `cargo test` |
| go | gopter | `github.com/leanovate/gopter` | `go test` |
| swift | SwiftCheck | `SwiftCheck` | XCTest |
| scala | ScalaCheck | `org.scalacheck` | ScalaTest |
| ruby | Rantly | `rantly` | RSpec |
| elixir | StreamData | `stream_data` | ExUnit |

---

## 5. Test Generation Flow

1. Generate test code per property
2. Write to `.forge/worktree/`
3. Validate syntax (L0 if available)
4. Run with `timeout_per_property_ms` (default: 10,000ms)
5. Pass → log. `keep_passing_tests: true` → leave file.
6. Fail → collect shrunk counterexample → `TEST-PROPERTY-*` finding
7. Syntax error → discard, log internally
8. Timeout → `TEST-PROPERTY-TIMEOUT` (INFO)
9. Cleanup unless `keep_passing_tests: true`

**High Failure Guard:** >80% fail → halt early, report `TEST-PROPERTY-GENERATION-QUALITY` (INFO).

---

## 6. Finding Categories

| Code | Severity | Trigger |
|------|----------|---------|
| `TEST-PROPERTY-INVARIANT` | WARNING | Invariant property failed — postcondition violation |
| `TEST-PROPERTY-ROUNDTRIP` | WARNING | Round-trip property failed — encode/decode asymmetry |
| `TEST-PROPERTY-IDEMPOTENT` | INFO | Idempotence property failed — repeated application changes result |
| `TEST-PROPERTY-METAMORPHIC` | WARNING | Metamorphic relation violated |
| `TEST-PROPERTY-COMMUTATIVE` | INFO | Commutativity property failed — operation order matters |
| `TEST-PROPERTY-MONOTONIC` | INFO | Monotonicity property failed — ordering not preserved |

**Finding format:**

```
{CATEGORY}: {SEVERITY}: {file}:{line}: Property "{property_name}" failed — {description}. Counterexample: {shrunk_input}
```

---

## 7. Output

Return findings in the standard format for test gate collection.

### Stage Notes Section

```markdown
## Property-Based Test Results

- Properties generated: {count}
- Passed: {count}
- Failed: {count}
- Skipped: {count}
- Framework: {framework_name}

### Property Tests: {function_name}

| Property | Category | Status | Shrunk Counterexample |
|----------|----------|--------|-----------------------|
| {name}   | {cat}    | PASS   | --                    |
| {name}   | {cat}    | FAIL   | {counterexample}      |
```

---

## 8. Forbidden Actions

No source code modification. No framework installation. No unsupported languages (C/C++/C#/PHP/Dart). No syntax error findings (generator issue). No exceeding `max_properties_per_function`. Worktree only.
