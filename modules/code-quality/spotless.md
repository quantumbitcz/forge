---
name: spotless
categories: [formatter]
languages: [java, kotlin, scala]
exclusive_group: kotlin-formatter
recommendation_score: 70
detection_files: [build.gradle.kts, build.gradle, pom.xml]
---

# spotless

## Overview

Multi-language JVM code formatter Gradle/Maven plugin. A single Spotless configuration applies formatting to Java, Kotlin, Groovy, Scala, SQL, JSON, Markdown, XML, and more within one Gradle task. Spotless delegates to underlying formatters (google-java-format, ktlint, scalafmt, prettier) and adds license header management on top. Use `./gradlew spotlessCheck` in CI and `./gradlew spotlessApply` locally. Spotless integrates with Gradle's incremental build system — only reformats changed files.

## Architecture Patterns

### Installation & Setup

```kotlin
// build.gradle.kts (root project)
plugins {
    id("com.diffplug.spotless") version "7.0.2"
}

spotless {
    java {
        googleJavaFormat("1.24.0")
        removeUnusedImports()
        trimTrailingWhitespace()
        endWithNewline()
        licenseHeaderFile(rootProject.file("config/spotless/license-header.txt"))
    }
    kotlin {
        ktlint("1.5.0")
            .editorConfigOverride(mapOf(
                "indent_size" to "4",
                "max_line_length" to "120"
            ))
        trimTrailingWhitespace()
        endWithNewline()
        licenseHeaderFile(rootProject.file("config/spotless/license-header.txt"))
    }
    kotlinGradle {
        ktlint("1.5.0")
        trimTrailingWhitespace()
        endWithNewline()
    }
}
```

**License header file (`config/spotless/license-header.txt`):**
```
/*
 * Copyright $YEAR MyCompany. All rights reserved.
 * SPDX-License-Identifier: Apache-2.0
 */
```

Spotless replaces `$YEAR` with the current year in new files and preserves the original year in existing files.

### Rule Categories

Spotless delegates formatting to language-specific tools:

| Language | Recommended Formatter | Key Options |
|---|---|---|
| Java | `googleJavaFormat` | `aosp()` for 4-space variant |
| Kotlin | `ktlint` | `editorConfigOverride` for project settings |
| Groovy | `greclipse` or `importOrder` | Gradle build files |
| Scala | `scalafmt` | Config via `.scalafmt.conf` |
| JSON | `jackson` or `gson` | Normalize JSON formatting |
| SQL | `dbeaver` | SQL style enforcement |
| Markdown | `flexmark` | `.md` file formatting |
| XML | `eclipse` WTP | WSDL, Spring XML, pom.xml |

### Configuration Patterns

**Multi-module Gradle project:**
```kotlin
// build.gradle.kts (root)
subprojects {
    apply(plugin = "com.diffplug.spotless")
    configure<com.diffplug.gradle.spotless.SpotlessExtension> {
        java {
            target("src/**/*.java")
            googleJavaFormat("1.24.0")
            licenseHeaderFile(rootProject.file("config/spotless/license-header.txt"))
        }
        kotlin {
            target("src/**/*.kt")
            ktlint("1.5.0")
            licenseHeaderFile(rootProject.file("config/spotless/license-header.txt"))
        }
    }
}
```

**Custom exclusions:**
```kotlin
spotless {
    java {
        targetExclude("**/generated/**", "**/build/**", "**/*_.java")
        googleJavaFormat()
    }
}
```

**JSON formatting with Jackson:**
```kotlin
spotless {
    json {
        target("src/**/*.json", "config/**/*.json")
        jackson()
            .feature("INDENT_OUTPUT", true)
            .feature("ORDER_MAP_ENTRIES_BY_KEYS", true)
    }
}
```

### CI Integration

```yaml
# .github/workflows/quality.yml
- name: Spotless check
  run: ./gradlew spotlessCheck

# With caching (important — Spotless downloads formatters)
- name: Cache Gradle packages
  uses: actions/cache@v4
  with:
    path: |
      ~/.gradle/caches
      ~/.gradle/wrapper
    key: gradle-${{ hashFiles('**/*.gradle.kts', '**/gradle-wrapper.properties') }}
```

**Fail fast — run before tests:**
```yaml
jobs:
  quality:
    steps:
      - uses: actions/checkout@v4
      - name: Set up JDK
        uses: actions/setup-java@v4
        with:
          java-version: "21"
          distribution: temurin
      - name: Spotless check
        run: ./gradlew spotlessCheck --no-daemon
```

**Pre-commit hook:**
```bash
#!/usr/bin/env bash
# .git/hooks/pre-commit
./gradlew spotlessApply --quiet
git add -u
```

## Performance

- Spotless uses Gradle's incremental task execution — only re-formats files that have changed since the last run.
- On cold runs (first CI execution, no cache), Spotless downloads formatter JARs — ensure the Gradle cache is warm in CI.
- `spotlessCheck` is faster than `spotlessApply` — it short-circuits on the first formatting difference per file.
- For large monorepos, run spotless scoped to the changed module: `./gradlew :api:spotlessCheck :worker:spotlessCheck`.
- google-java-format and ktlint run in-process — no external process spawn overhead per file.

## Security

- google-java-format and ktlint are fetched from Maven Central — verify the Gradle checksum verification is enabled:
  ```kotlin
  // settings.gradle.kts
  dependencyResolutionManagement {
      repositories {
          mavenCentral()
      }
  }
  ```
- License headers enforce copyright attribution on all source files — critical for open-source projects with contributor agreements.
- Spotless does not execute code in the files it formats — safe to run on untrusted codebases.
- Pin Spotless plugin version and all formatter versions (google-java-format, ktlint) in `build.gradle.kts` — formatter behavior changes on upgrade.

## Testing

```bash
# Check all files without writing (CI mode)
./gradlew spotlessCheck

# Apply formatting to all files
./gradlew spotlessApply

# Check a specific subproject
./gradlew :api:spotlessCheck

# Apply to a specific subproject
./gradlew :api:spotlessApply

# Force re-check of all files (bypass incremental)
./gradlew spotlessCheck --rerun-tasks

# Diagnose which files would change
./gradlew spotlessCheck 2>&1 | grep "Spotless found"
```

## Dos

- Cache the Gradle wrapper and `~/.gradle/caches` in CI — Spotless downloads formatter JARs (google-java-format, ktlint) on first run and the cold start is slow.
- Use `licenseHeaderFile` with a shared header template — it prevents license header drift across modules and enforces copyright on all new files.
- Set `targetExclude` to skip generated code directories — generated files (protobuf, JOOQ, MapStruct) should not be reformatted.
- Pin formatter versions (`googleJavaFormat("1.24.0")`, `ktlint("1.5.0")`) — un-pinned formatters pick up the latest version and can cause unexpected formatting changes.
- Run `spotlessApply` in a git pre-commit hook — apply before staging to ensure commits are always formatted.
- Use `kotlinGradle {}` block separately from `kotlin {}` — Gradle Kotlin DSL files have different formatting rules than application Kotlin files.

## Don'ts

- Don't run `spotlessCheck` and `spotlessApply` in the same CI step — apply writes files, which would cause a dirty working tree and mislead CI.
- Don't skip caching in CI — un-cached Spotless downloads can add 30-60 seconds to CI runs on every execution.
- Don't configure ktlint via both `ktlint()` and a separate `.editorconfig` without reconciling them — conflicting settings produce unpredictable output.
- Don't use `spotlessApply` on generated source roots (`build/generated/`) — it modifies auto-generated files that will be overwritten on the next build, causing spurious changes.
- Don't add custom format tasks that overlap with Spotless's target globs — running two formatters on the same files produces conflicts and non-deterministic output.
- Don't ignore `spotlessCheck` failures as "cosmetic" — license header violations are legal/compliance issues, not just style.
