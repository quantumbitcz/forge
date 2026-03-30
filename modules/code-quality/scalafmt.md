# scalafmt

## Overview

Opinionated Scala code formatter that enforces consistent style across a codebase. Scalafmt formats source files to a canonical form based on `.scalafmt.conf` and integrates with sbt, Maven, IntelliJ IDEA, and CI pipelines. Unlike a linter, scalafmt only handles formatting (whitespace, indentation, line breaks) — pair with scalafix for semantic code quality rules. The key config decisions are `dialect` (Scala 3 vs 2.x) and `maxColumn` — all other defaults are generally acceptable.

## Architecture Patterns

### Installation & Setup

```scala
// project/plugins.sbt (sbt)
addSbtPlugin("org.scalameta" % "sbt-scalafmt" % "2.5.2")
```

```bash
# Run formatter
sbt scalafmt          # format source files
sbt Test/scalafmt     # format test files
sbt scalafmtCheck     # check only (CI mode — no writes)
sbt scalafmtAll       # format all configurations
sbt scalafmtCheckAll  # check all configurations (CI mode)

# Standalone CLI
cs install scalafmt
scalafmt --check      # check mode
scalafmt              # format in place
```

For Maven projects, use the `scalafmt-maven-plugin`:
```xml
<plugin>
    <groupId>org.antipathy</groupId>
    <artifactId>mvn-scalafmt_2.13</artifactId>
    <version>1.1.1640084764.9f463a9</version>
</plugin>
```

### Rule Categories

Scalafmt has no "rule categories" in the lint sense — it is purely a formatter. Key configuration dimensions:

| Config Key | What It Controls | Recommended Value |
|---|---|---|
| `dialect` | Scala language version | `scala3` or `scala213` |
| `maxColumn` | Line length before wrapping | 120 |
| `rewrite.rules` | Structural rewrites | `SortImports`, `PreferCurlyFors` |
| `align.preset` | Vertical alignment style | `more` or `none` |
| `newlines.source` | Line break handling mode | `keep` or `fold` |
| `indent.main` | Main indentation width | 2 |

### Configuration Patterns

`.scalafmt.conf` at the project root:

```hocon
# .scalafmt.conf
version = "3.8.3"
runner.dialect = scala3           # or scala213, scala212

maxColumn = 120

indent.main = 2
indent.significant = 2            # Scala 3 significant indentation

align.preset = more               # align equals, case arrows, etc.
align.allowOverflow = true

newlines.source = keep            # preserve developer line breaks when possible
newlines.beforeCurlyLambdaParams = multilineWithCaseOnly
newlines.implicitParamListModifierForce = [after]

spaces.inImportCurlyBraces = true  # import { A, B }

rewrite.rules = [
  SortImports,             # sort import selectors alphabetically
  PreferCurlyFors,         # for (x <- xs) { } over for (x <- xs) yield
  RedundantBraces,         # remove unnecessary braces
  RedundantParens          # remove unnecessary parentheses
]

rewrite.imports.sort = scalastyle  # scala.* last, others alphabetical

# Trailing commas
trailingCommas.style = multiple   # trailing commas on multi-line args

# Project settings
project.git = true                # only format git-tracked files
project.excludeFilters = [
  ".metals",
  ".bloop",
  "target/",
  "project/target/"
]
```

Scala 2 specific config (when `runner.dialect = scala213`):
```hocon
version = "3.8.3"
runner.dialect = scala213
maxColumn = 100
rewrite.scala3.convertToNewSyntax = false  # don't migrate to Scala 3 syntax
```

Disable formatting for a code block:
```scala
// format: off
val matrix = Array(
  Array(1, 0, 0),
  Array(0, 1, 0),
  Array(0, 0, 1)
)
// format: on
```

### CI Integration

```yaml
# .github/workflows/quality.yml
- name: Scalafmt check
  run: sbt scalafmtCheckAll
```

For sbt multi-project builds:
```bash
# Check all sub-projects
sbt '+ scalafmtCheckAll'
```

In GitHub Actions with caching:
```yaml
- name: Cache sbt
  uses: actions/cache@v4
  with:
    path: |
      ~/.sbt
      ~/.ivy2/cache
      ~/.coursier/cache
    key: sbt-${{ hashFiles('**/build.sbt', '**/plugins.sbt') }}

- name: Check formatting
  run: sbt scalafmtCheckAll --no-colors
```

## Performance

- Scalafmt is fast on individual files but `sbt scalafmtAll` formats the entire project serially. For large codebases (> 500 files), expect 10-30s.
- `project.git = true` limits formatting to git-tracked files — useful during migration to avoid re-formatting generated or vendored files.
- `scalafmtCheck` (not `scalafmt`) in CI avoids writing files and is slightly faster.
- IntelliJ IDEA's scalafmt integration uses a background daemon — format-on-save is near-instant after warm-up.
- Cache the `~/.coursier/cache` and `~/.sbt` directories in CI to avoid re-downloading scalafmt artifacts on every run.

## Security

Scalafmt is a formatter with no security analysis capabilities. The only security-relevant consideration is:

- Verify the `version` field in `.scalafmt.conf` is pinned to a specific release — a floating version could pull a newer release with different formatting output, causing spurious CI failures or unexpected source changes.
- Use `project.git = true` to ensure scalafmt does not touch files outside source control (e.g., generated code in `target/`).

## Testing

```bash
# Check all files (CI standard)
sbt scalafmtCheckAll

# Format all files (developer workflow)
sbt scalafmtAll

# Check specific source set
sbt scalafmtCheck
sbt Test/scalafmtCheck

# Format a single file (standalone CLI)
scalafmt src/main/scala/MyClass.scala

# Check a single file
scalafmt --check src/main/scala/MyClass.scala

# Preview changes without writing (diff mode)
scalafmt --test src/main/scala/MyClass.scala

# Migrate config to current version
scalafmt --migrate-config
```

## Dos

- Set `version` explicitly in `.scalafmt.conf` — scalafmt warns (and sbt plugin errors) when the version is missing or mismatched between config and plugin.
- Configure `runner.dialect` matching your Scala version — formatting is syntax-aware and incorrect dialect produces broken output for Scala 3 syntax.
- Add `project.excludeFilters` for `.metals`, `.bloop`, and `target/` — scalafmt will format files in these directories if they contain `.scala` files and can corrupt generated sources.
- Use `scalafmtCheckAll` in CI (not `scalafmtAll`) — check-only mode fails the build without writing files, making CI behavior predictable.
- Format on save in IntelliJ IDEA via scalafmt integration — keeps files consistently formatted and reduces PR noise from style-only changes.
- Use `// format: off` / `// format: on` only for manually aligned data structures like matrices or lookup tables — not as a general escape hatch.

## Don'ts

- Don't commit auto-formatted diffs in the same commit as functional changes — reviewers cannot distinguish style changes from logic changes.
- Don't use `align.preset = most` in large codebases — alignment causes cascading reformatting when variable names change length, creating noisy diffs.
- Don't change `maxColumn` or `indent.main` without formatting the entire codebase in a single dedicated commit — partial formatting creates inconsistent style.
- Don't use `newlines.source = unfold` on existing codebases — it rewrites every multi-line expression to single-line where possible, creating massive diffs.
- Don't skip adding `.scalafmt.conf` to version control — without it, developers and CI use different default settings.
- Don't configure scalafmt at both workspace and project level with conflicting settings — scalafmt uses the nearest `.scalafmt.conf` upward from the file being formatted.
