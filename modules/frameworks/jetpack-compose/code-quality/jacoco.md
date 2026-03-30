# Jetpack Compose + JaCoCo

> Extends `modules/code-quality/jacoco.md` with Jetpack Compose-specific integration.
> Generic JaCoCo conventions are NOT repeated here.

## Integration Setup

Compose projects have two distinct test types requiring separate JaCoCo configurations:

```kotlin
// build.gradle.kts
plugins {
    jacoco
}

jacoco {
    toolVersion = "0.8.12"
}

// Unit tests (JVM, fast, uses Robolectric for Compose host)
tasks.test {
    useJUnitPlatform()
    finalizedBy(tasks.jacocoTestReport)
}

// Instrumented tests (Android emulator/device) — coverage requires separate flag
android {
    buildTypes {
        debug {
            enableAndroidTestCoverage = true   // formerly: testCoverageEnabled
        }
    }
}

tasks.jacocoTestReport {
    dependsOn(tasks.test)
    reports {
        xml.required = true
        html.required = true
    }
    classDirectories.setFrom(
        files(classDirectories.files.map {
            fileTree(it) {
                exclude(
                    "**/R.class", "**/R$*.class",
                    "**/*_HiltModules*",
                    "**/*_Factory*",
                    "**/*_MembersInjector*",
                    "**/Hilt_*",
                    "**/databinding/**",
                    "**/BuildConfig.class",
                    "**/*ComposableSingletons*",   // Compose compiler internal
                    "**/*_Impl.class"              // generated implementations
                )
            }
        })
    )
}
```

## Framework-Specific Patterns

### Robolectric for Compose Unit Tests

Robolectric enables Compose UI tests to run on the JVM (no emulator needed), so JaCoCo can instrument them:

```kotlin
// build.gradle.kts
android {
    testOptions {
        unitTests {
            isIncludeAndroidResources = true   // required for Compose Robolectric
        }
    }
}

dependencies {
    testImplementation("org.robolectric:robolectric:4.13")
    testImplementation("androidx.compose.ui:ui-test-junit4")
}
```

With Robolectric, `composeTestRule.setContent { ... }` works in unit tests and JaCoCo captures the coverage.

### Instrumented vs Unit Coverage

| Test Type | Coverage Tool | JaCoCo Captures? |
|---|---|---|
| Unit tests (`test/`) + Robolectric | `jacocoTestReport` Gradle task | Yes |
| Instrumented tests (`androidTest/`) | `enableAndroidTestCoverage` | Via `createDebugCoverageReport` |
| UI test with emulator | Android Gradle plugin | Yes, separate `.ec` file |

Merge both for a combined report:

```kotlin
tasks.register<JacocoReport>("jacocoCombinedReport") {
    dependsOn("test", "createDebugCoverageReport")
    executionData.setFrom(
        fileTree("${buildDir}/outputs/unit_test_code_coverage"),
        fileTree("${buildDir}/outputs/code_coverage")
    )
    sourceDirectories.setFrom("src/main/kotlin")
    classDirectories.setFrom(/* same exclusions as above */)
    reports { xml.required = true; html.required = true }
}
```

### Coverage Thresholds for Compose

ViewModel and domain layer are fully testable with unit tests — target 80%+ INSTRUCTION. Composables themselves have lower testable surface:

```kotlin
tasks.jacocoTestCoverageVerification {
    violationRules {
        rule {
            // Overall project threshold
            limit { minimum = "0.70".toBigDecimal() }
        }
        rule {
            // ViewModel layer must be well-covered
            includes = listOf("*.viewmodel.*")
            limit {
                counter = "INSTRUCTION"
                minimum = "0.85".toBigDecimal()
            }
        }
    }
}
```

## Additional Dos

- Exclude `**/ComposableSingletons*` — the Compose compiler generates these internal classes and they inflate line counts.
- Use Robolectric for ViewModel + state logic tests to get JaCoCo coverage without an emulator.
- Set `enableAndroidTestCoverage = true` only in `debug` build type — production builds must not include coverage instrumentation.
- Merge unit and instrumented `.exec`/`.ec` files in a combined report task for the CI dashboard.

## Additional Don'ts

- Don't set instrumented test coverage thresholds on the same task as unit test coverage — emulator tests are flaky and corrupt threshold enforcement.
- Don't include `Hilt_*` generated files in coverage — they are not user-authored code.
- Don't target 100% line coverage on `@Composable` functions — preview-only composables and layout-only functions have no testable logic.
- Don't skip `isIncludeAndroidResources = true` when using Robolectric — Compose requires resource loading.
