# scoverage

## Overview

sbt-scoverage is the standard statement and branch coverage plugin for Scala. Instrument source with `sbt coverage test` and generate reports with `sbt coverageReport` or `sbt coverageAggregate` for multi-module builds. Enforce thresholds via `coverageMinimumStmtTotal`, `coverageMinimumBranchTotal`, and fail the build with `coverageFailOnMinimum := true`. Suppress specific code blocks with `// $COVERAGE-OFF$` / `// $COVERAGE-ON$` comments. Compatible with ScalaTest, Specs2, MUnit, and other test frameworks.

## Architecture Patterns

### Installation & Setup

```scala
// project/plugins.sbt
addSbtPlugin("org.scoverage" % "sbt-scoverage" % "2.1.0")
```

```bash
# Run with coverage
sbt coverage test

# Generate HTML/XML report
sbt coverageReport

# Multi-module aggregate report
sbt coverageAggregate

# All in one
sbt clean coverage test coverageReport coverageAggregate
```

**`build.sbt` configuration:**
```scala
// build.sbt
lazy val root = (project in file("."))
  .settings(
    name := "my-app",
    scalaVersion := "3.3.3",

    // Coverage thresholds
    coverageMinimumStmtTotal := 80,
    coverageMinimumBranchTotal := 70,
    coverageFailOnMinimum := true,
    coverageHighlighting := true,        // highlight uncovered lines in HTML
    coverageExcludedPackages := Seq(
      "<empty>",
      ".*\\.generated\\..*",
      ".*Routes",                          // Play Framework generated routes
      ".*ReverseRoutes",
      ".*\\.BuildInfo\\$",
    ).mkString(";"),
    coverageExcludedFiles := Seq(
      ".*/main/generated/.*",
      ".*/target/.*"
    ).mkString(";")
  )
```

**Multi-module build:**
```scala
// build.sbt
lazy val core = (project in file("core"))
  .settings(
    coverageMinimumStmtTotal := 85,
    coverageMinimumBranchTotal := 75,
    coverageFailOnMinimum := true
  )

lazy val api = (project in file("api"))
  .settings(
    coverageMinimumStmtTotal := 80,
    coverageMinimumBranchTotal := 65,
    coverageFailOnMinimum := true
  )
  .dependsOn(core)

lazy val root = (project in file("."))
  .aggregate(core, api)
  .settings(
    // Aggregate report — uses per-subproject minimums
    coverageMinimumStmtTotal := 80,
    coverageFailOnMinimum := true
  )
```

### Rule Categories

| Setting | Description | Default |
|---|---|---|
| `coverageMinimumStmtTotal` | Minimum statement coverage (%) | 0 (disabled) |
| `coverageMinimumBranchTotal` | Minimum branch coverage (%) | 0 (disabled) |
| `coverageMinimumStmtPerPackage` | Per-package statement minimum | 0 |
| `coverageMinimumBranchPerPackage` | Per-package branch minimum | 0 |
| `coverageFailOnMinimum` | Fail build on threshold violation | `false` |
| `coverageHighlighting` | Color-highlight uncovered code in HTML | `true` |

### Configuration Patterns

**Suppressing coverage for specific code:**
```scala
// $COVERAGE-OFF$
// Suppress: Play Framework generated code or platform-specific bootstrap
object ApplicationLoader extends play.api.ApplicationLoader {
  override def load(context: Context): Application = {
    new MyApplicationLoader().load(context)
  }
}
// $COVERAGE-ON$

// Suppress a single expression (still on that line)
def impossibleBranch: Nothing = throw new RuntimeException("unreachable") // $COVERAGE-OFF$
```

**Per-file exclusion patterns:**
```scala
// build.sbt
coverageExcludedFiles := Seq(
  ".*\\/generated\\/.*",
  ".*Main\\.scala",             // application entry point
  ".*Module\\.scala",           // Guice/Play DI wiring
  ".*\\.pb\\.scala",            // Protobuf generated
  ".*\\.Routes\\.scala",        // Play routes
).mkString(";")
```

**LCOV output for Codecov:**
```bash
# scoverage generates Cobertura XML in target/scala-*/scoverage-report/
# Convert to LCOV using a script or upload Cobertura directly
sbt coverage test coverageReport

# Upload Cobertura XML
ls target/scala-3.3.3/scoverage-report/scoverage.xml
```

**Checking thresholds separately from test run:**
```bash
# Run tests with instrumentation
sbt coverage test

# Check thresholds and generate report (without re-running tests)
sbt coverageReport
# coverageReport runs coverageCheck internally when coverageFailOnMinimum := true
```

### CI Integration

```yaml
# .github/workflows/test.yml
- name: Set up JDK
  uses: actions/setup-java@v4
  with:
    java-version: "21"
    distribution: temurin

- name: Cache sbt
  uses: actions/cache@v4
  with:
    path: |
      ~/.sbt
      ~/.ivy2/cache
      ~/.coursier
    key: sbt-${{ hashFiles('**/build.sbt', '**/plugins.sbt') }}

- name: Run tests with coverage
  run: sbt clean coverage test coverageReport coverageAggregate

- name: Upload Cobertura report
  uses: codecov/codecov-action@v4
  with:
    files: target/scala-3.3.3/scoverage-report/scoverage.xml
    fail_ci_if_error: true

- name: Upload HTML coverage
  if: always()
  uses: actions/upload-artifact@v4
  with:
    name: scoverage-report
    path: target/scala-3.3.3/scoverage-report/
```

## Performance

- `sbt coverage` instruments all compiled classes — adds 15-30% compilation time overhead and 10-20% test execution overhead.
- `sbt coverageAggregate` runs after per-subproject reports — it re-processes all instrumentation data and is slow for large multi-module builds.
- Avoid running `sbt clean coverage` for incremental local runs — `clean` triggers full recompilation. Use `sbt coverage test` with incremental compilation when iterating.
- Coverage data is written to `target/scala-*/scoverage-data/` — these directories are large; add them to `.gitignore`.
- Use `coverageHighlighting := false` in CI if HTML report generation is slow — Cobertura XML is sufficient for ingestion.

## Security

- Scoverage generates `.xml` and `.html` reports under `target/` — add `target/` to `.gitignore` (standard for sbt projects).
- Scoverage does not transmit data externally — all reports are local.
- HTML reports embed source code — do not publish publicly for proprietary Scala applications.
- `// $COVERAGE-OFF$` suppression comments are visible in source control — they document intentional coverage exclusions, which is desirable for review.

## Testing

```bash
# Run with coverage
sbt clean coverage test

# Generate report
sbt coverageReport

# Multi-module aggregate
sbt coverageAggregate

# All combined
sbt clean coverage test coverageReport coverageAggregate

# Show report location
find target -name "scoverage.xml" 2>/dev/null
find target -name "index.html" -path "*/scoverage-report/*" 2>/dev/null

# Open HTML report
open target/scala-3.3.3/scoverage-report/index.html
```

## Dos

- Set `coverageFailOnMinimum := true` in `build.sbt` — without it, threshold settings are informational only and do not fail the build.
- Run `sbt clean coverage test coverageReport coverageAggregate` as a single CI step — ensures instrumentation is fresh and aggregation reflects the current test run.
- Use `// $COVERAGE-OFF$` blocks with a comment explaining why the code is excluded — code review can then verify exclusions are justified.
- Set per-subproject thresholds in multi-module builds rather than relying solely on the aggregate — low-coverage modules are hidden by high-coverage ones in the aggregate.
- Add `target/` to `.gitignore` — scoverage data files are large and change on every build.
- Upload `scoverage.xml` (Cobertura format) to Codecov for coverage trend tracking across commits.

## Don'ts

- Don't run `sbt coverage` in the production build pipeline — it adds compilation overhead and produces larger JARs with instrumentation metadata.
- Don't use `// $COVERAGE-OFF$` for business logic — reserve it for generated code (Protobuf, Play routes), DI wiring, and platform entry points.
- Don't set `coverageMinimumStmtTotal := 100` for projects with Play routes, generated code, or main entry points — 100% is unreachable without meaningless tests or excessive `COVERAGE-OFF` suppressions.
- Don't rely on scoverage's branch coverage alone — complement with mutation testing (`stryker4s` or `scalameta/munit-scalacheck`) to verify tests actually assert behavior.
- Don't commit `target/scala-*/scoverage-data/` — the instrumentation data files are binary, large, and regenerated on every run.
