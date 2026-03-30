# Kotlin Multiplatform + Dokka

> Extends `modules/code-quality/dokka.md` with Kotlin Multiplatform-specific integration.
> Generic Dokka conventions are NOT repeated here.

## Integration Setup

KMP projects use `dokkaHtmlMultiModule` at the root to produce a unified doc site spanning all source sets:

```kotlin
// root build.gradle.kts
plugins {
    id("org.jetbrains.dokka") version "1.9.20"
}

// shared/build.gradle.kts
plugins {
    id("org.jetbrains.dokka") version "1.9.20"
}

tasks.dokkaHtml {
    outputDirectory.set(layout.buildDirectory.dir("dokka"))
    dokkaSourceSets {
        named("commonMain") {
            moduleName.set("shared-common")
            displayName.set("Common")
            sourceLink {
                localDirectory.set(file("src/commonMain/kotlin"))
                remoteUrl.set(uri("https://github.com/org/app/blob/main/shared/src/commonMain/kotlin").toURL())
                remoteLineSuffix.set("#L")
            }
        }
        named("androidMain") {
            displayName.set("Android")
            dependsOn(named("commonMain"))
        }
        named("iosMain") {
            displayName.set("iOS")
            dependsOn(named("commonMain"))
        }
    }
}

// root build.gradle.kts
tasks.dokkaHtmlMultiModule {
    outputDirectory.set(rootDir.resolve("docs/api"))
    moduleName.set("MyKMPApp")
}
```

## Framework-Specific Patterns

### Platform-Specific API Markers

Use `@JvmName` and `@JsName` annotations with KDoc to clarify platform-specific naming:

```kotlin
/**
 * Parses an ISO-8601 datetime string into a [LocalDateTime].
 *
 * On Android and JVM, delegates to `java.time.LocalDateTime.parse`.
 * On iOS, uses `NSDateFormatter` via the `iosMain` actual.
 *
 * @param isoString ISO-8601 formatted datetime string (e.g., "2024-01-15T10:30:00Z").
 * @return Parsed [LocalDateTime] in UTC.
 * @throws IllegalArgumentException if [isoString] is not valid ISO-8601.
 */
@JvmName("parseDateTime")
expect fun parseIsoDateTime(isoString: String): LocalDateTime
```

Document `expect` declarations in `commonMain` — the KDoc there is what appears in the generated documentation. `actual` implementations do not need duplicate KDoc unless they add platform-specific constraints.

### Suppressing Platform Internals

Suppress platform-specific internal packages from the multi-module docs:

```kotlin
tasks.dokkaHtml {
    dokkaSourceSets {
        configureEach {
            // Suppress generated source sets and internal packages
            perPackageOption {
                matchingRegex.set(".*\\.internal.*")
                suppress.set(true)
            }
        }
        named("androidMain") {
            // Suppress Android platform glue — not part of public API
            perPackageOption {
                matchingRegex.set(".*\\.android\\.impl.*")
                suppress.set(true)
            }
        }
        named("iosMain") {
            perPackageOption {
                matchingRegex.set(".*\\.ios\\.impl.*")
                suppress.set(true)
            }
        }
    }
}
```

### Documenting expect/actual Contract

Document `expect` declarations as the authoritative API. Mention platform-specific behaviors inline:

```kotlin
/**
 * Generates a cryptographically secure random UUID.
 *
 * Platform implementations:
 * - **Android/JVM**: `java.util.UUID.randomUUID()`
 * - **iOS**: `NSUUID().uuidString`
 * - **JS**: `crypto.randomUUID()`
 *
 * @return RFC 4122 UUID string in lowercase hyphenated format.
 */
expect fun generateUuid(): String
```

### Multi-Module Docs CI

```yaml
# .github/workflows/docs.yml (runs on main branch only)
- name: Generate multi-module API docs
  run: ./gradlew dokkaHtmlMultiModule

- name: Deploy to GitHub Pages
  uses: peaceiris/actions-gh-pages@v4
  with:
    github_token: ${{ secrets.GITHUB_TOKEN }}
    publish_dir: ./docs/api
```

## Additional Dos

- Configure `dependsOn` between source sets in `dokkaSourceSets` to enable cross-source-set linking (e.g., `androidMain` docs can link to `commonMain` types).
- Document `expect` declarations in `commonMain` with full KDoc — the `actual` implementations inherit the documentation.
- Use `displayName` on each source set for readable navigation: "Common", "Android", "iOS" instead of "commonMain".
- Suppress internal `actual` implementation packages from generated docs.

## Additional Don'ts

- Don't add KDoc to `actual` implementations that duplicate what the `expect` already documents — it causes divergence.
- Don't run `dokkaHtmlMultiModule` on every PR — it is slow (30-120s) and only needed for releases.
- Don't skip configuring `dependsOn` between source sets — without it, types from `commonMain` won't hyperlink in `androidMain` docs.
- Don't use `@suppress` on public `expect` declarations — if it's in the public API, document it.
