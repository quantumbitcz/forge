# Spring + Spotless

> Extends `modules/code-quality/spotless.md` with Spring Boot-specific integration.
> Generic Spotless conventions (installation, format targets, CI integration) are NOT repeated here.

## Integration Setup

Configure Spotless to handle Kotlin (via ktlint), Java, and build scripts in a Spring Boot project:

```kotlin
// build.gradle.kts
plugins {
    id("com.diffplug.spotless") version "6.25.0"
}

spotless {
    kotlin {
        ktlint("1.4.1")
            .editorConfigOverride(mapOf(
                "max_line_length" to "140",
                "ktlint_standard_no-wildcard-imports" to "enabled"
            ))
        licenseHeaderFile("$rootDir/config/spotless/license-header.txt")
        targetExclude("**/generated/**", "**/build/**")
    }
    kotlinGradle {
        ktlint("1.4.1")
        targetExclude("**/generated/**")
    }
    java {
        googleJavaFormat("1.22.0")
        licenseHeaderFile("$rootDir/config/spotless/license-header.txt")
        targetExclude("**/generated/**", "**/build/**")
    }
}
```

## Framework-Specific Patterns

### License headers

Spring Boot enterprise projects often require copyright headers. Define the header template and apply it consistently:

```text
# config/spotless/license-header.txt
/*
 * Copyright (C) $YEAR Acme Corp. All rights reserved.
 *
 * This software is proprietary and confidential.
 */
```

Spotless inserts/updates the header automatically. The `$YEAR` placeholder is replaced with the current year on format.

For open source Spring projects, use the Apache 2.0 header pattern:

```text
/*
 * Copyright $YEAR the original author or authors.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 */
```

### ktlint via Spotless — don't double-apply

If ktlint is already applied via the `org.jlleitschuh.gradle.ktlint` Gradle plugin, use Spotless only for license header management, not formatting — running both on the same source produces conflicts:

```kotlin
spotless {
    kotlin {
        // License header only — formatting handled by standalone ktlint plugin
        licenseHeaderFile("$rootDir/config/spotless/license-header.txt")
        // Do NOT add ktlint() here if ktlint plugin is active
    }
}
```

### Import ordering

Spring Boot imports follow a consistent grouping: Java standard library, then Spring framework, then third-party, then project-internal. Configure import ordering in `.editorconfig` (picked up by ktlint via Spotless):

```ini
# .editorconfig
[*.{kt,kts}]
ktlint_standard_import-ordering = enabled
ij_kotlin_imports_layout = java.**, javax.**, jakarta.**, kotlin.**, org.springframework.**, *, ^
```

### Spotless check in CI

Use `spotlessCheck` (not `spotlessApply`) in CI to detect formatting drift without modifying files:

```yaml
# .github/workflows/quality.yml
- name: Spotless check
  run: ./gradlew spotlessCheck
```

Apply locally before committing:

```bash
./gradlew spotlessApply
```

## Additional Dos

- Use Spotless for license headers and import ordering; use the standalone ktlint plugin for formatting rules — they have complementary scopes.
- Exclude `build/generated/` from all Spotless targets — license headers on generated code cause conflicts with codegen tools.
- Run `spotlessApply` in a pre-commit hook to prevent formatting-only CI failures.

## Additional Don'ts

- Don't configure both `ktlint()` in Spotless and the `org.jlleitschuh.gradle.ktlint` plugin — they conflict on rule execution order and produce duplicate violations.
- Don't set `licenseHeaderFile` to a path that doesn't exist — Spotless silently skips missing license files, leaving headers unenforced.
- Don't use `googleJavaFormat` for Kotlin files — it misparses Kotlin syntax; use `ktlint()` for `*.kt` targets.
