# SBT

## Overview

SBT (Simple Build Tool, rebranded as Scala Build Tool) is the standard build system for Scala projects. It uses a Scala-based DSL for build definitions, provides an interactive shell with continuous compilation and testing, and handles Scala's unique cross-building requirements (building the same library against multiple Scala versions). SBT is deeply integrated with the Scala ecosystem — Scala compiler plugins, Scala.js, Scala Native, and the Scala standard library releases are all built and published with SBT.

Use SBT when the project is primarily Scala, when the project needs to publish libraries cross-built against multiple Scala versions (2.13 and 3.x), when the project uses Scala.js or Scala Native (SBT has first-class support), or when the team is embedded in the Scala ecosystem and needs seamless integration with Scala-specific tools (Scalafmt, Scalafix, Metals IDE, Bloop). SBT's interactive shell with `~compile` (continuous compilation) and `~test` (continuous testing) provides the tightest feedback loop for Scala development, catching type errors within seconds of saving a file.

Do not use SBT for pure Java projects (use Gradle or Maven), for polyglot monorepos that include non-JVM languages (Bazel is better suited), or for projects where the team has no Scala experience (SBT's Scala-based configuration has a learning curve that is only justified if the project also uses Scala). SBT's build performance lags behind Gradle for large multi-project builds due to less aggressive caching and parallelism, though sbt 2.x (currently in development) addresses many of these limitations.

Key differentiators from Gradle/Maven: (1) SBT's build definition is Scala code — not XML (Maven), not Kotlin (Gradle), but the same language the project uses. This eliminates the mental context switch between application code and build code. (2) Cross-building (`crossScalaVersions`) is a first-class feature that handles the Scala binary compatibility problem (Scala 2.13 and 3.x produce incompatible bytecode). Gradle and Maven require manual configuration for this. (3) SBT's interactive shell keeps the build server running between commands, providing instant compilation feedback — `compile` after a small change typically takes <1 second. (4) SBT's task graph is lazy and incremental by default — tasks automatically track their inputs and skip execution when inputs are unchanged. (5) Bloop integration exports the project model for IDE consumption, enabling Metals (the Scala LSP) to provide rich IDE support.

## Architecture Patterns

### Multi-Project Builds

SBT's multi-project builds use Scala objects to define subprojects, their settings, and their inter-dependencies. Each subproject can have its own source directory, dependencies, and Scala version. The root project aggregates subprojects for unified commands (`compile`, `test`, `publish`).

**`build.sbt` — multi-project build definition:**
```scala
ThisBuild / organization := "com.example"
ThisBuild / version      := "1.0.0-SNAPSHOT"
ThisBuild / scalaVersion := "3.5.2"

// Common settings shared across all projects
lazy val commonSettings = Seq(
  scalacOptions ++= Seq(
    "-deprecation",
    "-feature",
    "-unchecked",
    "-Wunused:all",
    "-Xfatal-warnings",
  ),
  testFrameworks += new TestFramework("munit.Framework"),
  libraryDependencies ++= Seq(
    "org.scalameta" %% "munit"       % "1.0.3" % Test,
    "org.scalameta" %% "munit-scalacheck" % "1.0.3" % Test,
  ),
)

// Root project — aggregates all subprojects
lazy val root = (project in file("."))
  .aggregate(core, api, persistence, app)
  .settings(
    name := "my-project",
    publish / skip := true,
  )

// Domain core — no framework dependencies
lazy val core = (project in file("core"))
  .settings(
    commonSettings,
    name := "core",
    libraryDependencies ++= Seq(
      "org.typelevel" %% "cats-core"   % "2.12.0",
      "org.typelevel" %% "cats-effect" % "3.5.7",
    ),
  )

// HTTP API layer
lazy val api = (project in file("api"))
  .dependsOn(core)
  .settings(
    commonSettings,
    name := "api",
    libraryDependencies ++= Seq(
      "org.http4s" %% "http4s-ember-server" % "0.23.30",
      "org.http4s" %% "http4s-circe"        % "0.23.30",
      "org.http4s" %% "http4s-dsl"          % "0.23.30",
      "io.circe"   %% "circe-generic"       % "0.14.10",
    ),
  )

// Persistence layer
lazy val persistence = (project in file("persistence"))
  .dependsOn(core)
  .settings(
    commonSettings,
    name := "persistence",
    libraryDependencies ++= Seq(
      "org.tpolecat" %% "skunk-core"  % "1.0.0-M8",
      "org.flywaydb"  % "flyway-core" % "11.1.0",
    ),
  )

// Application entrypoint
lazy val app = (project in file("app"))
  .dependsOn(api, persistence)
  .enablePlugins(JavaAppPackaging)
  .settings(
    commonSettings,
    name := "app",
    Compile / mainClass := Some("com.example.Main"),
    Docker / packageName := "my-project",
    dockerBaseImage := "eclipse-temurin:21-jre",
    dockerExposedPorts := Seq(8080),
  )
```

Key patterns in the build definition:
- `ThisBuild` scope — settings that apply to the entire build. `ThisBuild / scalaVersion` ensures all subprojects use the same Scala version unless explicitly overridden.
- `commonSettings` — a reusable `Seq[Setting[_]]` that multiple projects include via `.settings(commonSettings)`. This is SBT's equivalent of Gradle convention plugins — less powerful (no composable plugin IDs) but simpler.
- `.dependsOn(core)` — declares an inter-project dependency. SBT resolves the classpath automatically and ensures the dependency is compiled first.
- `.aggregate(core, api, persistence, app)` — the root project aggregates subprojects so that `sbt compile` compiles all of them.
- `.enablePlugins(JavaAppPackaging)` — activates `sbt-native-packager` for Docker image generation.

**Dependency declaration patterns:**
```scala
libraryDependencies ++= Seq(
  // %% appends the Scala binary version (_3, _2.13) to the artifact name
  "org.typelevel" %% "cats-core" % "2.12.0",

  // % uses the artifact name exactly (for Java libraries)
  "org.flywaydb" % "flyway-core" % "11.1.0",

  // % Test scope — only available in test sources
  "org.scalameta" %% "munit" % "1.0.3" % Test,

  // % IntegrationTest scope
  "com.dimafeng" %% "testcontainers-scala-postgresql" % "0.41.4" % IntegrationTest,

  // Excludes for transitive dependency conflicts
  "org.http4s" %% "http4s-ember-server" % "0.23.30" exclude("org.slf4j", "slf4j-api"),

  // Classifier (sources, javadoc)
  "org.typelevel" %% "cats-core" % "2.12.0" classifier "sources",
)
```

The `%%` operator is Scala-specific: it appends the Scala binary version to the artifact name, resolving `cats-core_3` for Scala 3 or `cats-core_2.13` for Scala 2.13. This handles Scala's binary incompatibility between major versions. Java libraries use `%` (no version suffix).

### Plugin Ecosystem

SBT plugins extend the build with additional tasks, settings, and commands. They are declared in `project/plugins.sbt` and loaded at build startup.

**`project/plugins.sbt` — plugin declarations:**
```scala
// Code formatting
addSbtPlugin("org.scalameta" % "sbt-scalafmt" % "2.5.2")

// Code rewriting and linting
addSbtPlugin("ch.epfl.scala" % "sbt-scalafix" % "0.13.0")

// Packaging (Docker, native packages, fat JARs)
addSbtPlugin("com.github.sbt" % "sbt-native-packager" % "1.10.4")

// Assembly (fat JARs)
addSbtPlugin("com.eed3si9n" % "sbt-assembly" % "2.3.0")

// Dependency graph visualization
addSbtPlugin("net.virtual-void" % "sbt-dependency-graph" % "0.10.0-RC1")

// Release management
addSbtPlugin("com.github.sbt" % "sbt-release" % "1.4.0")

// CI publishing
addSbtPlugin("com.github.sbt" % "sbt-ci-release" % "1.9.2")

// Coverage
addSbtPlugin("org.scoverage" % "sbt-scoverage" % "2.2.2")

// Header/license management
addSbtPlugin("de.heikoseeberger" % "sbt-header" % "5.10.0")

// Build info (embed version, git hash in compiled code)
addSbtPlugin("com.eed3si9n" % "sbt-buildinfo" % "0.13.1")
```

**`project/build.properties`** — pins the SBT version:
```properties
sbt.version=1.10.6
```

Always pin the SBT version. SBT's launcher (analogous to Gradle Wrapper) downloads the pinned version automatically. This file is the single source of truth for which SBT version builds the project.

**sbt-assembly for fat JARs:**
```scala
lazy val app = (project in file("app"))
  .dependsOn(core, api, persistence)
  .settings(
    commonSettings,
    assembly / assemblyJarName := "my-project.jar",
    assembly / mainClass := Some("com.example.Main"),
    assembly / assemblyMergeStrategy := {
      case PathList("META-INF", "services", _*) => MergeStrategy.concat
      case PathList("META-INF", _*)             => MergeStrategy.discard
      case "reference.conf"                     => MergeStrategy.concat
      case _                                    => MergeStrategy.first
    },
  )
```

The `assemblyMergeStrategy` resolves conflicts when multiple JARs contain files with the same path — a common issue with service provider files (`META-INF/services/`) and Typesafe/Lightbend config files (`reference.conf`). The merge strategy is the most common source of assembly failures and must be configured explicitly.

**sbt-native-packager for Docker:**
```scala
lazy val app = (project in file("app"))
  .enablePlugins(JavaAppPackaging, DockerPlugin)
  .settings(
    Docker / packageName := "my-project",
    Docker / version := version.value,
    dockerBaseImage := "eclipse-temurin:21-jre-alpine",
    dockerExposedPorts := Seq(8080),
    dockerLabels := Map(
      "org.opencontainers.image.source" -> "https://github.com/example/my-project",
    ),
    dockerEnvVars := Map("JAVA_OPTS" -> "-Xmx512m"),
  )
```

```bash
# Build Docker image
sbt "app / Docker / publishLocal"

# Publish to registry
sbt "app / Docker / publish"
```

### Cross-Building

Cross-building is SBT's solution to Scala's binary incompatibility between major versions. A library published for Scala 2.13 cannot be used by a Scala 3 project (and vice versa) unless it is compiled separately for each version. SBT automates this by compiling, testing, and publishing the library against each version in `crossScalaVersions`.

**Cross-building configuration:**
```scala
ThisBuild / scalaVersion       := "3.5.2"
ThisBuild / crossScalaVersions := Seq("2.13.15", "3.5.2")

lazy val core = (project in file("core"))
  .settings(
    commonSettings,
    name := "core",
    libraryDependencies ++= Seq(
      "org.typelevel" %% "cats-core" % "2.12.0",
    ),
    // Scala 2/3 source compatibility
    scalacOptions ++= {
      CrossVersion.partialVersion(scalaVersion.value) match {
        case Some((2, _)) => Seq("-Ytasty-reader")  // Read Scala 3 TASTy from Scala 2
        case Some((3, _)) => Seq("-source:3.5")
        case _            => Seq.empty
      }
    },
  )
```

**Cross-building commands:**
```bash
# Compile for all Scala versions
sbt +compile

# Test for all Scala versions
sbt +test

# Publish for all Scala versions
sbt +publish

# Compile for a specific version
sbt ++2.13.15 compile
sbt ++3.5.2 compile
```

The `+` prefix runs the command for all `crossScalaVersions`. The `++` prefix temporarily switches to a specific Scala version. Published artifacts include the Scala binary version suffix (`_2.13`, `_3`) in the artifact name, allowing consumers to pull the correct binary.

**Scala 2/3 cross-compilation with source directories:**
```scala
// In build.sbt
Compile / unmanagedSourceDirectories ++= {
  val base = (Compile / sourceDirectory).value
  CrossVersion.partialVersion(scalaVersion.value) match {
    case Some((2, _)) => Seq(base / "scala-2")
    case Some((3, _)) => Seq(base / "scala-3")
    case _            => Seq.empty
  }
}
```

This enables version-specific source files alongside shared source: `src/main/scala/` (shared), `src/main/scala-2/` (Scala 2 only), `src/main/scala-3/` (Scala 3 only). Use this for code that uses Scala version-specific features (macros, implicits vs. given/using, etc.).

### Assembly and Packaging

**sbt-assembly** creates a single "fat JAR" containing the project code and all dependencies. This is the simplest deployment model but has limitations (classpath conflicts, large artifact size).

**sbt-native-packager** provides multiple packaging formats:
- **Docker** — generates Dockerfiles and builds images.
- **Universal** — creates `.zip`/`.tar.gz` archives with launcher scripts.
- **Debian/RPM** — creates Linux packages.
- **GraalVM Native Image** — compiles to native executables (experimental).

**Recommended packaging strategy:**
```scala
lazy val app = (project in file("app"))
  .enablePlugins(JavaAppPackaging, DockerPlugin)
  .settings(
    // Universal archive (for non-Docker deployments)
    Universal / mappings ++= Seq(
      file("README.md") -> "README.md",
      file("config/application.conf") -> "conf/application.conf",
    ),

    // Docker (primary deployment target)
    dockerBaseImage := "eclipse-temurin:21-jre-alpine",
    dockerExposedPorts := Seq(8080),

    // JVM options baked into the launcher script
    Universal / javaOptions ++= Seq(
      "-Xmx512m",
      "-XX:+UseG1GC",
      "-Dconfig.file=/opt/docker/conf/application.conf",
    ),
  )
```

Use Docker packaging for containerized deployments (the standard path). Use Universal packaging for traditional server deployments. Use sbt-assembly only for standalone CLI tools or AWS Lambda-style deployments where a single JAR is required.

## Configuration

### Development

SBT's interactive shell is the primary development interface. It keeps the JVM warm, caches the project model, and provides instant feedback:

```bash
# Start the interactive shell
sbt

# Inside the shell:
compile                    # Compile all projects
test                       # Run all tests
~compile                   # Continuous compilation (recompiles on file save)
~test                      # Continuous testing
~testQuick                 # Re-run only tests that failed or whose code changed
core/compile               # Compile only the core subproject
app/run                    # Run the application
```

**Global SBT settings (`~/.sbt/1.0/global.sbt`):**
```scala
// Show test durations
Test / testOptions += Tests.Argument("-oD")

// Use coursier for faster dependency resolution
ThisBuild / useCoursier := true
```

**JVM settings (`~/.sbt/1.0/.jvmopts` or `.jvmopts` in project root):**
```
-Xmx4g
-Xss4m
-XX:+UseG1GC
-XX:MaxMetaspaceSize=512m
```

**Repository configuration (`~/.sbt/1.0/repositories`):**
```
[repositories]
  local
  maven-local: file://${user.home}/.m2/repository
  internal: https://nexus.internal.example.com/repository/maven-central/
  maven-central
```

### Production

**CI invocation:**
```bash
# Full build + test
sbt clean compile test

# With specific settings
sbt -Dsbt.log.noformat=true \
    -Dsbt.ci=true \
    clean test

# Parallel test execution
sbt "set ThisBuild / Test / parallelExecution := true" test

# Publish with CI-specific settings
sbt "set ThisBuild / version := sys.env.getOrElse(\"VERSION\", version.value)" publish
```

**GitHub Actions example:**
```yaml
- name: Set up JDK 21
  uses: actions/setup-java@v4
  with:
    java-version: '21'
    distribution: 'temurin'
    cache: 'sbt'

- name: Build and test
  run: sbt -Dsbt.log.noformat=true clean coverage test coverageReport

- name: Publish test results
  uses: mikepenz/action-junit-report@v4
  if: always()
  with:
    report_paths: '**/target/test-reports/TEST-*.xml'
```

**sbt-ci-release for automated publishing:**
```scala
// project/plugins.sbt
addSbtPlugin("com.github.sbt" % "sbt-ci-release" % "1.9.2")

// build.sbt
ThisBuild / sonatypeCredentialHost := "s01.oss.sonatype.org"
ThisBuild / publishMavenStyle := true
ThisBuild / licenses := Seq("Apache-2.0" -> url("https://www.apache.org/licenses/LICENSE-2.0"))
ThisBuild / homepage := Some(url("https://github.com/example/my-project"))
```

`sbt-ci-release` automates the Maven Central publishing workflow: GPG signing, staging, release, and version derivation from git tags. Tag a commit with `v1.0.0` and CI publishes automatically.

## Performance

**SBT server mode** — SBT runs as a long-lived server process (since SBT 1.x). The first command starts the server; subsequent commands connect to it. This amortizes JVM startup, classloading, and project model evaluation across all commands in a session. The interactive shell leverages this naturally. For CI, use `sbt compile test` (single SBT invocation with multiple commands) rather than `sbt compile && sbt test` (two cold starts).

**Incremental compilation** — SBT uses Zinc, the incremental Scala/Java compiler. Zinc tracks file-level dependencies and recompiles only changed files plus their dependents. For Scala, this is particularly important because the Scala compiler is slower than `javac` — full recompilation of a large project can take minutes, while incremental compilation after a small change takes seconds.

**Parallel compilation:**
```scala
// In build.sbt
ThisBuild / usePipelining := true  // SBT 2.x pipelining (if available)
```

SBT compiles independent subprojects in parallel by default. Within a single subproject, compilation is sequential (Scala's compiler does not parallelize well internally). The key optimization is to keep subprojects small and loosely coupled — this maximizes parallelism across the project graph.

**Bloop for faster compilation:**
```bash
# Export project to Bloop
sbt bloopInstall

# Compile via Bloop (bypasses SBT overhead)
bloop compile root

# Continuous compilation
bloop compile root --watch
```

Bloop is a build server that caches the compilation state more aggressively than SBT. It is used by Metals (the Scala LSP for VS Code, IntelliJ, etc.) for IDE compilation. For development, Bloop provides faster feedback than SBT's built-in compiler for large projects.

**Dependency resolution caching:**
SBT uses Coursier for dependency resolution, which maintains a local cache at `~/.cache/coursier/v1/`. Coursier resolves dependencies in parallel and caches both metadata and artifacts. First resolution of a new project may take 30-60 seconds; subsequent builds resolve in <1 second.

**Avoiding recompilation triggers:**
- Minimize changes to `build.sbt` — every change triggers a full reload of the build definition.
- Keep `project/` directory changes minimal — `plugins.sbt` changes trigger a full rebuild of the build definition.
- Use `ThisBuild` scope for settings that are truly global — per-project settings that differ across subprojects should be declared in each subproject.

## Security

**Dependency resolution over HTTPS** — SBT and Coursier resolve dependencies over HTTPS by default from Maven Central. Ensure all custom repositories use HTTPS:
```scala
resolvers += "Internal" at "https://nexus.internal.example.com/repository/releases/"
```

**Credential management — never hardcode in `build.sbt`:**
```scala
// Read from environment variables
credentials += Credentials(
  "Sonatype Nexus Repository Manager",
  "nexus.internal.example.com",
  sys.env.getOrElse("NEXUS_USERNAME", ""),
  sys.env.getOrElse("NEXUS_PASSWORD", ""),
)
```

**Or use the credentials file (`~/.sbt/1.0/credentials`):**
```properties
realm=Sonatype Nexus Repository Manager
host=nexus.internal.example.com
user=admin
password=changeme
```

Reference it in `build.sbt`:
```scala
credentials += Credentials(Path.userHome / ".sbt" / "1.0" / "credentials")
```

**GPG signing for publishing:**
```scala
// build.sbt
ThisBuild / publishMavenStyle := true
```

`sbt-ci-release` handles GPG signing automatically using `PGP_PASSPHRASE`, `PGP_SECRET`, and `SONATYPE_PASSWORD` environment variables. Never store GPG keys in the repository.

**Dependency vulnerability scanning:**
```scala
// project/plugins.sbt
addSbtPlugin("net.vonbuchholtz" % "sbt-dependency-check" % "5.1.0")
```

```bash
sbt dependencyCheck
```

This runs OWASP Dependency Check against all project dependencies, reporting CVEs with severity scores. Integrate it into CI to fail the build on critical vulnerabilities.

**Supply chain hardening checklist:**
- Pin the SBT version in `project/build.properties`.
- Pin all plugin versions in `project/plugins.sbt`.
- Use HTTPS for all repository URLs.
- Use `sbt-dependency-check` for CVE scanning in CI.
- Use `sbt-ci-release` for automated, GPG-signed publishing.
- Review `sbt dependencyTree` output for unexpected transitive dependencies.
- Use `evictionWarningOptions` to surface dependency eviction conflicts.

## Testing

**Running tests:**
```bash
# Run all tests
sbt test

# Run tests for a specific subproject
sbt "core / test"

# Run a specific test class
sbt "core / testOnly com.example.core.UserServiceSpec"

# Run tests matching a pattern
sbt "core / testOnly *UserService*"

# Continuous testing (re-runs on file changes)
sbt ~test

# Re-run only failed tests
sbt testQuick
```

**Test framework configuration:**
```scala
// Use MUnit
testFrameworks += new TestFramework("munit.Framework")

// Use ScalaTest
testFrameworks += new TestFramework("org.scalatest.tools.Framework")

// Use Specs2
testFrameworks += new TestFramework("org.specs2.runner.Specs2Framework")
```

**Integration tests with separate source set:**
```scala
lazy val core = (project in file("core"))
  .configs(IntegrationTest)
  .settings(
    Defaults.itSettings,
    IntegrationTest / fork := true,
    IntegrationTest / parallelExecution := false,
    libraryDependencies ++= Seq(
      "com.dimafeng" %% "testcontainers-scala-postgresql" % "0.41.4" % IntegrationTest,
    ),
  )
```

```bash
# Run integration tests
sbt "core / IntegrationTest / test"

# Run specific integration test
sbt "core / IntegrationTest / testOnly *PostgresRepositoryIT"
```

The `IntegrationTest` configuration creates a separate source directory (`src/it/scala`), classpath, and test command. `fork := true` ensures integration tests run in a separate JVM with a clean classpath. `parallelExecution := false` runs tests sequentially to avoid resource conflicts (database ports, Docker containers).

**Test reporting:**
```scala
// Generate JUnit XML reports for CI
Test / testOptions += Tests.Argument(TestFrameworks.MUnit, "-b")  // MUnit brief output
Test / testOptions += Tests.Argument("-o", "-u", "target/test-reports")  // JUnit XML
```

Test reports are generated at `target/test-reports/TEST-*.xml` in standard JUnit format, consumed by CI test result aggregators.

**Code coverage with sbt-scoverage:**
```bash
sbt clean coverage test coverageReport coverageAggregate
```

Coverage reports are generated at `target/scala-3.5.2/scoverage-report/`. The `coverageAggregate` task merges coverage from all subprojects into a single report.

## Dos

- Pin the SBT version in `project/build.properties`. SBT's launcher downloads the pinned version automatically, ensuring every developer and CI runner uses the same version. Never rely on a globally installed SBT.
- Use `ThisBuild` scope for truly global settings (scalaVersion, organization, version) and per-project settings for project-specific configuration. Misusing `ThisBuild` for settings that differ across subprojects causes confusion and unexpected behavior.
- Use `%%` for Scala library dependencies and `%` for Java library dependencies. The `%%` operator appends the Scala binary version to the artifact name, resolving the correct binary for your Scala version. Using `%` for Scala libraries resolves the wrong artifact.
- Use the interactive shell (`sbt` then commands) for development. Single-command invocations (`sbt compile`) incur JVM startup overhead on every invocation. The shell keeps the JVM warm and provides sub-second feedback for incremental compilation.
- Use `~compile` and `~testQuick` for continuous feedback during development. These commands watch source files and recompile/re-test on every save, providing the tightest possible feedback loop for Scala development.
- Separate unit tests (default `test` configuration) from integration tests (`IntegrationTest` configuration). Fork integration tests and disable parallel execution to avoid resource conflicts.
- Use sbt-native-packager for Docker image generation rather than writing Dockerfiles manually. The plugin generates optimized, layered images with proper JVM configuration and handles the SBT-specific packaging steps automatically.
- Use sbt-ci-release for automated publishing to Maven Central or Sonatype. It handles GPG signing, versioning, staging, and release with minimal configuration.
- Use Coursier's local cache for offline development. After initial dependency resolution, SBT works fully offline from the Coursier cache — no network access needed for subsequent builds.
- Configure `scalacOptions` with `-Xfatal-warnings` and `-Wunused:all` to catch code quality issues at compile time. Scala's compiler has powerful linting capabilities that are disabled by default.

## Don'ts

- Don't use `sbt compile && sbt test` in CI. Each invocation starts a cold JVM, evaluates the build definition, and resolves dependencies. Use `sbt compile test` (single invocation, multiple commands) to amortize startup cost across all commands.
- Don't hardcode Scala versions in dependency declarations. Use `%%` to automatically append the Scala binary version. Hardcoded versions (e.g., `"org.typelevel" % "cats-core_2.13" % "2.12.0"`) break when the project's Scala version changes.
- Don't use sbt-assembly for Docker-deployed applications. Fat JARs include all dependencies in a single file, producing large images with no layer caching. Use sbt-native-packager's Docker plugin, which produces layered images where dependency changes are cached separately from application code changes.
- Don't ignore eviction warnings. SBT's dependency mediation may evict (downgrade) a dependency to resolve conflicts. An eviction warning means a library may receive a version older than it requires, leading to runtime `NoSuchMethodError` or `ClassNotFoundException`. Resolve evictions explicitly with `dependencyOverrides`.
- Don't store credentials in `build.sbt` or `project/plugins.sbt`. These files are committed to version control. Credentials belong in `~/.sbt/1.0/credentials` (developer machines) or environment variables (CI).
- Don't use `publishLocal` as a substitute for proper multi-project `dependsOn`. Publishing to the local Ivy cache to share code between projects in the same build is a workaround that breaks incremental compilation, version tracking, and IDE support. Use `.dependsOn()` for intra-build dependencies.
- Don't modify `build.sbt` to change runtime configuration. Build definition changes trigger a full reload. Use application configuration files (Typesafe Config `application.conf`, environment variables) for runtime settings.
- Don't use `lazy val` for settings that should be evaluated eagerly. SBT's `lazy val` project definitions are standard practice, but `lazy val` inside settings sequences can cause initialization order issues. Define settings directly in `.settings()` blocks.
- Don't ignore `project/build.properties`. If this file is missing, SBT uses whatever version is globally installed, creating "works on my machine" problems. Always pin the SBT version.
- Don't use `crossScalaVersions` on application projects (only on libraries). Applications deploy a single binary — cross-building doubles the build time for no benefit. Reserve cross-building for libraries that consumers need in multiple Scala versions.
