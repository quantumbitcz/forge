# Generalized Check Engine & Multi-Language Pipeline Enhancement

**Date:** 2026-03-21
**Status:** Reviewed (spec review iteration 1 — all critical/important issues resolved)
**Author:** Denis Sajnar + Claude

## Summary

Restructure the dev-pipeline plugin from per-module bash scripts to a generalized, three-layer check engine with best-practice examples, support for 11 language/framework modules, and four new pipeline capabilities. The goal is to make adding a new language/framework module as simple as writing 3 config files while providing deep, linter-grade analysis across all supported languages.

## Motivation

The current pipeline has two fully-implemented modules (kotlin-spring, react-vite) with scripts tightly coupled to the wellplanned project structure. Adding a new language requires duplicating and adapting ~8 scripts per module. The two consuming projects (wellplanned-be, wellplanned-fe) also need capabilities the pipeline doesn't yet offer: test coverage bootstrapping, cross-repo contract validation, migration orchestration, and post-ship preview validation.

## Design Decisions

| Decision | Choice | Alternatives considered |
|---|---|---|
| Module architecture | Generalized core + thin modules (3 files each) | Full parity per module (~15 files each), tiered approach |
| Check architecture | Three-layer hybrid (fast patterns + linter bridge + agent intelligence) | Pure YAML/bash engine, pure linter delegation |
| Deprecation sourcing | Hybrid: curated YAML baselines + agent-driven refresh via context7 | Manual-only, live-only |
| Rule seeding | From existing linter databases (SonarQube, Detekt, ESLint, Clippy, Ruff, etc.) | Hand-written only |
| Examples | Generic best-practice per language + hook for future project-specific auto-discovery | Project-specific only, none |
| Sequencing | Foundation-first (engine + modules), then new capabilities | Impact-first, vertical slice |
| Backward compatibility | Old scripts become thin wrappers for 1 release, then removed | Hard cut, no transition |
| Rule file format | JSON (machine-parsed by `python3 -c "import json"`) | YAML (needs external parser), pure bash (fragile) |
| Severity levels | Three levels: CRITICAL, WARNING, INFO (matching `scoring.md`) | Adding a fourth `HIGH` level (breaks existing scoring formula) |

---

## Foundational Contracts

### Severity Levels

All layers use exactly three severity levels, matching `scoring.md`:

| Level | Score impact | Meaning |
|---|---|---|
| CRITICAL | -20 points | Must fix. Blocks PASS verdict if any present. Security, data loss, build break. |
| WARNING | -5 points | Should fix. Architecture violations, performance issues, readability problems. |
| INFO | -2 points | Consider fixing. Style, minor improvements, suggestions. |

No other severity levels exist. Rules and linter severity maps must normalize to these three.

### Output Format (`output-format.md`)

Every finding across all three layers uses this format:

```
file:line | CATEGORY-CODE | SEVERITY | message | fix_hint
```

- `file` — project-relative path (e.g., `src/main/kotlin/domain/User.kt`)
- `line` — 1-based line number. Use `0` for file-level findings (e.g., file too large).
- `CATEGORY-CODE` — from `scoring.md` taxonomy: `ARCH-*`, `SEC-*`, `PERF-*`, `QUAL-*`, `CONV-*`, `DOC-*`, `TEST-*`, plus module-specific codes (`HEX-*`, `THEME-*`). New subcategories: `QUAL-NULL`, `QUAL-READ`, `PERF-BLOCK`, `PERF-ASYNC`.
- `SEVERITY` — exactly one of: `CRITICAL`, `WARNING`, `INFO`.
- `message` — human-readable description.
- `fix_hint` — one-line suggested fix. Optional (empty string if no hint).
- Pipe `|` delimiter. If message or hint contains `|`, escape as `\|`.
- Multi-line findings: emit one line per finding location. Group in post-processing via deduplication key `(file, line, category)`.

### Invocation Contract for `engine.sh`

`engine.sh` operates in three modes, determined by arguments:

```bash
# Mode 1: PostToolUse hook (single file, Layer 1 only)
# Called by plugin.json hook. Receives TOOL_INPUT env var from Claude Code.
engine.sh --hook
# Reads: $TOOL_INPUT (JSON with file_path field)
# Runs: Layer 1 only
# Speed: <1s target

# Mode 2: VERIFY stage (full project scan, Layer 1 + Layer 2)
engine.sh --verify --project-root /path/to/project [--files-changed file1 file2 ...]
# Runs: Layer 1 on changed files + Layer 2 linter on project
# Speed: 5-30s target

# Mode 3: REVIEW stage (full project scan, all layers)
engine.sh --review --project-root /path/to/project [--files-changed file1 file2 ...]
# Runs: Layer 1 + Layer 2 + Layer 3 agent findings (passed in via stdin)
# Speed: depends on Layer 3 agent runtime
```

**Environment variables:**
- `TOOL_INPUT` — JSON from Claude Code hook system (Mode 1 only). Contains `file_path`.
- `PLUGIN_ROOT` — path to dev-pipeline plugin root (set by Claude Code for plugins).

### Module Detection

In all modes, `engine.sh` needs to know the active module for loading `rules-override.json`. Detection strategy:

1. **Check `dev-pipeline.local.md`** — read the `module:` field from the YAML frontmatter in `{project-root}/.claude/dev-pipeline.local.md`. This is the authoritative source.
2. **Fallback: auto-detect from project markers** — if no `dev-pipeline.local.md` exists (e.g., project not yet configured):
   - `build.gradle.kts` + `src/main/kotlin/` → `kotlin-spring`
   - `build.gradle.kts` + `src/main/java/` → `java-spring`
   - `package.json` + `vite.config.*` + React dependency → `react-vite`
   - `package.json` + `svelte.config.*` → `typescript-svelte`
   - `package.json` + no frontend framework → `typescript-node`
   - `pyproject.toml` + FastAPI dependency → `python-fastapi`
   - `go.mod` → `go-stdlib`
   - `Cargo.toml` → `rust-axum`
   - `Package.swift` + Vapor dependency → `swift-vapor`
   - `*.xcodeproj` or `Package.swift` + no Vapor → `swift-ios`
   - `Makefile` + `*.c`/`*.h` files → `c-embedded`
3. **Fallback: language-only** — if no module detected, use base language rules only (no `rules-override.json`).

In PostToolUse mode (Mode 1), `engine.sh` caches the detected module in `.pipeline/.module-cache` (a single line: the module name) to avoid re-parsing `dev-pipeline.local.md` on every file edit. Cache is invalidated when `dev-pipeline.local.md` is modified.

### Hook Registration in `plugin.json`

The updated `plugin.json` registers `engine.sh` for Edit and Write tool use:

```json
{
  "hooks": [
    {
      "event": "PostToolUse",
      "matcher": "Edit|Write",
      "command": "shared/checks/engine.sh --hook",
      "timeout": 5000
    },
    {
      "event": "PostToolUse",
      "matcher": "Skill",
      "command": "hooks/pipeline-checkpoint.sh",
      "timeout": 5000
    },
    {
      "event": "Stop",
      "command": "hooks/feedback-capture.sh",
      "timeout": 3000
    }
  ]
}
```

The existing checkpoint and feedback hooks remain unchanged. The new `engine.sh --hook` entry replaces per-module hook registrations in consuming projects' `settings.json`.

---

## Phase 1: Generalized Check Engine + Multi-Language Modules

### Architecture Overview

```
shared/checks/
  engine.sh                          # Unified entry point: detect language, dispatch layers
  output-format.md                   # Unified finding schema matching scoring.md

  layer-1-fast/                      # PostToolUse hook — grep + awk based, <1s
    patterns/
      kotlin.json
      java.json
      typescript.json
      python.json
      go.json
      rust.json
      c.json
      swift.json
    run-patterns.sh                  # Reads JSON via python3, runs grep, formats findings

  layer-2-linter/                    # VERIFY stage — real linters, 5-30s
    adapters/
      detekt.sh
      eslint.sh
      clippy.sh
      ruff.sh
      go-vet.sh
      clang-tidy.sh
      swiftlint.sh
    config/
      severity-map.json              # Linter rule ID -> pipeline severity
    defaults/                        # Default linter configs for unconfigured projects
      detekt.yml
      eslint.config.js
      ruff.toml
    run-linter.sh                    # Detect available linter, run adapter, normalize

  layer-3-agent/                     # REVIEW + PREFLIGHT — AI-powered, 30-60s
    deprecation-refresh.md           # Agent: query context7 + registries -> update known-deprecations
    version-compat.md                # Agent: analyze dependency tree for conflicts
    known-deprecations/
      kotlin.json
      typescript.json
      python.json
      go.json
      rust.json
      c.json
      swift.json
      java.json

  examples/                          # Best-practice reference code
    kotlin/
      null-safety.md
      coroutines.md
      error-handling.md
      testing.md
      readability.md
    typescript/
      async-patterns.md
      error-handling.md
      component-patterns.md
      testing.md
      readability.md
    python/
      error-handling.md
      async-patterns.md
      testing.md
      readability.md
    go/
      error-handling.md
      concurrency.md
      testing.md
      readability.md
    rust/
      ownership-patterns.md
      error-handling.md
      testing.md
      readability.md
    c/
      memory-safety.md
      error-handling.md
      readability.md
    swift/
      optionals.md
      concurrency.md
      testing.md
      readability.md
    java/
      null-safety.md
      error-handling.md
      testing.md
      readability.md
```

### Layer 1: Fast Pattern Checks

Runs on every file edit via PostToolUse. Replaces all current per-module scripts.

**Flow:**
1. `engine.sh` receives mode flag and input (see Invocation Contract above)
2. Detects language from file extension (`.kt` -> kotlin, `.tsx` -> typescript, etc.)
3. Detects active module (see Module Detection above)
4. Loads `layer-1-fast/patterns/{language}.json` via `python3 -c "import json; ..."`
5. If module override exists (e.g., `modules/kotlin-spring/rules-override.json`), merges it
6. `run-patterns.sh` iterates rules, runs grep per pattern, formats output per `output-format.md`

**Rule file format: JSON** (parsed via `python3 -c "import json"` — stdlib, no pip install needed). JSON chosen over YAML because: (a) `python3` is already a runtime dependency in existing scripts, (b) `json` is in Python's stdlib unlike `yaml`, (c) no ambiguity in parsing.

**Rule JSON schema** (e.g., `layer-1-fast/patterns/kotlin.json`):

```json
{
  "language": "kotlin",
  "extensions": [".kt", ".kts"],
  "source": "detekt, SonarKotlin, kotlinlang.org best practices",
  "rules": [
    {
      "id": "KT-NULL-001",
      "name": "non-null-assertion",
      "pattern": "!!",
      "exclude_pattern": "^\\s*//",
      "severity": "WARNING",
      "category": "QUAL-NULL",
      "message": "Non-null assertion (!!) — use safe calls or Elvis operator",
      "fix_hint": "Replace x!! with x ?: default or x?.let { }",
      "example_ref": "kotlin/null-safety.md#safe-call-pattern",
      "scope": "all"
    },
    {
      "id": "KT-BLOCK-001",
      "name": "blocking-call",
      "pattern": "Thread\\.sleep|runBlocking",
      "exclude_pattern": "^\\s*//",
      "severity": "WARNING",
      "category": "PERF-BLOCK",
      "message": "Blocking call in coroutine codebase — use delay() or withContext(Dispatchers.IO)",
      "fix_hint": "Replace Thread.sleep() with delay(), wrap blocking IO in withContext(Dispatchers.IO)",
      "example_ref": "kotlin/coroutines.md#structured-concurrency",
      "scope": "main"
    },
    {
      "id": "KT-SEC-001",
      "name": "hardcoded-credential",
      "pattern": "(password|secret|token|apikey)\\s*=\\s*\"[^\"]{3,}\"",
      "case_insensitive": true,
      "severity": "CRITICAL",
      "category": "SEC-CRED",
      "message": "Possible hardcoded credential",
      "fix_hint": "Move to environment variable or secret manager",
      "scope": "main"
    }
  ],
  "thresholds": {
    "file_size": {
      "default": 300,
      "overrides": {
        "impl/": 150,
        "controller/": 250,
        "mapper/": 200,
        "test/": 500
      }
    },
    "function_size": {
      "default": 30,
      "_note": "Detected via awk brace-counting, not grep. See Structural Checks below."
    }
  },
  "boundaries": [
    {
      "name": "No framework imports in domain",
      "scope_pattern": "core/domain/",
      "forbidden_imports": [
        "org.springframework.data",
        "org.springframework.r2dbc"
      ],
      "message": "Domain model must be framework-free",
      "severity": "WARNING",
      "category": "ARCH-BOUNDARY"
    }
  ],
  "deprecations": {
    "known_deprecations_file": "layer-3-agent/known-deprecations/kotlin.json"
  }
}
```

**Scope field semantics:**
- `"all"` — check all files matching this language's extensions
- `"main"` — files NOT matching `/test/`, `/tests/`, `/spec/`, `/test-fixtures/`, `/integrationTest/`
- `"test"` — files matching the above test path patterns
- Any other string is a regex matched against the **project-relative** path (e.g., `"core/domain/"`)

**Structural checks** (function size, nesting depth):

These cannot be implemented with grep alone. `run-patterns.sh` includes a lightweight `awk` pass for:
- **Function size** — counts lines between function boundaries (language-specific: `fun`/`{` in Kotlin, `function`/`=>` in TS, `def` in Python, `func` in Go, `fn` in Rust, function signatures in C/Swift/Java). Uses brace/indent counting.
- **Nesting depth** — tracks indent level or brace depth during the same awk pass.

These are the only non-grep checks in Layer 1. The awk pass runs once per file and checks both thresholds in a single scan.

**Readability rules** (present in every language JSON):

| Rule | Pattern | Severity | Category |
|---|---|---|---|
| Deep nesting (>3 levels) | awk-based (see above) | WARNING | QUAL-READ |
| Magic numbers in comparisons | `[=<>!]=?\s*\d{2,}` | INFO | QUAL-READ |
| Single-letter variable names (non-loop) | Language-specific | INFO | QUAL-READ |
| Negated conditionals | `!is[A-Z].*\|\|`, `!has[A-Z]` | INFO | QUAL-READ |
| Abbreviated names (<4 chars) | Language-specific | INFO | QUAL-READ |

**Module override schema** (e.g., `modules/kotlin-spring/rules-override.json`):

```json
{
  "extends": "kotlin",
  "framework": "spring",
  "additional_rules": [
    {
      "id": "KS-ARCH-001",
      "name": "transactional-on-adapter",
      "pattern": "@Transactional",
      "scope_pattern": "/adapter/",
      "severity": "WARNING",
      "category": "ARCH-BOUNDARY",
      "message": "@Transactional on adapter class — should be on use case only"
    }
  ],
  "additional_boundaries": [
    {
      "name": "Core must not import adapters",
      "scope_pattern": "core/src/main",
      "forbidden_imports": ["adapter\\."],
      "severity": "CRITICAL",
      "category": "ARCH-BOUNDARY"
    }
  ],
  "disabled_rules": ["KT-BLOCK-001"],
  "severity_overrides": {
    "KT-NULL-001": "INFO"
  },
  "threshold_overrides": {
    "file_size": {
      "port/": 100,
      "adapter/": 200
    }
  }
}
```

**Merge strategy:**
- Module overrides **add** rules via `additional_rules` and `additional_boundaries`.
- Module overrides can **disable** base rules via `disabled_rules` (list of rule IDs to skip).
- Module overrides can **change severity** of base rules via `severity_overrides` (rule ID -> new severity).
- Module overrides can **override thresholds** via `threshold_overrides` (path pattern -> value replaces base).
- Base language rules not in `disabled_rules` always apply at their (possibly overridden) severity.

### Layer 2: Linter Bridge

Runs during the VERIFY stage. Delegates to real, installed linters and normalizes output.

**Linter adapter mapping:**

| Language | Primary linter | Fallback | Config detection |
|---|---|---|---|
| Kotlin | detekt | ktlint | `detekt.yml` or gradle plugin |
| Java | detekt / SonarLint | checkstyle | `checkstyle.xml` or gradle plugin |
| TypeScript | eslint | biome | `eslint.config.*` or `.eslintrc.*` |
| Python | ruff | pylint, mypy | `ruff.toml`, `pyproject.toml [tool.ruff]` |
| Go | staticcheck | go vet | always available with Go toolchain |
| Rust | clippy | — | always available with cargo |
| C/C++ | clang-tidy | cppcheck | `.clang-tidy` or `compile_commands.json` |
| Swift | swiftlint | — | `.swiftlint.yml` |

**Adapter contract:**

```bash
#!/usr/bin/env bash
# Input:  $1 = project root, $2 = file or directory, $3 = severity-map config path
# Output: Unified findings to stdout: file:line | CATEGORY | SEVERITY | message | fix_hint
# Exit:   0 = ran successfully (findings may or may not be present in stdout)
#         1 = linter not installed or not available
#         2 = linter crashed or produced unparseable output
#
# IMPORTANT: Linters often exit non-zero when they find violations.
# Adapters MUST trap the linter exit code and normalize:
#   - Linter found issues but ran successfully -> exit 0, findings in stdout
#   - Linter is not installed -> exit 1
#   - Linter crashed or config error -> exit 2, error message to stderr
```

**Severity mapping** (`config/severity-map.json`):

Matching algorithm: exact rule ID match takes priority over glob pattern. Glob patterns use `*` suffix matching only (not full regex). Within globs, more specific patterns match first (longer prefix wins).

```json
{
  "detekt": {
    "_match_order": "exact first, then longest glob prefix",
    "SwallowedException": "CRITICAL",
    "complexity.*": "WARNING",
    "coroutines.*": "WARNING",
    "exceptions.*": "WARNING",
    "performance.*": "WARNING",
    "style.*": "INFO"
  },
  "eslint": {
    "no-eval": "CRITICAL",
    "react-hooks/exhaustive-deps": "WARNING",
    "_severity_map": {
      "error": "WARNING",
      "warn": "INFO"
    }
  },
  "clippy": {
    "correctness": "CRITICAL",
    "suspicious": "WARNING",
    "perf": "WARNING",
    "style": "INFO"
  },
  "ruff": {
    "S*": "WARNING",
    "E*": "WARNING",
    "F*": "WARNING",
    "UP*": "INFO",
    "ASYNC*": "WARNING"
  }
}
```

**Graceful degradation:**
- Linter installed + configured: run, normalize, merge with Layer 1
- Linter installed, not configured: run with adapter-provided defaults from `layer-2-linter/defaults/`
- Linter not installed: log INFO ("detekt not available, using pattern-based checks only"), Layer 1 findings stand alone

### Layer 3: Agent Intelligence

AI-powered checks for problems grep and linters can't solve.

**Deprecation Refresh Agent** (`deprecation-refresh.md`):
- Runs at PREFLIGHT stage
- For each project language: check age of `known-deprecations/{lang}.json`, skip if <7 days old
- Query context7 for latest library docs, check package registries
- Merge new deprecations into JSON, preserving existing entries
- Layer 1 picks up refreshed data on next file edit

**Known deprecations JSON schema:**

```json
{
  "language": "kotlin",
  "last_refreshed": "2026-03-21",
  "entries": [
    {
      "id": "KT-DEP-001",
      "pattern": "kotlin\\.jvm\\.Throws",
      "library": "kotlin-stdlib",
      "deprecated_in": "2.1.0",
      "removed_in": null,
      "replacement": "Use @Throws from kotlin package directly",
      "source": "kotlinlang.org/docs/whatsnew21.html",
      "severity": "WARNING"
    }
  ]
}
```

**Version Compatibility Agent** (`version-compat.md`):
- Runs at REVIEW stage, after implementation
- Three checks:
  1. **Dependency version conflicts** — reads dependency file, checks for incompatible pairs (e.g., react-dnd v16 + React 19). Build breaks = CRITICAL, runtime errors = CRITICAL, deprecation warnings = WARNING.
  2. **Language version feature usage** — detects features from newer language versions used against an older target (e.g., Kotlin context receivers on 1.9 target). Compile errors = CRITICAL, behavioral changes = WARNING.
  3. **Runtime compatibility** — checks for APIs removed in target runtime (e.g., SecurityManager in Java 17+, asyncio.coroutine in Python 3.11). Uses context7 for current docs. Removed APIs = CRITICAL, deprecated APIs = WARNING.
- If context7 is unavailable, the agent logs an INFO finding and skips live lookups. Curated deprecation baselines still apply.

### Best-Practice Examples

Reference code library that agents and Layer 1 cite when suggesting fixes.

**Structure per file:**

```markdown
# Null Safety Patterns (Kotlin)

## safe-call-pattern

**Instead of:**
...bad code...

**Do this:**
...good code...

**Why:** One sentence explaining the reasoning.
```

**Design principles:**
- Anchored by heading ID for `example_ref` linking (`kotlin/null-safety.md#safe-call-pattern`)
- Before/after pairs for every pattern
- Brief "why" (one sentence, not a tutorial)
- ~4-5 files per language, 4-8 patterns each, ~150-200 reference patterns total

**Categories per language:** error handling, null/optional safety, async/concurrency, testing, readability.

**Auto-discovery hook:** The `example_ref` field supports a future `project://` prefix for project-specific examples discovered during PREFLIGHT. Not implemented in this phase.

### Multi-Language Modules

**New modules (9):**

| Module | Prefix | Base language | Framework focus |
|---|---|---|---|
| `java-spring` | `ja-` | java | Spring Boot, Spring Security, JPA/Hibernate |
| `typescript-node` | `tn-` | typescript | Express, NestJS, Prisma |
| `typescript-svelte` | `sv-` | typescript | SvelteKit, Svelte 5 runes |
| `python-fastapi` | `py-` | python | FastAPI, SQLAlchemy, Pydantic |
| `go-stdlib` | `go-` | go | Standard library, Gin, Echo |
| `rust-axum` | `rs-` | rust | Axum, Tokio, SQLx |
| `c-embedded` | `ce-` | c | POSIX, embedded patterns |
| `swift-vapor` | `sw-` | swift | Vapor, SwiftNIO, Fluent |
| `swift-ios` | `si-` | swift | SwiftUI, UIKit, Combine |

**Each module contains 3-4 files:**

```
modules/{module-name}/
  conventions.md              # Agent-readable prose: architecture, patterns, idioms
  local-template.md           # Build/test/lint commands, scaffolder patterns, quality gate batches
  rules-override.json         # Framework-specific Layer 1 rules + threshold overrides
  pipeline-config-template.md # (optional) Runtime params — only if module needs non-default values
```

The existing modules have `pipeline-config-template.md` for mutable runtime params (max_fix_loops, domain hotspots, etc.). New modules inherit sensible defaults from the orchestrator and only need this file if they require module-specific tuning (e.g., different risk thresholds for embedded C vs web frameworks). Most new modules will ship without it initially.

**Multi-language project handling:**

Projects can be polyglot. `engine.sh` handles this by:
- In PostToolUse mode: checks only the edited file's language. Non-code extensions (`.yaml`, `.sql`, `.sh`, `.md`) are skipped unless a language JSON declares that extension.
- In VERIFY/REVIEW mode: scans all files matching any active language's extensions. The active module determines the primary language; additional languages are detected from file extensions present in the project.
- Module override rules only apply to files matching the module's base language. Base language rules apply to all files of that language regardless of module.

**Existing modules updated:**

| Module | Change |
|---|---|
| `kotlin-spring` | Delete `scripts/check-*.sh`, add `rules-override.json`, keep `pipeline-config-template.md` |
| `react-vite` | Delete `hooks/*-guard.sh`, move `known-deprecations.json` (schema migrated, see below), add `rules-override.json`, keep `pipeline-config-template.md` |

**Deprecation JSON schema migration:**

The existing `known-deprecations.json` in react-vite uses an older schema (`version`, `deprecations[]` with `package`, `since`, `added`, `addedBy` fields). During migration:
1. A one-time conversion script transforms old entries to the new schema (`deprecations[]` -> `entries[]`, `package` -> `library`, `since` -> `deprecated_in`, new fields `id`, `removed_in`, `source`, `severity` populated with sensible defaults).
2. The thin wrapper scripts during the transition period use the new schema (they delegate to engine.sh which reads the new format).
3. The conversion script is included in PR #6 (`feat/migrate-existing-modules`).

**Custom agents per module:**

Only kotlin-spring and react-vite retain custom review agents (existing `be-hex-*`, `fe-*`). java-spring shares the `be-hex-*` agents but with a note in its `conventions.md` that Java-specific patterns (JPA annotations, non-sealed interfaces) differ from Kotlin — the shared agent's instructions should check file extension and adjust accordingly. All other modules use built-in Code Reviewer + Security Engineer + plugin reviewers in their quality gate batches. Custom agents can be added later as patterns emerge.

---

## Phase 2: New Pipeline Capabilities

### Capability 1: Test Coverage Bootstrapping

**Agent:** `pl-150-test-bootstrapper`
**Trigger:** Manual via `/pipeline-run "bootstrap test coverage for {module}"` or when orchestrator detects coverage below threshold during PREFLIGHT.

**Flow:**
1. Analyze project structure, identify testable units
2. Prioritize by risk: business logic with branching (HIGH), data transformation (MEDIUM), pure UI (LOW)
3. Generate test files in batches (5-10 at a time), using `examples/` for idiomatic patterns
4. Run generated tests, fix failures, commit passing batch
5. Report: coverage before/after, files tested, files skipped

Not a replacement for TDD — generates regression safety net for existing code.

### Capability 2: Cross-Repo Contract Validation

**Agent:** `pl-250-contract-validator`
**Runs at:** VALIDATE stage (Stage 3)

**Configuration:**

```yaml
contracts:
  - type: openapi
    source: /path/to/api.yml
    consumer: /path/to/frontend/api/
    breaking_change_severity: CRITICAL
```

**Detects:**

| Change type | Severity |
|---|---|
| Endpoint removed | CRITICAL |
| Field removed from response | CRITICAL |
| Field type changed | CRITICAL |
| Required field added to request | WARNING |
| Enum value removed | WARNING |
| Endpoint path changed | WARNING |
| Optional field added | INFO |

Supports OpenAPI (first implementation), with extension points for Protobuf, GraphQL, shared TypeScript types.

### Capability 3: Migration/Upgrade Orchestration

**Agent:** `pl-160-migration-planner`
**Trigger:** `/pipeline-run "migrate: {description}"` — `migrate:` prefix activates migration mode.

**Migration mode vs feature mode:**

| Aspect | Feature mode | Migration mode |
|---|---|---|
| Scope | Single story | Project-wide |
| Planning | One pass | Multi-phase with checkpoints |
| Testing | Write new tests | Existing tests must keep passing |
| Risk | Assessed once | Re-assessed after each phase |
| Commits | One commit | Separate commit per phase |
| Quality gate | Once at end | After each phase |

**Phases:** Audit -> Compatibility -> Migrate (batch by feature area) -> Cleanup -> Verify

### Capability 4: Post-Ship Preview Validation

**Agent:** `pl-650-preview-validator`
**Runs at:** After `pl-600-pr-builder` creates the PR.

**Configuration:**

```yaml
preview:
  url_pattern: "https://pr-{pr_number}.preview.wellplanned.app"
  wait_for_deploy: 120
  health_endpoint: "/health"
  checks:
    - type: smoke
    - type: lighthouse
    - type: visual_regression
    - type: playwright
```

Uses Playwright MCP for smoke checks and visual regression. Appends results to PR as comment. Triggers fix cycle if auto-fixable issues found.

---

## Migration Path

### Impact on existing files

| File/Directory | Action |
|---|---|
| `modules/kotlin-spring/scripts/check-*.sh` (3) | Delete (replaced by engine + kotlin.yaml) |
| `modules/react-vite/hooks/*-guard.sh` (5) | Delete (replaced by engine + typescript.yaml) |
| `modules/react-vite/known-deprecations.json` | Move to `shared/checks/layer-3-agent/known-deprecations/typescript.json` + schema migration |
| `modules/*/local-template.md` | Update to point at `shared/checks/engine.sh` |
| `shared/stage-contract.md` | Add new agent entries, migration mode |
| `shared/state-schema.md` | Add migration mode fields, contract/preview results |
| `agents/pl-100-orchestrator.md` | Add migration mode, new agent dispatch |
| `plugin.json` | Update PostToolUse hook to call engine.sh |
| `CLAUDE.md`, `README.md` | Document new architecture |

### Consuming project updates

Both wellplanned-be and wellplanned-fe `.claude/settings.json` hooks update from:
```
.claude/plugins/dev-pipeline/modules/kotlin-spring/scripts/check-antipatterns.sh
```
to:
```
.claude/plugins/dev-pipeline/shared/checks/engine.sh
```

### Backward compatibility

1. `engine.sh` detects old-style per-module arguments, logs deprecation warning
2. For 1 release: old scripts become thin wrappers calling `engine.sh`
3. Next release: remove wrappers

### Delivery sequence

| # | Branch | Contents | Depends on |
|---|---|---|---|
| 1 | `feat/check-engine-core` | engine.sh, run-patterns.sh, output-format.md, JSON schema | — |
| 2 | `feat/language-rules` | `patterns/*.json` (8 languages) + `examples/` (~35 files) | #1 |
| 3 | `feat/linter-bridge` | `layer-2-linter/` — adapters, severity-map, run-linter.sh | #1 |
| 4 | `feat/agent-intelligence` | `layer-3-agent/` — agents, known-deprecations JSONs | #1 |
| 5 | `feat/new-modules` | 9 new module directories (3-4 files each) | #2 |
| 6 | `feat/migrate-existing-modules` | Update kotlin-spring + react-vite, delete old scripts, deprecation schema migration | #1, #2 |
| 7 | `feat/test-bootstrapper` | `pl-150-test-bootstrapper` agent | #1 |
| 8 | `feat/contract-validator` | `pl-250-contract-validator` agent | #1 |
| 9 | `feat/migration-orchestrator` | `pl-160-migration-planner` agent + orchestrator updates | #1 |
| 10 | `feat/preview-validator` | `pl-650-preview-validator` agent | #1 |
| 11 | `feat/update-contracts` | stage-contract.md, state-schema.md, scoring.md, CLAUDE.md, README | #6-#10 |

PRs 1-6 = Phase 1. PRs 7-11 = Phase 2.

### Estimated file count

| Category | Files |
|---|---|
| Check engine core (engine.sh, run-patterns.sh, output-format.md) | ~5 |
| Language rule JSONs | 8 |
| Linter adapters + config + defaults | ~13 |
| Agent intelligence (agents, deprecation JSONs) | ~12 |
| Examples | ~35 |
| New modules (9 x 3-4 files) | ~30 |
| New agents (Phase 2) | 4 |
| Migration (conversion script, updated existing files) | ~12 |
| **Total** | **~119** |
