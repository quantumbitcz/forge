# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`dev-pipeline` is a Claude Code plugin (v1.0.0, installable from the `quantumbitcz` marketplace or as a Git submodule). It orchestrates a 10-stage autonomous development pipeline: Preflight → Explore → Plan → Validate → Implement (TDD) → Verify → Review → Docs → Ship → Learn. The entry point is the `/pipeline-run` skill which dispatches `pl-100-orchestrator`.

## Architecture

Three-layer design with resolution flowing top-down:

1. **Project config** (`.claude/dev-pipeline.local.md`, `.claude/pipeline-config.md`, `.claude/pipeline-log.md`) — per-project settings, mutable runtime params, and accumulated learnings. Lives in the consuming repo, not here.
2. **Module layer** (`modules/`) — sublayers for convention composition:
   - `modules/languages/` — 9 language files (kotlin, java, typescript, python, go, rust, swift, c, csharp): language-level idioms, type conventions, and baseline rules.
   - `modules/frameworks/` — 21 framework directories (spring, react, fastapi, axum, swiftui, vapor, express, sveltekit, k8s, embedded, go-stdlib, aspnet, django, nextjs, gin, jetpack-compose, kotlin-multiplatform, angular, nestjs, vue, svelte), each with `conventions.md`, config files, `variants/` for language-specific overrides, and subdirectories for framework-specific bindings (e.g., `testing/`, `persistence/`, `messaging/`).
   - `modules/testing/` — 11 generic testing framework files (kotest, junit5, vitest, jest, pytest, go-testing, xctest, rust-test, xunit-nunit, testcontainers, playwright).
   - `modules/databases/` — database engine best practices (query patterns, indexing, connection pooling).
   - `modules/persistence/` — ORM/mapping patterns (entity design, repository conventions, transaction boundaries).
   - `modules/migrations/` — schema migration tool patterns (versioning, rollback, zero-downtime strategies).
   - `modules/api-protocols/` — API protocol patterns (REST, GraphQL, gRPC, WebSocket conventions).
   - `modules/messaging/` — event-driven patterns (producers, consumers, dead-letter queues, idempotency).
   - `modules/caching/` — cache strategy patterns (TTL, invalidation, cache-aside, write-through).
   - `modules/search/` — full-text search patterns (indexing, query building, relevance tuning).
   - `modules/storage/` — object storage patterns (upload flows, presigned URLs, lifecycle policies).
   - `modules/auth/` — authentication/authorization patterns (JWT, OAuth2, RBAC, ABAC).
   - `modules/observability/` — metrics, tracing, and logging patterns (OpenTelemetry, structured logging, alerting).
   Convention composition order (most specific wins): variant > framework-binding > framework > language > generic-layer > testing. Note: framework-testing is a specific case of framework-binding. All framework subdirectory bindings (testing/, persistence/, messaging/, etc.) share the same precedence level.
3. **Shared core** (`agents/`, `shared/`, `hooks/`, `skills/`) — the pipeline engine: 29 agents, check engine, recovery system, scoring, discovery (`shared/discovery/`), and frontend design theory.

Parameter resolution: `pipeline-config.md` > `dev-pipeline.local.md` > plugin hardcoded defaults.

## Quick start

```bash
./tests/validate-plugin.sh          # 27 structural checks, ~2s
./tests/run-all.sh                  # Full test suite, ~30s

# To test in a consuming project
ln -s "$(pwd)" /path/to/project/.claude/plugins/dev-pipeline
cd /path/to/project && claude       # then run /pipeline-init
```

## Development workflow

This is a documentation-only plugin (no build step). To test changes:

1. Install locally: symlink or clone into `.claude/plugins/` of a test project
2. Run `/pipeline-init` in the test project to generate config files
3. Run `/pipeline-run --dry-run <requirement>` to verify PREFLIGHT through VALIDATE
4. Run `/pipeline-run <requirement>` for a full end-to-end test
5. Check `.pipeline/state.json` and stage notes for correct behavior

## Key conventions

### Agents (29 total, in `agents/*.md`)

**Pipeline agents** (`pl-{NNN}-{role}` naming):
- Pre-pipeline: `pl-010-shaper`, `pl-050-project-bootstrapper`
- Orchestration: `pl-100-orchestrator` (coordinator — dispatches all others, never writes code)
- Preflight: `pl-140-deprecation-refresh`, `pl-150-test-bootstrapper`, `pl-160-migration-planner`
- Plan/Validate: `pl-200-planner`, `pl-210-validator`, `pl-250-contract-validator`
- Implement: `pl-300-implementer`, `pl-310-scaffolder`, `pl-320-frontend-polisher` (conditional on `frontend_polish.enabled`)
- Verify/Review: `pl-400-quality-gate`, `pl-500-test-gate`
- Ship: `pl-600-pr-builder`, `pl-650-preview-validator`, `infra-deploy-verifier`
- Learn: `pl-700-retrospective`, `pl-710-feedback-capture`, `pl-720-recap`

**Review agents** (9, dispatched by quality gate): `architecture-reviewer`, `security-reviewer`, `frontend-reviewer`, `frontend-design-reviewer`, `frontend-a11y-reviewer`, `frontend-performance-reviewer`, `backend-performance-reviewer`, `version-compat-reviewer`, `infra-deploy-reviewer`.

**Agent file rules:**
- YAML frontmatter required: `name` (must match filename without `.md`), `description`, `tools`. Agents that dispatch others **must** include `Agent` in tools list. The orchestrator also uses `TaskCreate`/`TaskUpdate` for visual progress tracking (checkbox UI that updates as each stage completes).
- Module config uses `components:` in `dev-pipeline.local.md` (`language:`, `framework:`, `variant:`, `testing:`) — replaces old flat `module:` field. Optional crosscutting layer fields: `database`, `persistence`, `migrations`, `api_protocol`, `messaging`, `caching`, `search`, `storage`, `auth`, `observability`. All optional — omit to skip. Multi-service mode: `components:` entries with `path:` fields for monorepo per-service stacks.
- **Worktree isolation:** All implementation runs in `.pipeline/worktree`. User's working tree is never modified. Branch collision uses epoch suffix fallback.
- **Challenge Brief:** Every plan must include one (considered alternatives + justification). Validator returns REVISE if missing.
- **APPROACH-* findings:** Solution quality issues scored as INFO (-2). 3+ recurrences → escalated to convention rules by retrospective.
- All agents reference `shared/agent-philosophy.md` for critical thinking principles.

### Core contracts (in `shared/`)

Read source files for full details. Key facts:

- **Scoring** (`scoring.md`): `100 - 20*CRITICAL - 5*WARNING - 2*INFO`. PASS >= 80, CONCERNS 60-79, FAIL < 60 or any CRITICAL. `SCOUT-*` findings: no deduction. Sub-bands (95-99, 80-94, 60-79, <60) guide Linear documentation granularity. Oscillation tolerance: configurable (default 5 pts). Timed-out security/architecture reviewers: coverage gap upgraded INFO → WARNING.
- **Stage contracts** (`stage-contract.md`): Entry/exit conditions per stage. States: PREFLIGHT → EXPLORING → PLANNING → VALIDATING → IMPLEMENTING → VERIFYING → REVIEWING → DOCUMENTING → SHIPPING → LEARNING. Migration states: MIGRATING, MIGRATION_PAUSED, MIGRATION_CLEANUP, MIGRATION_VERIFY. PR rejection routes to Stage 4 (impl feedback) or Stage 2 (design feedback) via `pl-710-feedback-capture`.
- **State schema** (`state-schema.md`): Version **1.1.0**. v1.0.0 was a clean break — old files from pre-1.0 schema versions are incompatible; use `/pipeline-reset` to clear them. v1.1.0 is an additive extension of v1.0.0 — no `/pipeline-reset` required. State in `.pipeline/` (gitignored). Checkpoints per task. Corrupted counters recovered from checkpoints — fallback uses configured maximum (conservative), not zero.
- **Recovery** (`recovery/`): 7 strategies, weighted budget ceiling 5.0 (extremes: graceful-stop 0.0/free, state-reconstruction 1.5/costliest). See `recovery-engine.md`.
- **Error taxonomy** (`error-taxonomy.md`): 15 types, 12-level severity priority. MCP failures handled inline (skip + INFO), NOT by recovery engine. 3 consecutive transient-retry failures for same endpoint within 60s → reclassified as non-recoverable.
- **Agent communication** (`agent-communication.md`): All data flows through orchestrator via stage notes. Agents are isolated — cannot dispatch others, write state, or message user. Quality gate includes previous batch findings (top 20) to reduce duplicates. PREEMPT tracking via `PREEMPT_APPLIED`/`PREEMPT_SKIPPED` markers.
- **Frontend design** (`frontend-design-theory.md`): Gestalt, visual hierarchy, color theory, typography, 8pt grid, motion — shared by all frontend agents.
- **Learnings** (`learnings/`): Per-framework files + JSON schemas (`rule-learning-schema.json`, `agent-effectiveness-schema.json`) for tracking check rule evolution and agent performance.
- **Version detection:** PREFLIGHT detects dependency versions from manifest files (build.gradle.kts, package.json, go.mod, etc.) → `state.json.detected_versions`. Enables version-gated deprecation rules.
- **Convention drift:** Detected mid-run via per-section SHA256 hash comparison. Agents only react to changes in their relevant section.
- **Global retry budget:** Cumulative `total_retries` counter (default max: 10, configurable). Prevents unbounded cascades.
- **Concurrent run lock:** `.pipeline/.lock` with PID check + 24h stale timeout.

### Integrations

- **Linear** (optional): Epic/Stories/Tasks during PLAN, status updates per stage. Configured via `linear:` in `dev-pipeline.local.md` (disabled by default). Failures retry once then degrade gracefully — recovery engine NOT invoked for MCP failures.
- **MCP detection**: `pipeline-run` detects available MCPs (Linear, Playwright, Slack, Context7, Figma). First failure marks MCP as degraded for the run. No MCP required.
- **Cross-repo**: 5-step discovery during `/pipeline-init`. Contract validation (`pl-250-contract-validator`), linked PRs, multi-repo worktrees during runs. State in `state.json.cross_repo`. Configurable via `discovery:` section.

### Check engine (`shared/checks/`)

3-layer engine triggered on every `Edit`/`Write` via PostToolUse hook:
- **Layer 1** (`layer-1-fast/`): regex patterns, sub-second. Enforces design tokens (hex/rgb detection) and animation performance.
- **Layer 2** (`layer-2-linter/`): framework-aware linter adapters.
- **Layer 3** (`layer-3-agent/`): AI-driven — `pl-140-deprecation-refresh` (PREFLIGHT) and `version-compat-reviewer` (REVIEW). Not triggered by `engine.sh`. Version-gated: rules only fire when project version >= `applies_from`.
- Modules customize via `rules-override.json` (extends shared defaults; use `"disabled": true` to suppress).
- Skip tracking: timeouts increment `.pipeline/.check-engine-skipped`, reported in VERIFY. Output format in `output-format.md`.

### Deprecation registries (`modules/frameworks/*/known-deprecations.json`)

**Schema v2**: `pattern`, `replacement`, `package`, `since`, `removed_in`, `applies_from`, `applies_to`, `added`, `addedBy`. Rules skip when project version < `applies_from`. Severity: WARNING if deprecated, CRITICAL if `removed_in` reached. Auto-updated by `pl-140-deprecation-refresh` during PREFLIGHT.

### Skills (13 in `skills/`)

`pipeline-run` (main entry), `pipeline-init`, `pipeline-status`, `pipeline-reset`, `pipeline-rollback`, `pipeline-history`, `pipeline-shape`, `verify`, `security-audit`, `codebase-health`, `migration`, `bootstrap-project`, `deploy`. Frontend commands (`fe-check-theme`, `fe-design-review`, etc.) live in the consuming project, not here.

### Hooks (`hooks/hooks.json`)

3 hooks: check engine on `Edit|Write`, checkpoint on `Skill`, feedback capture on `Stop`.

## Adding a new framework

Create `modules/frameworks/{name}/` with:
- `conventions.md` — must include Dos/Don'ts section
- `local-template.md` — using `components:` structure
- `pipeline-config-template.md` — must include `total_retries_max` and `oscillation_tolerance`
- `rules-override.json` — framework-specific check overrides
- `known-deprecations.json` — schema v2 (`applies_from`, `removed_in`, `applies_to` required). Seed 5-15 entries.
- Optional: `variants/{language}.md`, `testing/{test-framework}.md`, `scripts/check-*.sh`, `hooks/*-guard.sh`

Add `shared/learnings/{name}.md`. Wire into the local template's `quality_gate` batches.

**New language?** Also add `modules/languages/{lang}.md`. **New testing framework?** Also add `modules/testing/{test-framework}.md`.

## Adding a new layer module

Create `modules/{layer}/{name}.md` with the standard structure (Overview, Architecture Patterns, Configuration, Performance, Security, Testing, Dos, Don'ts). Optionally add `{name}.rules-override.json` and `{name}.known-deprecations.json`.

Create framework bindings under `modules/frameworks/{fw}/{layer}/{name}.md` for each applicable framework.

Add a learnings file at `shared/learnings/{name}.md`.

## Module-specific gotchas

All 21 frameworks share the same base structure — see their `conventions.md` for details. Only non-obvious conventions listed here:

- **spring**: Kotlin variant uses hexagonal architecture with sealed interface hierarchy (`XxxPersisted`/`XxxNotPersisted`/`XxxId`), ports & adapters. Core uses Kotlin types; persistence uses Java types. Reactive stack: WebFlux + R2DBC + CoroutineCrudRepository. `@Transactional` on use case impls only. R2DBC UPDATE sets all columns — use `@Query` for partial updates.
- **react**: Typography via inline `style={{ fontSize }}`, not Tailwind `text-*`. Colors via theme tokens, never hardcoded hex. Error Boundaries at route level. Server data in TanStack Query/SWR, not useState.
- **embedded**: No `malloc`/`printf`/`float` in ISR handlers, max 10us duration. `volatile` for ISR-shared variables.
- **k8s**: `language: null` — no language layer loaded. Pin image tags to SHA digests in prod.
- **swiftui**: `[weak self]` in stored closures. SPM over CocoaPods. Pin exact versions for releases.
- **angular**: Standalone components, signals, OnPush change detection by default, NgRx SignalStore for state management.
- **nestjs**: Module-based DI, decorators, Pipes/Guards/Interceptors pattern, microservices transport layer.
- **vue**: Composition API + `<script setup>`, Pinia for state, Nuxt auto-imports, `useFetch`/`useAsyncData` for data fetching.
- **svelte**: Svelte 5 runes (`$state`/`$derived`/`$effect`), standalone SPAs — distinct from SvelteKit (no SSR/routing layer).

## Validation

```bash
./tests/run-all.sh                  # Full suite (~30s)
./tests/run-all.sh structural       # 27 checks, no bats needed
./tests/run-all.sh unit             # 8 test files
./tests/run-all.sh contract         # 11 test files
./tests/run-all.sh scenario         # 7 test files
```

Manual debugging:
```bash
grep -A1 "^name:" agents/*.md                    # List agents
shared/checks/engine.sh --dry-run                 # Dry-run check engine
grep -L "Forbidden Actions" agents/*.md           # Find non-compliant agents
for m in modules/frameworks/*/local-template.md; do grep -q "linear:" "$m" || echo "MISSING: $m"; done
for m in modules/frameworks/*/pipeline-config-template.md; do grep -q "total_retries_max" "$m" || echo "MISSING: $m"; done
```

## Gotchas

- Agent `name` in frontmatter **must** match filename without `.md` — orchestrator dispatch depends on it.
- Scripts need shebang (`#!/usr/bin/env bash`) and `chmod +x` — hooks fail silently without this.
- `shared/` files are contracts — changing `scoring.md`, `stage-contract.md`, `state-schema.md`, or `frontend-design-theory.md` affects all agents/modules. Verify downstream impact. Breaking state schema changes (like the v1.0.0 clean break) require `/pipeline-reset`; additive changes (like v1.1.0) do not.
- The plugin never touches consuming project files. Runtime state goes to `.pipeline/`.
- `pipeline-config.md` is auto-tuned by retrospective — manual edits may be overwritten.
- If `engine.sh` is broken/non-executable, all edits trigger hook errors. On timeout, skip counter increments but edit succeeds.
- `rules-override.json` extends (not replaces) shared defaults. Use `"disabled": true` to suppress.
- Scoring constraints at PREFLIGHT: `critical_weight >= 10`, `pass_threshold >= 60`, `oscillation_tolerance` 0-20, `total_retries_max` 5-30.
- PREEMPT confidence decay: 10 domain-matched unused runs → HIGH → MEDIUM → LOW → ARCHIVED. 1 false positive = 3 unused runs. Archived items are not loaded at PREFLIGHT.
- Orchestrator enforces parallel task conflict detection at IMPLEMENT — scaffolders serial first, then conflict detection, then implementers parallel. Shared-file tasks auto-serialized.
- `--dry-run` runs PREFLIGHT→VALIDATE only. No worktree, no Linear, no file changes.
- `known-deprecations.json` v1 entries (without `applies_from`) apply universally (backward compatible). Unknown project versions → all rules apply.
- Framework-level binding files (e.g., `testing/`, `persistence/`, `messaging/`) EXTEND their corresponding generic layer files — they don't replace.
- Framework-less projects (`go-stdlib` or `framework: null`): only language + testing layers. Infra frameworks (`k8s`): `language: null`, only framework layer.
- Cross-repo: PR failures don't block main PR. Worktrees use alphabetical lock ordering to prevent deadlocks. Discovery results stored with `detected_via` — re-run `/pipeline-init` to refresh.

## Plugin distribution (`.claude-plugin/`)

- `plugin.json` — manifest (v1.0.0). `marketplace.json` — catalog for `quantumbitcz`.
- Hooks in `hooks/hooks.json` only (NOT in plugin.json).
- Install: `/plugin marketplace add quantumbitcz/dev-pipeline` then `/plugin install dev-pipeline@quantumbitcz`.

## Governance

- `LICENSE` — Proprietary (QuantumBit s.r.o.)
- `CONTRIBUTING.md` — How to add modules, agents, hooks, skills
- `SECURITY.md` — Vulnerability reporting and plugin security practices
- `.github/CODEOWNERS` — Auto-assigns `@quantumbitcz` to all PRs
- `.github/release.yml` — Auto-generated release notes by PR label
