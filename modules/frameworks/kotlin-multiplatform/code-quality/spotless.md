# Kotlin Multiplatform + Spotless

> Extends `modules/code-quality/spotless.md` with Kotlin Multiplatform-specific integration.
> Generic Spotless conventions are NOT repeated here.

## Integration Setup

Apply Spotless via a shared convention plugin so all KMP modules use consistent formatting:

```kotlin
// build-logic/src/main/kotlin/kmp-conventions.gradle.kts
plugins {
    id("com.diffplug.spotless")
}

spotless {
    kotlin {
        // Cover all KMP source sets under src/
        target("src/**/*.kt")
        targetExclude(
            "**/generated/**",
            "**/build/**",
            // KSP and SQLDelight generated sources
            "**/sqldelight/**",
            "**/ksp/**"
        )
        ktlint("1.4.1")
            .editorConfigOverride(mapOf(
                "indent_size" to "4",
                "max_line_length" to "140",
                "ktlint_standard_trailing-comma-on-call-site" to "enabled",
                "ktlint_standard_trailing-comma-on-declaration-site" to "enabled"
            ))
        trimTrailingWhitespace()
        endWithNewline()
        licenseHeaderFile(
            rootProject.file("config/spotless/license-header.txt"),
            "^(package|import|@file|//)"
        )
    }
    kotlinGradle {
        target("*.gradle.kts", "build-logic/**/*.gradle.kts")
        ktlint("1.4.1")
        trimTrailingWhitespace()
        endWithNewline()
    }
}
```

For the `androidApp/` module which targets Android specifically:

```kotlin
// androidApp/build.gradle.kts
spotless {
    kotlin {
        target("src/**/*.kt")
        ktlint("1.4.1")
            .editorConfigOverride(mapOf(
                "android" to "true",   // Android style for the Android app module only
                "ktlint_standard_function-naming" to "disabled"  // Compose PascalCase
            ))
    }
}
```

## Framework-Specific Patterns

### Source Set Glob Coverage

The `src/**/*.kt` glob covers all KMP source sets automatically:

```
src/commonMain/kotlin/     → covered
src/androidMain/kotlin/    → covered
src/iosMain/kotlin/        → covered
src/jsMain/kotlin/         → covered
src/commonTest/kotlin/     → covered
```

No per-source-set configuration is needed — the glob handles it.

### Android vs Non-Android Source Sets

`android.set(true)` in ktlint applies Android-specific rules (e.g., Google's Kotlin style for Android). Apply this only to the Android app module, not the shared KMP module:

```kotlin
// CORRECT — android style only in androidApp module
// androidApp/build.gradle.kts
ktlint("1.4.1").editorConfigOverride(mapOf("android" to "true"))

// WRONG — do not set android style on shared/ module
// shared/build.gradle.kts
ktlint("1.4.1").editorConfigOverride(mapOf("android" to "true"))  // affects iosMain too
```

### Excluding Generated KMP Sources

KMP code generation tools (KSP, SQLDelight, Ktor code gen) output to well-known directories:

```kotlin
targetExclude(
    "**/generated/**",
    "**/build/**",
    // SQLDelight generates to src/commonMain/sqldelight/ then compiles to build/
    "**/sqldelight/**",
    // KSP generates to build/generated/ksp/
    "**/ksp/**",
    // Room (Android) generates to build/generated/
    "**/room/**"
)
```

### Multi-Module Root Check

Run `spotlessCheck` across all modules from the root in CI:

```yaml
# .github/workflows/quality.yml
- name: Spotless check (all KMP modules)
  run: ./gradlew spotlessCheck

# For faster PR feedback, scope to changed modules:
- name: Spotless check (shared + androidApp)
  run: ./gradlew :shared:spotlessCheck :androidApp:spotlessCheck
```

## Additional Dos

- Configure Spotless in a shared convention plugin (`build-logic/`) — avoids duplicating the ktlint version and config in every KMP module.
- Use `src/**/*.kt` as the target glob — it covers all source sets without listing them individually.
- Apply `android.set(true)` (or `"android" to "true"`) only to the Android app module, not to the shared KMP library.
- Exclude KSP and SQLDelight generated directories explicitly — they are regenerated on build and must not be reformatted.

## Additional Don'ts

- Don't create a separate Spotless configuration per source set — a single `kotlin {}` block with `src/**/*.kt` is sufficient.
- Don't apply Spotless to `iosApp/` Swift files — Spotless's Kotlin formatter does not support Swift; use `swift-format` separately.
- Don't run `spotlessApply` in CI without committing the result — it modifies source files and leaves a dirty working tree.
- Don't mix `android.set(true)` between the shared module and app module — Android-specific formatting rules are inappropriate for `iosMain` source files.
