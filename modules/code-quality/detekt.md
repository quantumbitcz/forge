---
name: detekt
categories: [linter]
languages: [kotlin]
exclusive_group: kotlin-linter
recommendation_score: 90
detection_files: [detekt.yml, config/detekt.yml, .detekt.yml]
---

# detekt

## Overview

Static code analysis for Kotlin. Inspects for code smells, complexity violations, potential bugs, and style issues via configurable rule sets. Use detekt when you need deep Kotlin-aware static analysis with type resolution (e.g., coroutines misuse, sealed class exhaustiveness gaps) — it complements ktlint (formatting) rather than replacing it. Unlike SonarQube, detekt runs entirely offline and integrates natively into the Gradle task graph.

## Architecture Patterns

### Installation & Setup

Gradle plugin `io.gitlab.arturbosch.detekt` (current: 1.23.x). Add to `build.gradle.kts`:

```kotlin
plugins {
    id("io.gitlab.arturbosch.detekt") version "1.23.7"
}

detekt {
    config.setFrom(files("$rootDir/config/detekt.yml"))
    buildUponDefaultConfig = true
    allRules = false          // only enabled rules fire
    autoCorrect = false       // set true only in format tasks
    parallel = true
}

dependencies {
    detektPlugins("io.gitlab.arturbosch.detekt:detekt-formatting:1.23.7")
    // optional: detektPlugins("io.gitlab.arturbosch.detekt:detekt-rules-libraries:1.23.7")
}
```

For multi-module projects, configure in `build-logic/src/main/kotlin/kotlin-conventions.gradle.kts` to apply consistently. Use `detektMain` and `detektTest` tasks independently — test code often warrants relaxed complexity thresholds.

### Rule Categories

| Rule Set | What It Checks | Pipeline Severity |
|---|---|---|
| `complexity` | CyclomaticComplexity, LongMethod, LargeClass, TooManyFunctions | WARNING (>threshold) |
| `coroutines` | GlobalCoroutineUsage, RedundantSuspendModifier, SuspendFunWithFlowReturnType | CRITICAL |
| `empty-blocks` | EmptyFunctionBlock, EmptyIfBlock, EmptyCatchBlock | WARNING |
| `exceptions` | SwallowedException, TooGenericExceptionCaught, ThrowingExceptionsWithoutMessageOrCause | CRITICAL |
| `naming` | FunctionNaming, ClassNaming, VariableNaming, MatchingDeclarationName | WARNING |
| `performance` | SpreadOperator, ArrayPrimitive, ForEachOnRange | WARNING |
| `potential-bugs` | LateinitUsage, UnreachableCode, UnsafeCallOnNullableType, DontDowncastCollectionTypes | CRITICAL |
| `style` | MagicNumber, WildcardImport, UnusedImports, MaxLineLength | INFO |

### Configuration Patterns

Baseline config at `config/detekt.yml`:

```yaml
build:
  maxIssues: 0
  excludeCorrectable: false

config:
  validation: true
  warningsAsErrors: false

processors:
  active: true
  exclude:
    - 'DetektProgressListener'

console-reports:
  active: true

complexity:
  active: true
  CyclomaticComplexity:
    threshold: 15
  LongMethod:
    threshold: 60
  LargeClass:
    threshold: 600
  TooManyFunctions:
    thresholdInFiles: 20
    thresholdInClasses: 15

coroutines:
  active: true
  GlobalCoroutineUsage:
    active: true

exceptions:
  active: true
  SwallowedException:
    active: true
  TooGenericExceptionCaught:
    active: true

naming:
  active: true
  FunctionNaming:
    functionPattern: '[a-z][a-zA-Z0-9]*'
    excludes: ['**/test/**', '**/androidTest/**']
  MatchingDeclarationName:
    mustBeFirst: true

performance:
  active: true
  SpreadOperator:
    active: true
    excludes: ['**/test/**']

potential-bugs:
  active: true
  LateinitUsage:
    active: true
    excludes: ['**/test/**']

style:
  active: true
  MagicNumber:
    excludes: ['**/test/**', '**/androidTest/**']
  WildcardImport:
    active: true
    excludeImports: ['java.util.*', 'kotlinx.coroutines.*']
  MaxLineLength:
    maxLineLength: 140
    excludePackageStatements: true
    excludeImportStatements: true
```

To exclude generated code or third-party sources:
```yaml
# In detekt.yml
# OR via Gradle:
detekt {
  source.setFrom("src/main/kotlin")  # exclude generated/
}
```

Suppress individual violations inline:
```kotlin
@Suppress("MagicNumber")
val timeout = 30_000

@Suppress("LongMethod")
fun complexSetup() { ... }
```

### CI Integration

```yaml
# .github/workflows/quality.yml
- name: Run detekt
  run: ./gradlew detekt --continue

- name: Upload SARIF report
  if: always()
  uses: github/codeql-action/upload-sarif@v3
  with:
    sarif_file: build/reports/detekt/detekt.sarif
```

Enable SARIF output in `build.gradle.kts`:
```kotlin
detekt {
    reports {
        sarif { required.set(true) }
        html { required.set(true) }
        xml { required.set(false) }
    }
}
```

Fail the build on any issue: `maxIssues: 0` in config (recommended). Baseline file for gradual adoption: `./gradlew detektBaseline` generates `config/detekt-baseline.xml` — existing violations are whitelisted, only new ones fail.

## Performance

- Parallel analysis (`parallel = true`) reduces wall-clock time by ~40% on 8-core machines for large codebases.
- Type resolution (`detektMain` vs `detekt`) adds ~30% overhead but catches coroutine and nullability issues that regex-based analysis misses. Always enable for production code.
- Incremental: detekt uses Gradle's up-to-date checks — unchanged source sets are skipped entirely. Expect < 5s on incremental runs for most projects.
- Exclude generated sources (`build/generated/`) from `source.setFrom()` to avoid false positives and wasted analysis time.

## Security

The `potential-bugs` rule set catches several security-adjacent patterns:
- `UnsafeCallOnNullableType` — `!!` operators that can throw `NullPointerException` in untrusted input paths
- `IgnoredReturnValue` — ignoring return values from security-sensitive APIs (e.g., `File.delete()`, `mkdir()`)
- `UnusedPrivateMember` — dead code that may contain stale security logic

For deeper security analysis, pair detekt with SpotBugs + FindSecBugs on the JVM output rather than relying on detekt alone.

## Testing

Verify your config file is valid before CI runs:
```bash
./gradlew detektGenerateConfig   # generates default config for inspection
./gradlew detektMain             # run on main sources only
./gradlew detektTest             # run on test sources (can have relaxed rules)
```

Write custom rules as a separate Gradle subproject:
```kotlin
// custom-rules/build.gradle.kts
dependencies {
    compileOnly("io.gitlab.arturbosch.detekt:detekt-api:1.23.7")
    testImplementation("io.gitlab.arturbosch.detekt:detekt-test:1.23.7")
}
```

Test custom rules with `detekt-test`:
```kotlin
class NoSingletonRuleTest : RuleSetProviderTest(NoSingletonRule::class) {
    @Test fun `reports object declaration`() {
        val code = "object MySingleton { fun doWork() {} }"
        assertThat(NoSingletonRule().lint(code)).hasSize(1)
    }
}
```

## Dos

- Set `buildUponDefaultConfig = true` so your config extends rather than replaces the default rule set — new detekt versions add rules without breaking your config.
- Use `detektBaseline` when onboarding existing codebases — it whitelists current violations and fails only on regressions.
- Configure separate thresholds for `detektMain` and `detektTest` — test code legitimately has higher complexity.
- Enable `coroutines` rule set with type resolution — it catches `GlobalCoroutineUsage` and `SuspendFunWithFlowReturnType` that plain Kotlin compilation misses.
- Pin `detekt-formatting` to the same version as `detekt` plugin to avoid rule conflicts.
- Upload SARIF reports to GitHub Security tab for PR-level annotations.
- Run `detektGenerateConfig` once to understand all available rules before customizing.

## Don'ts

- Don't set `allRules = true` on an existing codebase — you'll get hundreds of violations and developers will start mass-suppressing.
- Don't suppress rules globally with `active: false` for performance or complexity rules — these are early indicators of maintainability decay.
- Don't include `build/generated/` or `build/tmp/` in detekt source sets — generated code has legitimate violations and poisons your reports.
- Don't use `autoCorrect = true` in CI — it modifies source files mid-build and creates confusing diffs. Reserve for local developer tasks.
- Don't ignore the `coroutines` rule set — misusing `GlobalScope` or wrong suspend return types causes runtime issues that tests may not catch.
- Don't skip type resolution (`detektMain`) to save time — the most valuable rules (coroutine, nullability) require it.
