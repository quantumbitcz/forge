---
name: dokka
categories: [doc-generator]
languages: [kotlin]
exclusive_group: kotlin-doc-generator
recommendation_score: 90
detection_files: [build.gradle.kts, build.gradle]
---

# dokka

## Overview

Dokka is the official documentation engine for Kotlin. It generates API docs from KDoc comments in multiple output formats: HTML (default), Javadoc-compatible, GFM (GitHub Flavored Markdown), and Jekyll. Apply the `org.jetbrains.dokka` Gradle plugin; for multi-module projects use `dokkaHtmlMultiModule` to produce a unified doc site with cross-module linking. KDoc syntax mirrors Javadoc but supports Markdown inline and block-level formatting.

## Architecture Patterns

### Installation & Setup

```kotlin
// build.gradle.kts (root)
plugins {
    id("org.jetbrains.dokka") version "1.9.20"
}

// For multi-module: apply to subprojects
subprojects {
    apply(plugin = "org.jetbrains.dokka")
}
```

```kotlin
// Submodule build.gradle.kts — per-module config
tasks.dokkaHtml {
    outputDirectory.set(layout.buildDirectory.dir("dokka"))
    dokkaSourceSets {
        named("main") {
            moduleName.set("MyModule")
            includes.from("Module.md")           // module-level documentation file
            sourceLink {
                localDirectory.set(file("src/main/kotlin"))
                remoteUrl.set(uri("https://github.com/org/repo/blob/main/src/main/kotlin").toURL())
                remoteLineSuffix.set("#L")
            }
            perPackageOption {
                matchingRegex.set(".*\\.internal.*")
                suppress.set(true)              // hide internal packages
            }
        }
    }
}
```

**Multi-module unified docs:**
```kotlin
// root build.gradle.kts
tasks.dokkaHtmlMultiModule {
    outputDirectory.set(rootDir.resolve("docs/api"))
    moduleName.set("My Project")
}
```

### Rule Categories

| Category | Pattern | Pipeline Severity |
|---|---|---|
| Missing public KDoc | Public class/fun without `/**` comment | WARNING |
| Missing `@param` | Function param without `@param` tag | INFO |
| Missing `@return` | Non-Unit return without `@return` tag | INFO |
| Undocumented `@throws` | Declared exception without `@throws` | WARNING |
| `@suppress` overuse | Public API marked `@suppress` | WARNING |

### Configuration Patterns

**KDoc syntax essentials:**
```kotlin
/**
 * Calculates compound interest over [periods] at the given [rate].
 *
 * Uses the standard formula: `P * (1 + r)^n`.
 *
 * @param principal Initial investment amount in cents (must be > 0).
 * @param rate Annual interest rate as a decimal (e.g. `0.05` for 5%).
 * @param periods Number of compounding periods.
 * @return Total value after compounding, in cents.
 * @throws IllegalArgumentException if [principal] is negative.
 * @sample com.example.FinanceTest.compoundInterestSample
 * @see SimpleInterestCalculator
 */
fun compoundInterest(principal: Long, rate: Double, periods: Int): Long
```

**`@sample` tag** — links to a function in the test/sample source set that is inlined verbatim into the docs:
```kotlin
// src/test/kotlin/com/example/FinanceTest.kt
fun compoundInterestSample() {
    val result = compoundInterest(100_00L, 0.05, 12)
    println(result) // 179_59
}
```

**`@suppress`** — hides a declaration from generated output without removing it:
```kotlin
/** @suppress Internal implementation detail. */
class InternalCache
```

**Module documentation file (`Module.md`):**
```markdown
# Module core

High-level description of this module's purpose, included at the top of the module's doc page.

## Package com.example.api

Public API contracts exposed to consumers.
```

### CI Integration

```yaml
# .github/workflows/docs.yml
- name: Generate Dokka HTML
  run: ./gradlew dokkaHtmlMultiModule

- name: Deploy to GitHub Pages
  uses: peaceiris/actions-gh-pages@v4
  with:
    github_token: ${{ secrets.GITHUB_TOKEN }}
    publish_dir: ./docs/api
```

```yaml
# Validate docs build in PRs without deploying
- name: Dokka check
  run: ./gradlew dokkaHtml --no-daemon
```

## Performance

- Dokka analysis is slow on large projects (30-120s for 100k+ LOC). Run `dokkaHtml` only on the publishing branch, not on every PR — use a separate CI job gated on `main`.
- Use Gradle build cache: Dokka tasks are cacheable. Set `org.gradle.caching=true` in `gradle.properties`.
- `perPackageOption { suppress.set(true) }` on internal packages reduces analysis scope noticeably.
- For incremental local development, run `dokkaHtml` on a single submodule rather than `dokkaHtmlMultiModule`.

## Security

- Dokka does not execute user code — no runtime security concern.
- Source links expose file paths and line numbers. Verify `remoteUrl` points to a public repo before publishing external docs. For private repos, omit `sourceLink` blocks.
- Avoid including credentials, API keys, or internal hostnames in KDoc comments — they will appear verbatim in generated HTML.

## Testing

```bash
# Generate HTML docs locally
./gradlew dokkaHtml

# Generate multi-module unified site
./gradlew dokkaHtmlMultiModule

# Generate Javadoc-compatible output (for library publishing)
./gradlew dokkaJavadoc

# Verify docs build succeeds (no output check, just exit code)
./gradlew dokkaHtml --dry-run

# Open generated docs
open build/dokka/html/index.html
```

## Dos

- Apply `org.jetbrains.dokka` per submodule and use `dokkaHtmlMultiModule` at the root for unified cross-module linking.
- Document every public API with KDoc — at minimum a one-line summary, `@param` for each parameter, and `@return` for non-Unit returns.
- Use `@sample` to include runnable examples from test sources — the examples are compiled and verified, not just copied text.
- Suppress internal packages via `perPackageOption { suppress.set(true) }` rather than marking every class `@suppress` individually.
- Add a `Module.md` file per submodule to give context at the module index page.
- Wire `sourceLink` to your VCS so readers can navigate from doc to source in one click.

## Don'ts

- Don't use `@suppress` on public API to paper over missing documentation — document it properly or make it internal.
- Don't run `dokkaHtmlMultiModule` on every push — it adds significant CI time. Gate it on the main/release branch.
- Don't put HTML tags in KDoc — Dokka renders Markdown; raw HTML is inconsistently supported across output formats.
- Don't skip the `moduleName` setting — unnamed modules produce confusing navigation in multi-module sites.
- Don't commit generated docs into the repo alongside source — publish to GitHub Pages or another static host.
- Don't rely on Dokka to catch documentation gaps automatically — enforce coverage with a custom Dokka plugin or a separate `kdoc-check` task.
