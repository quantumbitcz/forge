---
name: pitest
categories: [mutation-tester]
languages: [java, kotlin]
exclusive_group: jvm-mutation
recommendation_score: 90
detection_files: [build.gradle.kts, build.gradle, pom.xml]
---

# pitest

## Overview

PIT (PiTest) is the de facto mutation testing tool for JVM languages. It injects faults (mutants) into bytecode and verifies that existing tests detect them — a mutation test suite that kills <60% of mutants indicates tests that assert the wrong things or missing assertions entirely. PiTest integrates with Gradle via `info.solidsoft.pitest` and Maven via `pitest-maven`. Kotlin projects require the `pitest-kotlin` plugin bridge. Reports are generated in HTML and XML; XML is consumed by CI dashboards. Incremental analysis (history files) drastically reduces re-run times in CI by skipping unmodified classes.

## Architecture Patterns

### Installation & Setup

**Gradle (Kotlin DSL):**
```kotlin
// build.gradle.kts
plugins {
    id("info.solidsoft.pitest") version "1.15.0"
}

dependencies {
    // Kotlin support — required for Kotlin projects
    testImplementation("org.pitest:pitest-kotlin:1.2.0")
}

pitest {
    pitestVersion = "1.16.1"
    junit5PluginVersion = "1.2.1"          // for JUnit 5 test discovery
    targetClasses = setOf("com.example.domain.*", "com.example.service.*")
    targetTests = setOf("com.example.*Test", "com.example.*Spec")
    mutators = setOf("CONDITIONALS_BOUNDARY", "NEGATE_CONDITIONALS", "MATH", "RETURN_VALS", "VOID_METHOD_CALLS")
    mutationThreshold = 60                 // fail build below 60% mutation score
    coverageThreshold = 80
    outputFormats = setOf("HTML", "XML")
    threads = 4
    timeoutConstant = 5000L                // ms added to baseline per-test timeout
    excludedClasses = setOf(
        "*.generated.*",
        "*.config.*",
        "*.Application",
        "*Dto",
        "*Mapper"
    )
    historyInputLocation = file("build/pitest/history.bin")
    historyOutputLocation = file("build/pitest/history.bin")
    withHistory = true                     // incremental analysis
}
```

**Maven:**
```xml
<!-- pom.xml -->
<plugin>
  <groupId>org.pitest</groupId>
  <artifactId>pitest-maven</artifactId>
  <version>1.16.1</version>
  <dependencies>
    <dependency>
      <groupId>org.pitest</groupId>
      <artifactId>pitest-junit5-plugin</artifactId>
      <version>1.2.1</version>
    </dependency>
  </dependencies>
  <configuration>
    <targetClasses>
      <param>com.example.domain.*</param>
      <param>com.example.service.*</param>
    </targetClasses>
    <targetTests>
      <param>com.example.*Test</param>
    </targetTests>
    <mutators>
      <mutator>CONDITIONALS_BOUNDARY</mutator>
      <mutator>NEGATE_CONDITIONALS</mutator>
      <mutator>MATH</mutator>
      <mutator>RETURN_VALS</mutator>
    </mutators>
    <mutationThreshold>60</mutationThreshold>
    <outputFormats>
      <param>HTML</param>
      <param>XML</param>
    </outputFormats>
    <historyInputFile>${project.build.directory}/pitest/history.bin</historyInputFile>
    <historyOutputFile>${project.build.directory}/pitest/history.bin</historyOutputFile>
    <withHistory>true</withHistory>
    <excludedClasses>
      <param>*.generated.*</param>
      <param>*Dto</param>
      <param>*Mapper</param>
    </excludedClasses>
  </configuration>
  <executions>
    <execution>
      <id>pitest</id>
      <phase>verify</phase>
      <goals><goal>mutationCoverage</goal></goals>
    </execution>
  </executions>
</plugin>
```

### Rule Categories

| Mutator | What it changes | What tests must assert |
|---|---|---|
| `CONDITIONALS_BOUNDARY` | `<` → `<=`, `>` → `>=` | Off-by-one boundary conditions |
| `NEGATE_CONDITIONALS` | `==` → `!=`, `>` → `<=` | Negated branching logic |
| `MATH` | `+` → `-`, `*` → `/`, `%` → `*` | Arithmetic correctness |
| `RETURN_VALS` | Returns 0/null/false/empty instead of computed value | Return value assertions |
| `VOID_METHOD_CALLS` | Removes void method calls entirely | Side-effect verification |
| `EMPTY_RETURNS` | Returns empty collection/null | Null/empty return handling |
| `NULL_RETURNS` | Returns `null` for reference returns | Null-safety assertions |

### Configuration Patterns

**Scoped to domain layer only (avoid testing infrastructure):**
```kotlin
pitest {
    targetClasses = setOf(
        "com.example.domain.**",
        "com.example.application.**"
    )
    // Exclude Spring wiring, Flyway, generated code
    excludedClasses = setOf(
        "com.example.infrastructure.**",
        "*.config.**",
        "*.migration.**",
        "*Repository",          // Spring Data proxies
        "*.generated.**"
    )
}
```

**Stronger mutator set for critical business logic:**
```kotlin
mutators = setOf(
    "STRONGER",         // preset: includes all default + REMOVE_CONDITIONALS, INVERT_NEGS
    "CONSTRUCTOR_CALLS",
    "INLINE_CONSTS"
)
```

### CI Integration

```yaml
# .github/workflows/mutation.yml
- name: Restore PIT history
  uses: actions/cache@v4
  with:
    path: build/pitest/history.bin
    key: pitest-history-${{ github.ref }}-${{ github.sha }}
    restore-keys: |
      pitest-history-${{ github.ref }}-
      pitest-history-

- name: Run mutation tests
  run: ./gradlew pitest

- name: Upload PIT HTML report
  if: always()
  uses: actions/upload-artifact@v4
  with:
    name: pitest-report
    path: build/reports/pitest/

- name: Save PIT history
  if: always()
  uses: actions/cache/save@v4
  with:
    path: build/pitest/history.bin
    key: pitest-history-${{ github.ref }}-${{ github.sha }}
```

## Performance

- PIT re-compiles and re-runs tests for every mutant — expect 5-20× longer than a normal test run without history.
- Enable `withHistory = true` and cache `history.bin` in CI — unchanged classes are skipped on subsequent runs, reducing re-run time by 60-90% on incremental changes.
- Use `threads = N` (set to CPU count) for parallel mutant evaluation; PIT is embarrassingly parallel within a test suite.
- Scope `targetClasses` tightly to business logic — testing infrastructure (repositories, config, serialization) generates mutants with low kill value.
- Exclude slow integration tests from the `targetTests` glob — PIT runs each mutant against the full matched test suite; integration tests multiply runtime dramatically.
- Prefer `STRONGER` preset on CI nightly runs; use default mutators on PR checks for speed.

## Security

- PIT generates modified bytecode in a sandboxed subprocess — it does not write mutated classes back to your build output.
- HTML reports contain class names, line numbers, and surviving mutant code snippets — treat as internal development artifacts, not for public exposure.
- Do not run PIT against test suites that connect to production databases or external services — mutants trigger all matched tests, including ones with side effects.

## Testing

```bash
# Gradle: run mutation tests (generates report in build/reports/pitest/)
./gradlew pitest

# Maven: mutation coverage during verify phase
mvn pitest:mutationCoverage

# View HTML report locally
open build/reports/pitest/index.html

# Run only for changed modules in multi-module Gradle build
./gradlew :domain:pitest :service:pitest

# Check mutation score from XML report
grep -E 'mutation_coverage|mutations detected' build/reports/pitest/mutations.xml | head -5
```

## Dos

- Set `mutationThreshold` to at least 60 and wire PIT into the `verify` lifecycle — a threshold that never fails gives false confidence.
- Cache `history.bin` in CI keyed by branch and SHA — incremental analysis is the single biggest PIT performance win.
- Scope `targetClasses` to domain and application layers only — infrastructure code (Spring config, Flyway, Hibernate entities) produces noisy, low-value mutants.
- Use `pitest-kotlin` plugin for Kotlin projects — without it, Kotlin-generated bytecode (data class `copy`, `equals`, `hashCode`) inflates mutant counts with untestable generated code.
- Add `NULL_RETURNS` and `EMPTY_RETURNS` to the mutator set — they catch missing null/empty guards that `RETURN_VALS` alone misses.
- Review surviving mutants as a prioritized backlog: surviving `NEGATE_CONDITIONALS` mutants are the highest-risk gaps (missing negative-path tests).

## Don'ts

- Don't run PIT on every commit for large codebases without history caching — the 10-20× slowdown makes it impractical without incremental mode.
- Don't set `mutationThreshold` to 80+ on a project that has never used mutation testing — start at 60 and raise incrementally as gaps are closed.
- Don't include generated code (Lombok, MapStruct, Protobuf, QueryDSL) in `targetClasses` — generated methods produce unkillable mutants that drag down the score artificially.
- Don't ignore surviving `CONDITIONALS_BOUNDARY` mutants in numeric validation logic — they indicate off-by-one bugs that pass line coverage checks but fail at boundary values.
- Don't conflate mutation score with code correctness — a 80% kill rate means 20% of injected faults go undetected, not that 80% of code is correct.
