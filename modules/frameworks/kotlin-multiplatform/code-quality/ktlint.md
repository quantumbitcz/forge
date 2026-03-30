# Kotlin Multiplatform + ktlint

> Extends `modules/code-quality/ktlint.md` with Kotlin Multiplatform-specific integration.
> Generic ktlint conventions are NOT repeated here.

## Integration Setup

Apply ktlint via convention plugin in `build-logic/` to ensure all source sets in all KMP modules share the same formatting rules:

```kotlin
// build-logic/src/main/kotlin/kmp-conventions.gradle.kts
plugins {
    id("org.jlleitschuh.gradle.ktlint")
}

ktlint {
    version.set("1.4.1")
    android.set(false)   // false for commonMain/iosMain; android modules set true separately
    outputToConsole.set(true)
    filter {
        // Include all KMP source sets
        include("**/kotlin/**")
        exclude("**/generated/**", "**/build/**")
    }
}
```

For modules that have an Android target alongside other platforms:

```kotlin
// androidApp/build.gradle.kts
ktlint {
    version.set("1.4.1")
    android.set(true)    // applies Google Android style for the Android module
}
```

## Framework-Specific Patterns

### Source Set Include Patterns

KMP source layout differs from standard JVM: source lives in `src/commonMain/kotlin/`, `src/iosMain/kotlin/`, etc. The default ktlint `**/kotlin/**` glob covers all of them:

```kotlin
filter {
    include("**/kotlin/**")
    // This covers:
    // src/commonMain/kotlin/
    // src/androidMain/kotlin/
    // src/iosMain/kotlin/
    // src/jsMain/kotlin/
}
```

### Per-Platform .editorconfig

A single `.editorconfig` at the repository root applies to all source sets. Avoid per-source-set `.editorconfig` files — they cause divergent formatting between `commonMain` and platform implementations:

```ini
# .editorconfig (repository root)
root = true

[*.{kt,kts}]
charset = utf-8
indent_size = 4
indent_style = space
max_line_length = 140
insert_final_newline = true
trim_trailing_whitespace = true
ktlint_standard_trailing-comma-on-call-site = enabled
ktlint_standard_trailing-comma-on-declaration-site = enabled
```

### expect/actual File Formatting

`expect` declarations in `commonMain` and their `actual` counterparts in platform source sets should format identically. ktlint handles both the same way — no special treatment is needed. Keep `actual` implementations on the same indentation level as their `expect` signatures.

### CI for Multi-Platform Source

Run `ktlintCheck` once at the root — it picks up all source sets via the `include("**/kotlin/**")` filter:

```yaml
# .github/workflows/quality.yml
- name: ktlint check (all source sets)
  run: ./gradlew ktlintCheck
```

For large monorepos, scope to changed modules:

```yaml
- name: ktlint check (shared module)
  run: ./gradlew :shared:ktlintCheck :androidApp:ktlintCheck
```

## Additional Dos

- Apply ktlint through a shared convention plugin in `build-logic/` — ensures `commonMain`, `androidMain`, and `iosMain` all use the same ktlint version.
- Keep `.editorconfig` at repository root — a single file covers all source sets without duplication.
- Set `android.set(true)` only in the Android app module, not in the shared KMP module — `commonMain` and `iosMain` should use standard Kotlin style.
- Exclude `build/generated/` source sets — KMP code generation (e.g., from KSP, SQLDelight) produces files that should not be reformatted.

## Additional Don'ts

- Don't create separate `.editorconfig` files per source set — divergent configs cause formatting conflicts between platform implementations and their common code.
- Don't set `android.set(true)` on the shared KMP module — it applies Android-specific rules to `iosMain` and `jsMain` source sets.
- Don't exclude `*.kts` files — `build.gradle.kts` files in KMP projects are complex and benefit equally from ktlint formatting.
- Don't suppress formatting violations in `actual` implementations differently than in `expect` declarations — it signals a naming or style mismatch.
