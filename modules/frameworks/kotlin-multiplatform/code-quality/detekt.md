# Kotlin Multiplatform + detekt

> Extends `modules/code-quality/detekt.md` with Kotlin Multiplatform-specific integration.
> Generic detekt conventions are NOT repeated here.

## Integration Setup

In KMP projects, detekt must be configured per source set. Apply it in each submodule's `build.gradle.kts`:

```kotlin
// shared/build.gradle.kts
plugins {
    id("io.gitlab.arturbosch.detekt") version "1.23.7"
}

detekt {
    config.setFrom(files("$rootDir/config/detekt.yml"))
    buildUponDefaultConfig = true
    parallel = true
    // Scan all source sets explicitly
    source.setFrom(
        "src/commonMain/kotlin",
        "src/androidMain/kotlin",
        "src/iosMain/kotlin",
        "src/jsMain/kotlin"
    )
}

dependencies {
    detektPlugins("io.gitlab.arturbosch.detekt:detekt-formatting:1.23.7")
}
```

For a monorepo with separate `androidApp/` and `shared/` modules, configure detekt on both and run `detektAll` via a root aggregator task:

```kotlin
// root build.gradle.kts
tasks.register("detektAll") {
    dependsOn(subprojects.map { "${it.path}:detekt" })
}
```

## Framework-Specific Patterns

### Per-Source-Set Rule Relaxations

Different source sets have different constraints. Use separate config files or exclusion patterns:

```yaml
# config/detekt.yml
naming:
  FunctionNaming:
    excludes:
      - '**/commonTest/**'
      - '**/androidTest/**'
      - '**/iosTest/**'

complexity:
  LongMethod:
    # iOS actual implementations are sometimes verbose due to Darwin API
    excludes: ['**/iosMain/**']
    threshold: 80

style:
  MagicNumber:
    excludes: ['**/test/**', '**/androidTest/**', '**/iosTest/**', '**/commonTest/**']
```

### expect/actual Handling

detekt analyzes `expect` declarations and `actual` implementations independently. Several rules produce false positives on `actual` functions — suppress at the declaration level:

```kotlin
// EXPECTED in commonMain — always document with KDoc
expect fun platformLog(tag: String, message: String)

// ACTUAL in iosMain — suppress MagicNumber for platform constant values
@Suppress("MagicNumber")
actual fun platformLog(tag: String, message: String) {
    NSLog("[$tag] $message")
}
```

Add to detekt config to avoid `EmptyFunctionBlock` false positives on `expect` declarations:

```yaml
empty-blocks:
  EmptyFunctionBlock:
    ignoreOverridden: true
```

### Coroutine Rules in commonMain

KMP `commonMain` code runs on all platforms — coroutine misuse in shared code is especially harmful. Enable the coroutines rule set with full type resolution:

```yaml
coroutines:
  active: true
  GlobalCoroutineUsage:
    active: true    # GlobalScope forbidden in shared code
  SuspendFunWithFlowReturnType:
    active: true
  InjectDispatcher:
    active: true    # inject Dispatchers, never hardcode
```

### Multi-Module Source Set Discovery

For large KMP projects with many source sets, ensure the Gradle `source.setFrom` covers all active targets:

```kotlin
kotlin.sourceSets.all {
    // Dynamically include all source sets for detekt
    detekt.source.from(kotlin.srcDirs)
}
```

## Additional Dos

- Run detekt on `commonMain` with type resolution enabled — cross-platform code has the highest quality impact.
- Configure separate complexity thresholds for `iosMain` — Darwin platform APIs often require more verbose `actual` implementations.
- Add `commonTest`, `androidTest`, and `iosTest` to exclusion lists for `MagicNumber` and `LongMethod`.
- Use the `InjectDispatcher` rule — hardcoded `Dispatchers.IO` in `commonMain` causes iOS test failures.

## Additional Don'ts

- Don't exclude entire source sets (e.g., `iosMain`) from detekt — platform-specific code still benefits from complexity and naming analysis.
- Don't suppress `GlobalCoroutineUsage` in `commonMain` — leaked coroutines in shared code affect all platforms.
- Don't configure detekt only at the root without including sub-source-set paths — `androidMain` and `iosMain` are silently skipped.
- Don't use `allRules = true` in KMP projects — several rules are JVM-specific and produce misleading violations in `iosMain`.
