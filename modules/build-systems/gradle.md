# Gradle

## Overview

JVM build automation tool using a task DAG with Kotlin DSL. Default for Android and Kotlin; dominant in modern Java. Dramatically faster than Maven on multi-module projects via incremental compilation, build caching (local/remote), configuration cache, and parallel execution.

- **Use for:** JVM projects (Kotlin, Java, Scala), Android, polyglot monorepos with JVM core, highly customizable pipelines
- **Avoid for:** pure JS/TS (use npm/pnpm/Bun), pure Python (use uv/poetry), pure Go, pure Rust (use Cargo)
- **vs Maven:** task DAG vs fixed lifecycle, configuration cache, build caching, Kotlin DSL type safety, composable convention plugins vs parent POM inheritance

## Architecture Patterns

### Convention Plugin Pattern

Convention plugins are the single most important architectural pattern in Gradle. They replace the legacy `allprojects {}` and `subprojects {}` blocks with composable, testable, version-controlled build logic that lives in its own included build. Every multi-module project should use them.

**Directory structure:**
```
project-root/
  build-logic/
    build.gradle.kts
    settings.gradle.kts
    src/main/kotlin/
      kotlin-conventions.gradle.kts
      spring-conventions.gradle.kts
      test-conventions.gradle.kts
      publishing-conventions.gradle.kts
  gradle/
    libs.versions.toml
  core/
    build.gradle.kts
  adapter/
    build.gradle.kts
  app/
    build.gradle.kts
  settings.gradle.kts
  build.gradle.kts
```

**`build-logic/settings.gradle.kts`** — the included build's own settings:
```kotlin
dependencyResolutionManagement {
    versionCatalogs {
        create("libs") {
            from(files("../gradle/libs.versions.toml"))
        }
    }
}

rootProject.name = "build-logic"
```

**`build-logic/build.gradle.kts`** — declares `kotlin-dsl` so `.gradle.kts` files in `src/main/kotlin/` become precompiled script plugins:
```kotlin
plugins {
    `kotlin-dsl`
}

repositories {
    gradlePluginPortal()
    mavenCentral()
}

dependencies {
    implementation(libs.kotlin.gradle.plugin)
    implementation(libs.spring.boot.gradle.plugin)
    implementation(libs.kotlin.allopen)
    implementation(libs.kotlin.noarg)
}
```

Plugin dependency artifacts must be declared here because convention plugins apply them at configuration time. When a convention plugin contains `plugins { kotlin("jvm") }`, Gradle needs the Kotlin Gradle plugin on the classpath of the `build-logic` project. The version catalog (`libs`) is available because of the `versionCatalogs` block in `build-logic/settings.gradle.kts`, which references the same TOML file used by the root project — ensuring a single source of truth for all versions.

The critical insight about convention plugins is that they are regular Kotlin scripts compiled by the `kotlin-dsl` plugin. They can contain any Gradle API call, access extensions, apply other plugins, and configure tasks. When placed in `src/main/kotlin/`, their filename (minus `.gradle.kts`) becomes the plugin ID. For example, `kotlin-conventions.gradle.kts` is applied as `id("kotlin-conventions")`.

**`build-logic/src/main/kotlin/kotlin-conventions.gradle.kts`** — a complete convention plugin for Kotlin modules:
```kotlin
plugins {
    kotlin("jvm")
}

kotlin {
    jvmToolchain(21)

    compilerOptions {
        freeCompilerArgs.addAll(
            "-Xjsr305=strict",
            "-Xcontext-receivers",
        )
        allWarningsAsErrors.set(true)
        progressiveMode.set(true)
    }
}

tasks.withType<Test>().configureEach {
    useJUnitPlatform()
    jvmArgs("-XX:+EnableDynamicAgentLoading")
    testLogging {
        events("passed", "skipped", "failed")
        showStandardStreams = false
    }
}

dependencies {
    implementation(platform("org.jetbrains.kotlin:kotlin-bom"))
    implementation("org.jetbrains.kotlin:kotlin-stdlib")
}
```

Convention plugins compose by applying each other. The `spring-conventions` plugin applies `kotlin-conventions` as a prerequisite, inheriting all Kotlin compiler settings, test configuration, and dependencies. This layering eliminates duplication and ensures that changing a Kotlin compiler flag in one place propagates to every Spring module automatically.

**`build-logic/src/main/kotlin/spring-conventions.gradle.kts`** — layered on top of Kotlin conventions:
```kotlin
plugins {
    id("kotlin-conventions")
    kotlin("plugin.spring")
    id("org.springframework.boot")
    id("io.spring.dependency-management")
}

tasks.named<org.springframework.boot.gradle.tasks.bundling.BootJar>("bootJar") {
    archiveClassifier.set("")
    layered {
        enabled.set(true)
    }
}

// Spring-specific Kotlin compiler settings
kotlin {
    compilerOptions {
        freeCompilerArgs.addAll(
            "-Xjvm-default=all",
        )
    }
}
```

The test-conventions plugin demonstrates a cross-cutting concern: separating unit tests from integration tests. By using the JVM Test Suite plugin, it creates a distinct source set, classpath, and Gradle task for integration tests. This convention can be applied alongside any framework convention plugin — a module can be both a Spring module and a test-conventions module simultaneously.

**`build-logic/src/main/kotlin/test-conventions.gradle.kts`** — separates unit and integration tests:
```kotlin
plugins {
    id("kotlin-conventions")
    id("jvm-test-suite")
}

testing {
    suites {
        val test by getting(JvmTestSuite::class) {
            useJUnitJupiter()
        }

        register<JvmTestSuite>("integrationTest") {
            useJUnitJupiter()
            dependencies {
                implementation(project())
            }
            targets {
                all {
                    testTask.configure {
                        shouldRunAfter(test)
                    }
                }
            }
        }
    }
}

tasks.named("check") {
    dependsOn(testing.suites.named("integrationTest"))
}
```

### TOML Version Catalog

The version catalog (`gradle/libs.versions.toml`) centralizes all dependency coordinates and versions in one declarative file. It replaces `ext` blocks, `buildSrc` constants, and scattered version strings. Gradle generates type-safe accessors (`libs.spring.boot.starter.web`) that provide IDE autocompletion. The TOML format was chosen for its human readability and diff-friendliness — version upgrades show as clean single-line diffs in pull requests, making dependency review trivial.

The catalog has four sections: `[versions]` declares version constants, `[libraries]` maps library aliases to Maven coordinates (optionally referencing versions), `[bundles]` groups related libraries for bulk declaration, and `[plugins]` declares Gradle plugin aliases. Libraries managed by a BOM (like Spring Boot starters managed by `spring-boot-dependencies`) can omit `version.ref` — the BOM controls their version at resolution time.

**Complete `gradle/libs.versions.toml`:**
```toml
[versions]
kotlin = "2.1.0"
spring-boot = "3.4.1"
spring-dependency-management = "1.1.7"
kotest = "5.9.1"
mockk = "1.13.13"
testcontainers = "1.20.4"
detekt = "1.23.7"
flyway = "11.1.0"
jooq = "3.19.15"
jackson = "2.18.2"
coroutines = "1.10.1"

[libraries]
# Kotlin
kotlin-stdlib = { module = "org.jetbrains.kotlin:kotlin-stdlib" }
kotlin-reflect = { module = "org.jetbrains.kotlin:kotlin-reflect" }
kotlinx-coroutines-core = { module = "org.jetbrains.kotlinx:kotlinx-coroutines-core", version.ref = "coroutines" }
kotlinx-coroutines-reactor = { module = "org.jetbrains.kotlinx:kotlinx-coroutines-reactor", version.ref = "coroutines" }

# Spring Boot starters
spring-boot-starter-web = { module = "org.springframework.boot:spring-boot-starter-web" }
spring-boot-starter-webflux = { module = "org.springframework.boot:spring-boot-starter-webflux" }
spring-boot-starter-actuator = { module = "org.springframework.boot:spring-boot-starter-actuator" }
spring-boot-starter-security = { module = "org.springframework.boot:spring-boot-starter-security" }
spring-boot-starter-data-jpa = { module = "org.springframework.boot:spring-boot-starter-data-jpa" }
spring-boot-starter-test = { module = "org.springframework.boot:spring-boot-starter-test" }

# Persistence
flyway-core = { module = "org.flywaydb:flyway-core", version.ref = "flyway" }
flyway-database-postgresql = { module = "org.flywaydb:flyway-database-postgresql", version.ref = "flyway" }
jooq = { module = "org.jooq:jooq", version.ref = "jooq" }

# Serialization
jackson-module-kotlin = { module = "com.fasterxml.jackson.module:jackson-module-kotlin", version.ref = "jackson" }

# Testing
kotest-runner-junit5 = { module = "io.kotest:kotest-runner-junit5", version.ref = "kotest" }
kotest-assertions-core = { module = "io.kotest:kotest-assertions-core", version.ref = "kotest" }
kotest-property = { module = "io.kotest:kotest-property", version.ref = "kotest" }
mockk = { module = "io.mockk:mockk", version.ref = "mockk" }
testcontainers-junit-jupiter = { module = "org.testcontainers:junit-jupiter", version.ref = "testcontainers" }
testcontainers-postgresql = { module = "org.testcontainers:postgresql", version.ref = "testcontainers" }

# Build plugins (used as dependencies in build-logic)
kotlin-gradle-plugin = { module = "org.jetbrains.kotlin:kotlin-gradle-plugin", version.ref = "kotlin" }
spring-boot-gradle-plugin = { module = "org.springframework.boot:spring-boot-gradle-plugin", version.ref = "spring-boot" }
kotlin-allopen = { module = "org.jetbrains.kotlin:kotlin-allopen", version.ref = "kotlin" }
kotlin-noarg = { module = "org.jetbrains.kotlin:kotlin-noarg", version.ref = "kotlin" }

[bundles]
spring-web = ["spring-boot-starter-web", "spring-boot-starter-actuator", "jackson-module-kotlin"]
spring-webflux = ["spring-boot-starter-webflux", "spring-boot-starter-actuator", "jackson-module-kotlin", "kotlinx-coroutines-reactor"]
kotest = ["kotest-runner-junit5", "kotest-assertions-core", "kotest-property"]
testcontainers-pg = ["testcontainers-junit-jupiter", "testcontainers-postgresql"]

[plugins]
kotlin-jvm = { id = "org.jetbrains.kotlin.jvm", version.ref = "kotlin" }
kotlin-spring = { id = "org.jetbrains.kotlin.plugin.spring", version.ref = "kotlin" }
kotlin-jpa = { id = "org.jetbrains.kotlin.plugin.jpa", version.ref = "kotlin" }
spring-boot = { id = "org.springframework.boot", version.ref = "spring-boot" }
spring-dependency-management = { id = "io.spring.dependency-management", version.ref = "spring-dependency-management" }
detekt = { id = "io.gitlab.arturbosch.detekt", version.ref = "detekt" }
flyway = { id = "org.flywaydb.flyway", version.ref = "flyway" }
```

**Using the catalog in `build.gradle.kts`:**
```kotlin
plugins {
    alias(libs.plugins.kotlin.jvm) apply false
    alias(libs.plugins.spring.boot) apply false
}
```

**Using library accessors in module `build.gradle.kts`:**
```kotlin
dependencies {
    implementation(libs.bundles.spring.web)
    implementation(libs.flyway.core)
    implementation(libs.jooq)

    testImplementation(libs.bundles.kotest)
    testImplementation(libs.mockk)
    testImplementation(libs.spring.boot.starter.test)
    testRuntimeOnly(libs.bundles.testcontainers.pg)
}
```

Dots in TOML keys map to hyphens in accessors: `spring-boot-starter-web` becomes `libs.spring.boot.starter.web`. Bundles group related dependencies for cleaner declarations — prefer them for common stacks (web, testing, persistence). When a team has multiple microservices, the catalog ensures every service uses the same library versions, eliminating the "works on my service" class of dependency conflicts.

**Version catalog sharing across projects** — for organizations with multiple repositories, publish the version catalog as a Gradle platform:
```kotlin
// In a shared catalog project's build.gradle.kts
plugins {
    `version-catalog`
    `maven-publish`
}

catalog {
    versionCatalog {
        from(files("gradle/libs.versions.toml"))
    }
}

publishing {
    publications {
        create<MavenPublication>("catalog") {
            from(components["versionCatalog"])
        }
    }
}
```

Consuming projects import it in `settings.gradle.kts`:
```kotlin
dependencyResolutionManagement {
    versionCatalogs {
        create("libs") {
            from("com.example:version-catalog:1.0.0")
        }
    }
}
```

This pattern is particularly valuable in monorepo-to-multi-repo transitions where consistent dependency versions are critical.

### Composite Build Structure

Composite builds connect the `build-logic` convention plugin project to the root project via `includeBuild()`. This architecture replaces `buildSrc`, which triggers a full recompilation of all build logic on any change — even a whitespace edit in a comment. With composite builds, only the changed convention plugin recompiles, and the compilation is incremental. The difference is dramatic in practice: a `buildSrc` change on a 20-module project can add 10-30 seconds to every build; a composite build change adds 1-3 seconds.

Composite builds also enable dependency substitution — replacing published Maven artifacts with local source projects during development. This is invaluable for shared libraries: the CI resolves the published artifact from Nexus/Artifactory, while developers automatically use the local source checkout for instant feedback.

**Root `settings.gradle.kts`:**
```kotlin
pluginManagement {
    includeBuild("build-logic")
    repositories {
        gradlePluginPortal()
        mavenCentral()
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        mavenCentral()
    }
}

rootProject.name = "my-project"

include("core")
include("adapter")
include("adapter:input:api")
include("adapter:output:persistence")
include("app")
```

Key points:
- `includeBuild("build-logic")` makes convention plugins available by their file name (e.g., `id("kotlin-conventions")`).
- `repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)` enforces that all repository declarations happen in settings, not in individual `build.gradle.kts` files. This prevents repository drift.
- Use `include()` with colon-separated paths for nested modules. The filesystem path follows the colon hierarchy (`adapter/input/api/`).

**Multi-project composite builds for shared libraries:**
```kotlin
pluginManagement {
    includeBuild("build-logic")
    includeBuild("../shared-commons") {
        dependencySubstitution {
            substitute(module("com.example:shared-commons"))
                .using(project(":"))
        }
    }
}
```

This allows developing `shared-commons` locally while the CI resolves it from a Maven repository. The substitution is transparent to module `build.gradle.kts` files — they declare `implementation("com.example:shared-commons:1.0")` regardless.

### Multi-Module Layout

Each module applies convention plugins and declares only its unique dependencies. The convention plugin handles all boilerplate (compiler flags, test framework, Spring plugin application). This produces remarkably concise `build.gradle.kts` files — often 10-20 lines per module versus 80-150 lines in projects that inline everything. The brevity is not just aesthetic: it means every line in a module's build file represents a deliberate architectural decision (which plugins compose this module, which projects does it depend on, which unique libraries does it need).

**`core/build.gradle.kts`** — domain module, no framework dependencies:
```kotlin
plugins {
    id("kotlin-conventions")
}

dependencies {
    implementation(libs.kotlinx.coroutines.core)

    testImplementation(libs.bundles.kotest)
    testImplementation(libs.mockk)
}
```

**`adapter/output/persistence/build.gradle.kts`** — persistence adapter:
```kotlin
plugins {
    id("kotlin-conventions")
    id("spring-conventions")
    alias(libs.plugins.kotlin.jpa)
}

dependencies {
    implementation(project(":core"))
    implementation(libs.spring.boot.starter.data.jpa)
    implementation(libs.flyway.core)
    implementation(libs.flyway.database.postgresql)

    runtimeOnly("org.postgresql:postgresql")

    testImplementation(libs.bundles.kotest)
    testImplementation(libs.spring.boot.starter.test)
    testRuntimeOnly(libs.bundles.testcontainers.pg)
}
```

**`app/build.gradle.kts`** — the Spring Boot application module:
```kotlin
plugins {
    id("spring-conventions")
    id("test-conventions")
}

dependencies {
    implementation(project(":core"))
    implementation(project(":adapter:input:api"))
    implementation(project(":adapter:output:persistence"))
    implementation(libs.bundles.spring.web)
    implementation(libs.spring.boot.starter.security)

    testImplementation(libs.bundles.kotest)
    testImplementation(libs.mockk)
    testImplementation(libs.spring.boot.starter.test)
}
```

Note how each module declares only what it needs. The convention plugins provide the rest. Module boundaries enforce dependency direction: `core` has zero framework imports, `adapter` depends on `core`, and `app` wires everything together.

**Dependency configuration scopes:**
- `implementation` — compile and runtime, not exposed to consumers. Use this by default.
- `api` — compile and runtime, exposed to consumers. Use only in libraries where the dependency is part of the public API.
- `runtimeOnly` — needed at runtime but not at compile time (JDBC drivers, logging backends).
- `compileOnly` — needed at compile time but not at runtime (annotation processors, provided scopes).
- `testImplementation` — test compile and runtime.
- `testRuntimeOnly` — test runtime only (JUnit platform launcher, Testcontainers JDBC driver).

Prefer `implementation` over `api` for all internal project modules. Leaking transitive dependencies through `api` couples consumers to implementation details and slows compilation (every consumer recompiles when the transitive dependency changes).

**Platform (BOM) alignment** — when multiple libraries share a version family (e.g., Jackson modules, Spring Cloud modules), use a platform dependency to enforce consistent versions:
```kotlin
dependencies {
    implementation(platform(libs.spring.boot.dependencies))
    implementation("org.springframework.boot:spring-boot-starter-web") // version managed by BOM
    implementation("org.springframework.boot:spring-boot-starter-actuator") // version managed by BOM
}
```

The platform enforces version alignment: all Spring Boot starters resolve to the same version, regardless of transitive pulls. For strict alignment (fail if any dependency diverges), use `enforcedPlatform()`:
```kotlin
dependencies {
    implementation(enforcedPlatform(libs.jackson.bom))
    implementation("com.fasterxml.jackson.core:jackson-databind")
    implementation("com.fasterxml.jackson.module:jackson-module-kotlin")
}
```

**Dependency constraints for vulnerability management** — when a transitive dependency has a known CVE, override its version without changing the direct dependency:
```kotlin
dependencies {
    constraints {
        implementation("org.apache.commons:commons-text:1.12.0") {
            because("CVE-2022-42889 — text4shell vulnerability in versions < 1.10.0")
        }
    }
}
```

This is cleaner than `force = true` (which is a blunt instrument) and documents the reason for the override in a way that survives dependency upgrades.

**Multi-module dependency analysis:**
```bash
# Show all dependencies for a specific module
./gradlew :adapter:output:persistence:dependencies --configuration runtimeClasspath

# Find where a specific dependency is pulled from
./gradlew :app:dependencyInsight --dependency jackson-databind --configuration runtimeClasspath
```

The `dependencyInsight` report shows the dependency resolution path, including which dependency pulled it in transitively, which version was selected, and why (conflict resolution, BOM enforcement, constraint). Run this before every dependency upgrade to understand the blast radius.

## Configuration

### Development

Gradle's configuration is layered: project-level `gradle.properties` (committed, shared by team), user-level `~/.gradle/gradle.properties` (not committed, per-developer overrides), command-line flags (`-P`, `-D`), and environment variables (`ORG_GRADLE_PROJECT_*`). The resolution order is: command line > environment > user-level > project-level. This layering allows teams to establish sensible defaults while letting individual developers and CI systems override them.

**`gradle.properties`** — committed to version control, tuned for developer workstations:
```properties
# Parallel module compilation
org.gradle.parallel=true

# Build cache (local by default)
org.gradle.caching=true

# Configuration cache (avoids re-evaluating build scripts)
org.gradle.configuration-cache=true

# JVM args for the Gradle Daemon
org.gradle.jvmargs=-Xmx4g -XX:+UseG1GC -XX:+HeapDumpOnOutOfMemoryError \
  -Dfile.encoding=UTF-8

# Kotlin incremental compilation
kotlin.incremental=true

# Kotlin daemon JVM args
kotlin.daemon.jvmargs=-Xmx2g

# Disable Kotlin daemon fallback (fail fast instead of silent fallback to in-process)
kotlin.daemon.useFallbackStrategy=false
```

**`gradle-wrapper.properties`** — pins the exact Gradle version:
```properties
distributionBase=GRADLE_USER_HOME
distributionPath=wrapper/dists
distributionUrl=https\://services.gradle.org/distributions/gradle-8.12-bin.zip
distributionSha256Sum=7a00d51fb93147819aab76024feece20b6b84e420694f1f43a3571bb4e581568
networkTimeout=10000
validateDistributionUrl=true
zipStoreBase=GRADLE_USER_HOME
zipStorePath=wrapper/dists
```

Always include `distributionSha256Sum` to verify Wrapper integrity. Generate it with `gradle wrapper --gradle-version 8.12 --distribution-type bin` and commit the resulting `gradle-wrapper.jar`, `gradle-wrapper.properties`, `gradlew`, and `gradlew.bat`. The Wrapper is the only Gradle file that should be committed as a binary (`gradle-wrapper.jar`) — it bootstraps the exact Gradle version without requiring a pre-installed Gradle on the machine. This ensures every developer and CI runner uses the identical Gradle version, eliminating "works with my Gradle" problems.

**Gradle Wrapper upgrade workflow:**
```bash
# Upgrade Wrapper to a new version
./gradlew wrapper --gradle-version 8.12 --distribution-type bin

# Verify the generated checksum
cat gradle/wrapper/gradle-wrapper.properties | grep distributionSha256Sum

# Commit all four Wrapper files
git add gradle/wrapper/gradle-wrapper.jar \
        gradle/wrapper/gradle-wrapper.properties \
        gradlew gradlew.bat
git commit -m "chore: upgrade Gradle Wrapper to 8.12"
```

**`~/.gradle/gradle.properties`** (user-level, not committed) — for local overrides and secrets:
```properties
# Override JVM args for machines with more RAM
org.gradle.jvmargs=-Xmx8g -XX:+UseG1GC

# Publishing credentials (never commit these)
mavenCentralUsername=...
mavenCentralPassword=...
```

### Production

CI environments differ fundamentally from developer workstations: runners are ephemeral (no daemon reuse), builds compete for shared resources (memory, CPU), and reproducibility trumps speed. The configuration below reflects these constraints.

**CI pipeline settings** — optimized for ephemeral runners:
```bash
./gradlew build \
  --no-daemon \
  --build-cache \
  --parallel \
  --console=plain \
  --warning-mode=all \
  -Dorg.gradle.workers.max=4
```

- `--no-daemon` — CI runners are ephemeral; the daemon adds startup cost for a single invocation with no subsequent reuse.
- `--build-cache` — still valuable; populate from a remote cache.
- `--console=plain` — no ANSI escape codes in CI logs.
- `--warning-mode=all` — surface all deprecation warnings so they are caught early.

**Remote build cache configuration (in `settings.gradle.kts`):**
```kotlin
buildCache {
    local {
        isEnabled = true
    }
    remote<HttpBuildCache> {
        url = uri(providers.gradleProperty("buildCacheUrl").getOrElse("https://cache.example.com/cache/"))
        isPush = System.getenv("CI") != null
        credentials {
            username = providers.gradleProperty("buildCacheUser").orNull
            password = providers.gradleProperty("buildCachePassword").orNull
        }
    }
}
```

Remote cache is read-only for developers (`isPush = false` by default) and write-enabled on CI (`isPush = true` when `CI` env var is set). This prevents cache pollution from local builds while allowing CI to populate the cache for everyone.

**GitHub Actions example:**
```yaml
- name: Setup Gradle
  uses: gradle/actions/setup-gradle@v4
  with:
    cache-read-only: ${{ github.ref != 'refs/heads/main' }}

- name: Build
  run: ./gradlew build --no-daemon --parallel --warning-mode=all

- name: Publish test results
  uses: mikepenz/action-junit-report@v4
  if: always()
  with:
    report_paths: '**/build/test-results/test/TEST-*.xml'
```

The `gradle/actions/setup-gradle` action handles Gradle distribution caching, dependency caching, and build cache coordination automatically. Use `cache-read-only` on non-main branches to avoid cache thrashing from feature branches.

**Dependency lock files for reproducible CI builds:**
```bash
# Generate lock files (run once, commit the results)
./gradlew dependencies --write-locks
```

This creates `gradle.lockfile` in each module directory, pinning every transitive dependency to an exact version. CI builds verify the lock file matches the resolution — if a transitive dependency shifts unexpectedly (e.g., a BOM update pulls in a different version), the build fails immediately rather than silently introducing untested code.

**Gradle scan for CI diagnostics:**
```bash
./gradlew build --scan --no-daemon
```

Build scans (hosted by Develocity or the free Gradle public scan service) capture the complete build timeline, dependency resolution graph, task execution details, test results, and configuration cache hits/misses. They are invaluable for diagnosing CI slowdowns — the scan URL is printed at the end of every build and can be shared with the team.

## Performance

**Configuration cache** is the single biggest performance win in modern Gradle. It serializes the fully-configured task graph after the first run and reuses it on subsequent runs, skipping all build script evaluation, plugin application, and dependency resolution. On a 30-module project, this typically saves 5-15 seconds per build. Enable it with `org.gradle.configuration-cache=true` in `gradle.properties`. Not all plugins support it yet — Gradle reports incompatibilities at runtime with clear error messages and a link to the HTML report.

**Build cache** avoids re-executing tasks whose inputs have not changed. The local cache (`~/.gradle/caches/build-cache-1/`) stores outputs keyed by task input hashes. The remote cache (Develocity, HTTP, or cloud storage) shares outputs across machines. For CI, the remote cache typically reduces build times by 40-70% after the first population. Declare task inputs and outputs explicitly (`@InputFiles`, `@OutputDirectory`) for custom tasks — without them, caching does not work.

**Parallel execution** (`org.gradle.parallel=true`) runs independent modules concurrently. Combined with `org.gradle.workers.max=N`, it saturates available CPU cores. The Worker API extends parallelism within a single task — use it for code generation, file processing, or test execution that can be split across workers.

**Task avoidance API** — always use `tasks.register()` instead of `tasks.create()` (or the `task()` shorthand). Registration defers task creation until the task is actually needed, avoiding object allocation and configuration for tasks that are never executed:
```kotlin
// Correct — lazy registration
tasks.register<Copy>("copyDocs") {
    from("src/docs")
    into(layout.buildDirectory.dir("docs"))
}

// Wrong — eager creation (always allocates, always configures)
tasks.create<Copy>("copyDocs") {
    from("src/docs")
    into(layout.buildDirectory.dir("docs"))
}
```

**Avoid `allprojects {}`, `subprojects {}`, and `afterEvaluate {}`** — the first two force Gradle to configure every project in the build, defeating configuration-on-demand and the configuration cache, while creating implicit cross-project coupling. `afterEvaluate` creates implicit ordering coupling within a project — it runs after the current project's build script is evaluated, but the exact timing relative to other plugins is unpredictable. Use convention plugins instead (applied only by the modules that need them) and `pluginManager.withPlugin()` for conditional plugin configuration.

**Profiling slow builds** — before optimizing, measure. Gradle provides several diagnostic tools:
```bash
# Profile a build (generates HTML report in build/reports/profile/)
./gradlew build --profile

# Detailed logging of task execution times
./gradlew build --info 2>&1 | grep -E "^> Task|executed in"

# Build scan (the gold standard for performance analysis)
./gradlew build --scan
```

The `--profile` report shows time spent in configuration, dependency resolution, and task execution. The build scan provides a waterfall timeline that visualizes parallel execution, cache hits, and bottleneck tasks. Focus optimization efforts on the critical path — the longest chain of dependent tasks.

**Custom task cacheability** — any task that declares inputs and outputs can be cached. For custom tasks, annotate properties with `@Input`, `@InputFiles`, `@InputDirectory`, `@OutputFile`, or `@OutputDirectory`:
```kotlin
@CacheableTask
abstract class GenerateApi : DefaultTask() {
    @get:InputFile
    @get:PathSensitive(PathSensitivity.RELATIVE)
    abstract val specFile: RegularFileProperty

    @get:OutputDirectory
    abstract val outputDir: DirectoryProperty

    @TaskAction
    fun generate() {
        // Generate API client from OpenAPI spec
    }
}
```

The `@PathSensitive(PathSensitivity.RELATIVE)` annotation tells Gradle that only the relative path matters for cache key computation — moving the project directory does not invalidate the cache. Without this annotation, absolute paths are used, which breaks cross-machine caching.

**Dependency resolution optimization:**
- Use `dependencyResolutionManagement` in `settings.gradle.kts` with `RepositoriesMode.FAIL_ON_PROJECT_REPOS` to centralize repository declarations.
- Use version catalogs instead of platform BOMs where possible — they resolve at configuration time and produce better error messages.
- Avoid dynamic versions (`1.+`, `latest.release`) — they require network checks on every build and break reproducibility.

**Gradle Daemon tuning** — for developer workstations, the daemon persists between builds and amortizes JVM startup, classloading, and JIT compilation. Tune its memory in `gradle.properties`:
```properties
org.gradle.jvmargs=-Xmx4g -XX:+UseG1GC -XX:MaxMetaspaceSize=512m
```
The daemon idles for 3 hours by default. On CI, use `--no-daemon` — ephemeral runners gain nothing from persistence.

**Incremental compilation** — Kotlin and Java compilers track file-level dependencies and only recompile changed files plus their dependents. Ensure `kotlin.incremental=true` (default since Kotlin 1.4). For Java, Gradle's built-in incremental compiler is enabled by default. Avoid annotation processors that break incremental compilation (check Gradle's `--info` output for "full recompilation" warnings).

**Build scan analysis workflow** — when a CI build is slower than expected:
1. Open the build scan URL from the build output.
2. Check the "Performance" tab: look for configuration time > 5s (convention plugin issue), dependency resolution time > 10s (repository or network issue), or task execution dominated by a single task (bottleneck).
3. Check the "Timeline" tab: look for gaps where no tasks execute (dependency chain problem) or tasks that run sequentially when they should run in parallel (missing `mustRunAfter` declarations or resource locks).
4. Check the "Build Cache" tab: look for cache misses on tasks that should be cached (missing input/output annotations) or cache evictions (cache size too small).
5. Compare with a baseline scan from main branch to identify regressions.

**Avoiding expensive work at configuration time** — a common performance mistake is performing heavy computation or resolving configurations during the configuration phase (when Gradle evaluates `build.gradle.kts` files) rather than the execution phase (when tasks run). This defeats the configuration cache and slows every build. Any I/O, network calls, file scanning, or expensive computation in the body of a `build.gradle.kts`, or inside a `tasks.create { }` or realized `tasks.register { }` block (but outside `doLast`/`doFirst`/`@TaskAction`), runs at configuration time rather than execution time. Move all such work into task actions:
```kotlin
// Wrong — resolves at configuration time
val jarFiles = configurations.runtimeClasspath.get().files
println("Found ${jarFiles.size} jars")

// Correct — resolves at execution time via Provider API
tasks.register("listJars") {
    val classpath = configurations.runtimeClasspath
    doLast {
        println("Found ${classpath.get().files.size} jars")
    }
}
```

The Provider API (`Property<T>`, `Provider<T>`, `FileCollection`) defers resolution until the value is actually needed. This is the foundation of configuration cache compatibility and task avoidance.

## Security

Build system security is often overlooked because build scripts are not "production code" — but they execute with full filesystem and network access on every developer machine and CI runner, making them a high-value supply chain attack vector. Gradle's security features address three threat surfaces: distribution integrity (Wrapper verification), dependency integrity (verification metadata), and secret management (credential isolation).

**Gradle Wrapper verification** is the first line of defense. The Wrapper (`gradlew`) downloads and executes a specific Gradle distribution — if an attacker replaces `gradle-wrapper.jar` or modifies the distribution URL, they get arbitrary code execution on every developer machine and CI runner. Always:
1. Commit `gradle-wrapper.jar` to version control.
2. Include `distributionSha256Sum` in `gradle-wrapper.properties`.
3. Use `gradle wrapper --gradle-version X.Y --distribution-type bin` to regenerate.
4. Verify the checksum against Gradle's official release page.

**Dependency verification** (`gradle/verification-metadata.xml`) validates checksums and PGP signatures of all downloaded dependencies:
```bash
# Generate verification metadata (run once, commit the result)
./gradlew --write-verification-metadata sha256,pgp help

# Verify on every build (automatic when the file exists)
./gradlew build
```

This generates an XML file containing SHA-256 checksums and PGP key fingerprints for every downloaded artifact. Gradle checks these on every resolve — if an artifact has been tampered with (supply chain attack) or a new untrusted artifact appears (dependency confusion), the build fails with a clear error message. CI should fail on verification failures. Update the file when upgrading dependencies by re-running `--write-verification-metadata`. Review the diff to ensure only expected artifacts changed.

**Trusted PGP keys** — for dependencies signed with PGP, add trusted keys to the verification metadata to avoid false positives:
```xml
<!-- gradle/verification-metadata.xml (excerpt) -->
<verification-metadata>
    <configuration>
        <verify-metadata>true</verify-metadata>
        <verify-signatures>true</verify-signatures>
        <trusted-keys>
            <trusted-key id="6F538074CCEBF35F28AF9B066A0975F26D609814" group="org.jetbrains.kotlin"/>
            <trusted-key id="EFE8086F9E93774E" group="org.springframework"/>
        </trusted-keys>
    </configuration>
</verification-metadata>
```

**No secrets in `gradle.properties`** (project-level, committed). Use environment variables or the user-level `~/.gradle/gradle.properties` (not committed) for credentials:
```kotlin
// In build script — read from env
val mavenUser = providers.environmentVariable("MAVEN_USERNAME")
val mavenPass = providers.environmentVariable("MAVEN_PASSWORD")

publishing {
    repositories {
        maven {
            url = uri("https://maven.example.com/releases")
            credentials {
                username = mavenUser.get()
                password = mavenPass.get()
            }
        }
    }
}
```

**Plugin portal vs custom repositories** — the Gradle Plugin Portal (`plugins.gradle.org`) is public and not curated with the same rigor as Maven Central. For enterprise builds, restrict plugin resolution to your internal repository:
```kotlin
// settings.gradle.kts
pluginManagement {
    repositories {
        maven {
            url = uri("https://nexus.internal.example.com/repository/gradle-plugins/")
        }
        gradlePluginPortal() // fallback — remove in high-security environments
    }
}
```

**Signing artifacts for publishing:**
```kotlin
plugins {
    signing
    `maven-publish`
}

signing {
    val signingKey = providers.environmentVariable("GPG_SIGNING_KEY")
    val signingPassword = providers.environmentVariable("GPG_SIGNING_PASSWORD")
    useInMemoryPgpKeys(signingKey.get(), signingPassword.get())
    sign(publishing.publications)
}
```

Never store GPG keys in the repository or in `gradle.properties`. Pass them via CI secrets and environment variables.

**Repository security** — limit which repositories can serve which dependencies to prevent dependency confusion attacks:
```kotlin
// settings.gradle.kts
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        exclusiveContent {
            forRepository {
                maven {
                    url = uri("https://nexus.internal.example.com/repository/internal/")
                }
            }
            filter {
                includeGroupByRegex("com\\.example\\..*")
            }
        }
        mavenCentral()
    }
}
```

The `exclusiveContent` block ensures that `com.example.*` dependencies are only resolved from the internal repository — an attacker cannot publish a same-named package to Maven Central and hijack the build. This is the Gradle equivalent of npm's scope registry mapping.

**Supply chain hardening checklist:**
- Pin all plugin versions in the version catalog (never use `latest`).
- Enable dependency verification and commit the metadata file.
- Use `--write-locks` to generate dependency lock files for reproducible builds.
- Run `./gradlew dependencies --configuration runtimeClasspath` in CI and diff against the previous run to detect unexpected transitive changes.
- Audit new dependencies with `dependencyInsight` before adding them.
- Configure `exclusiveContent` blocks to prevent dependency confusion attacks — ensure internal group IDs can only resolve from internal repositories.
- Use Gradle's `--scan` to audit the full dependency tree for unexpected transitive dependencies after any version upgrade.

## Testing

**`gradle test` vs `gradle check`** — `test` runs the default test suite only. `check` runs `test` plus all verification tasks (static analysis, integration tests if wired, code coverage thresholds). Use `check` in CI; use `test` during development for faster feedback. The `build` task depends on `check` plus `assemble`, so `./gradlew build` is the full CI command that compiles, tests, verifies, and packages.

**Test reporting** — Gradle generates HTML and XML test reports per module. For multi-module projects, aggregate them:
```kotlin
// Root build.gradle.kts
tasks.register<TestReport>("aggregateTestReport") {
    destinationDirectory.set(layout.buildDirectory.dir("reports/tests/all"))
    testResults.from(subprojects.map { it.tasks.withType<Test>() })
}
```

For CI, the JUnit XML reports at `build/test-results/test/TEST-*.xml` are consumed by CI platforms (GitHub Actions, GitLab CI, Jenkins) to display test results inline in PRs. Configure the path in your CI pipeline to surface failures without requiring developers to download artifacts.

**JVM Test Suite plugin** (built into Gradle 7.3+) is the standard way to separate unit, integration, and functional tests:
```kotlin
testing {
    suites {
        val test by getting(JvmTestSuite::class) {
            useJUnitJupiter()
        }

        register<JvmTestSuite>("integrationTest") {
            useJUnitJupiter()
            dependencies {
                implementation(project())
                implementation(libs.spring.boot.starter.test)
                implementation(libs.testcontainers.junit.jupiter)
            }
            targets {
                all {
                    testTask.configure {
                        shouldRunAfter(test)
                        systemProperty("spring.profiles.active", "integration")
                    }
                }
            }
        }
    }
}

tasks.named("check") {
    dependsOn(testing.suites.named("integrationTest"))
}
```

This creates a separate source set (`src/integrationTest/kotlin`), classpath, and task (`integrationTest`) with its own dependencies. The `shouldRunAfter` ordering ensures unit tests run first (fail fast), but both can execute in parallel across modules.

**Test distribution and parallelism:**
```kotlin
tasks.withType<Test>().configureEach {
    maxParallelForks = (Runtime.getRuntime().availableProcessors() / 2).coerceAtLeast(1)
    forkEvery = 100 // restart JVM every 100 tests to prevent memory leaks
}
```

Combine with `org.gradle.parallel=true` for cross-module parallelism and `maxParallelForks` for within-module parallelism. For Testcontainers-based tests, keep `maxParallelForks = 1` per module to avoid port conflicts, but let Gradle's parallel execution handle cross-module concurrency.

**Test filtering for fast feedback during development:**
```bash
# Run a single test class
./gradlew :core:test --tests "com.example.core.UserServiceTest"

# Run tests matching a pattern
./gradlew :core:test --tests "*UserService*"

# Run a single test method
./gradlew :core:test --tests "com.example.core.UserServiceTest.should create user with valid email"

# Rerun only failed tests from the last run
./gradlew :core:test --rerun

# Run tests continuously on file changes
./gradlew :core:test --continuous
```

The `--continuous` flag watches source files and reruns tests on every save — essential for TDD workflows. Combined with module-specific targeting (`:core:test`), developers get sub-second feedback loops on unit tests.

**Build logic testing with TestKit** — convention plugins are code and deserve tests:
```kotlin
// build-logic/src/test/kotlin/KotlinConventionsTest.kt
class KotlinConventionsTest {
    @TempDir
    lateinit var projectDir: File

    @Test
    fun `kotlin-conventions compiles Kotlin sources`() {
        projectDir.resolve("settings.gradle.kts").writeText("")
        projectDir.resolve("build.gradle.kts").writeText("""
            plugins {
                id("kotlin-conventions")
            }
        """.trimIndent())
        projectDir.resolve("src/main/kotlin/Hello.kt").apply {
            parentFile.mkdirs()
            writeText("fun main() = println(\"hello\")")
        }

        val result = GradleRunner.create()
            .withProjectDir(projectDir)
            .withArguments("compileKotlin", "--stacktrace")
            .withPluginClasspath()
            .build()

        assertThat(result.task(":compileKotlin")?.outcome).isEqualTo(TaskOutcome.SUCCESS)
    }
}
```

TestKit spins up a real Gradle build in an isolated directory, applies your convention plugin, and asserts on task outcomes and output. This catches configuration errors, missing plugin dependencies, and task wiring issues before they reach downstream projects.

**Verifying convention plugins work correctly:**
- Test each convention plugin in isolation (single module, minimal source).
- Test plugin composition (two convention plugins applied together).
- Test that configuration cache is compatible (`--configuration-cache` flag in TestKit).
- Test upgrade paths: apply the plugin to a project using an older Gradle version to catch API breakage.

**Testing configuration cache compatibility:**
```kotlin
@Test
fun `kotlin-conventions is configuration-cache compatible`() {
    projectDir.resolve("settings.gradle.kts").writeText("")
    projectDir.resolve("build.gradle.kts").writeText("""
        plugins {
            id("kotlin-conventions")
        }
    """.trimIndent())
    projectDir.resolve("src/main/kotlin/Hello.kt").apply {
        parentFile.mkdirs()
        writeText("fun main() = println(\"hello\")")
    }

    // First run populates the configuration cache
    GradleRunner.create()
        .withProjectDir(projectDir)
        .withArguments("compileKotlin", "--configuration-cache")
        .withPluginClasspath()
        .build()

    // Second run reuses the cached configuration
    val result = GradleRunner.create()
        .withProjectDir(projectDir)
        .withArguments("compileKotlin", "--configuration-cache")
        .withPluginClasspath()
        .build()

    assertThat(result.output).contains("Reusing configuration cache")
}
```

This two-phase test catches configuration cache incompatibilities that only surface on the second run. Common causes: build scripts that read system properties at configuration time, tasks that reference `Project` objects (which are not serializable), and plugins that use global mutable state.

**Testing dependency resolution in convention plugins:**
```kotlin
@Test
fun `spring-conventions applies spring boot dependency management`() {
    projectDir.resolve("settings.gradle.kts").writeText("")
    projectDir.resolve("build.gradle.kts").writeText("""
        plugins {
            id("spring-conventions")
        }

        dependencies {
            implementation("org.springframework.boot:spring-boot-starter-web")
        }
    """.trimIndent())

    val result = GradleRunner.create()
        .withProjectDir(projectDir)
        .withArguments("dependencies", "--configuration", "runtimeClasspath")
        .withPluginClasspath()
        .build()

    assertThat(result.output).contains("org.springframework.boot:spring-boot-starter-web")
    assertThat(result.task(":dependencies")?.outcome).isEqualTo(TaskOutcome.SUCCESS)
}
```

Convention plugin tests serve as living documentation: they demonstrate exactly which plugins are applied, which dependencies are included, and which tasks are configured. When a team member asks "what does `spring-conventions` give me?", the tests are the definitive answer.

## Dos

- Use convention plugins (`build-logic/` composite build) instead of `allprojects {}` / `subprojects {}` / `afterEvaluate {}` for all shared build configuration. Convention plugins are composable, testable, and configuration-cache-friendly. They turn build logic into versioned, reviewable code rather than scattered script blocks.
- Use version catalogs (`gradle/libs.versions.toml`) for all dependency versions. Never hardcode version strings in `build.gradle.kts` files. The catalog provides a single source of truth that makes dependency upgrades a one-line diff.
- Pin the Gradle Wrapper version and commit `gradle-wrapper.jar`, `gradlew`, and `gradlew.bat`. Include `distributionSha256Sum` for integrity verification. The Wrapper is your guarantee that every team member and CI runner uses the exact same Gradle version.
- Enable the configuration cache (`org.gradle.configuration-cache=true`) and fix compatibility issues as they arise. The performance gain compounds with project size — 20%+ faster builds on typical multi-module projects.
- Use `implementation` instead of `api` for all internal module dependencies. Reserve `api` for public library modules where the dependency is part of the published API surface. Leaking transitive dependencies through `api` creates invisible coupling.
- Use `--build-scan` (or `--scan` with Develocity plugin) to debug slow builds, dependency resolution issues, and task execution problems. Build scans are the single best debugging tool for Gradle — they capture the complete build model and timeline in a shareable URL.
- Declare explicit inputs and outputs on all custom tasks using `@Input`, `@InputFiles`, `@OutputFile`, `@OutputDirectory` annotations. Without them, the build cache and up-to-date checking cannot function, and tasks re-execute unnecessarily on every build.
- Use the Kotlin DSL (`build.gradle.kts`) for type-safe builds with IDE autocompletion, refactoring support, and compile-time error detection. The Kotlin DSL catches configuration errors at script compilation time rather than at task execution time.
- Centralize repository declarations in `settings.gradle.kts` with `RepositoriesMode.FAIL_ON_PROJECT_REPOS` to prevent repository drift across modules. This ensures every module resolves dependencies from the same set of repositories.
- Use `tasks.register()` (lazy) instead of `tasks.create()` (eager) for all custom task definitions to benefit from task avoidance. Lazy registration defers object allocation until the task is actually needed in the execution graph.
- Use `pluginManager.withPlugin("plugin-id") { ... }` to conditionally configure tasks or extensions from another plugin. This fires exactly when the plugin is applied, regardless of script evaluation order, and replaces the fragile `afterEvaluate` pattern. If your plugin requires the other plugin, apply it explicitly with `pluginManager.apply("plugin-id")` instead.
- Wire task inputs lazily using `Provider.map()` and `Provider.flatMap()` instead of resolving values at configuration time. For example, use `someProperty.map { "prefix=$it" }` rather than `"prefix=${someProperty.get()}"`. This preserves configuration cache compatibility and ensures values are only resolved when the task actually executes.

## Don'ts

- Don't use `buildSrc/` for convention plugins — it causes a full rebuild of all build logic on any change, even a whitespace edit in a comment. The rebuild invalidates the entire configuration cache for all modules. Use `build-logic/` as an included build instead, which supports incremental compilation and isolated cache invalidation.
- Don't hardcode dependency versions in `build.gradle.kts` files. Every version string belongs in `gradle/libs.versions.toml`. Scattered versions across 15 modules make it impossible to answer "which version of Jackson are we using?" without grepping the entire codebase. Version catalogs provide a single authoritative answer.
- Don't use the deprecated `compile`, `runtime`, `testCompile`, or `testRuntime` configurations. They were removed in Gradle 7.0 and will produce build errors on any modern Gradle version. Use `implementation`, `runtimeOnly`, `testImplementation`, and `testRuntimeOnly` — these configurations properly encapsulate dependencies and enable faster compilation through better classpath isolation.
- Don't disable the configuration cache without documenting the specific incompatibility in a code comment with a link to the plugin issue. File an issue with the offending plugin and track the fix. Disabling it project-wide for one plugin's bug punishes every developer's build time for the plugin author's technical debt.
- Don't put business logic in build scripts. Build scripts configure the build graph — they should not contain application code, data transformations, or complex algorithms. If a build script exceeds 50 lines of custom logic, extract it into a convention plugin, a custom Gradle plugin, or a standalone CLI tool.
- Don't use `allprojects {}`, `subprojects {}`, or `afterEvaluate {}` blocks. `allprojects`/`subprojects` force Gradle to configure every project in the build (even those not needed for the current task), break configuration-on-demand, prevent the configuration cache from caching individual project configurations, and create implicit coupling where adding a module inherits configuration it may not want. `afterEvaluate` is fragile because it depends on script evaluation order — minor structural changes (reordering plugin application, moving a module) silently break configuration that appeared to work. Convention plugins solve every use case these blocks addressed, with explicit opt-in rather than implicit inheritance. When you need to configure a task from another plugin conditionally, use `pluginManager.withPlugin("java") { ... }` instead of `afterEvaluate` — it fires exactly when the plugin is applied, regardless of ordering.
- Don't use `ext` properties or `extra` for version management. They are stringly-typed, invisible to IDE autocompletion, not refactoring-safe, and produce unhelpful error messages when misspelled. Version catalogs replace them with generated type-safe accessors that fail at compile time if the alias does not exist.
- Don't use the Groovy DSL (`build.gradle`) for new projects. The Kotlin DSL provides compile-time safety, autocompletion, navigation to source, and refactoring support that Groovy fundamentally cannot offer. The Groovy DSL is maintained for backward compatibility only; Gradle's own documentation defaults to Kotlin DSL.
- Don't use dynamic dependency versions (`1.+`, `latest.release`, `SNAPSHOT` in release builds). They break build reproducibility — the same commit can produce different artifacts depending on when it was built. Use exact versions in the version catalog and dependency locking (`--write-locks`) for transitive dependencies.
- Don't use internal Gradle APIs (`org.gradle.internal.*` packages). They change or disappear without notice between Gradle versions — even minor releases. If a build or plugin depends on internal APIs, it will break unpredictably on Gradle upgrades. Use only the public API (`org.gradle.api.*`). If no public API exists for what you need, file a Gradle feature request rather than reaching into internals.
- Don't ignore deprecation warnings in build output. Gradle deprecates APIs with multi-version lead time (typically 2-3 major versions) and eventually removes them. Run with `--warning-mode=all` in CI and treat deprecation warnings as build failures in your quality gate. Fixing them incrementally is trivial; fixing 50 accumulated warnings during a forced Gradle upgrade is painful.
