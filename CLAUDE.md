# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`forge` is a Claude Code plugin (v1.14.0, `quantumbitcz` marketplace / Git submodule). 10-stage autonomous pipeline: Preflight → Explore → Plan → Validate → Implement (TDD) → Verify → Review → Docs → Ship → Learn. Entry: `/forge-run` → `fg-100-orchestrator`.

## Architecture

Layered, resolution top-down:

1. **Project config** (`.claude/forge.local.md`, `.claude/forge-config.md`, `.claude/forge-log.md`) — per-project settings in consuming repo.
2. **Module layer** (`modules/`):
   - `languages/` (15): kotlin, java, typescript, python, go, rust, swift, c, csharp, ruby, php, dart, elixir, scala, cpp
   - `frameworks/` (21): spring, react, fastapi, axum, swiftui, vapor, express, sveltekit, k8s, embedded, go-stdlib, aspnet, django, nextjs, gin, jetpack-compose, kotlin-multiplatform, angular, nestjs, vue, svelte — each with `conventions.md`, config files, `variants/`, and subdirectory bindings (`testing/`, `persistence/`, `messaging/`, etc.)
   - `testing/` (19): kotest, junit5, vitest, jest, pytest, go-testing, xctest, rust-test, xunit-nunit, testcontainers, playwright, cypress, cucumber, k6, detox, rspec, phpunit, exunit, scalatest
   - `databases/`, `persistence/`, `migrations/`, `api-protocols/`, `messaging/`, `caching/`, `search/`, `storage/`, `auth/`, `observability/` — domain-specific best practices
   - `build-systems/` (7), `ci-cd/` (7), `container-orchestration/` (11) — tooling patterns
   - `documentation/` — doc conventions. `code-quality/` — ~70 tool files (linters, formatters, coverage, doc generators, security scanners, mutation testing)
   - **Composition order** (most specific wins): variant > framework-binding > framework > language > code-quality > generic-layer > testing
3. **Shared core** (`agents/`, `shared/`, `hooks/`, `skills/`) — 38 agents, check engine, recovery, scoring, discovery, knowledge graph, frontend design theory.

**Resolution:** `forge-config.md` > `forge.local.md` > plugin defaults. Orchestrator loads agent `.md` as subagent system prompt — size = token cost.

## Quick start

```bash
./tests/validate-plugin.sh          # 51 structural checks, ~2s
./tests/run-all.sh                  # Full test suite, ~30s
ln -s "$(pwd)" /path/to/project/.claude/plugins/forge  # Local install, then /forge-init
```

**First-time?** Read `shared/agent-philosophy.md` first. Run `validate-plugin.sh` after every change.

## Development workflow

Doc-only plugin (no build). Test: symlink into `.claude/plugins/` → `/forge-init` → `/forge-run --dry-run <req>` → `/forge-run <req>` → check `.forge/state.json`.

## Key entry points

| Topic | File |
|---|---|
| Pipeline flow | `shared/stage-contract.md` |
| Orchestrator | `agents/fg-100-orchestrator.md` |
| Scoring | `shared/scoring.md` |
| State | `shared/state-schema.md` (v1.5.0) |
| Errors | `shared/error-taxonomy.md` + `shared/recovery/recovery-engine.md` |
| Agent design | `shared/agent-philosophy.md` + `shared/agent-communication.md` |
| Graph | `shared/graph/schema.md` |
| Tokens | `shared/agent-defaults.md` + `shared/logging-rules.md` |
| Convergence | `shared/convergence-engine.md` |
| Evidence | `shared/verification-evidence.md` |
| Kanban | `shared/tracking/tracking-schema.md` |
| Git | `shared/git-conventions.md` |
| MCP | `shared/mcp-provisioning.md` |
| Versions | `shared/version-resolution.md` |
| UI | `shared/agent-ui.md` |
| Sprint | `shared/sprint-state-schema.md` |
| Intent | `shared/intent-classification.md` |
| State machine | `shared/state-transitions.md` |
| Domain detection | `shared/domain-detection.md` |
| Decision log | `shared/decision-log.md` |
| State integrity | `shared/state-integrity.sh` |

## Agents (38 total, `agents/*.md`)

**Pipeline** (`fg-{NNN}-{role}`):
- Pre-pipeline: `fg-010-shaper`, `fg-015-scope-decomposer`, `fg-020-bug-investigator`, `fg-050-project-bootstrapper`
- Sprint: `fg-090-sprint-orchestrator`
- Core: `fg-100-orchestrator` (coordinator, never writes code), helpers: `fg-101-worktree-manager`, `fg-102-conflict-resolver`, `fg-103-cross-repo-coordinator`
- Preflight: `fg-130-docs-discoverer`, `fg-140-deprecation-refresh`, `fg-150-test-bootstrapper`, `fg-160-migration-planner`
- Plan/Validate: `fg-200-planner`, `fg-210-validator`, `fg-250-contract-validator`
- Implement: `fg-300-implementer`, `fg-310-scaffolder`, `fg-320-frontend-polisher` (conditional on `frontend_polish.enabled`)
- Docs: `fg-350-docs-generator`
- Verify/Review: `fg-400-quality-gate`, `fg-505-build-verifier`, `fg-500-test-gate`
- Ship: `fg-590-pre-ship-verifier`, `fg-600-pr-builder`, `fg-650-preview-validator`, `fg-610-infra-deploy-verifier` (conditional on k8s/infra)
- Learn: `fg-700-retrospective`, `fg-710-post-run`

**Review** (9, via quality gate): `fg-410-code-reviewer`, `fg-411-security-reviewer`, `fg-412-architecture-reviewer`, `fg-413-frontend-reviewer` (supports modes: full/conventions-only/a11y-only/performance-only), `fg-416-backend-performance-reviewer`, `fg-417-version-compat-reviewer`, `fg-418-docs-consistency-reviewer`, `fg-419-infra-deploy-reviewer`, `fg-420-dependency-reviewer`.

### Agent rules

- **Frontmatter required:** `name` (must match filename sans `.md`), `description`, `tools`. Dispatch agents must include `Agent`.
- **UI:** `AskUserQuestion` for multi-option choices (never `Options: (1)...`). `EnterPlanMode`/`ExitPlanMode` for planning (skip in autonomous/replanning). `TaskCreate`/`TaskUpdate` wraps every dispatch.
- **UI tiers:** Tier 1 (tasks+ask+plan): shaper, scope-decomposer, planner, migration planner, bootstrapper, sprint orchestrator. Tier 2 (tasks+ask): orchestrator, bug investigator, quality gate, test gate, PR builder, cross-repo coordinator, post-run. Tier 3 (tasks): implementer, frontend polisher, retrospective, docs discoverer, deprecation refresh, preview validator, pre-ship verifier, infra verifier, scaffolder, docs generator, contract validator, test bootstrapper, build-verifier. Tier 4 (none): all reviewers (fg-410 through fg-420), validator, worktree manager, conflict resolver.
- **`ui:` frontmatter** declares capabilities; enforced by `ui-frontmatter-consistency.bats`.
- **Config:** `components:` in `forge.local.md` — core: `language:`, `framework:`, `variant:`, `testing:`. Framework-specific: `web`, `persistence` (distinct from crosscutting `modules/persistence/`). Optional crosscutting: `database`, `migrations`, `api_protocol`, `messaging`, `caching`, `search`, `storage`, `auth`, `observability`, `build_system`, `ci`, `container`, `orchestrator`, `documentation`, `code_quality` (list type, supports object form with external ruleset). Multi-service: entries with `path:`. Documentation config: `documentation:` section controls generation.
- **`mode_config:`** defines per-stage agent selection and mode overlays. `mode_config.stages` maps each pipeline stage to its default agent. `mode_config.mode_overlays` overrides specific stages per pipeline mode (bugfix, migration, bootstrap). Resolution: overlay > stage default > hardcoded fallback.
- **Worktree:** All impl in `.forge/worktree`. User's tree never modified. Branch collision → epoch suffix.
- **Challenge Brief required** in every plan. Validator returns REVISE if missing.
- **APPROACH-*/DOC-* findings:** APPROACH scored as INFO (-2), escalated at 3+ recurrences. DOC ranges CRITICAL→WARNING→INFO.
- **Token management:** Agent `.md` = subagent system prompt (every line = tokens). Constraints compressed with reference to `shared/agent-defaults.md`. Output format references `shared/checks/output-format.md`. Convention stack soft cap: 12 files/component. Module overviews max 15 lines.
- **Description tiering:** Tier 1 (entry, 6): description + example. Tier 2 (reviewers, 9): single-line. Tier 3 (internal, 22): minimal. Full capability in `.md` body.

### Routing & decomposition

- `/forge-run` auto-classifies intent and routes. Requirements <50 words missing 3+ of (actors, entities, surface, criteria) → shaper. Prefixes (`bugfix:`, `migrate:`, `bootstrap:`) and flags (`--sprint`, `--parallel`) override. Config: `routing.*`, `scope.*` in `forge-config.md`.
- Multi-feature detected via fast scan (text) or deep scan (post-EXPLORE). Triggers `fg-015-scope-decomposer` → `fg-090-sprint-orchestrator`.
- Frontend design preview via superpowers visual companion during PLAN (optional, graceful degradation).

## Core contracts

### Scoring (`scoring.md`)

Formula: `max(0, 100 - 20×CRITICAL - 5×WARNING - 2×INFO)`. PASS ≥80, CONCERNS 60-79, FAIL <60 or unresolved CRITICAL. 19 shared categories (16 wildcard prefixes: `ARCH-*`, `SEC-*`, `PERF-*`, `FE-PERF-*`, `TEST-*`, `CONV-*`, `DOC-*`, `QUAL-*`, `APPROACH-*`, `SCOUT-*`, `A11Y-*`, `DEP-*`, `COMPAT-*`, `CONTRACT-*`, `STRUCT-*`, `INFRA-*` + 3 discrete: `REVIEW-GAP`, `DESIGN-TOKEN`, `DESIGN-MOTION`). Dedup key: `(component, file, line, category)`. SCOUT-* excluded from score (two-point filtering). 5 iteration counters: `verify_fix_count`, `test_cycles`, `quality_cycles` (inner-loop); `phase_iterations` (per-phase, resets); `total_iterations` (cumulative). Timed-out reviewers: INFO → WARNING. 7 validation perspectives.

### State, recovery & errors

- **State** (`state-schema.md`): v1.5.0. `.forge/` (gitignored). Checkpoints per task. Corrupted counters → fallback to configured max. Key fields: `mode` (standard/migration/bootstrap/bugfix), `feedback_loop_count` (escalates at 2), `recovery`, `ticket_id`, `branch_name`, `graph`. Concurrent run lock: `.forge/.lock` (PID + 24h stale timeout).
- **Recovery** (`recovery/`): 7 strategies, budget ceiling 5.5 (resets per run; sprint = independent budgets). Highest-severity first. Global retry budget: `total_retries` (default max 10, configurable).
- **Errors** (`error-taxonomy.md`): 22 types, 16-level severity. MCP failures → inline skip + INFO (not recovery engine). 3 consecutive transients in 60s → non-recoverable. `BUILD`/`TEST`/`LINT_FAILURE` → orchestrator fix loop.
- **Communication:** Inter-stage via orchestrator stage notes. Coordinators (fg-400/500/600/200/310) can dispatch sub-agents within stage. Quality gate includes previous batch findings (top 20). PREEMPT tracking via `PREEMPT_APPLIED`/`PREEMPT_SKIPPED`.

### Stage contracts & shipping

States: PREFLIGHT → EXPLORING → PLANNING → VALIDATING → IMPLEMENTING → VERIFYING → REVIEWING → DOCUMENTING → SHIPPING → LEARNING. Migration: MIGRATING/PAUSED/CLEANUP/VERIFY. PR rejection → Stage 4 (impl) or Stage 2 (design) via `fg-710-post-run`.

**Evidence-based shipping:** `fg-590-pre-ship-verifier` runs fresh build+test+lint+review → `.forge/evidence.json`. PR builder refuses without `verdict: SHIP`. No "continue anyway" — fix, retry, or abort.

### Supporting systems

- **Version detection:** PREFLIGHT detects from manifests → `state.json.detected_versions`. Enables version-gated deprecation rules.
- **Convention drift:** Mid-run SHA256 hash comparison. Agents react only to their relevant section changes.
- **Learnings** (`learnings/`): Per-module files + JSON schemas for rule evolution and agent effectiveness.
- **Frontend design** (`frontend-design-theory.md`): Gestalt, visual hierarchy, color theory, typography, 8pt grid, motion.

### Deterministic Control Flow

Pipeline control flow follows the formal transition table in `shared/state-transitions.md`. LLM judgment is used for code review, implementation, and architecture decisions — NOT for state transitions. Every branching decision is logged to `.forge/decisions.jsonl` per `shared/decision-log.md`. Recovery uses circuit breakers per failure category (`shared/recovery/recovery-engine.md` §8.1). Reviewer conflicts are resolved by priority ordering in `shared/agent-communication.md` §3.1.

### Shared scripts (`shared/`)

| Script | Purpose |
|---|---|
| `forge-state.sh` | Executable state machine (57+ transitions from `state-transitions.md`) |
| `forge-state-write.sh` | Atomic JSON writes with WAL and `_seq` versioning |
| `forge-token-tracker.sh` | Token budget tracking and ceiling enforcement |
| `forge-linear-sync.sh` | Event-driven Linear sync (audit layer) |
| `forge-sim.sh` | Pipeline simulation harness |
| `forge-timeout.sh` | Pipeline timeout enforcement |
| `forge-compact-check.sh` | Compaction suggestion hook |
| `check-prerequisites.sh` | bash 4+ and python3 validation |

### Mode overlays (`shared/modes/`)

7 pipeline mode overlays: `standard`, `bugfix`, `migration`, `bootstrap`, `testing`, `refactor`, `performance`. Loaded by orchestrator at PREFLIGHT based on `state.mode`. Each overlay defines phase-specific adjustments (skip conditions, reduced thresholds, extra agents).

## Integrations

- **Linear** (optional): Epic/Stories/Tasks at PLAN, status per stage. Disabled by default. MCP failures → graceful degradation (no recovery engine).
- **MCP detection:** Detects Linear, Playwright, Slack, Context7, Figma, Excalidraw, Neo4j. First failure → degraded for run. No MCP required.
- **Cross-repo:** 5-step discovery at `/forge-init`. Contract validation, linked PRs, multi-repo worktrees. Timeout: 30min (configurable). Alphabetical lock ordering. PR failures don't block main PR. Discovery results stored with `detected_via`.

## Knowledge graph

Neo4j dual-purpose: (1) plugin module graph (seed), (2) project codebase graph. Docker-managed, disable with `graph.enabled: false`. Scoped by `project_id` (git remote) + optional `component`. 8 agents with `neo4j-mcp`: fg-010/020/090/100/102/200/210/400. Doc nodes for coverage tracking. Auto-updates post-IMPLEMENT/VERIFY/pre-REVIEW. Pipeline works without Neo4j. Query patterns: Bug Hotspots (14), Test Coverage (15), Cross-Feature Overlap (19), Cross-Repo Deps (20).

## Check engine (`shared/checks/`)

3 layers on every `Edit`/`Write` via PostToolUse hook:
- **L1** (regex, sub-second): design tokens, animation perf. **L2** (linter adapters). **L3** (AI-driven, not in `engine.sh`): deprecation refresh + version compat, version-gated.
- `rules-override.json` extends defaults; `"disabled": true` to suppress. Skip tracking in `.forge/.check-engine-skipped`.

**Deprecation registries** (`modules/frameworks/*/known-deprecations.json`): Schema v2 (`pattern`, `replacement`, `package`, `since`, `removed_in`, `applies_from`, `applies_to`, `added`, `addedBy`). Skip when project version < `applies_from`. WARNING if deprecated, CRITICAL if `removed_in` reached. Auto-updated at PREFLIGHT.

## Infra testing (`fg-610-infra-deploy-verifier`)

5 tiers: T1 (<10s, static lint), T2 (<60s, container build+trivy), T3 (<5min, ephemeral cluster — **default**), T4 (<5min, contract stubs), T5 (<15min, full integration). Config: `infra.max_verification_tier` (1-5). Missing tools skip tiers. Findings: `INFRA-HEALTH` (CRITICAL), `INFRA-SMOKE` (WARNING), `INFRA-CONTRACT`/`INFRA-E2E` (CRITICAL), `INFRA-IMAGE` (WARNING/CRITICAL).

## Skills (29), hooks, kanban, git

**Skills:** `forge-run` (main entry), `forge-fix`, `forge-init`, `forge-status`, `forge-reset`, `forge-rollback`, `forge-history`, `forge-shape`, `forge-sprint`, `forge-review` (quick: 3 agents, full: up to 9; loops to score 100), `verify`, `security-audit`, `codebase-health`, `deep-health`, `migration`, `bootstrap-project`, `deploy`, `graph-init`, `graph-status`, `graph-query`, `graph-rebuild`, `graph-debug` (targeted Neo4j diagnostics), `docs-generate`, `forge-diagnose` (read-only diagnostic), `repair-state` (targeted state.json fixes), `config-validate` (pre-pipeline config check), `forge-abort` (graceful pipeline stop), `forge-resume` (resume from checkpoint), `forge-profile` (pipeline performance analysis).

**Hooks** (4): check engine on `Edit|Write`, checkpoint on `Skill`, feedback capture on `Stop`, compaction check on `Agent`.

**Kanban** (`.forge/tracking/`): File-based board (`backlog/`, `in-progress/`, `review/`, `done/`). Prefix configurable (default `FG`). IDs never reused. Shaper creates → orchestrator moves → PR builder updates → retrospective closes. Silently skips if uninitialized.

**Git:** Branch `{type}/{ticket}-{slug}` (configurable). Conventional Commits or `project` (auto-detected). **Never:** `Co-Authored-By`, AI attribution, `--no-verify`.

**Init:** `/forge-init` generates project-local plugin with hooks, skills, agents. Respects existing hooks. MCP auto-provisioning at init.

## Adding new modules

### New framework

Create `modules/frameworks/{name}/` with: `conventions.md` (with Dos/Don'ts), `local-template.md`, `forge-config-template.md` (must include `total_retries_max`, `oscillation_tolerance`), `rules-override.json`, `known-deprecations.json` (v2, 5-15 entries). Optional: `variants/`, `testing/`, `scripts/`, `hooks/`. Add `shared/learnings/{name}.md`. Bump `MIN_*` in `tests/lib/module-lists.bash`.

New language → also `modules/languages/{lang}.md` + learnings. New test framework → also `modules/testing/{name}.md` + learnings.

### New layer module

Create `modules/{layer}/{name}.md` (Overview, Architecture, Config, Performance, Security, Testing, Dos, Don'ts). Optional: `.rules-override.json`, `.known-deprecations.json`. Add framework bindings and learnings file.

## Framework gotchas

All 21 share the same base structure. Non-obvious conventions only:

- **spring**: Kotlin variant = hexagonal arch, sealed interfaces, ports & adapters. `@Transactional` on use case impls only. `web` and `persistence` are independent choices.
- **react**: Typography via `style={{ fontSize }}` not Tailwind. Colors via tokens. Error Boundaries at route level.
- **embedded**: No `malloc`/`printf`/`float` in ISR. `volatile` for shared vars.
- **k8s**: `language: null`. Pin images to SHA.
- **swiftui**: `[weak self]` in stored closures. SPM over CocoaPods.
- **angular**: Standalone components, signals, OnPush, NgRx SignalStore.
- **nestjs**: Module DI, Pipes/Guards/Interceptors.
- **vue**: Composition API + `<script setup>`, Pinia, Nuxt auto-imports.
- **svelte**: Svelte 5 runes, standalone SPAs (distinct from SvelteKit).

## Validation

```bash
./tests/run-all.sh                  # Full (~30s)
./tests/run-all.sh structural       # 51 checks
./tests/run-all.sh unit|contract|scenario
./tests/lib/bats-core/bin/bats tests/unit/scoring.bats  # Single file
```

## Gotchas

### Structural

- Agent `name` must match filename sans `.md`.
- Scripts need `#!/usr/bin/env bash` + `chmod +x`. Graph scripts, `run-linter.sh`, `engine.sh` require **bash 4.0+** (macOS needs `brew install bash`). Graph scripts guard via `require_bash4()` from `shared/platform.sh`; `run-linter.sh`/`engine.sh` use inline checks. All scripts use `_glob_exists()` instead of `compgen -G` (`engine.sh` keeps inline copy to avoid sourcing `platform.sh` on every hook).
- `shared/` files are contracts — changes affect all agents/modules. Verify downstream impact.
- Plugin never touches consuming project files. Runtime state → `.forge/`.
- `forge-config.md` auto-tuned by retrospective. Use `<!-- locked -->` fences to protect.
- `.forge/` deletion mid-run = unrecoverable. Use `/forge-reset`.

### Check engine

- Broken `engine.sh` → all edits error. Timeout → skip counter + edit succeeds. Hook scripts validated at install.
- `rules-override.json` extends (not replaces). YAML parsing expects 2-space indent (non-standard → WARNING + fallback).
- Deprecation v1 entries (no `applies_from`) apply universally. Unknown versions → all rules apply.

### PREFLIGHT constraints

- Scoring: `critical_weight ≥ 10`, `warning_weight ≥ 1 > info_weight ≥ 0`, `pass_threshold ≥ 60`, `concerns_threshold ≥ 40`, gap ≥ 10, `oscillation_tolerance` 0-20. `total_retries_max` 5-30.
- Convergence: `max_iterations` 3-20, `plateau_threshold` 0-10, `plateau_patience` 1-5, `target_score` ∈ [pass_threshold, 100].
- Sprint: `sprint.poll_interval_seconds` 10-120 (default 30), `sprint.dependency_timeout_minutes` 5-180 (default 60).
- Tracking: `tracking.archive_after_days` 30-365 or 0 (default 90).
- Scope: `decomposition_threshold` 2-10 (default 3). Routing: `vague_threshold` low/medium/high (default medium).
- Shipping: `min_score` ∈ [pass_threshold, 100] (default 90), `evidence_max_age_minutes` 5-60 (default 30).

### Pipeline modes

- **Greenfield:** `/forge-init` detects empty projects → Bootstrap/Select stack/Skip.
- **Bootstrap:** Stage 4 skipped. Reduced validation + review. Target = `pass_threshold`.
- **Bugfix:** `fg-020-bug-investigator` → reproduction (max 3) → 4-perspective validation → reduced reviewers. Patterns in `.forge/forge-log.md`.
- **Migration:** All 10 stages. `fg-160-migration-planner` at Stage 2. Stage 4 cycles through MIGRATING, MIGRATION_PAUSED, MIGRATION_CLEANUP, MIGRATION_VERIFY.
- **Dry-run:** PREFLIGHT→VALIDATE only. No worktree/Linear/lock/checkpoints.
- **Autonomous:** `autonomous: true` → auto-selection (logged `[AUTO]`). Never pauses except unrecoverable CRITICAL.
- **Sprint:** `--sprint`/`--parallel`. Independence analysis → parallel orchestrators. Isolation: `.forge/runs/{id}/` + `.forge/worktrees/{id}/`. Serialize = complete SHIP before second starts IMPLEMENT.

### Convergence & review

- PREEMPT decay: 10 unused → HIGH→MEDIUM→LOW→ARCHIVED. 1 false positive = 3 unused.
- Safety gate restart: resets phase state, NOT `total_iterations`/`score_history`. First cycle exempt from plateau.
- PLATEAUED: ≥pass_threshold → safety gate. CONCERNS → escalate to user. FAIL → recommend abort.
- Preview gating: FAIL blocks Stage 8. Fix loop (max `preview.max_fix_loops`). Exhaustion → user choice.

### Implementation

- Worktree created at PREFLIGHT (not IMPLEMENT). Exceptions: `--dry-run`, `/forge-init`. Branch from kanban ticket ID.
- Parallel task conflict detection: scaffolders serial → conflict detect → implementers parallel. Shared files auto-serialized.
- Feedback loop: same PR rejection 2+ times → escalate options. `feedback_loop_count` incremented by orchestrator.
- Framework bindings EXTEND generic layers. `go-stdlib`/`framework: null` → language + testing only. `k8s` → `language: null`.
- `components` = per-service (monorepo). `modules` = per-repo (multi-repo). Both can coexist.
- **Version resolution:** NEVER use training data versions. Always search internet at runtime.
- **Test counts:** Auto-discovered via `module-lists.bash`. Bump `MIN_*` when adding modules.

## Distribution

`plugin.json` (v1.14.0), `marketplace.json`. Hooks in `hooks/hooks.json` only. Install: `/plugin marketplace add quantumbitcz/forge` → `/plugin install forge@quantumbitcz`.

## Governance

`LICENSE` (Proprietary, QuantumBit s.r.o.), `CONTRIBUTING.md`, `SECURITY.md`, `.github/CODEOWNERS` (@quantumbitcz), `.github/release.yml`.
