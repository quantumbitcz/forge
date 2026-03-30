# Kotlin Multiplatform + JaCoCo

> Extends `modules/code-quality/jacoco.md` with Kotlin Multiplatform-specific integration.
> Generic JaCoCo conventions are NOT repeated here.

## Integration Setup

JaCoCo runs only on JVM targets — it cannot instrument Kotlin/Native or Kotlin/JS bytecode. Configure it for `commonMain` and `androidMain` source sets that compile to JVM:

```kotlin
// shared/build.gradle.kts
plugins {
    jacoco
}

jacoco {
    toolVersion = "0.8.12"
}

// JVM unit tests (covers commonMain + jvmMain)
tasks.named<Test>("jvmTest") {
    useJUnitPlatform()
    finalizedBy(tasks.named("jacocoJvmTestReport"))
}

tasks.register<JacocoReport>("jacocoJvmTestReport") {
    dependsOn(tasks.named("jvmTest"))
    executionData.setFrom(
        fileTree("${buildDir}/jacoco") { include("*.exec") }
    )
    sourceDirectories.setFrom(
        "src/commonMain/kotlin",
        "src/jvmMain/kotlin"
    )
    classDirectories.setFrom(
        fileTree("${buildDir}/classes/kotlin/jvm/main") {
            exclude("**/generated/**")
        }
    )
    reports { xml.required = true; html.required = true }
}
```

## Framework-Specific Patterns

### Coverage Scope: JVM Proxy for commonMain

`commonMain` code is tested via the JVM target (`jvmTest` or `desktopTest`). JaCoCo covers the JVM compilation of `commonMain` — this is the practical way to measure shared logic coverage:

| Source Set | JaCoCo Coverage | How |
|---|---|---|
| `commonMain` | Yes (via JVM target) | `jacocoJvmTestReport` covers JVM compilation |
| `androidMain` | Yes | `enableAndroidTestCoverage` + `createDebugCoverageReport` |
| `iosMain` | No | Use Kotlin/Native LLVM coverage (llvm-cov) separately |
| `jsMain` | No | Use Istanbul/c8 for JS coverage |

### Multi-Platform Coverage Aggregation

Aggregate JVM and Android coverage into a combined report for CI dashboards:

```kotlin
// root build.gradle.kts
tasks.register<JacocoReport>("jacocoAggregatedReport") {
    dependsOn(
        ":shared:jacocoJvmTestReport",
        ":androidApp:createDebugCoverageReport"
    )
    executionData.setFrom(
        fileTree("shared/build/jacoco"),
        fileTree("androidApp/build/outputs/code_coverage")
    )
    sourceDirectories.setFrom(
        "shared/src/commonMain/kotlin",
        "shared/src/androidMain/kotlin",
        "androidApp/src/main/kotlin"
    )
    classDirectories.setFrom(
        fileTree("shared/build/classes/kotlin/jvm/main"),
        fileTree("androidApp/build/tmp/kotlin-classes/debug") {
            exclude("**/R.class", "**/R$*.class", "**/BuildConfig.class",
                    "**/*_HiltModules*", "**/*_Factory*")
        }
    )
    reports { xml.required = true; html.required = true }
}
```

### Coverage Thresholds

Apply thresholds to `commonMain` only — it contains the most testable business logic:

```kotlin
tasks.jacocoTestCoverageVerification {
    violationRules {
        rule {
            // commonMain domain logic
            includes = listOf("com.example.domain.*", "com.example.usecase.*")
            limit {
                counter = "INSTRUCTION"
                minimum = "0.85".toBigDecimal()
            }
        }
        rule {
            // Overall JVM compilation
            limit {
                minimum = "0.70".toBigDecimal()
            }
        }
    }
}
```

### iOS Coverage with llvm-cov

For iOS-specific `actual` implementations, use Xcode's built-in coverage or llvm-cov separately — JaCoCo does not apply:

```bash
# Run iOS tests with coverage via xcodebuild
xcodebuild test -scheme iosApp -destination "platform=iOS Simulator,name=iPhone 15" \
  -enableCodeCoverage YES
# Export with xcov or xcresult parser
```

## Additional Dos

- Configure `jvmTest` task with JaCoCo even if the primary targets are Android and iOS — it gives fast, CI-friendly coverage of all `commonMain` logic.
- Aggregate JVM + Android coverage into one Codecov/SonarQube upload to get a project-wide view.
- Exclude `iosMain` source from the JVM JaCoCo report — iOS actuals aren't compiled for JVM and their absence inflates gaps.
- Document that iOS coverage is tracked separately in your `CONTRIBUTING.md`.

## Additional Don'ts

- Don't claim full coverage from JaCoCo alone — `iosMain` and `jsMain` source sets are not measured.
- Don't set coverage thresholds that include `iosMain` class directories in the JVM report — they won't appear and will look like 0% covered classes.
- Don't skip the JVM target entirely for coverage savings — `commonMain` tests on JVM are fast and provide the most coverage value per second.
- Don't include generated sources (KSP, SQLDelight) in coverage class directories — they inflate the gap.
