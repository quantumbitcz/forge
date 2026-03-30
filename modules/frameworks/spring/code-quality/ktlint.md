# Spring + ktlint

> Extends `modules/code-quality/ktlint.md` with Spring Boot-specific integration.
> Generic ktlint conventions (installation, rule categories, CI integration) are NOT repeated here.

## Integration Setup

Apply in the shared convention plugin so all Spring modules share the same version and `.editorconfig`:

```kotlin
// build-logic/src/main/kotlin/spring-conventions.gradle.kts
plugins {
    id("org.jlleitschuh.gradle.ktlint")
}

ktlint {
    version.set("1.4.1")
    filter {
        exclude("**/generated/**")
        exclude("**/build/**")
    }
}
```

## Framework-Specific Patterns

### `.editorconfig` integration for Spring code

Spring Boot projects use annotation-heavy declarations where line length 120 is routinely exceeded. Set a consistent limit in `.editorconfig` and align it with detekt's `MaxLineLength`:

```ini
# .editorconfig (project root)
[*.{kt,kts}]
max_line_length = 140
ktlint_standard_max-line-length = enabled

# Spring DSL wildcard imports — allow for Spring test utilities
ktlint_standard_no-wildcard-imports = disabled
```

### Wildcard imports for Spring DSL

Some Spring test DSLs and MockMvc result matchers are ergonomic with star imports. Selectively allow them:

```ini
# .editorconfig
[*Test.kt]
ktlint_standard_no-wildcard-imports = disabled
```

For production code, keep wildcard imports disabled and add explicit Spring imports:

```kotlin
// Prefer explicit imports in production beans
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.RestController
```

### Build script formatting

Spring Boot projects use `build.gradle.kts` extensively with Spring dependency blocks. ktlint applies to `*.kts` files by default — ensure the build scripts are covered:

```kotlin
ktlint {
    filter {
        include("**/kotlin/**")
        include("**/*.kts")
        exclude("**/generated/**")
        exclude("**/build/**")
    }
}
```

## Additional Dos

- Align `max_line_length` in `.editorconfig` with detekt's `MaxLineLength` — divergence causes one tool to pass while the other fails.
- Use `ktlintFormat` as a pre-commit hook to avoid formatting-only CI failures on annotation-heavy Spring code.
- Exclude `build/generated/` — Spring annotation processors (OpenAPI, MapStruct) emit Kotlin files that fail ktlint intentionally.

## Additional Don'ts

- Don't disable `no-wildcard-imports` globally — allow it only for test files where Spring test DSLs benefit from star imports.
- Don't set `android.set(true)` for Spring projects — it applies Android-specific style rules that conflict with Spring Boot conventions.
- Don't suppress `trailing-comma-on-declaration-site` for data classes — trailing commas reduce diff noise in Spring DTO definitions.
