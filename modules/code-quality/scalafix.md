---
name: scalafix
categories: [linter]
languages: [scala]
exclusive_group: scala-linter
recommendation_score: 90
detection_files: [.scalafix.conf, project/plugins.sbt]
---

# scalafix

## Overview

Scala linter and automated refactoring tool. Scalafix applies semantic rewrites (e.g., remove unused imports, upgrade deprecated APIs, enforce naming conventions) via a pluggable rule system. Configuration lives in `.scalafix.conf`. Unlike scalafmt (formatting only), scalafix understands the Scala semantic model — it knows which identifiers are unused, which methods are deprecated, and how to safely migrate code across API versions. It integrates into sbt via `sbt-scalafix` and can run in check mode (`--check`) for CI enforcement.

## Architecture Patterns

### Installation & Setup

```scala
// project/plugins.sbt
addSbtPlugin("ch.epfl.scala" % "sbt-scalafix" % "0.13.0")
```

For semantic rules (most useful rules), enable the SemanticDB compiler plugin:
```scala
// build.sbt
ThisBuild / semanticdbEnabled := true
ThisBuild / semanticdbVersion := scalafixSemanticdb.revision
```

```bash
# Run all configured rules
sbt scalafix

# Check mode (CI — no writes)
sbt "scalafix --check"

# Run a specific rule
sbt "scalafix RemoveUnused"

# Run on test sources too
sbt "Test / scalafix"
```

Standalone CLI:
```bash
cs install scalafix
scalafix --rules RemoveUnused --check
```

### Rule Categories

| Rule | Type | What It Does | Pipeline Severity |
|---|---|---|---|
| `RemoveUnused` | Semantic | Remove unused imports, variables, private members | WARNING |
| `OrganizeImports` | Semantic | Group and sort imports per configurable policy | INFO |
| `DisableSyntax` | Syntactic | Ban specific syntax (e.g., `null`, `throw`, `var`) | WARNING/CRITICAL |
| `LeakingImplicitClassVal` | Semantic | Flag implicit class `val` members that leak to outer scope | WARNING |
| `NoValInForComprehension` | Syntactic | Disallow `val` in for-comprehension body | INFO |
| `ProcedureSyntax` | Syntactic | Migrate `def foo() { }` to `def foo(): Unit = { }` | WARNING |
| `ExplicitResultTypes` | Semantic | Require explicit return types on public members | WARNING |

Community rules (via `scalafix-rules` or custom):
- `scala/scala-migrations` — Scala 2.x → 3.x API migration rewrites
- `typelevel/cats-scalafix` — cats idiom enforcement
- Custom organizational rules via `scalafix-core` API

### Configuration Patterns

`.scalafix.conf` at the project root:

```hocon
# .scalafix.conf
rules = [
  RemoveUnused,
  OrganizeImports,
  DisableSyntax
]

# RemoveUnused configuration
RemoveUnused.imports = true
RemoveUnused.privates = true
RemoveUnused.locals = true
RemoveUnused.patternvars = true
RemoveUnused.params = false   # params removal can break overrides

# OrganizeImports configuration
OrganizeImports.groups = [
  "re:javax?\\.",      # Java standard library first
  "scala.",            # Scala standard library second
  "*",                 # Third-party
  "com.yourorg."       # Internal last
]
OrganizeImports.removeUnused = true
OrganizeImports.blankLines = Auto

# DisableSyntax — ban dangerous or deprecated patterns
DisableSyntax.noVars = true
DisableSyntax.noNulls = true
DisableSyntax.noReturns = true
DisableSyntax.noWhileLoops = false    # allow while loops
DisableSyntax.noAsInstanceOf = true   # force pattern matching over casts
DisableSyntax.noIsInstanceOf = true   # force pattern matching
DisableSyntax.noSemicolons = true
DisableSyntax.noXml = true
DisableSyntax.noFinalVal = false      # allow final val

# ExplicitResultTypes (opt-in)
# ExplicitResultTypes.memberVisibility = [Public, Protected]
```

Inline suppression:
```scala
// scalafix:off RemoveUnused
import scala.util.control.NonFatal  // imported for re-export in this package object
// scalafix:on RemoveUnused

val x = 1 // scalafix:ok DisableSyntax.noVars — needed for mutable accumulator
```

### CI Integration

```yaml
# .github/workflows/quality.yml
- name: Scalafix check
  run: sbt "scalafix --check; Test / scalafix --check"

- name: Cache sbt
  uses: actions/cache@v4
  with:
    path: |
      ~/.sbt
      ~/.ivy2/cache
      ~/.coursier/cache
    key: sbt-${{ hashFiles('**/build.sbt', '**/plugins.sbt') }}
```

Separate scalafix and scalafmt checks:
```yaml
- name: Scalafmt check
  run: sbt scalafmtCheckAll

- name: Scalafix check
  run: sbt "scalafix --check"
```

## Performance

- Semantic rules require SemanticDB compilation, adding ~10-20% compile time overhead. Syntactic rules (e.g., `DisableSyntax`, `ProcedureSyntax`) run without SemanticDB.
- Enable SemanticDB only in development and CI — not in release builds: `ThisBuild / semanticdbEnabled := !insideCI.value` or gate with a separate sbt configuration.
- `RemoveUnused` and `OrganizeImports` require a full compilation pass before running — they cannot run incrementally without SemanticDB data.
- For large multi-project builds, run scalafix per sub-project in parallel CI jobs rather than sequentially from root.
- The `.scalafix/` cache directory stores rule compilation artifacts — cache it in CI alongside `.ivy2/` and `.sbt/`.

## Security

Scalafix is primarily a code quality tool, but `DisableSyntax` can enforce security-relevant conventions:

- `DisableSyntax.noNulls` — eliminates null references that can cause NullPointerException in unexpected code paths.
- `DisableSyntax.noAsInstanceOf` — unsafe casts can cause ClassCastException; pattern matching with sealed types is safer.
- `DisableSyntax.noVars` — mutable state is harder to reason about in concurrent code; banning vars enforces immutability.

For Scala security analysis (SSRF, injection), pair scalafix with dedicated SAST tools. Scalafix does not perform taint analysis.

## Testing

```bash
# Run all rules
sbt scalafix

# Check only (CI mode)
sbt "scalafix --check"

# Run on test sources
sbt "Test / scalafix"

# Run a specific rule without adding to config
sbt "scalafix RemoveUnused"

# Run with verbose output
sbt "scalafix --verbose"

# List available rules
sbt "scalafix --rules"

# Validate .scalafix.conf
sbt "scalafix --check --rules RemoveUnused"

# Apply fixes and check diff
git diff --stat  # after running sbt scalafix
```

## Dos

- Enable `semanticdbEnabled` in `build.sbt` for all projects that use semantic rules — without SemanticDB, `RemoveUnused` and `OrganizeImports` silently skip files.
- Run `scalafix` and `scalafmt` in separate sbt tasks in CI — they are independent tools with independent caches and interleaving them creates unnecessary recompilation.
- Use `OrganizeImports` with a defined group order matching your project conventions — consistent import ordering reduces merge conflicts in frequently edited files.
- Enable `DisableSyntax.noNulls` and `DisableSyntax.noAsInstanceOf` for new Scala code — these patterns are incompatible with idiomatic Scala and Option-based null safety.
- Add `.scalafix.conf` to version control — team-wide consistency requires shared configuration.
- Run `Test / scalafix` in CI — test code accumulates unused imports and vars just as production code does.

## Don'ts

- Don't enable `ExplicitResultTypes` for all members without measuring CI impact — it triggers a full recompilation of every file that changes and can double build times.
- Don't enable `RemoveUnused.params = true` — removing unused parameters in method signatures breaks overrides and callers; it requires manual intervention, not automated removal.
- Don't mix `scalafix` and `scalafmt` rewrites in the same commit — reviewing automated rewrites alongside semantic fixes is confusing. Apply formatting first, then semantic rules.
- Don't disable SemanticDB in release builds by default and then wonder why CI scalafix results differ from local — use a dedicated `scalafixCheck` sbt configuration that always enables SemanticDB.
- Don't use `scalafix:off` without re-enabling with `scalafix:on` — file-wide suppression is not the intended use and masks entire rule categories.
