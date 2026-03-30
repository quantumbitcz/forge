# Jetpack Compose + ktlint

> Extends `modules/code-quality/ktlint.md` with Jetpack Compose-specific integration.
> Generic ktlint conventions are NOT repeated here.

## Integration Setup

Enable Android mode in the Gradle plugin — this applies Google's Android Kotlin style guide:

```kotlin
// build.gradle.kts
ktlint {
    version.set("1.4.1")
    android.set(true)   // required for Compose projects
    outputToConsole.set(true)
    filter {
        exclude("**/generated/**")
        exclude("**/build/**")
    }
}
```

Add Compose-specific `.editorconfig` overrides at the module root:

```ini
[*.{kt,kts}]
max_line_length = 140
ktlint_standard_trailing-comma-on-call-site = enabled
ktlint_standard_trailing-comma-on-declaration-site = enabled

# Compose: allow PascalCase function names (composables)
ktlint_standard_function-naming = disabled
```

Disabling `function-naming` is necessary because ktlint's standard rule enforces camelCase for all functions — Composable PascalCase names are then enforced by the `compose-rules` detekt plugin instead.

## Framework-Specific Patterns

### Trailing Commas in Composable Call Sites

Compose functions commonly have many parameters. Trailing commas reduce diff noise:

```kotlin
// CORRECT — trailing comma enables clean per-line diffs
Button(
    text = "Submit",
    enabled = isFormValid,
    onClick = onSubmit,   // trailing comma
)

// WRONG — no trailing comma causes extra diff line on parameter add
Button(
    text = "Submit",
    enabled = isFormValid,
    onClick = onSubmit
)
```

### Import Ordering for Compose APIs

Compose imports cluster under `androidx.compose.*` — ensure ASCII-sorted import ordering groups them correctly:

```ini
# .editorconfig
ktlint_standard_import-ordering = enabled
```

Avoid wildcard imports for compose packages — they hide which APIs are actually used and make IDE navigation harder.

### Modifier Extension Functions

`Modifier` extension chains format best with trailing-dot alignment. ktlint's standard wrapping rules handle this correctly when `max_line_length` is respected:

```kotlin
Box(
    modifier = Modifier
        .fillMaxSize()
        .padding(horizontal = 16.dp)
        .background(MaterialTheme.colorScheme.surface)
)
```

## Additional Dos

- Set `android.set(true)` — it aligns formatting with Android Studio's built-in formatter to reduce developer friction.
- Keep `.editorconfig` at the repository root shared between `app/` and any other Android modules.
- Disable only `function-naming` for the Compose PascalCase exception — all other standard rules apply unchanged.
- Run `ktlintFormat` as a pre-commit hook via the Gradle plugin to catch formatting before review.

## Additional Don'ts

- Don't enable `ktlint_experimental_function-expression-body` in Compose modules — single-expression composables are often harder to read than block-body ones.
- Don't configure separate `.editorconfig` files per source set — a single root config applies consistently.
- Don't suppress ktlint violations inline in composables without a comment explaining the exception.
- Don't run `ktlintFormat` in CI on `androidTest/` sources without first confirming it doesn't reformat generated test harness files.
