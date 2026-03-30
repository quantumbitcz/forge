# Jetpack Compose + Spotless

> Extends `modules/code-quality/spotless.md` with Jetpack Compose-specific integration.
> Generic Spotless conventions are NOT repeated here.

## Integration Setup

```kotlin
// build.gradle.kts
plugins {
    id("com.diffplug.spotless") version "7.0.2"
}

spotless {
    kotlin {
        target("src/**/*.kt")
        targetExclude(
            "**/generated/**",
            "**/build/**",
            "**/*_HiltModules.kt",
            "**/*_Factory.kt"
        )
        ktlint("1.4.1")
            .editorConfigOverride(mapOf(
                "android" to "true",            // Google Android style
                "indent_size" to "4",
                "max_line_length" to "140",
                // Allow PascalCase composable functions
                "ktlint_standard_function-naming" to "disabled"
            ))
        trimTrailingWhitespace()
        endWithNewline()
        licenseHeaderFile(
            rootProject.file("config/spotless/license-header.txt"),
            "^(package|import|@file|//)"       // match Kotlin file start
        )
    }
    kotlinGradle {
        target("*.gradle.kts", "buildSrc/**/*.gradle.kts")
        ktlint("1.4.1")
        trimTrailingWhitespace()
        endWithNewline()
    }
    // Format XML resources (layouts, manifests, themes)
    format("xml") {
        target("src/**/*.xml")
        targetExclude("**/generated/**")
        eclipseWtp(com.diffplug.spotless.extra.wtp.EclipseWtpFormatterStep.XML)
        trimTrailingWhitespace()
        endWithNewline()
    }
}
```

## Framework-Specific Patterns

### Compose-Specific ktlint Override

The `ktlint_standard_function-naming = disabled` override is required because Compose composables must be PascalCase (a naming convention ktlint's standard rule rejects). Keep this override scoped to `kotlin {}` only — do not disable in `kotlinGradle {}`.

### XML Resource Formatting

Compose projects still use XML for `AndroidManifest.xml`, `res/values/themes.xml`, and `res/drawable/` files. The `format("xml")` block standardizes these alongside Kotlin formatting:

```kotlin
format("xml") {
    target(
        "src/main/AndroidManifest.xml",
        "src/main/res/**/*.xml"
    )
    eclipseWtp(com.diffplug.spotless.extra.wtp.EclipseWtpFormatterStep.XML)
}
```

### License Headers

For Android projects, the license header matcher must handle `@file:` annotations that Kotlin files sometimes begin with:

```kotlin
licenseHeaderFile(
    rootProject.file("config/spotless/license-header.txt"),
    "^(package|import|@file|//)"
)
```

### Excluding Hilt Generated Files

Hilt-generated Kotlin files (`Hilt_*.kt`, `*_HiltModules.kt`, `*_Factory.kt`) must be excluded — they are auto-generated and not under developer control:

```kotlin
kotlin {
    targetExclude(
        "**/generated/**",
        "**/*_HiltModules.kt",
        "**/*_Factory.kt",
        "**/*_MembersInjector.kt",
        "**/Hilt_*.kt"
    )
}
```

## Additional Dos

- Add `kotlinGradle {}` to also format `build.gradle.kts` files — Compose projects often have complex Gradle configurations that benefit from consistent formatting.
- Include the `format("xml")` block — Android manifest and resource XML files are part of the codebase and should be formatted.
- Use `android.set(true)` via `editorConfigOverride` — aligns Spotless output with Android Studio's built-in formatter.
- Cache `~/.gradle/caches` and `~/.gradle/wrapper` in CI — Spotless downloads ktlint JARs on first run.

## Additional Don'ts

- Don't apply Spotless to `build/generated/` or `kapt/generated/` directories — reformatting auto-generated code causes build instability.
- Don't configure `spotlessApply` in CI without committing the result — the check will still fail after apply if working tree changes aren't staged.
- Don't remove the `ktlint_standard_function-naming = disabled` override — without it, `spotlessCheck` rejects every `@Composable` function name.
- Don't format `res/raw/` XML files with the Eclipse WTP XML formatter — they may contain data files (fonts, configs) that need exact byte-level preservation.
