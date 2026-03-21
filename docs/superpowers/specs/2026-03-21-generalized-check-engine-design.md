# Generalized Check Engine & Multi-Language Pipeline Enhancement

**Date:** 2026-03-21
**Status:** Reviewed (2 iterations — all critical/important issues resolved)
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

### Pipeline Modes

The pipeline operates in one of three modes. Each mode has its own `story_state` values and `--from` behavior:

| Mode | Trigger | `story_state` values | `--from` targets | Checkpoint `stage` field |
|---|---|---|---|---|
| **feature** (default) | `/pipeline-run "..."` | 10 standard states (PREFLIGHT through LEARNING) | Stage names: `explore`, `plan`, `validate`, `implement`, `verify`, `review`, `docs`, `ship`, `learn` | Integer 0-9 |
| **migration** | `/pipeline-run "migrate: ..."` | `MIGRATING`, `MIGRATION_PAUSED`, `MIGRATION_CLEANUP`, `MIGRATION_VERIFY` | Phase names: `migrate`, `cleanup`, `verify` + phase number: `migrate:3` (resume at phase 3) | String `"migration:{phase_number}"` |
| **bootstrap** | `/pipeline-run "bootstrap test coverage ..."` | `BOOTSTRAPPING` | Batch number: `bootstrap:5` (resume at batch 5) | String `"bootstrap:{batch_number}"` |

The `mode` field in `state.json` determines which state machine is active. The orchestrator, recovery engine, and checkpoint system all check `mode` before interpreting `story_state` or `stage` values.

Recovery engine behavior per mode:
- **feature mode:** Pre-stage health check matrix applies as documented. Recovery interacts with existing retry counters (`quality_cycles`, `test_cycles`, etc.).
- **migration mode:** Health checks run before each migration phase (not each batch). Recovery checkpoints at phase + batch granularity.
- **bootstrap mode:** Health checks run before each test generation batch. Recovery checkpoints at batch granularity.

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
- `CLAUDE_PLUGIN_ROOT` — path to dev-pipeline plugin root (set by Claude Code for plugins). Used for resolving relative paths to rule files, examples, etc.

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

The updated `plugin.json` adds an `engine.sh` entry for Edit and Write tool use, preserving the existing hook structure:

```json
{
  "name": "dev-pipeline",
  "description": "Reusable autonomous development pipeline with framework modules",
  "version": "0.2.0",
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/shared/checks/engine.sh --hook",
            "timeout": 5000
          }
        ]
      },
      {
        "matcher": "Skill",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/hooks/pipeline-checkpoint.sh",
            "timeout": 5000
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/hooks/feedback-capture.sh",
            "timeout": 3000
          }
        ]
      }
    ]
  }
}
```

The existing checkpoint and feedback hooks remain unchanged. The new `engine.sh --hook` entry replaces per-module hook registrations in consuming projects' `settings.json`. **Consuming projects should remove their old check/guard hook entries from `.claude/settings.json`** — the plugin-level hook now handles this centrally.

Convention for JSON metadata keys: underscore-prefixed keys (`_match_order`, `_severity_map`, `_note`) in any JSON config file are documentation/metadata, not functional data. Parsers must skip keys starting with `_`.

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
      checkstyle.sh
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

| Language | Primary linter | Fallback | Config detection | Adapter |
|---|---|---|---|---|
| Kotlin | detekt | ktlint | `detekt.yml` or gradle plugin | `detekt.sh` |
| Java | checkstyle | spotbugs | `checkstyle.xml` or gradle plugin | `checkstyle.sh` (new) |
| TypeScript | eslint | biome | `eslint.config.*` or `.eslintrc.*` | `eslint.sh` |
| Python | ruff | pylint, mypy | `ruff.toml`, `pyproject.toml [tool.ruff]` | `ruff.sh` |
| Go | staticcheck | go vet | always available with Go toolchain | `go-vet.sh` |
| Rust | clippy | — | always available with cargo | `clippy.sh` |
| C/C++ | clang-tidy | cppcheck | `.clang-tidy` or `compile_commands.json` | `clang-tidy.sh` |
| Swift | swiftlint | — | `.swiftlint.yml` | `swiftlint.sh` |

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
**Agent file:** `agents/pl-150-test-bootstrapper.md`
**Tools:** `Read`, `Write`, `Edit`, `Bash`, `Glob`, `Grep`, `Agent` (for dispatching parallel test generators)

#### Trigger Conditions

Two entry paths:

1. **Manual:** `/pipeline-run "bootstrap test coverage for {feature-area}"` — runs as a standalone pipeline (skips PLAN/VALIDATE, goes straight to test generation).
2. **Automatic:** During PREFLIGHT, if the orchestrator detects test coverage below `test_bootstrapper.coverage_threshold` (default: 30%, configurable in `pipeline-config.md`), it suggests bootstrapping before proceeding with the feature. User can accept or skip.

#### Configuration (in `dev-pipeline.local.md`)

```yaml
test_bootstrapper:
  coverage_threshold: 30        # Below this %, suggest bootstrapping
  batch_size: 8                 # Tests generated per batch before running
  max_batches: 20               # Safety limit
  target_coverage: 60           # Stop when this % is reached
  skip_patterns:                # Files to never generate tests for
    - "**/generated/**"
    - "**/test-fixtures/**"
    - "**/types.ts"
    - "**/index.ts"
  priority_patterns:            # P1 targets (always test first)
    - "**/core/impl/**"         # Use cases
    - "**/hooks/use-*.ts"       # Custom hooks
    - "**/api/*.ts"             # API layer
```

#### Flow

```
PREFLIGHT
  → Read project config, detect test framework and conventions
  → Run coverage tool to get baseline (e.g., `./gradlew jacocoTestReport`, `bun run test -- --coverage`)
  → Parse coverage report → identify untested files

ANALYZE
  → For each untested file:
    1. Read the file, understand its purpose
    2. Classify: P1 (critical path — branching logic, state mutations, API calls),
                 P2 (core — mappers, transformers, utilities),
                 P3 (peripheral — pure rendering, constants, types)
    3. Estimate test complexity: simple (1-3 test cases), moderate (4-8), complex (9+)
  → Sort by priority (P1 first), then by complexity (simple first within priority)
  → Write analysis to `.pipeline/stage_notes_bootstrap.md`

GENERATE (batch loop)
  → For each batch of `batch_size` files (starting from top of priority list):
    1. Read the source file + any types/interfaces it depends on
    2. Read relevant `examples/{lang}/testing.md` for idiomatic patterns
    3. Read existing test files in the project for conventions (describe style, import patterns, mock setup)
    4. Generate test file following project conventions:
       - File placement: project's test directory structure (e.g., `src/tests/{feature}/` or co-located)
       - Test framework: detected from config (Kotest, Vitest, pytest, Go testing, etc.)
       - Test fixtures: reuse existing factories/helpers if available
       - Coverage targets: at minimum test the happy path + one error path per public function
       - Data: use realistic domain data, not "foo"/"bar" placeholder values
    5. Run the test: `{test_command} --filter={test_file}`
    6. If test fails:
       - Read error output
       - Fix the test (up to 3 attempts per file)
       - If still failing after 3 attempts: skip file, log reason
    7. If test passes: stage the file

  → After each batch:
    - Run full test suite to catch regressions
    - If regressions: revert the batch, skip problematic files, re-run
    - If clean: commit batch with message `test: bootstrap coverage for {feature-area} (batch N)`
    - Re-run coverage tool, check against `target_coverage`
    - If target reached: stop

REPORT
  → Write `.pipeline/reports/bootstrap-{date}.md`:
    - Coverage before: X%
    - Coverage after: Y%
    - Files tested: N (P1: a, P2: b, P3: c)
    - Files skipped: M (with reasons)
    - Test quality notes: any patterns the generated tests don't cover well
  → Update `pipeline-log.md` with PREEMPT items for untestable patterns discovered
```

#### Output Artifacts

| Artifact | Location | Committed? |
|---|---|---|
| Generated test files | Project's test directory | Yes (one commit per batch) |
| Bootstrap report | `.pipeline/reports/bootstrap-{date}.md` | No |
| Stage notes | `.pipeline/stage_notes_bootstrap.md` | No |
| Coverage reports | `.pipeline/coverage/` | No |

#### State Schema Extension

New fields in `state.json` when running in bootstrap mode:

```json
{
  "mode": "bootstrap",
  "bootstrap": {
    "coverage_before": 2.1,
    "coverage_current": 45.3,
    "coverage_target": 60,
    "batches_completed": 5,
    "files_tested": 38,
    "files_skipped": 4,
    "files_remaining": 12
  }
}
```

#### Constraints

- **Not a replacement for TDD.** This generates regression tests for *existing* untested code. New features still go through the TDD implementation stage (pl-300-implementer RED/GREEN/REFACTOR).
- **Does not mock everything.** For integration-heavy code (database, API calls), generates integration test stubs that assert the function signature and basic behavior, not full integration tests. Those require project-specific infrastructure (Testcontainers, MSW, etc.).
- **Respects existing test conventions.** If the project already has 5 tests using a specific pattern, the bootstrapper follows that pattern, not the generic examples.
- **Idempotent.** Running bootstrap twice skips already-tested files. The priority list is re-calculated each run based on current coverage.

---

### Capability 2: Cross-Repo Contract Validation

**Agent:** `pl-250-contract-validator`
**Agent file:** `agents/pl-250-contract-validator.md`
**Tools:** `Read`, `Glob`, `Grep`, `Bash`, `Agent` (for dispatching diff analysis)

#### When It Runs

During the VALIDATE stage (Stage 3), after the planner produces a plan but before implementation begins. The orchestrator checks `contracts` config — if present, dispatches this agent before `pl-210-validator`.

Also available as a standalone check: `/pipeline-run "validate contracts"`.

#### Configuration (in `dev-pipeline.local.md`)

```yaml
contracts:
  - name: "wellplanned-api"
    type: openapi
    source: /Users/denissajnar/IdeaProjects/wellplanned-be/wellplanned-adapter/input/api/spec/api.yml
    consumer: /Users/denissajnar/WebstormProjects/wellplanned-fe/src/app/api/
    baseline_branch: master          # Compare against this branch's version
    breaking_change_severity: CRITICAL

  # Future extension examples:
  # - name: "shared-types"
  #   type: typescript
  #   source: /path/to/shared/types/index.ts
  #   consumer: /path/to/consuming/project/
  #   baseline_branch: main
  #
  # - name: "grpc-contract"
  #   type: protobuf
  #   source: /path/to/proto/
  #   consumer: /path/to/generated/client/
  #   baseline_branch: main
```

#### Flow

```
LOAD CONTRACTS
  → Read contracts config from dev-pipeline.local.md
  → For each contract:

DIFF
  → Get baseline version: `git show {baseline_branch}:{source_path}` (the contract as it was before changes)
  → Get current version: read current file from disk
  → If no baseline (new contract): skip diff, report INFO "new contract detected"
  → If unchanged: skip, report "contract unchanged"

ANALYZE (OpenAPI-specific)
  → Parse both versions (baseline and current) as OpenAPI 3.x specs
  → Compare at structural level:

  Endpoint-level changes:
    → For each endpoint in baseline:
      - If missing in current: CRITICAL "Endpoint removed: {method} {path}"
      - If path changed: WARNING "Endpoint path changed: {old} -> {new}"
    → For each endpoint in current not in baseline:
      - INFO "New endpoint: {method} {path}"

  Schema-level changes (request/response bodies):
    → For each schema referenced by an endpoint:
      - Field removed from response: CRITICAL "Response field removed: {schema}.{field}"
      - Field type changed: CRITICAL "Field type changed: {schema}.{field} ({old_type} -> {new_type})"
      - Required field added to request: WARNING "Required request field added: {schema}.{field}"
      - Optional field added to request: INFO "Optional request field added: {schema}.{field}"
      - Field added to response: INFO "Response field added: {schema}.{field}"
      - Enum value removed: WARNING "Enum value removed: {schema}.{field}.{value}"
      - Enum value added: INFO "Enum value added: {schema}.{field}.{value}"

  Parameter changes:
    → Required path/query parameter added: WARNING
    → Parameter removed: CRITICAL
    → Parameter type changed: CRITICAL

CONSUMER IMPACT
  → For each breaking/warning finding, search the consumer codebase for usage:
    - Grep consumer directory for endpoint paths, field names, enum values
    - If used: annotate finding with "USED by: {consumer_file}:{line}"
    - If not used: downgrade severity by one level (CRITICAL -> WARNING, WARNING -> INFO)
    This prevents false alarms for contract changes that don't affect the actual consumer.

REPORT
  → Emit findings in unified output format (file:line | CATEGORY | SEVERITY | message | fix_hint)
  → File = contract source path, line = best-effort line in spec
  → Category: `CONTRACT-BREAK`, `CONTRACT-CHANGE`, `CONTRACT-ADD`
  → Write detailed analysis to `.pipeline/stage_3_notes_{storyId}.md`
  → If any CRITICAL findings: recommend plan revision to handle contract migration
```

#### Breaking Change Detection Matrix

| Change Type | Category | Base Severity | If unused by consumer |
|---|---|---|---|
| Endpoint removed | CONTRACT-BREAK | CRITICAL | WARNING |
| Field removed from response | CONTRACT-BREAK | CRITICAL | WARNING |
| Field type changed | CONTRACT-BREAK | CRITICAL | WARNING |
| Parameter removed | CONTRACT-BREAK | CRITICAL | WARNING |
| Parameter type changed | CONTRACT-BREAK | CRITICAL | WARNING |
| Required field added to request | CONTRACT-CHANGE | WARNING | INFO |
| Enum value removed | CONTRACT-CHANGE | WARNING | INFO |
| Endpoint path changed | CONTRACT-CHANGE | WARNING | INFO |
| Required parameter added | CONTRACT-CHANGE | WARNING | INFO |
| Optional field added to request | CONTRACT-ADD | INFO | INFO |
| Field added to response | CONTRACT-ADD | INFO | INFO |
| Enum value added | CONTRACT-ADD | INFO | INFO |
| New endpoint | CONTRACT-ADD | INFO | INFO |

#### State Schema Extension

New fields in `state.json`:

```json
{
  "contract_validation": {
    "contracts_checked": 1,
    "breaking_changes": 0,
    "warnings": 2,
    "infos": 5,
    "consumer_impact_findings": 1
  }
}
```

#### Extension Points for Future Contract Types

The agent uses a strategy pattern internally. Each contract type implements:

```
interface ContractDiffer:
  parse(content: string) -> ParsedContract
  diff(baseline: ParsedContract, current: ParsedContract) -> Finding[]
  findConsumerUsage(finding: Finding, consumerPath: string) -> Usage[]
```

| Type | Parser | Diff strategy | Consumer search |
|---|---|---|---|
| `openapi` | OpenAPI 3.x YAML/JSON parser | Endpoint + schema structural diff | Grep for paths, field names, types |
| `protobuf` (future) | Proto3 parser | Message field + service method diff | Grep for generated client method names |
| `graphql` (future) | GraphQL schema parser | Type + field + query diff | Grep for query/mutation names |
| `typescript` (future) | TS type extractor | Exported type structural diff | TS compiler import resolution |

Only `openapi` is implemented in Phase 2. Others are extension points documented in the agent file.

#### Constraints

- **Read-only on both repos.** The agent never modifies the source or consumer project. It only reads and compares.
- **Baseline from git, current from disk.** This catches uncommitted contract changes that would break the consumer.
- **Consumer impact is advisory.** Even if a field is unused by the consumer, the finding still exists at reduced severity — other consumers may exist.
- **Requires both repos accessible.** If the consumer path is unreachable, the agent runs diff-only without consumer impact analysis and logs an INFO finding.

---

### Capability 3: Migration/Upgrade Orchestration

**Agent:** `pl-160-migration-planner`
**Agent file:** `agents/pl-160-migration-planner.md`
**Tools:** `Read`, `Write`, `Edit`, `Bash`, `Glob`, `Grep`, `Agent` (for dispatching migration workers)

#### Trigger

`/pipeline-run "migrate: {description}"` — the `migrate:` prefix tells the orchestrator to activate migration mode instead of feature mode.

Examples:
- `/pipeline-run "migrate: replace react-dnd with @dnd-kit"`
- `/pipeline-run "migrate: upgrade React 18 to React 19"`
- `/pipeline-run "migrate: remove shadcn/ui wrapper layer"`
- `/pipeline-run "migrate: upgrade Spring Boot 3.x to 4.x"`

#### How Migration Mode Differs from Feature Mode

| Aspect | Feature mode (today) | Migration mode (new) |
|---|---|---|
| story_state | Uses standard 10 states | Uses `MIGRATING` with sub-states |
| Scope | Single story, localized changes | Project-wide, touches many files |
| Planning | One plan, one implementation pass | Multi-phase plan with per-phase checkpoints |
| Testing | Write new tests (TDD) | Existing tests must keep passing throughout. No new tests unless behavior changes. |
| Risk | Assessed once at PLAN stage | Re-assessed after each phase |
| Rollback | Git revert one commit | Each phase is a separate commit, independently revertable |
| Quality gate | Runs once after IMPLEMENT | Runs after each migration phase |
| Implementation | `pl-300-implementer` (TDD) | `pl-300-implementer` in migration-aware mode (no RED phase, preserve existing tests) |

#### Configuration (in `dev-pipeline.local.md`)

```yaml
migration:
  max_phases: 10                    # Safety limit on migration phases
  max_files_per_batch: 20           # Files changed per migration batch within a phase
  require_green_after_batch: true   # Run tests after each batch, not just each phase
  auto_rollback_on_failure: true    # Revert batch if tests fail
  parallel_batches: false           # Sequential by default (safer for interdependent changes)
```

#### Flow

```
PREFLIGHT (same as feature mode)
  → Config loaded, state initialized
  → Detect migration mode from "migrate:" prefix

EXPLORE (Stage 1)
  → Standard exploration, but focused on migration scope:
    - What library/pattern is being replaced?
    - How many files use it? (full audit)
    - What are the API surface changes? (old API vs new API)
    - Are there known migration guides? (use context7)

PLAN (Stage 2 — migration-specific)
  → `pl-160-migration-planner` replaces `pl-200-planner`
  → Produces a multi-phase migration plan:

  Phase 1: AUDIT
    - List every file using the old library/pattern
    - Categorize by migration complexity:
      - Simple (1:1 API replacement, e.g., import rename)
      - Moderate (API shape change, needs adaptation)
      - Complex (behavioral change, needs redesign)
    - Output: `.pipeline/migration-audit.json`

  Phase 2: PREPARE
    - Add new dependency alongside old (if applicable)
    - Create adapter/shim layer if needed for gradual migration
    - Verify project still builds and all tests pass
    - Commit: "chore: add {new-lib} alongside {old-lib}"

  Phase 3-N: MIGRATE (one phase per feature area)
    - Group files by feature area (e.g., "builder components", "shared hooks", "API layer")
    - For each group:
      Batch loop:
        1. Replace old API with new API in batch of files
        2. Run type checker / compiler
        3. If type errors: fix them
        4. Run tests
        5. If test failures:
           - If `auto_rollback_on_failure`: revert batch, log problematic files
           - If not: attempt fix (up to 3 tries), then escalate to user
        6. If clean: commit batch "refactor: migrate {feature-area} from {old} to {new} (batch M)"
      After all batches in phase:
        - Run full test suite
        - Run Layer 1 + Layer 2 checks
        - Quality gate scoring
        - If FAIL: pause, present findings to user
        - If PASS/CONCERNS: proceed to next phase
        - Update risk assessment

  Phase N+1: CLEANUP
    - Remove old dependency from package manifest
    - Remove adapter/shim layer
    - Remove old imports that are no longer used
    - Run dead code detection (Layer 2 linter)
    - Commit: "chore: remove {old-lib} and migration shims"

  Phase N+2: VERIFY
    - Full test suite
    - Full Layer 1 + Layer 2 + Layer 3 checks
    - Version compatibility check (new dependency tree is clean)
    - Quality gate with all review agents
    - Final commit if any cleanup needed

SHIP (Stage 8)
  → PR with all phase commits (squash optional, default: keep individual commits for traceability)
  → PR description includes migration summary:
    - Files migrated: N
    - Phases completed: M
    - Test suite: all passing
    - Quality score: X

LEARN (Stage 9)
  → Standard retrospective, plus:
    - Record migration patterns in pipeline-log.md for future similar migrations
    - If migration took >5 phases, record PREEMPT suggesting smaller scope next time
```

#### Migration Audit JSON Schema

```json
{
  "migration_id": "replace-react-dnd-with-dnd-kit",
  "old_library": "react-dnd",
  "new_library": "@dnd-kit/core",
  "total_files_affected": 23,
  "files": [
    {
      "path": "src/app/components/builder/day-column.tsx",
      "complexity": "complex",
      "feature_area": "builder",
      "usages": ["useDrag", "useDrop", "DndProvider"],
      "estimated_changes": 15,
      "dependencies": ["src/app/components/builder/plan-builder.tsx"]
    }
  ],
  "phases": [
    {
      "phase": 1,
      "name": "audit",
      "status": "completed"
    },
    {
      "phase": 2,
      "name": "prepare",
      "files": [],
      "status": "completed"
    },
    {
      "phase": 3,
      "name": "migrate-builder",
      "files": ["day-column.tsx", "plan-builder.tsx", "..."],
      "status": "in_progress",
      "batches_completed": 2,
      "batches_total": 4
    }
  ]
}
```

#### State Schema Extension

New fields in `state.json` when in migration mode:

```json
{
  "mode": "migration",
  "story_state": "MIGRATING",
  "migration": {
    "migration_id": "replace-react-dnd-with-dnd-kit",
    "current_phase": 3,
    "total_phases": 6,
    "phase_name": "migrate-builder",
    "batch_in_phase": 2,
    "total_batches_in_phase": 4,
    "files_migrated": 12,
    "files_remaining": 11,
    "files_skipped": 0,
    "phase_quality_scores": [95, 88],
    "rollbacks": 0
  }
}
```

New `story_state` values for migration mode:

| Value | Description |
|---|---|
| `"MIGRATING"` | Active migration in progress (phases 1-N) |
| `"MIGRATION_PAUSED"` | Paused due to quality gate failure or user request |
| `"MIGRATION_CLEANUP"` | Removing old dependencies and shims |
| `"MIGRATION_VERIFY"` | Final full verification after all phases |

These are additional valid values — the standard 10 states remain for feature mode.

#### Constraints

- **Never mixes old and new in the same file.** Each file is fully migrated or untouched — no partial migrations within a file.
- **Tests are the safety net, not the target.** Migration mode does NOT write new tests. If existing tests pass, the migration is correct. If behavior needs to change, that's a separate feature pipeline run.
- **User can pause and resume.** State is checkpointed after each batch. `/pipeline-run --from=migrate` resumes from the last completed batch.
- **Rollback granularity is per-batch.** Each batch is a separate commit. `git revert {batch-commit}` undoes exactly that batch.
- **Complex files may need manual intervention.** If a file fails 3 auto-fix attempts, the agent logs it as "manual intervention needed" and continues with other files. The SHIP stage PR lists these files as "requires manual review."

---

### Capability 4: Post-Ship Preview Validation

**Agent:** `pl-650-preview-validator`
**Agent file:** `agents/pl-650-preview-validator.md`
**Tools:** `Read`, `Bash`, `Grep`, `mcp__plugin_playwright_playwright__*` (all Playwright tools)

#### When It Runs

After `pl-600-pr-builder` creates the PR in Stage 8 (SHIP), the orchestrator checks for `preview` config. If present, it dispatches `pl-650-preview-validator` before transitioning to Stage 9 (LEARN).

This is an **optional sub-stage** of SHIP — projects without preview environments skip it entirely.

#### Configuration (in `dev-pipeline.local.md`)

```yaml
preview:
  enabled: true
  url_pattern: "https://pr-{pr_number}.preview.wellplanned.app"
  wait_for_deploy:
    timeout: 180                    # Seconds to wait for preview to become healthy
    poll_interval: 10               # Seconds between health checks
  health_endpoint: "/health"        # GET this endpoint, expect 200

  checks:
    - type: smoke
      routes:                       # Key routes to verify (200 OK, no blank page)
        - /
        - /coach/dashboard
        - /client/dashboard
        - /admin

    - type: lighthouse
      thresholds:
        performance: 50             # Minimum Lighthouse score (0-100)
        accessibility: 80
        best_practices: 80
        seo: 60
      pages:                        # Pages to audit (default: routes from smoke check)
        - /
        - /coach/dashboard

    - type: visual_regression
      baseline_url: "https://staging.wellplanned.app"  # Compare against this
      pages:
        - /coach/dashboard
        - /client/dashboard
      threshold: 0.05               # Max 5% pixel difference

    - type: playwright
      test_command: "bun run test:e2e"  # Run project's own E2E suite
      env:
        BASE_URL: "{preview_url}"   # Injected at runtime

  on_failure:
    comment_on_pr: true             # Post findings as PR comment
    add_label: "preview-failed"     # Add label to PR
    block_merge: false              # Advisory, not blocking (default)
    retry_fix_cycle: false          # If true, sends auto-fixable findings back to IMPLEMENT

  on_success:
    comment_on_pr: true             # Post success summary
    add_label: "preview-validated"  # Add label to PR
```

#### Flow

```
WAIT FOR PREVIEW
  → Extract PR number from pl-600-pr-builder output
  → Construct preview URL from url_pattern
  → Poll health endpoint:
    - GET {preview_url}{health_endpoint} every poll_interval seconds
    - If 200 within timeout: proceed
    - If timeout reached: report WARNING "Preview not ready after {timeout}s", skip preview checks
      Possible reasons: CI still building, deployment pending, infrastructure issue
    - Write deploy timing to `.pipeline/stage_8_notes_{storyId}.md`

SMOKE CHECK (if configured)
  → For each route:
    1. browser_navigate to {preview_url}{route}
    2. Wait for network idle
    3. Check HTTP status (expect 200)
    4. browser_snapshot → verify page is not blank (has meaningful content)
    5. browser_console_messages → check for JavaScript errors (any console.error)
  → Findings:
    - 500/404 response: CRITICAL "Route {route} returned {status}"
    - Blank page: CRITICAL "Route {route} renders blank page"
    - JS errors: WARNING "Route {route} has console errors: {messages}"
    - Slow load (>5s): WARNING "Route {route} took {time}s to load"

LIGHTHOUSE AUDIT (if configured)
  → For each page:
    1. Run Lighthouse via CLI: `lighthouse {preview_url}{page} --output=json --chrome-flags="--headless"`
    2. Parse JSON results
    3. Compare scores against thresholds
  → Findings:
    - Score below threshold: WARNING "Lighthouse {category} score {actual} below threshold {expected} on {page}"
    - If any score <30: CRITICAL "Lighthouse {category} critically low ({actual}) on {page}"
  → Write full Lighthouse report to `.pipeline/reports/lighthouse-{pr_number}.json`

VISUAL REGRESSION (if configured)
  → For each page:
    1. browser_navigate to {preview_url}{page}
    2. browser_take_screenshot → save as `.pipeline/screenshots/preview-{page-slug}.png`
    3. browser_navigate to {baseline_url}{page}
    4. browser_take_screenshot → save as `.pipeline/screenshots/baseline-{page-slug}.png`
    5. Compare screenshots pixel-by-pixel (using ImageMagick `compare` or `pixelmatch` via Bash)
    6. Calculate diff percentage
  → Findings:
    - Diff > threshold: WARNING "Visual regression on {page}: {diff_percent}% pixel difference"
    - Diff > 3x threshold: CRITICAL "Major visual regression on {page}: {diff_percent}%"
    - Screenshots saved for human review
  → If no baseline URL configured: skip, log INFO "No baseline URL, skipping visual regression"

PLAYWRIGHT E2E (if configured)
  → Run project's E2E test suite against preview URL:
    1. Set environment variables (BASE_URL, etc.)
    2. Execute test_command via Bash
    3. Parse test results (exit code + stdout)
  → Findings:
    - Test failures: CRITICAL "E2E test failed: {test_name} — {error_message}" (one finding per failed test)
    - All passed: no findings
  → If test command not found or fails to start: WARNING "E2E suite could not run: {error}"

SCORING
  → All findings scored using standard scoring.md formula
  → Verdict thresholds same as quality gate (PASS >= 80, CONCERNS 60-79, FAIL < 60)

REPORT
  → Generate PR comment with results:

    ## Preview Validation Results

    | Check | Result | Details |
    |-------|--------|---------|
    | Smoke | PASS | 4/4 routes healthy |
    | Lighthouse | CONCERNS | Performance 48 (threshold 50) on /coach/dashboard |
    | Visual Regression | PASS | All pages within 5% threshold |
    | Playwright E2E | PASS | 12/12 tests passed |

    **Score: 95/100 — PASS**

    <details><summary>Findings (1)</summary>
    /coach/dashboard:0 | PERF-LIGHTHOUSE | WARNING | Performance score 48 below threshold 50
    </details>

  → Post comment via `gh pr comment {pr_number} --body "..."`
  → Add label via `gh pr edit {pr_number} --add-label "preview-validated"`

ON FAILURE (if retry_fix_cycle enabled)
  → Filter findings to auto-fixable only:
    - JS errors with stack traces → fixable
    - Blank pages → likely missing route/import → fixable
    - Lighthouse performance → may need optimization → flag for manual
    - Visual regression → not auto-fixable → flag for manual
  → Send fixable findings back to orchestrator
  → Orchestrator returns to IMPLEMENT → VERIFY → REVIEW → SHIP cycle
  → Re-run preview validation after new PR push
  → Max 1 fix cycle (prevent infinite loops)
```

#### State Schema Extension

New fields in `state.json`:

```json
{
  "preview_validation": {
    "preview_url": "https://pr-42.preview.wellplanned.app",
    "deploy_wait_seconds": 45,
    "checks_run": ["smoke", "lighthouse", "visual_regression", "playwright"],
    "score": 95,
    "verdict": "PASS",
    "findings_count": 1,
    "fix_cycle_triggered": false
  }
}
```

#### Dependencies

| Dependency | Required? | Fallback |
|---|---|---|
| Playwright MCP plugin | Yes (for smoke, visual regression) | If unavailable, skip those checks, log WARNING |
| `gh` CLI | Yes (for PR comments, labels) | If unavailable, write report to stage notes only |
| Lighthouse CLI | No (for lighthouse check) | If not installed, skip lighthouse check, log INFO |
| ImageMagick (`compare`) or `pixelmatch` | No (for visual regression) | If unavailable, skip visual regression, log INFO |
| Project's E2E test suite | No (for playwright check) | If test_command fails to start, skip, log WARNING |

#### Constraints

- **Read-only on the codebase.** The validator only reads code and navigates the preview. It never modifies source files directly. Fix cycles go through the orchestrator -> implementer path.
- **Network required.** Preview validation inherently needs network access to the preview URL.
- **Time-boxed.** Total preview validation time is capped at 10 minutes (configurable). If checks exceed this, remaining checks are skipped with a WARNING.
- **Non-blocking by default.** `block_merge: false` means findings are advisory. Teams can set `block_merge: true` to make preview validation a merge gate.
- **Screenshots are ephemeral.** Stored in `.pipeline/screenshots/`, not committed. The PR comment contains the findings summary; screenshots are for local review only.

---

## Phase 3: Self-Healing Pipeline & Recovery Patterns

### Overview

The pipeline currently has basic retry loops (quality fix cycles, test fix cycles) but lacks structured recovery for infrastructure failures, API timeouts, tool crashes, and partial completions. This phase adds a resilience layer that makes the pipeline self-healing — it detects failures, classifies them, applies the appropriate recovery strategy, and continues without human intervention when possible.

### Failure Taxonomy

Every failure the pipeline can encounter falls into one of these categories:

| Category | Examples | Recovery strategy | Max retries |
|---|---|---|---|
| **TRANSIENT** | API timeout, network blip, rate limit, MCP server temporarily unavailable | Wait + retry with exponential backoff | 3 |
| **TOOL_FAILURE** | Bash command exits non-zero, linter crashes, build tool OOM | Diagnose, adjust, retry | 2 |
| **AGENT_FAILURE** | Agent produces malformed output, hits context limit, infinite loop detection | Reset agent context, retry with simplified prompt | 2 |
| **STATE_CORRUPTION** | state.json invalid, checkpoint missing, git state unexpected | Reconstruct from last known good state | 1 |
| **EXTERNAL_DEPENDENCY** | Docker not running, database unavailable, Keycloak down, preview env not deploying | Check dependency, wait or skip with degraded mode | 3 |
| **RESOURCE_EXHAUSTION** | Disk full, token budget exceeded, too many concurrent processes | Free resources, reduce scope, continue | 1 |
| **UNRECOVERABLE** | Permission denied, invalid credentials, fundamental config error, user cancellation | Checkpoint state, report to user, stop cleanly | 0 |

### Recovery Architecture

```
shared/
  recovery/
    recovery-engine.md            # Agent: classifies failures, selects recovery strategy
    strategies/
      transient-retry.md          # Exponential backoff with jitter
      tool-diagnosis.md           # Analyze tool failure, adjust and retry
      agent-reset.md              # Reset agent context, simplify prompt
      state-reconstruction.md     # Rebuild state from git + artifacts
      dependency-health.md        # Check and wait for external dependencies
      resource-cleanup.md         # Free resources, reduce scope
      graceful-stop.md            # Checkpoint everything, clean exit
    health-checks/
      pre-stage-health.sh         # Run before each stage: verify prerequisites
      dependency-check.sh         # Verify external deps (docker, db, network)
```

### Recovery Engine (`recovery-engine.md`)

A lightweight agent that intercepts failures at any pipeline stage. It does NOT replace the stage agents — it wraps them.

**Boundary with existing retry loops:** The recovery engine handles *infrastructure and runtime failures only*. It sits outside the existing stage retry loops. If a build command exits non-zero with compiler errors, that is routed through the existing `verify_fix_count` loop, not the recovery engine. The recovery engine only activates when the tool itself fails to run (OOM, crash, missing binary, network issue) rather than when the tool runs successfully and reports problems in the code.

**How the orchestrator uses it:**

```
For each stage:
  1. Run pre-stage-health.sh → verify prerequisites
     If unhealthy: dispatch recovery-engine with EXTERNAL_DEPENDENCY
  2. Execute stage agent
     If success: proceed to next stage
     If failure:
       a. Capture failure context (exit code, stderr, last output, stage, action)
       b. Dispatch recovery-engine with failure context
       c. Recovery engine classifies failure → selects strategy
       d. Execute strategy (retry, diagnose, reset, etc.)
       e. If recovered: re-run stage agent
       f. If not recovered after max retries: checkpoint state → escalate to user
```

**Failure context schema** (passed to recovery engine):

```json
{
  "failure_id": "f-20260321-001",
  "stage": "VERIFYING",
  "agent": "pl-500-test-gate",
  "action": "running tests via ./gradlew test",
  "error_type": "TOOL_FAILURE",
  "exit_code": 137,
  "stderr_tail": "Killed - process used too much memory",
  "stdout_tail": "Test > shouldCreateUser PASSED\nTest > shouldHandleBilling",
  "timestamp": "2026-03-21T14:30:00Z",
  "retry_count": 0,
  "max_retries": 2
}
```

### Recovery Strategies (detailed)

#### 1. Transient Retry (`transient-retry.md`)

For API timeouts, rate limits, network issues, MCP server hiccups.

```
Strategy:
  1. Wait: base_delay * 2^retry_count + random_jitter (0-1s)
     - Base delay: 2s for API calls, 5s for network, 10s for MCP servers
     - Max delay cap: 60s
  2. Retry the exact same operation
  3. If still failing after max_retries:
     - If MCP tool: try alternative tool or manual approach
     - If API call: check if API is fundamentally down (health endpoint)
     - Escalate if no alternative exists

Detection heuristics:
  - Exit code 28 (curl timeout), 52 (empty reply), 56 (network receive error)
  - stderr contains: "timeout", "ETIMEDOUT", "ECONNREFUSED", "rate limit", "429", "503"
  - MCP tool returns connection error
```

#### 2. Tool Diagnosis (`tool-diagnosis.md`)

For build failures, linter crashes, test runner errors.

```
Strategy:
  1. Classify the tool failure:
     - OOM (exit 137, "Killed", "OutOfMemoryError")
       → Reduce scope: run on changed files only, increase heap, split test suite
     - Config error (missing config file, invalid syntax)
       → Check config exists, validate syntax, offer to regenerate from template
     - Dependency missing (command not found, module not found)
       → Check PATH, suggest install command, try alternative tool
     - Compilation error (type errors, syntax errors)
       → This is NOT a tool failure — it's an implementation issue. Route back to implementer.
  2. Apply fix
  3. Retry
  4. If still failing: log diagnostic info, escalate

Detection heuristics:
  - Exit code 137/139: OOM/segfault
  - Exit code 127: command not found
  - Exit code 1-2: tool-specific (check stderr for classification)
  - stderr contains: "FATAL", "panic", "Segmentation fault", "Cannot find module"
```

#### 3. Agent Reset (`agent-reset.md`)

For agents that produce malformed output, hit context limits, or loop.

```
Strategy:
  1. Detect the agent failure:
     - Output doesn't match expected format (missing required fields)
     - Agent ran for >10 minutes without producing a stage transition
     - Agent made >20 tool calls without progress (loop detection)
     - Context window exceeded (truncation errors)
  2. Save partial results (whatever the agent did produce)
  3. Reset: dispatch a fresh agent instance with:
     - Simplified prompt (remove verbose context, keep essentials)
     - Partial results as starting point
     - Explicit instruction: "Continue from where the previous attempt left off"
  4. If still failing: reduce scope (e.g., review fewer files, plan fewer tasks)
  5. If still failing: escalate to user with partial results

Loop detection:
  Track last 20 tool calls. If >50% are the same tool with the same arguments:
    → Agent is looping. Kill and reset.
```

#### 4. State Reconstruction (`state-reconstruction.md`)

For corrupted state.json, missing checkpoints, or git drift.

```
Strategy:
  1. Check what's broken:
     - state.json missing → reconstruct from git log (find last pipeline commit)
     - state.json invalid JSON → restore from last checkpoint file
     - Checkpoint missing → scan .pipeline/ for latest checkpoint-*.json
     - Git drift (unexpected commits since last pipeline SHA)
       → Diff against last_commit_sha, ask user to incorporate or discard
  2. Reconstruct:
     - Read git log for pipeline commits (conventional commit messages)
     - Scan .pipeline/ for stage notes, checkpoints, reports
     - Infer current stage from available artifacts
     - Rebuild state.json with best-effort field values
  3. Resume from reconstructed state
  4. Log reconstruction details in stage notes

Never silently discard user changes. If git drift is detected:
  → Pause, show diff, ask user: "incorporate", "discard", or "abort"
```

#### 5. Dependency Health (`dependency-health.md`)

For Docker, database, Keycloak, preview environments, external APIs.

```
Strategy:
  1. Run dependency-check.sh for the current stage's requirements:
     - VERIFY stage: build tools, test tools, database (if integration tests)
     - SHIP stage: git remote, gh CLI
     - PREVIEW stage: preview URL, playwright
  2. For each unhealthy dependency:
     - Docker not running → attempt `docker start` or `colima start`
     - Database unreachable → check docker-compose, attempt restart
     - Keycloak down → check container status, attempt restart
     - Network unreachable → retry with backoff
     - Tool not installed → log clear install instructions, skip or degrade
  3. Wait for recovery (up to 60s per dependency)
  4. If recovered: proceed
  5. If not: determine if stage can run in degraded mode
     - Missing database → skip integration tests, run unit tests only, log WARNING
     - Missing Docker → skip container-based verification, log WARNING
     - Missing gh → write PR details to file instead of creating PR, log WARNING
  6. If critical dependency unrecoverable: escalate to user

Pre-stage health check matrix:
  | Stage | Required | Optional |
  |-------|----------|----------|
  | PREFLIGHT | git, python3 | — |
  | EXPLORE | Read/Glob/Grep tools | context7 |
  | PLAN | — | context7 |
  | VALIDATE | — | — |
  | IMPLEMENT | git, build tool | context7 |
  | VERIFY | build tool, test tool | docker, database |
  | REVIEW | — | linters |
  | DOCS | — | — |
  | SHIP | git | gh CLI |
  | PREVIEW | network, playwright | lighthouse |
  | LEARN | — | — |
```

#### 6. Resource Cleanup (`resource-cleanup.md`)

For disk full, token budget exceeded, too many processes.

```
Strategy:
  1. Diagnose resource issue:
     - Disk full → clean .pipeline/ old reports, clean build caches, suggest `docker system prune`
     - Token budget → reduce agent prompt size, summarize prior context, split remaining work
     - Process limit → kill orphaned processes, wait for others to complete
  2. Apply cleanup
  3. Retry operation
  4. If still exhausted: reduce scope
     - Fewer files in quality gate review
     - Skip optional checks (lighthouse, visual regression)
     - Summarize instead of full analysis
```

#### 7. Graceful Stop (`graceful-stop.md`)

For unrecoverable errors or user cancellation.

```
Strategy:
  1. Save everything:
     - Write state.json with current progress
     - Write checkpoint with last completed action
     - Flush stage notes with partial results
     - Commit any uncommitted work-in-progress to a WIP branch
  2. Report:
     - What was completed
     - What was in progress when stopped
     - What remains
     - How to resume: `/pipeline-run --from={current_stage}`
  3. Clean exit (exit 0, no error)

The pipeline never leaves work in an unrecoverable state. Even on SIGTERM:
  - The Stop hook fires and captures state
  - Next run detects interrupted state and offers resume
```

### State Schema Extension for Recovery

New fields in `state.json`:

```json
{
  "recovery": {
    "failures": [
      {
        "failure_id": "f-20260321-001",
        "stage": "VERIFYING",
        "category": "TOOL_FAILURE",
        "strategy_applied": "tool-diagnosis",
        "retries": 1,
        "resolved": true,
        "resolution": "Reduced test scope to changed modules only (OOM on full suite)",
        "timestamp": "2026-03-21T14:30:00Z",
        "duration_ms": 15000
      }
    ],
    "total_failures": 1,
    "total_recoveries": 1,
    "degraded_capabilities": ["integration-tests-skipped"]
  }
}
```

### Self-Healing Metrics & Learning

The retrospective agent (`pl-700-retrospective`) analyzes recovery data:

```
For each run with failures:
  1. Log failure patterns to pipeline-log.md:
     - PATTERN: "Gradle OOM on full test suite — needs -Xmx3g or module-scoped test runs"
     - PREEMPT: "Check heap config before VERIFY stage in large projects"
  2. Track failure frequency per category:
     - If TRANSIENT failures >3 across last 5 runs → suggest checking network/API health
     - If TOOL_FAILURE on same tool >2 runs → suggest tool version upgrade or config fix
     - If AGENT_FAILURE on same agent >2 runs → flag agent prompt as potentially too complex
  3. Auto-tune recovery params:
     - If retries rarely needed beyond 1 → reduce max_retries to save time
     - If backoff delays are too short (still failing) → increase base_delay
```

### Adaptive Learning System

Beyond self-healing recovery metrics, the pipeline learns and improves across three dimensions: rule evolution, agent effectiveness, and cross-project knowledge transfer.

#### 1. Rule Learning — Auto-Evolving Check Rules

When the quality gate (Stage 6) or human review finds a new antipattern that isn't covered by existing Layer 1 rules, the retrospective agent (Stage 9) can **automatically propose and add new rules** to the language JSON files.

**Flow:**

```
REVIEW stage findings → retrospective analysis at LEARN stage:

For each finding from quality gate review agents:
  1. Check: does a Layer 1 rule already cover this pattern?
     - Match finding's file:line against Layer 1 findings for the same run
     - If Layer 1 already caught it → skip (no new rule needed)
  2. If NOT caught by Layer 1:
     - Extract the pattern: what grep regex would catch this?
     - Classify: is this language-generic or framework-specific?
     - Determine severity from the review agent's assessment
     - Generate a candidate rule:
       {
         "id": "KT-LEARNED-{NNN}",
         "name": "{descriptive-name}",
         "pattern": "{extracted-regex}",
         "severity": "WARNING",
         "category": "{matched-category}",
         "message": "{from review finding}",
         "fix_hint": "{from review finding}",
         "example_ref": "",
         "scope": "all",
         "_learned_from": "run-{story_id}-{date}",
         "_confidence": 0.85
       }
  3. Validation:
     - Run the candidate pattern against the project's codebase
     - Count matches: if >50 hits → too broad, refine or discard
     - Count false positives: sample 5 random matches, check if they're real issues
     - If <3 false positives out of 5 samples → confidence is HIGH
  4. If confidence HIGH:
     - Append to language JSON's `rules` array (in `_learned_rules` section)
     - Log to pipeline-log.md: "RULE-LEARNED: {id} — {description}"
  5. If confidence LOW:
     - Log to pipeline-log.md as "RULE-CANDIDATE: {id} — needs manual review"
     - Do NOT auto-add to rules

Learned rules are prefixed with _learned_ metadata fields:
  - `_learned_from`: which pipeline run discovered this
  - `_confidence`: 0.0-1.0, based on false positive rate
  - `_hit_count`: incremented each run when the rule fires (tracks usefulness)
  - `_false_positive_reports`: incremented when the implementer ignores the finding

Pruning: if a learned rule has _hit_count == 0 over 10 runs, or _false_positive_reports > 3,
the retrospective agent removes it and logs "RULE-PRUNED: {id} — {reason}".
```

**Storage:** Learned rules live in the same language JSON files alongside curated rules. They're distinguished by the `_learned_from` metadata field. This means they benefit from the same engine.sh execution path — no separate processing.

#### 2. Agent Prompt Improvement — Effectiveness Tracking

The retrospective agent tracks which agents produce the best outcomes and suggests prompt refinements for underperforming agents.

**Metrics tracked per agent per run** (stored in `.pipeline/reports/`):

```json
{
  "agent_effectiveness": {
    "pl-300-implementer": {
      "runs": 15,
      "avg_fix_cycles_needed": 1.2,
      "avg_quality_score": 88,
      "common_failure_patterns": ["missing null checks", "wrong import order"],
      "avg_time_seconds": 120,
      "context_resets": 0
    },
    "pl-400-quality-gate": {
      "runs": 15,
      "false_positive_rate": 0.08,
      "missed_issues_found_in_preview": 2,
      "avg_findings_per_run": 4.5
    },
    "be-hex-reviewer": {
      "runs": 10,
      "findings_accepted": 45,
      "findings_ignored": 3,
      "false_positive_rate": 0.06
    }
  }
}
```

**Improvement triggers:**

| Signal | Action |
|---|---|
| Agent's `avg_fix_cycles_needed` > 2 for 5+ runs | Log PREEMPT: "Agent {name} frequently needs rework — consider adding examples for {common_failure_patterns} to its prompt" |
| Agent's `false_positive_rate` > 0.15 for 5+ runs | Log PREEMPT: "Agent {name} has high false positive rate — review its severity mapping or scope" |
| Agent's `context_resets` > 0 in 3+ of last 5 runs | Log PREEMPT: "Agent {name} hitting context limits — simplify prompt or split into sub-agents" |
| Agent's `findings_ignored` > 30% of `findings_accepted` | Log PREEMPT: "Agent {name} findings frequently ignored — recalibrate severity or refine detection" |
| Quality score consistently > 95 for 5+ runs | Log PATTERN: "Quality consistently high — consider increasing threshold from 80 to 85" |

**Prompt refinement suggestions** are logged to `pipeline-log.md` as `AGENT-IMPROVE` entries. They are NOT auto-applied to agent .md files — the user or a human reviewer decides whether to act on them. This is because agent prompts are nuanced and auto-editing them could degrade performance.

```
## AGENT-IMPROVE: pl-300-implementer (2026-03-22)
Signal: avg_fix_cycles_needed 2.4 over last 5 runs
Common failures: missing null checks in Kotlin domain models
Suggestion: Add to implementer prompt: "For Kotlin domain models, always use
nullable types with safe calls for optional fields. Reference
examples/kotlin/null-safety.md#safe-call-pattern"
```

#### 3. Cross-Project Knowledge Transfer

Learnings from one project should benefit other projects using the same module. This is achieved through **shared learnings** — patterns that are module-specific rather than project-specific.

**Architecture:**

```
Per-project (local):
  .claude/pipeline-log.md          # Project-specific PREEMPT items and run history

Plugin-level (shared):
  shared/learnings/
    kotlin-spring.md               # Cross-project learnings for kotlin-spring module
    react-vite.md                  # Cross-project learnings for react-vite module
    ...
```

**Flow:**

```
At LEARN stage, the retrospective agent:
  1. Analyze this run's findings, fix patterns, and recovery events
  2. For each learning, classify:
     - PROJECT-SPECIFIC: references project paths, domain entities, specific configs
       → Write to .claude/pipeline-log.md (as today)
     - MODULE-GENERIC: applies to any project using this module
       → Write to shared/learnings/{module}.md (in the plugin repo)
       → Also write to .claude/pipeline-log.md for local use

Classification heuristics:
  - Contains absolute paths or project-specific package names → PROJECT-SPECIFIC
  - References framework patterns, library quirks, or language idioms → MODULE-GENERIC
  - Example: "Always check TypeScript compiles after component changes" → MODULE-GENERIC
  - Example: "wellplanned-be billing module needs extra auth checks" → PROJECT-SPECIFIC

At PREFLIGHT stage:
  1. Load .claude/pipeline-log.md (project-specific PREEMPTs)
  2. Load shared/learnings/{module}.md (cross-project PREEMPTs)
  3. Merge, deduplicate, apply matching items
```

**Shared learnings file format:**

```markdown
# Cross-Project Learnings: kotlin-spring

## PREEMPT items

### KS-PREEMPT-001: Check R2DBC entity timestamps on update adapters
- **Source:** wellplanned-be run 2026-03-15
- **Domain:** persistence
- **Pattern:** R2DBC updates all columns — update adapters must fetch-then-set to preserve @CreatedDate
- **Confidence:** HIGH (confirmed across 3 runs)
- **Hit count:** 5

### KS-PREEMPT-002: Generated OpenAPI sources excluded from detekt
- **Source:** wellplanned-be run 2026-03-18
- **Domain:** build
- **Pattern:** Detekt globs don't work with srcDir-added generated sources — use post-eval exclusion
- **Confidence:** HIGH (confirmed across 2 projects)
- **Hit count:** 2
```

**Privacy:** Shared learnings are stripped of project-specific identifiers (paths, entity names, config values) before writing to the plugin repo. They contain only the pattern and the module context.

**Update mechanism:** When the plugin is updated (via marketplace or git pull), new cross-project learnings become available to all projects. The retrospective agent appends to shared learnings; the `/pipeline-init` skill loads them at setup time.

**Conflict resolution:** If a project-specific PREEMPT contradicts a shared one (e.g., project says "skip this check" but shared says "always do this check"), project-specific takes priority. This follows the existing parameter resolution order: `pipeline-config.md` > `dev-pipeline.local.md` > plugin defaults.

---

## Phase 4: Marketplace Distribution

### Overview

The plugin currently requires installation as a git submodule (`git submodule add ... .claude/plugins/dev-pipeline`). This is friction-heavy: manual setup, manual updates, submodule gotchas (detached HEAD, hook issues in worktrees).

Claude Code supports a **marketplace system** for plugin distribution. Plugins are installed via `/plugin install` and auto-updated. This phase migrates dev-pipeline to marketplace distribution.

**Note:** Phase 4 targets the Claude Code marketplace system whose API surface is based on observed conventions from existing marketplace plugins (superpowers, levnikolaevich-skills-marketplace). If the marketplace API differs from this design at implementation time, the manifest and catalog files will be adjusted accordingly; the migration strategy and consuming project impact remain the same.

### Current vs. Target Installation Experience

**Current (git submodule):**
```bash
cd your-project
git submodule add https://github.com/quantumbitcz/dev-pipeline .claude/plugins/dev-pipeline
git submodule update --init
# Manually configure .claude/dev-pipeline.local.md
# Manually update .claude/settings.json hooks
# On every update: git submodule update --remote
```

**Target (marketplace):**
```bash
# One-time: add the marketplace
/plugin marketplace add quantumbitcz/dev-pipeline

# Install the plugin
/plugin install dev-pipeline@quantumbitcz

# Use it
/pipeline-run "add user avatars"
```

Or declaratively in `.claude/settings.json`:
```json
{
  "enabledPlugins": {
    "dev-pipeline@quantumbitcz": true
  }
}
```

### Plugin Structure Migration

The plugin needs to move from the current root-level `plugin.json` to the standard `.claude-plugin/` structure:

**Current structure:**
```
dev-pipeline/
  plugin.json                    # Root-level manifest (non-standard)
  agents/
  skills/
  hooks/
  shared/
  modules/
```

**Target structure:**
```
dev-pipeline/
  .claude-plugin/
    plugin.json                  # Standard manifest location
    marketplace.json             # Marketplace catalog entry
  agents/
  skills/
  hooks/
    hooks.json                   # Hook definitions (separate from manifest)
    pipeline-checkpoint.sh
    feedback-capture.sh
  shared/
  modules/
```

### Manifest Migration

**Current `plugin.json` (root-level):**
```json
{
  "name": "dev-pipeline",
  "description": "Reusable autonomous development pipeline with framework modules",
  "version": "0.1.0",
  "hooks": {
    "PostToolUse": [ ... ],
    "Stop": [ ... ]
  }
}
```

**New `.claude-plugin/plugin.json`:**
```json
{
  "name": "dev-pipeline",
  "version": "1.0.0",
  "description": "Autonomous 10-stage development pipeline with multi-language support, self-healing recovery, and generalized code quality checks",
  "author": {
    "name": "QuantumBit s.r.o.",
    "url": "https://github.com/quantumbitcz"
  },
  "repository": "https://github.com/quantumbitcz/dev-pipeline",
  "license": "Proprietary",
  "keywords": [
    "pipeline", "tdd", "code-review", "quality-gate",
    "kotlin", "typescript", "python", "go", "rust", "swift", "java", "c"
  ]
}
```

**New `hooks/hooks.json`:**
```json
{
  "hooks": [
    {
      "event": "PostToolUse",
      "matcher": "Edit|Write",
      "hooks": [
        {
          "type": "command",
          "command": "${CLAUDE_PLUGIN_ROOT}/shared/checks/engine.sh --hook",
          "timeout": 5000
        }
      ]
    },
    {
      "event": "PostToolUse",
      "matcher": "Skill",
      "hooks": [
        {
          "type": "command",
          "command": "${CLAUDE_PLUGIN_ROOT}/hooks/pipeline-checkpoint.sh",
          "timeout": 5000
        }
      ]
    },
    {
      "event": "Stop",
      "hooks": [
        {
          "type": "command",
          "command": "${CLAUDE_PLUGIN_ROOT}/hooks/feedback-capture.sh",
          "timeout": 3000
        }
      ]
    }
  ]
}
```

### Marketplace Catalog

**New `.claude-plugin/marketplace.json`:**
```json
{
  "name": "quantumbitcz",
  "owner": {
    "name": "QuantumBit s.r.o.",
    "url": "https://github.com/quantumbitcz"
  },
  "metadata": {
    "description": "Autonomous development pipeline with multi-language support",
    "version": "2026.03.21"
  },
  "plugins": [
    {
      "name": "dev-pipeline",
      "description": "10-stage autonomous development pipeline: Preflight, Explore, Plan, Validate, Implement (TDD), Verify, Review, Docs, Ship, Learn. Supports Kotlin, TypeScript, Python, Go, Rust, C, Swift, Java with self-healing recovery and generalized code quality checks.",
      "source": "./",
      "strict": false
    }
  ]
}
```

### First-Run Experience

When a user installs via marketplace and runs `/pipeline-run` for the first time in a project without config:

```
1. Detect: no .claude/dev-pipeline.local.md exists
2. Display welcome message:
   "Dev Pipeline is installed but not configured for this project."
3. Auto-detect project:
   - Scan for project markers (build.gradle.kts, package.json, Cargo.toml, etc.)
   - Suggest module: "Detected: Kotlin + Spring Boot → kotlin-spring module"
4. Generate config:
   - Copy modules/{detected-module}/local-template.md → .claude/dev-pipeline.local.md
   - Copy modules/{detected-module}/pipeline-config-template.md → .claude/pipeline-config.md
   - Create empty .claude/pipeline-log.md
5. Verify:
   - Run engine.sh --verify to confirm config is valid
   - Run build/test commands from local-template to confirm they work
6. Ready:
   "Configuration complete. Run /pipeline-run 'your feature' to start."
```

This replaces the current 8-step manual setup from the README.

### Update Strategy

| Scenario | Behavior |
|---|---|
| Plugin update available | Claude Code notifies user, auto-updates on next session |
| Breaking change in config schema | Plugin detects old config format, offers migration |
| New module added | Available immediately after update |
| Rule files updated | New rules apply on next engine.sh invocation |
| New agent added | Available on next pipeline run |

### Impact on Consuming Projects

**Removal of git submodule:**

For `wellplanned-be` and `wellplanned-fe`:
```bash
# Remove submodule
git submodule deinit .claude/plugins/dev-pipeline
git rm .claude/plugins/dev-pipeline
rm -rf .git/modules/.claude/plugins/dev-pipeline

# Add marketplace plugin reference
# (in .claude/settings.json)
{
  "enabledPlugins": {
    "dev-pipeline@quantumbitcz": true
  }
}

# Keep existing config files (they still work):
# .claude/dev-pipeline.local.md
# .claude/pipeline-config.md
# .claude/pipeline-log.md

git add -A && git commit -m "chore: migrate dev-pipeline from submodule to marketplace plugin"
```

**Path references in settings.json hooks:**

Old hooks referencing `.claude/plugins/dev-pipeline/...` paths become invalid once the submodule is removed. With marketplace distribution, all hooks are registered through `hooks/hooks.json` within the plugin — consuming projects no longer need per-project hook entries in their `settings.json` for the pipeline's core checks.

Project-specific hooks (like BE's "block editing generated OpenAPI sources") remain in the project's `settings.json` — those are project concerns, not plugin concerns.

---

## Phase 5: Project Init & Command Consolidation

### Overview

Currently, each consuming project has its own `.claude/commands/` with framework-specific commands (e.g., wellplanned-be has `/build`, `/test`, `/scan`, `/usecase`, `/adapter`, etc.). These commands contain useful patterns but are duplicated across projects and disconnected from the pipeline plugin.

This phase:
1. **Moves reusable commands into the pipeline plugin** as module-specific commands
2. **Creates a `/pipeline-init` skill** that auto-configures any project for the pipeline
3. Eliminates manual setup entirely — install the plugin, run `/pipeline-init`, start building

### Command Classification & Migration

Commands from wellplanned-be analyzed for reuse:

| Command | Type | Migration target |
|---|---|---|
| `/dev` | Generic pipeline launcher | Already exists as `/pipeline-run` skill — delete from projects |
| `/build` | Generic (Gradle wrapper) | `modules/kotlin-spring/commands/build.md` — parameterized per module |
| `/test` | Generic (Gradle test wrapper) | `modules/kotlin-spring/commands/test.md` — parameterized per module |
| `/db` | Generic (Docker Compose) | `shared/commands/db.md` — works across all modules using Docker |
| `/migration` | Generic (Flyway) | `modules/kotlin-spring/commands/migration.md` — DB migration tool varies by module |
| `/scan` | Framework-specific (Kotlin) | Replaced by `engine.sh` — Layer 1+2 checks subsume scan functionality |
| `/usecase` | Framework-specific (Kotlin hexagonal) | `modules/kotlin-spring/commands/usecase.md` |
| `/adapter` | Framework-specific (Kotlin hexagonal) | `modules/kotlin-spring/commands/adapter.md` |
| `/controller` | Framework-specific (Kotlin OpenAPI) | `modules/kotlin-spring/commands/controller.md` |
| `/openapi` | Framework-specific (Kotlin) | `modules/kotlin-spring/commands/openapi.md` |

**New plugin directory structure for commands:**

```
commands/                              # Plugin-level shared commands
  pipeline-init.md                     # /pipeline-init — project setup wizard
  db.md                                # /db — Docker Compose database management

modules/
  kotlin-spring/
    commands/
      build.md                         # /build — Gradle build wrapper
      test.md                          # /test — Gradle test runner with module shortcuts
      usecase.md                       # /usecase — Scaffold hexagonal use case
      adapter.md                       # /adapter — Add persistence adapter methods
      controller.md                    # /controller — Implement OpenAPI endpoint
      migration.md                     # /migration — Create Flyway migration
      openapi.md                       # /openapi — Regenerate OpenAPI sources

  react-vite/
    commands/
      build.md                         # /build — Bun/Vite build wrapper
      test.md                          # /test — Vitest runner
      component.md                     # /component — Scaffold React component

  python-fastapi/
    commands/
      build.md                         # /build — uv/pip build wrapper
      test.md                          # /test — Pytest runner
      router.md                        # /router — Scaffold FastAPI router
      migration.md                     # /migration — Create Alembic migration

  go-stdlib/
    commands/
      build.md                         # /build — Go build wrapper
      test.md                          # /test — Go test runner

  rust-axum/
    commands/
      build.md                         # /build — Cargo build wrapper
      test.md                          # /test — Cargo test runner

  # Other modules get build.md + test.md at minimum
```

**Key principle:** Plugin-level commands in `commands/` are auto-discovered by Claude Code (same mechanism as skills — the plugin system scans `commands/*.md` at the plugin root). Module-specific commands in `modules/*/commands/` are NOT auto-discovered — `/pipeline-init` copies the active module's commands into the project's `.claude/commands/` directory during setup. This means only the relevant module's commands appear as slash commands for the user. If the user switches modules, re-running `/pipeline-init` updates the commands.

### `/pipeline-init` Skill

**Entry point:** `skills/pipeline-init/SKILL.md`
**Purpose:** Zero-config project setup. Scans a project, detects its stack, configures the pipeline, and validates everything works.

**Flow:**

```
DETECT
  → Scan project root for stack markers:
    | Marker | Detection |
    |--------|-----------|
    | build.gradle.kts + src/main/kotlin/ | kotlin-spring |
    | build.gradle.kts + src/main/java/ | java-spring |
    | package.json + vite.config.* + react | react-vite |
    | package.json + svelte.config.* | typescript-svelte |
    | package.json + (express\|nestjs) | typescript-node |
    | pyproject.toml + fastapi | python-fastapi |
    | go.mod | go-stdlib |
    | Cargo.toml | rust-axum |
    | Package.swift + Vapor | swift-vapor |
    | *.xcodeproj or Package.swift | swift-ios |
    | Makefile + *.c/*.h | c-embedded |

  → Detect additional features:
    - Docker Compose → enable /db command
    - CI/CD workflows → detect deployment patterns for preview config
    - Test framework → configure test commands
    - Linters installed → configure Layer 2 adapters
    - OpenAPI spec → enable contract validation config
    - Related repos (via git remotes or config) → suggest cross-repo contracts

  → Present findings to user:
    "Detected: Kotlin + Spring Boot (hexagonal architecture)
     Build: Gradle 8.x
     Tests: Kotest + Testcontainers (106 test classes)
     Linters: Detekt + ktlint
     Database: PostgreSQL via Docker Compose
     CI: GitHub Actions
     Module: kotlin-spring

     Ready to configure? [Y/n]"

CONFIGURE
  → Generate .claude/dev-pipeline.local.md from module template:
    - Fill in detected build/test/lint commands
    - Set scaffolder patterns from module defaults
    - Configure quality gate batches
    - Set file path patterns for the detected project structure

  → Generate .claude/pipeline-config.md from module template:
    - Set default runtime params (max_fix_loops, auto_proceed_risk, etc.)
    - Initialize domain hotspots as empty

  → Create empty .claude/pipeline-log.md

  → If project has related repos (e.g., shared OpenAPI spec):
    - Suggest contract validation config
    - Ask user for consumer/source paths

  → If project has preview environments:
    - Detect URL pattern from CI config
    - Suggest preview validation config

VALIDATE
  → Run build command → verify it works
  → Run test command → verify it works
  → Run engine.sh --verify → verify checks work
  → Run linter (if detected) → verify Layer 2 adapter works

  → Report:
    "Configuration complete!

     Module: kotlin-spring
     Build: ./gradlew build ✓
     Tests: ./gradlew test ✓ (106 tests passing)
     Checks: engine.sh ✓ (kotlin rules + spring overrides loaded)
     Linter: detekt ✓ (adapter working)

     Files created:
       .claude/dev-pipeline.local.md
       .claude/pipeline-config.md
       .claude/pipeline-log.md

     Available commands:
       /pipeline-run  — Run the full pipeline
       /build         — Build the project
       /test          — Run tests
       /usecase       — Scaffold a use case
       /adapter       — Add adapter methods
       /controller    — Implement an endpoint
       /migration     — Create DB migration
       /scan          — Run code checks (now via engine.sh)

     Ready to use: /pipeline-run 'your first feature'"

CLEANUP (for projects migrating from submodule)
  → If .claude/plugins/dev-pipeline exists as submodule:
    - Ask: "Found existing submodule installation. Remove it? [Y/n]"
    - If yes: run submodule removal commands
    - Preserve existing config files (.claude/dev-pipeline.local.md, etc.)
    - Update any settings.json hook paths
```

**Idempotent:** Running `/pipeline-init` on an already-configured project detects existing config, shows diff against what it would generate, and asks whether to update or keep current.

### Command Parameterization

Module commands are templates with placeholders filled from `dev-pipeline.local.md`:

```markdown
---
description: Build the project
allowed-tools: Bash(*)
---

# Build

Read the build command from .claude/dev-pipeline.local.md:
- Default: {{build_command}} (from local config)
- With --fast or no-test: skip tests
- With --clean: clean build
- With --module <name>: build specific module

Run the build command. If it fails, show only compiler errors (not full stacktraces).
```

The `{{build_command}}` is resolved from the module's `local-template.md` during `/pipeline-init`. This means `/build` works the same way across all projects — the command structure is shared, only the underlying tool invocation differs.

### State Schema Extension

No new `state.json` fields needed. Init runs outside the pipeline state machine — it's a one-time setup utility.

### Impact on Consuming Projects

After this phase, consuming projects:
1. **Delete** `.claude/commands/` entirely (all commands come from the plugin)
2. **Delete** `.claude/plugins/dev-pipeline` submodule (plugin comes from marketplace)
3. **Keep** `.claude/dev-pipeline.local.md`, `.claude/pipeline-config.md`, `.claude/pipeline-log.md` (project config stays in project)
4. **Simplify** `.claude/settings.json` (remove pipeline hook entries — hooks are in plugin now)

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

### Development conventions

**Git worktrees:** All implementation work MUST use git worktrees. Each PR branch gets its own worktree so the user's main working directory stays clean and usable. This allows parallel development — the user continues their own work while the pipeline enhancement builds in an isolated worktree. Clean up worktrees after the branch is merged.

**Commit messages:** No AI attribution in commit messages (no `Co-Authored-By: Claude` or similar). Commits should look like normal developer commits. Use conventional commit format (`feat:`, `fix:`, `refactor:`, `docs:`, `chore:`).

**Commit size:** Keep commits reasonably sized and logically scoped. One commit per logical change — don't bundle unrelated changes. A single PR may have multiple commits but each should be reviewable on its own.

### Delivery sequence

| # | Branch | Phase | Contents | Depends on |
|---|---|---|---|---|
| 1 | `feat/check-engine-core` | 1 | engine.sh, run-patterns.sh, output-format.md, JSON schema | — |
| 2 | `feat/language-rules` | 1 | `patterns/*.json` (8 languages) + `examples/` (~35 files) | #1 |
| 3 | `feat/linter-bridge` | 1 | `layer-2-linter/` — adapters, severity-map, run-linter.sh, defaults | #1 |
| 4 | `feat/agent-intelligence` | 1 | `layer-3-agent/` — agents, known-deprecations JSONs | #1 |
| 5 | `feat/new-modules` | 1 | 9 new module directories (3-4 files + commands each) | #2 |
| 6 | `feat/migrate-existing-modules` | 1 | Update kotlin-spring + react-vite, delete old scripts, deprecation schema migration | #1, #2 |
| 7 | `feat/test-bootstrapper` | 2 | `pl-150-test-bootstrapper` agent | #1 |
| 8 | `feat/contract-validator` | 2 | `pl-250-contract-validator` agent | #1 |
| 9 | `feat/migration-orchestrator` | 2 | `pl-160-migration-planner` agent + orchestrator migration mode | #1 |
| 10 | `feat/preview-validator` | 2 | `pl-650-preview-validator` agent | #1 |
| 11 | `feat/recovery-engine` | 3 | Recovery engine agent, strategies, health checks, pre-stage hooks | #1 |
| 12 | `feat/adaptive-learning` | 3 | Rule learning, agent effectiveness tracking, cross-project knowledge transfer | #1, #11 |
| 13 | `feat/marketplace-distribution` | 4 | .claude-plugin/ structure, hooks.json, marketplace.json, delete root plugin.json | #6 |
| 14 | `feat/pipeline-init` | 5 | /pipeline-init skill, project detection, config generation | #5, #13 |
| 15 | `feat/module-commands` | 5 | Module-specific commands (build, test, scaffolders per module) | #5 |
| 16 | `feat/update-contracts` | All | stage-contract.md, state-schema.md, scoring.md, CLAUDE.md, README | #6-#15 |

PRs 1-6 = Phase 1 (Check Engine + Modules). PRs 7-10 = Phase 2 (New Capabilities). PRs 11-12 = Phase 3 (Self-Healing + Learning). PR 13 = Phase 4 (Distribution). PRs 14-15 = Phase 5 (Init + Commands). PR 16 = cross-cutting docs update.

### Estimated file count

| Category | Files |
|---|---|
| Check engine core (engine.sh, run-patterns.sh, output-format.md) | ~5 |
| Language rule JSONs | 8 |
| Linter adapters + config + defaults | ~13 |
| Agent intelligence (agents, deprecation JSONs) | ~12 |
| Examples | ~35 |
| New modules (9 x 3-4 config files) | ~30 |
| Module commands (build, test, scaffolders) | ~25 |
| New pipeline agents (Phase 2) | 4 |
| Recovery engine + strategies + health checks (Phase 3) | ~10 |
| Adaptive learning (shared/learnings/, retrospective extensions) | ~5 |
| Marketplace structure (.claude-plugin/, hooks.json) | ~4 |
| Pipeline-init skill | ~2 |
| Migration (conversion script, updated existing files) | ~12 |
| **Total** | **~165** |
