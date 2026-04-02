# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`forge` is a Claude Code plugin (v1.0.0, installable from the `quantumbitcz` marketplace or as a Git submodule). It orchestrates a 10-stage autonomous development pipeline: Preflight → Explore → Plan → Validate → Implement (TDD) → Verify → Review → Docs → Ship → Learn. The entry point is the `/forge-run` skill which dispatches `fg-100-orchestrator`.

## Architecture

Layered design with resolution flowing top-down:

1. **Project config** (`.claude/forge.local.md`, `.claude/forge-config.md`, `.claude/forge-log.md`) — per-project settings, mutable runtime params, and accumulated learnings. Lives in the consuming repo, not here.
2. **Module layer** (`modules/`) — sublayers for convention composition:
   - `modules/languages/` — 15 language files (kotlin, java, typescript, python, go, rust, swift, c, csharp, ruby, php, dart, elixir, scala, cpp): language-level idioms, type conventions, and baseline rules.
   - `modules/frameworks/` — 21 framework directories (spring, react, fastapi, axum, swiftui, vapor, express, sveltekit, k8s, embedded, go-stdlib, aspnet, django, nextjs, gin, jetpack-compose, kotlin-multiplatform, angular, nestjs, vue, svelte), each with `conventions.md`, config files, `variants/` for language-specific overrides, and subdirectories for framework-specific bindings (e.g., `testing/`, `persistence/`, `messaging/`).
   - `modules/testing/` — 19 generic testing framework files (kotest, junit5, vitest, jest, pytest, go-testing, xctest, rust-test, xunit-nunit, testcontainers, playwright, cypress, cucumber, k6, detox, rspec, phpunit, exunit, scalatest).
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
   - `modules/build-systems/` — 7 build tool files (gradle, maven, cmake, ant, bazel, sbt, bun): build automation patterns, dependency management, multi-module structures, caching strategies.
   - `modules/ci-cd/` — 7 CI/CD platform files (github-actions, gitlab-ci, jenkins, circleci, azure-pipelines, bitbucket-pipelines, tekton): pipeline patterns, secrets management, caching, artifact handling.
   - `modules/container-orchestration/` — 11 container/orchestration tool files (docker, docker-compose, docker-swarm, helm, k3s, microk8s, openshift, rancher, podman, argocd, fluxcd): container builds, deployment patterns, GitOps workflows.
   - `modules/documentation/` — documentation conventions layer (doc structure, ADR patterns, API docs, changelog standards, cross-reference rules).
   - `modules/code-quality/` — code quality tooling best practices: linters (detekt, eslint, ruff, clippy, etc.), formatters (prettier, black, gofmt, etc.), coverage tools (jacoco, istanbul, coverage-py, etc.), doc generators (dokka, typedoc, sphinx, etc.), dependency security scanners (owasp-dependency-check, npm-audit, cargo-audit, etc.), mutation testing (pitest, stryker, mutmut). ~70 tool files.
   Convention composition order (most specific wins): variant > framework-binding > framework > language > code-quality > generic-layer > testing. Note: framework-testing is a specific case of framework-binding. All framework subdirectory bindings (testing/, persistence/, messaging/, etc.) share the same precedence level.
3. **Shared core** (`agents/`, `shared/`, `hooks/`, `skills/`) — the pipeline engine: 32 agents, check engine, recovery system, scoring, discovery (`shared/discovery/`), knowledge graph (`shared/graph/`), and frontend design theory.

Parameter resolution: `forge-config.md` > `forge.local.md` > plugin hardcoded defaults.

## Quick start

```bash
./tests/validate-plugin.sh          # 39 structural checks, ~2s
./tests/run-all.sh                  # Full test suite, ~30s

# To test in a consuming project
ln -s "$(pwd)" /path/to/project/.claude/plugins/forge
cd /path/to/project && claude       # then run /forge-init
```

## Development workflow

This is a documentation-only plugin (no build step). To test changes:

1. Install locally: symlink or clone into `.claude/plugins/` of a test project
2. Run `/forge-init` in the test project to generate config files
3. Run `/forge-run --dry-run <requirement>` to verify PREFLIGHT through VALIDATE
4. Run `/forge-run <requirement>` for a full end-to-end test
5. Check `.forge/state.json` and stage notes for correct behavior

## Key entry points

| To understand...   | Read                                                              |
|--------------------|-------------------------------------------------------------------|
| Pipeline flow      | `shared/stage-contract.md` (10 stages, entry/exit conditions)     |
| Orchestrator logic | `agents/fg-100-orchestrator.md` (state machine, dispatch rules)   |
| Quality scoring    | `shared/scoring.md` (formula, verdicts, thresholds)               |
| State persistence  | `shared/state-schema.md` (v1.0.0 JSON schema)                    |
| Error handling     | `shared/error-taxonomy.md` + `shared/recovery/recovery-engine.md` |
| Agent design       | `shared/agent-philosophy.md` + `shared/agent-communication.md`    |
| Graph schema       | `shared/graph/schema.md` (node types, relationships, lifecycle)   |
| Token management   | `shared/agent-defaults.md` (shared constraints) + `shared/logging-rules.md` (cross-cutting logging) |
| Convergence loop | `shared/convergence-engine.md` (two-phase iteration, plateau detection) |

## Key conventions

### Agents (32 total, in `agents/*.md`)

**Pipeline agents** (`fg-{NNN}-{role}` naming):
- Pre-pipeline: `fg-010-shaper`, `fg-050-project-bootstrapper`
- Orchestration: `fg-100-orchestrator` (coordinator — dispatches all others, never writes code)
- Preflight: `fg-130-docs-discoverer`, `fg-140-deprecation-refresh`, `fg-150-test-bootstrapper`, `fg-160-migration-planner`
- Plan/Validate: `fg-200-planner`, `fg-210-validator`, `fg-250-contract-validator`
- Implement: `fg-300-implementer`, `fg-310-scaffolder`, `fg-320-frontend-polisher` (conditional on `frontend_polish.enabled`)
- Docs (Stage 7): `fg-350-docs-generator`
- Verify/Review: `fg-400-quality-gate`, `fg-500-test-gate`
- Ship: `fg-600-pr-builder`, `fg-650-preview-validator`, `infra-deploy-verifier` (conditional on k8s/infra)
- Learn: `fg-700-retrospective`, `fg-710-feedback-capture`, `fg-720-recap`

**Review agents** (10, dispatched by quality gate): `architecture-reviewer`, `security-reviewer`, `frontend-reviewer`, `frontend-design-reviewer`, `frontend-a11y-reviewer`, `frontend-performance-reviewer`, `backend-performance-reviewer`, `version-compat-reviewer`, `infra-deploy-reviewer`, `docs-consistency-reviewer`.

**Agent file rules:**
- YAML frontmatter required: `name` (must match filename without `.md`), `description`, `tools`. Agents that dispatch others **must** include `Agent` in tools list. The orchestrator also uses `TaskCreate`/`TaskUpdate` for visual progress tracking (checkbox UI that updates as each stage completes). Agents and skills that present multi-option choices to the user **must** use `AskUserQuestion` with structured options (header, question, 2-4 options with descriptions) — never plain text `Options: (1)...` or `(y/n)` patterns. Planning agents (`fg-200-planner`, `fg-010-shaper`, `fg-160-migration-planner`, `fg-050-project-bootstrapper`) use `EnterPlanMode`/`ExitPlanMode` to present designs for user approval before implementation — skip in autonomous/replanning contexts where the validator serves as the gate.
- Module config uses `components:` in `forge.local.md` — core fields: `language:`, `framework:`, `variant:`, `testing:`.
  - Framework-specific stack fields: `web` (e.g., `mvc | webflux`), `persistence` (e.g., `hibernate | r2dbc` — distinct from crosscutting `modules/persistence/`).
  - Optional crosscutting layers: `database`, `migrations`, `api_protocol`, `messaging`, `caching`, `search`, `storage`, `auth`, `observability`, `build_system`, `ci`, `container`, `orchestrator`, `documentation`, `code_quality`. All optional — omit to skip.
  - `code_quality` is a list (`[detekt, ktlint, jacoco]`) unlike single-value crosscutting fields. Supports string form or object form with external ruleset config.
  - Multi-service mode: `components:` entries with `path:` fields for monorepo per-service stacks.
  - Documentation config: `documentation:` section controls doc generation (`enabled`, `output_dir`, `auto_generate`, `discovery`, `external_sources`, `export`, `user_maintained_marker`).
- **Worktree isolation:** All implementation runs in `.forge/worktree`. User's working tree is never modified. Branch collision uses epoch suffix fallback.
- **Challenge Brief:** Every plan must include one (considered alternatives + justification). Validator returns REVISE if missing.
- **APPROACH-* findings:** Solution quality issues scored as INFO (-2). 3+ recurrences → escalated to convention rules by retrospective.
- **DOC-* findings:** Documentation consistency issues reported by `docs-consistency-reviewer`. Severity ranges from CRITICAL (decision/constraint violations with HIGH confidence) through WARNING (stale docs, cross-doc inconsistency) to INFO (missing docs, diagram drift). See `scoring.md` for details.
- All agents reference `shared/agent-philosophy.md` for critical thinking principles.
- **Token management:** Agent `.md` files are the subagent's system prompt — every line costs tokens. Standard reviewer constraints (Forbidden Actions, Linear Tracking, Optional Integrations) are compressed inline with a canonical reference to `shared/agent-defaults.md`. Output format references `shared/checks/output-format.md` instead of duplicating. Cross-cutting logging rules live in `shared/logging-rules.md`, referenced by language modules. Convention stack soft cap: 12 files per component (advisory WARNING, not blocking). Module overview sections should be max 15 lines — lead with actionable rules, not tool philosophy.

### Core contracts (in `shared/`)

Read source files for full details. Key facts:

- **Scoring** (`scoring.md`): `max(0, 100 - 20*CRITICAL - 5*WARNING - 2*INFO)`. PASS >= 80, CONCERNS 60-79, FAIL < 60 or any CRITICAL remaining after convergence exhaustion. 18 shared categories — 15 wildcard prefixes: `ARCH-*`, `SEC-*`, `PERF-*`, `TEST-*`, `CONV-*`, `DOC-*`, `QUAL-*`, `FE-PERF-*`, `APPROACH-*`, `SCOUT-*` (no deduction), `A11Y-*`, `DEPS-*`, `COMPAT-*`, `STRUCT-*`, `INFRA-*` + 3 discrete codes: `REVIEW-GAP`, `DESIGN-TOKEN`, `DESIGN-MOTION`. Agent-specific categories (`BE-PERF-*`, `FE-*`, `CONTRACT-*`) defined in their respective agents. Component-aware deduplication: key is `(component, file, line, category)` in multi-component projects — same issue in different components is not deduplicated. Sub-bands (95-99, 80-94, 60-79, <60) guide Linear documentation granularity. Oscillation tolerance: configurable (default 5 pts). Convergence engine: two-phase iteration (correctness → perfection → safety gate) replaces hard-capped fix cycles. Global `max_iterations` cap is checked before inner caps (precedence rule). SCOUT-* findings filtered before dispatch to implementer. See `shared/convergence-engine.md`. Timed-out security/architecture reviewers: coverage gap upgraded INFO → WARNING. 7 validation perspectives: architecture, security, edge_cases, test_strategy, conventions, approach_quality, documentation_consistency.
- **Stage contracts** (`stage-contract.md`): Entry/exit conditions per stage. States: PREFLIGHT → EXPLORING → PLANNING → VALIDATING → IMPLEMENTING → VERIFYING → REVIEWING → DOCUMENTING → SHIPPING → LEARNING. Migration states: MIGRATING, MIGRATION_PAUSED, MIGRATION_CLEANUP, MIGRATION_VERIFY. PR rejection routes to Stage 4 (impl feedback) or Stage 2 (design feedback) via `fg-710-feedback-capture`.
- **State schema** (`state-schema.md`): Version **1.0.0**. State in `.forge/` (gitignored). Checkpoints per task. Corrupted counters recovered from checkpoints — fallback uses configured maximum (conservative), not zero. Key fields: `mode` (standard/migration/bootstrap — determines planner dispatch), `feedback_loop_count` (consecutive same-classification PR rejections — escalates at 2), `documentation.discovery_error` (degraded doc context when fg-130 fails), `abort_reason` (set on auto-abort, e.g., NO-GO timeout), `recovery` (runtime recovery state: failures, recoveries, degraded_capabilities).
- **Recovery** (`recovery/`): 7 strategies, weighted budget ceiling 5.5 (extremes: graceful-stop 0.0/free, state-reconstruction 1.5/costliest). See `recovery-engine.md`.
- **Error taxonomy** (`error-taxonomy.md`): 22 types (incl. `CONTEXT_OVERFLOW`), 16-level severity priority. MCP failures handled inline (skip + INFO), NOT by recovery engine. 3 consecutive transient-retry failures for same endpoint within 60s → reclassified as non-recoverable. `BUILD_FAILURE`/`TEST_FAILURE`/`LINT_FAILURE` are code-level errors handled by the orchestrator fix loop, not the recovery engine.
- **Agent communication** (`agent-communication.md`): Inter-stage data flows through orchestrator via stage notes. Agents cannot write state or message the user directly. However, coordinator agents (fg-400, fg-500, fg-600, fg-200, fg-310) **can** dispatch sub-agents within their stage — this is distinct from inter-stage communication. Quality gate includes previous batch findings (top 20) to reduce duplicates. PREEMPT tracking via `PREEMPT_APPLIED`/`PREEMPT_SKIPPED` markers.
- **Frontend design** (`frontend-design-theory.md`): Gestalt, visual hierarchy, color theory, typography, 8pt grid, motion — shared by all frontend agents.
- **Learnings** (`learnings/`): Per-module files (frameworks, languages, testing frameworks, crosscutting layers) + JSON schemas (`rule-learning-schema.json`, `agent-effectiveness-schema.json`) for tracking check rule evolution and agent performance.
- **Version detection:** PREFLIGHT detects dependency versions from manifest files (build.gradle.kts, package.json, go.mod, etc.) → `state.json.detected_versions`. Enables version-gated deprecation rules.
- **Convention drift:** Detected mid-run via per-section SHA256 hash comparison. Agents only react to changes in their relevant section.
- **Global retry budget:** Cumulative `total_retries` counter (default max: 10, configurable). Prevents unbounded cascades.
- **Concurrent run lock:** `.forge/.lock` with PID check + 24h stale timeout.

### Integrations

- **Linear** (optional): Epic/Stories/Tasks during PLAN, status updates per stage. Configured via `linear:` in `forge.local.md` (disabled by default). Failures retry once then degrade gracefully — recovery engine NOT invoked for MCP failures.
- **MCP detection**: `forge-run` detects available MCPs (Linear, Playwright, Slack, Context7, Figma). First failure marks MCP as degraded for the run. No MCP required.
- **Cross-repo**: 5-step discovery during `/forge-init`. Contract validation (`fg-250-contract-validator`), linked PRs, multi-repo worktrees during runs. State in `state.json.cross_repo`. Configurable via `discovery:` section.

### Knowledge Graph (`graph:` in `forge.local.md`)

Neo4j-based dual-purpose knowledge graph: (1) static plugin module relationship graph (pre-computed seed), (2) dynamic consuming project codebase graph (files, imports, classes, dependencies). Enables impact analysis, convention stack resolution, gap detection, and recommendation queries via Cypher. Docker-managed in `.forge/`, accessed by orchestrator via Neo4j MCP. Enabled by default — set `graph.enabled: false` to disable (e.g., if Docker is unavailable). See `shared/graph/schema.md` for node/relationship types and `shared/graph/query-patterns.md` for Cypher templates. Graceful degradation: pipeline works normally without Neo4j. Container name defaults to `forge-neo4j`, configurable via `graph.neo4j_container_name` in `forge.local.md` or `FORGE_NEO4J_CONTAINER` env var. Documentation node types: `DocFile`, `DocSection`, `DocDecision`, `DocConstraint`, `DocDiagram` — used by `fg-130-docs-discoverer` and `fg-350-docs-generator` to track documentation coverage and relationships.

### Check engine (`shared/checks/`)

3-layer engine triggered on every `Edit`/`Write` via PostToolUse hook:
- **Layer 1** (`layer-1-fast/`): regex patterns, sub-second. Enforces design tokens (hex/rgb detection) and animation performance.
- **Layer 2** (`layer-2-linter/`): framework-aware linter adapters.
- **Layer 3** (`layer-3-agent/`): AI-driven — `fg-140-deprecation-refresh` (PREFLIGHT) and `version-compat-reviewer` (REVIEW). Not triggered by `engine.sh`. Version-gated: rules only fire when project version >= `applies_from`.
- Modules customize via `rules-override.json` (extends shared defaults; use `"disabled": true` to suppress).
- Skip tracking: timeouts increment `.forge/.check-engine-skipped`, reported in VERIFY. Output format in `output-format.md`.

### Deprecation registries (`modules/frameworks/*/known-deprecations.json`)

**Schema v2**: `pattern`, `replacement`, `package`, `since`, `removed_in`, `applies_from`, `applies_to`, `added`, `addedBy`. Rules skip when project version < `applies_from`. Severity: WARNING if deprecated, CRITICAL if `removed_in` reached. Auto-updated by `fg-140-deprecation-refresh` during PREFLIGHT.

### Skills (18 in `skills/`)

`forge-run` (main entry), `forge-init`, `forge-status`, `forge-reset`, `forge-rollback`, `forge-history`, `forge-shape`, `verify`, `security-audit`, `codebase-health`, `migration`, `bootstrap-project`, `deploy`, `graph-init`, `graph-status`, `graph-query`, `graph-rebuild`, `docs-generate`. Frontend commands (`fe-check-theme`, `fe-design-review`, etc.) live in the consuming project, not here.

### Hooks (`hooks/hooks.json`)

3 hooks: check engine on `Edit|Write`, checkpoint on `Skill`, feedback capture on `Stop`.

## Adding a new framework

Create `modules/frameworks/{name}/` with:
- `conventions.md` — must include Dos/Don'ts section
- `local-template.md` — using `components:` structure
- `forge-config-template.md` — must include `total_retries_max` and `oscillation_tolerance`
- `rules-override.json` — framework-specific check overrides
- `known-deprecations.json` — schema v2 (`applies_from`, `removed_in`, `applies_to` required). Seed 5-15 entries.
- Optional: `variants/{language}.md`, `testing/{test-framework}.md`, `scripts/check-*.sh`, `hooks/*-guard.sh`

Add `shared/learnings/{name}.md`. Wire into the local template's `quality_gate` batches. Bump the corresponding `MIN_*` constant in `tests/lib/module-lists.bash` (module arrays are auto-discovered from disk).

**New language?** Also add `modules/languages/{lang}.md` and `shared/learnings/{lang}.md`. **New testing framework?** Also add `modules/testing/{test-framework}.md` and `shared/learnings/{test-framework}.md`.

## Adding a new layer module

Create `modules/{layer}/{name}.md` with the standard structure (Overview, Architecture Patterns, Configuration, Performance, Security, Testing, Dos, Don'ts). Optionally add `{name}.rules-override.json` and `{name}.known-deprecations.json`.

Create framework bindings under `modules/frameworks/{fw}/{layer}/{name}.md` for each applicable framework.

Add a learnings file at `shared/learnings/{name}.md`.

## Module-specific gotchas

All 21 frameworks share the same base structure — see their `conventions.md` for details. Only non-obvious conventions listed here:

- **spring**: Kotlin variant uses hexagonal architecture with sealed interface hierarchy (`XxxPersisted`/`XxxNotPersisted`/`XxxId`), ports & adapters. Core uses Kotlin types; persistence uses Java types. Web stack (`web: mvc | webflux`) and persistence (`persistence: hibernate | r2dbc | jooq | exposed`) are independent choices — variant files are language-only. `@Transactional` on use case impls only.
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
./tests/run-all.sh structural       # 39 checks, no bats needed
./tests/run-all.sh unit             # 10 test files
./tests/run-all.sh contract         # 20 test files
./tests/run-all.sh scenario         # 11 test files
./tests/lib/bats-core/bin/bats tests/unit/scoring.bats  # Single test file
```

Manual debugging:
```bash
grep -A1 "^name:" agents/*.md                    # List agents
shared/checks/engine.sh --verify --project-root . --files-changed src/Main.kt  # Verify mode (also: --hook, --review)
grep -L "Forbidden Actions" agents/*.md           # Find non-compliant agents
for m in modules/frameworks/*/local-template.md; do grep -q "linear:" "$m" || echo "MISSING: $m"; done
for m in modules/frameworks/*/forge-config-template.md; do grep -q "total_retries_max" "$m" || echo "MISSING: $m"; done

# Verify all modules have learnings files (auto-discovers from disk)
for dir in modules/languages modules/testing modules/databases modules/persistence \
           modules/migrations modules/api-protocols modules/messaging modules/caching \
           modules/search modules/storage modules/auth modules/observability \
           modules/build-systems modules/ci-cd modules/container-orchestration modules/code-quality; do
  for f in "$dir"/*.md; do
    name=$(basename "$f" .md)
    [ -f "shared/learnings/$name.md" ] || echo "MISSING: learnings/$name.md"
  done
done
for fw in modules/frameworks/*/; do
  name=$(basename "$fw")
  [ -f "shared/learnings/$name.md" ] || echo "MISSING: learnings/$name.md"
done
```

## Gotchas

### Structural rules

- Agent `name` in frontmatter **must** match filename without `.md` — orchestrator dispatch depends on it.
- Scripts need shebang (`#!/usr/bin/env bash`) and `chmod +x` — hooks fail silently without this.
- `shared/` files are contracts — changing `scoring.md`, `stage-contract.md`, `state-schema.md`, or `frontend-design-theory.md` affects all agents/modules. Verify downstream impact.
- The plugin never touches consuming project files. Runtime state goes to `.forge/`.
- `forge-config.md` is auto-tuned by retrospective — manual edits may be overwritten. Wrap parameters in `<!-- locked -->` / `<!-- /locked -->` fences to protect them from auto-tuning.

### Check engine

- If `engine.sh` is broken/non-executable, all edits trigger hook errors. On timeout, skip counter increments but edit succeeds. Hook scripts are validated at plugin installation (shebang + executable permission checks in `validate-plugin.sh`).
- `rules-override.json` extends (not replaces) shared defaults. Use `"disabled": true` to suppress.
- `engine.sh` multi-component YAML parsing expects 2-space indentation (component names at 2-space, path/framework at 4-space). Non-standard indentation (tabs, 4-space) now emits a WARNING to stderr and falls back to single-component detection. Forge-generated templates always use 2-space.
- `known-deprecations.json` v1 entries (without `applies_from`) apply universally (backward compatible). Unknown project versions → all rules apply.

### PREFLIGHT constraints

- Scoring: `critical_weight >= 10`, `warning_weight >= 1`, `warning_weight > info_weight`, `info_weight >= 0`, `pass_threshold >= 60`, `concerns_threshold >= 40`, `concerns_threshold < pass_threshold`, `pass_threshold - concerns_threshold >= 10`, `oscillation_tolerance` 0-20. Global retry budget: `total_retries_max` 5-30.
- Convergence: `max_iterations` 3-20, `plateau_threshold` 0-10, `plateau_patience` 1-5, `target_score` >= `pass_threshold` and <= 100.

### Pipeline modes

- **Greenfield projects:** `/forge-init` detects empty projects and offers three paths: Bootstrap (dispatch `fg-050-project-bootstrapper`), Select stack manually (choose from available frameworks), or Skip. Unknown/null detection on non-empty projects also triggers manual framework selection. See `forge-init` SKILL.md Greenfield Detection section.
- **Bootstrap mode:** Stage 4 (IMPLEMENT) is skipped — all files created by bootstrapper in Stage 2. Stage 3 uses bootstrap-scoped validation (no conventions check, no Challenge Brief required). Stage 6 uses reduced reviewer set (`architecture-reviewer` + `security-reviewer` only). Quality target is `pass_threshold`, not 100.
- **Migration mode:** All 10 stages run. Stage 2 uses `fg-160-migration-planner`. Stage 4 cycles through migration-specific states (`MIGRATING`, `MIGRATION_PAUSED`, `MIGRATION_CLEANUP`, `MIGRATION_VERIFY`). See `stage-contract.md` Migration Mode section.
- `--dry-run` runs PREFLIGHT→VALIDATE only. No worktree, no Linear, no file changes. No `.forge/.lock`, no checkpoint files, no `lastCheckpoint` updates.

### Convergence & review

- PREEMPT confidence decay: 10 domain-matched unused runs → HIGH → MEDIUM → LOW → ARCHIVED. 1 false positive = 3 unused runs. Archived items are not loaded at PREFLIGHT.
- **Convergence safety gate restart:** Resets `phase_iterations`, `plateau_count`, `last_score_delta`, `convergence_state` to initial values. Does NOT reset `total_iterations` or `score_history`. See `convergence-engine.md` safety_gate section.
- **PLATEAUED transition:** Score >= `pass_threshold` proceeds directly to safety gate. Score in CONCERNS range escalates to user first. Score in FAIL range recommends abort — does NOT proceed to safety gate.
- **Preview validator gating:** When `preview.block_merge: true`, FAIL verdict blocks Stage 8 progression. Orchestrator loops: implement fix → verify → re-validate preview (max `preview.max_fix_loops`, default 1).

### Implementation & shipping

- Orchestrator enforces parallel task conflict detection at IMPLEMENT — scaffolders serial first, then conflict detection, then implementers parallel. Shared-file tasks auto-serialized.
- **Feedback loop detection:** `previous_feedback_classification` tracks the preceding PR rejection category. When same classification occurs 2+ consecutive times, orchestrator escalates with Loop/Guide/Start fresh/Override options. `feedback_loop_count` is incremented by orchestrator (not just initialized to 0).

### Module & framework resolution

- Framework-level binding files (e.g., `testing/`, `persistence/`, `messaging/`) EXTEND their corresponding generic layer files — they don't replace.
- Framework-less projects (`go-stdlib` or `framework: null`): only language + testing layers. Infra frameworks (`k8s`): `language: null`, only framework layer.

### Cross-repo

- PR failures don't block main PR. Worktrees use alphabetical lock ordering to prevent deadlocks. Discovery results stored with `detected_via` — re-run `/forge-init` to refresh.
- Timeout: 30 minutes per project (configurable via `cross_repo.timeout_minutes`). Exceeded → task marked failed, main PR unaffected.

### State schema

- **`modules` vs `components`:** `components` = per-service state within a single monorepo. `modules` = per-repo state across related repositories. Both can be active simultaneously.

### Testing

- **Test module counts:** Module lists are auto-discovered from disk via `tests/lib/module-lists.bash`. Minimum count guards (e.g., `MIN_FRAMEWORKS=21`) catch accidental deletions. When intentionally adding modules, bump the corresponding `MIN_*` constant in `module-lists.bash`.

## Plugin distribution (`.claude-plugin/`)

- `plugin.json` — manifest (v1.0.0). `marketplace.json` — catalog for `quantumbitcz`.
- Hooks in `hooks/hooks.json` only (NOT in plugin.json).
- Install: `/plugin marketplace add quantumbitcz/forge` then `/plugin install forge@quantumbitcz`.

## Governance

- `LICENSE` — Proprietary (QuantumBit s.r.o.)
- `CONTRIBUTING.md` — How to add modules, agents, hooks, skills
- `SECURITY.md` — Vulnerability reporting and plugin security practices
- `.github/CODEOWNERS` — Auto-assigns `@quantumbitcz` to all PRs
- `.github/release.yml` — Auto-generated release notes by PR label
