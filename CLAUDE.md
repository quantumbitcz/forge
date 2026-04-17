# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`forge` is a Claude Code plugin (v2.8.0, `quantumbitcz` marketplace / Git submodule). 10-stage autonomous pipeline: Preflight → Explore → Plan → Validate → Implement (TDD) → Verify → Review → Docs → Ship → Learn. Entry: `/forge-run` → `fg-100-orchestrator`.

## Architecture

Layered, resolution top-down:

1. **Project config** (`.claude/forge.local.md`, `.claude/forge-config.md`, `.claude/forge-log.md`) — per-project settings in consuming repo.
2. **Module layer** (`modules/`):
   - `languages/` (15): kotlin, java, typescript, python, go, rust, swift, c, csharp, ruby, php, dart, elixir, scala, cpp
   - `frameworks/` (21): spring, react, fastapi, axum, swiftui, vapor, express, sveltekit, k8s, embedded, go-stdlib, aspnet, django, nextjs, gin, jetpack-compose, kotlin-multiplatform, angular, nestjs, vue, svelte — each with `conventions.md`, config files, `variants/`, and subdirectory bindings (`testing/`, `persistence/`, `messaging/`, etc.)
   - `testing/` (19): kotest, junit5, vitest, jest, pytest, go-testing, xctest, rust-test, xunit-nunit, testcontainers, playwright, cypress, cucumber, k6, detox, rspec, phpunit, exunit, scalatest
   - `databases/`, `persistence/`, `migrations/`, `api-protocols/`, `messaging/`, `caching/`, `search/`, `storage/`, `auth/`, `observability/` — domain-specific best practices
   - `ml-ops/` (4): mlflow, dvc, wandb, sagemaker. `data-pipelines/` (3): airflow, dagster, dbt. `feature-flags/` (3): conventions + launchdarkly, unleash
   - `build-systems/` (9), `ci-cd/` (7), `container-orchestration/` (11) — tooling patterns
   - `documentation/` — doc conventions. `code-quality/` — ~70 tool files (linters, formatters, coverage, doc generators, security scanners, mutation testing)
   - **Composition order** (most specific wins): variant > framework-binding > framework > language > code-quality > generic-layer > testing. Algorithm in `shared/composition.md`.
3. **Shared core** (`agents/`, `shared/`, `hooks/`, `skills/`) — 42 agents, check engine, recovery, scoring, discovery, knowledge graph, frontend design theory.
4. **MCP interface** (`shared/mcp-server/`) — Python MCP server exposing `.forge/` data to any MCP-capable AI client. Read-only. Optional (requires Python 3.10+).

**Resolution:** `forge-config.md` > `forge.local.md` > plugin defaults. Orchestrator loads agent `.md` as subagent system prompt — size = token cost.

## Quick start

```bash
./tests/validate-plugin.sh          # 73+ structural checks, ~2s
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
| State | `shared/state-schema.md` (v1.6.0) |
| Errors | `shared/error-taxonomy.md` + `shared/recovery/recovery-engine.md` |
| Agent design | `shared/agent-philosophy.md` + `shared/agent-communication.md` |
| Graph (Neo4j) | `shared/graph/schema.md` |
| Graph (SQLite) | `shared/graph/code-graph-schema.sql` |
| Convergence | `shared/convergence-engine.md` |
| State machine | `shared/state-transitions.md` |
| Agent registry | `shared/agent-registry.md` |
| Model routing | `shared/model-routing.md` |
| Confidence scoring | `shared/confidence-scoring.md` |
| Output compression | `shared/output-compression.md` |
| Input compression | `shared/input-compression.md` |
| Rule promotion | `shared/learnings/rule-promotion.md` |
| PREFLIGHT constraints | `shared/preflight-constraints.md` |
| Framework gotchas | `shared/framework-gotchas.md` |
| Cross-project learnings | `shared/cross-project-learnings.md` |
| Skill contract | `shared/skill-contract.md` |
| Agent colors + clusters | `shared/agent-colors.md` |
| AskUserQuestion patterns | `shared/ask-user-question-patterns.md` |

Additional docs in `shared/`: `agent-defaults.md`, `logging-rules.md`, `verification-evidence.md`, `tracking/tracking-schema.md`, `git-conventions.md`, `mcp-provisioning.md`, `version-resolution.md`, `agent-ui.md`, `sprint-state-schema.md`, `intent-classification.md`, `domain-detection.md`, `decision-log.md`, `state-integrity.sh`, `mcp-detection.md`, `learnings/README.md`, `learnings/memory-discovery.md`, `explore-cache.md`, `plan-cache.md`, `visual-verification.md`, `lsp-integration.md`, `observability.md`, `data-classification.md`, `security-posture.md`, `automations.md`, `background-execution.md`, `a2a-protocol.md`, `composition.md`, `living-specifications.md`, `spec-inference.md`, `accessibility-automation.md`, `i18n-validation.md`, `performance-regression.md`, `next-task-prediction.md`, `dx-metrics.md`, `monorepo-integration.md`, `feature-flag-management.md`, `a2a-http-transport.md`, `deployment-strategies.md`, `consumer-driven-contracts.md`.

## Skill selection guide

| Intent | Skill | Notes |
|---|---|---|
| Build a feature | `/forge-run` | Full 10-stage pipeline |
| Fix a bug | `/forge-fix` | Root cause investigation + targeted fix |
| Shape a vague idea | `/forge-shape` | Collaborative spec refinement |
| Review changed files | `/forge-review` | Quick (3 agents) or full (8 agents) |
| Review entire codebase | `/forge-codebase-health` | Read-only analysis, no fixes |
| Fix all codebase issues | `/forge-deep-health` | Iterative fix loop until clean |
| Quick build+lint+test | `/forge-verify` | No pipeline, just check commands |
| Security scan | `/forge-security-audit` | Module-appropriate vulnerability scanners |
| Pipeline broken? | `/forge-recover diagnose` | Read-only diagnostic, then `/forge-recover repair` to fix |
| Resume aborted run | `/forge-recover resume` | Continues from last checkpoint |
| Start fresh | `/forge-recover reset` | Clears state, preserves learnings |
| Multiple features | `/forge-sprint` | Parallel orchestration |
| Generate docs | `/forge-docs-generate` | README, ADRs, API specs, changelogs |
| Deploy | `/forge-deploy` | Staging, production, preview, rollback |
| Migrate framework | `/forge-migration` | Library/framework version upgrades |
| Ask about codebase | `/forge-ask` | Wiki, graph, explore cache, docs index |
| Pipeline analytics | `/forge-insights` | Quality, cost, convergence, memory trends |
| Reusable recipes | `/forge-playbooks` | Create, list, run, analyze pipeline playbooks |
| Review playbook refinements | `/forge-playbook-refine` | Interactive review/apply of improvement proposals |
| Compress agents | `/forge-compress` | Reduce agent .md token cost via terse rewriting |
| Toggle terse output | `/forge-compress output` | User-facing output compression (lite/full/ultra/off) |
| Quick commit | `/forge-commit` | Terse conventional commit from staged changes |
| Compression reference | `/forge-compress help` | Quick reference card for all compression features |
| Find the right skill | `/forge-help` | Interactive decision tree |
| New user onboarding | `/forge-tour` | 5-stop guided introduction |
| Edit config settings | `/forge-config` | Interactive config editor |

### Getting started flows

```
First time?        /forge-tour (5-stop guided introduction)
New project:       /forge-init → /forge-config-validate → /forge-verify → /forge-run <requirement>
Existing project:  /forge-init → /forge-codebase-health → /forge-deep-health → /forge-run <requirement>
Bug fix:           /forge-fix <description or ticket ID>
Code quality:      /forge-review --full  (changed files) or /forge-codebase-health (all files)
Before shipping:   /forge-verify → /forge-review --full
Pipeline trouble:  /forge-recover diagnose → /forge-recover repair (if needed) → /forge-recover resume
Multiple features: /forge-sprint (reads from Linear or manual list)
Quick decision:    /forge-help (interactive skill picker)
```

## Agents (42 total, `agents/*.md`)

**Pipeline** (`fg-{NNN}-{role}`):
- Pre-pipeline: `fg-010-shaper`, `fg-015-scope-decomposer`, `fg-020-bug-investigator`, `fg-050-project-bootstrapper`
- Sprint: `fg-090-sprint-orchestrator`
- Core: `fg-100-orchestrator` (coordinator, never writes code), helpers: `fg-101-worktree-manager`, `fg-102-conflict-resolver`, `fg-103-cross-repo-coordinator`
- Preflight: `fg-130-docs-discoverer`, `fg-135-wiki-generator`, `fg-140-deprecation-refresh`, `fg-150-test-bootstrapper`, `fg-160-migration-planner`
- Plan/Validate: `fg-200-planner`, `fg-205-planning-critic`, `fg-210-validator`, `fg-250-contract-validator`
- Implement: `fg-300-implementer` (TDD + inner-loop lint/test validation per task), `fg-310-scaffolder`, `fg-320-frontend-polisher` (conditional on `frontend_polish.enabled`)
- Docs: `fg-350-docs-generator`
- Verify/Review: `fg-400-quality-gate`, `fg-505-build-verifier`, `fg-500-test-gate`, `fg-510-mutation-analyzer`, `fg-515-property-test-generator` (conditional on `property_testing.enabled`)
- Ship: `fg-590-pre-ship-verifier`, `fg-600-pr-builder`, `fg-620-deploy-verifier` (conditional on deployment strategy), `fg-650-preview-validator`, `fg-610-infra-deploy-verifier` (conditional on k8s/infra)
- Learn: `fg-700-retrospective`, `fg-710-post-run`

**Review** (8, via quality gate): `fg-410-code-reviewer`, `fg-411-security-reviewer`, `fg-412-architecture-reviewer`, `fg-413-frontend-reviewer` (supports modes: full/conventions-only/a11y-only/performance-only), `fg-416-performance-reviewer`, `fg-417-dependency-reviewer`, `fg-418-docs-consistency-reviewer`, `fg-419-infra-deploy-reviewer`. Quality gate scales reviewer count by change scope: <50 lines = batch 1 only, 50-500 = all batches, >500 = all batches + splitting note.

### Agent rules

- **Frontmatter required:** `name` (must match filename sans `.md`), `description`, `tools`. Dispatch agents must include `Agent`.
- **UI:** `AskUserQuestion` for multi-option choices (never `Options: (1)...`). `EnterPlanMode`/`ExitPlanMode` for planning (skip in autonomous/replanning). `TaskCreate`/`TaskUpdate` wraps every dispatch. Substage tasks created per stage with agent color dots (🟢🔴🔵🟡🟣 etc.) for visual agent identification. Three-level nesting: stage → substage → leaf.
- **UI tiers:** Tier 1 (tasks+ask+plan_mode): shaper, scope-decomposer, planner, migration planner, bootstrapper, sprint orchestrator. Tier 2 (tasks+ask): orchestrator, bug investigator, quality gate, test gate, PR builder, cross-repo coordinator, post-run, validator (fg-210, GO/REVISE/NO-GO across 7 perspectives). Tier 3 (tasks): implementer, frontend polisher, retrospective, docs discoverer, deprecation refresh, preview validator, pre-ship verifier, infra verifier, scaffolder, docs generator, contract validator, test bootstrapper, build-verifier, property-test-generator, deploy-verifier. Tier 4 (none): all reviewers (fg-410 through fg-419), mutation analyzer, planning-critic (fg-205, silent adversarial plan reviewer), worktree manager, conflict resolver. Every agent's `ui:` frontmatter must be explicit — implicit Tier-4-by-omission is no longer accepted.
- **`ui:` frontmatter** declares capabilities; enforced by `ui-frontmatter-consistency.bats`.
- **Config:** `components:` in `forge.local.md` — core: `language:`, `framework:`, `variant:`, `testing:`. Framework-specific: `web`, `persistence` (distinct from crosscutting `modules/persistence/`). Optional crosscutting: `database`, `migrations`, `api_protocol`, `messaging`, `caching`, `search`, `storage`, `auth`, `observability`, `build_system`, `ci`, `container`, `orchestrator`, `documentation`, `code_quality` (list type, supports object form with external ruleset), `ml_ops`, `data_pipeline`, `feature_flags`. Multi-service: entries with `path:`. Documentation config: `documentation:` section controls generation.
- **`mode_config:`** defines per-stage agent selection and mode overlays. Resolution: overlay > stage default > hardcoded fallback.
- **Worktree:** All impl in `.forge/worktree`. User's tree never modified. Branch collision → epoch suffix.
- **Challenge Brief required** in every plan. Validator returns REVISE if missing.
- **APPROACH-*/DOC-* findings:** APPROACH scored as INFO (-2), escalated at 3+ recurrences. DOC ranges CRITICAL→WARNING→INFO.
- **Token management:** Agent `.md` = subagent system prompt (every line = tokens). Constraints compressed with reference to `shared/agent-defaults.md`. Output format references `shared/checks/output-format.md`. Convention stack soft cap: 12 files/component. Module overviews max 15 lines. Output compression (`shared/output-compression.md`) sets per-stage verbosity levels to reduce output tokens.
- **Description tiering:** Tier 1 (entry, 6): description + example. Tier 2 (reviewers, 9): single-line. Tier 3 (internal, 22): minimal. Full capability in `.md` body.

See `shared/agent-role-hierarchy.md` for the complete dispatch graph and tier definitions.

### Routing & decomposition

- `/forge-run` auto-classifies intent and routes. Requirements <50 words missing 3+ of (actors, entities, surface, criteria) → shaper. Prefixes (`bugfix:`, `migrate:`, `bootstrap:`) and flags (`--sprint` (deprecated, use `/forge-sprint`), `--parallel`) override. Config: `routing.*`, `scope.*` in `forge-config.md`.
- Multi-feature detected via fast scan (text) or deep scan (post-EXPLORE). Triggers `fg-015-scope-decomposer` → `fg-090-sprint-orchestrator`.
- Frontend design preview via superpowers visual companion during PLAN (optional, graceful degradation).
- Additional `forge-config.md` sections: `model_routing:` (tiered model selection), `explore:` (explore cache settings), `plan_cache:` (plan reuse settings).

## Core contracts

### Scoring (`scoring.md`)

Formula: `max(0, 100 - 20×CRITICAL - 5×WARNING - 2×INFO)`. PASS ≥80, CONCERNS 60-79, FAIL <60 or unresolved CRITICAL. 87 shared categories (27 wildcard prefixes + 60 discrete) in `shared/checks/category-registry.json`. Key wildcards: `ARCH-*`, `SEC-*`, `PERF-*`, `TEST-*`, `CONV-*`, `DOC-*`, `QUAL-*`, `SCOUT-*`, `A11Y-*`, `DEP-*`, `INFRA-*`, `AI-LOGIC-*`, `AI-PERF-*`, `AI-CONCURRENCY-*`, `AI-SEC-*`. Dedup key: `(component, file, line, category)`. SCOUT-* excluded from score (two-point filtering). 5 convergence counters: `verify_fix_count`, `test_cycles`, `quality_cycles` (inner-loop); `phase_iterations` (per-phase, resets); `total_iterations` (cumulative). Separate: `implementer_fix_cycles` (inner-loop, does NOT feed into convergence counters or `total_retries`). Timed-out reviewers: INFO → WARNING. 7 validation perspectives.

### State, recovery & errors

- **State** (`state-schema.md`): v1.6.0. `.forge/` (gitignored). Checkpoints per task. Key fields: `mode` (standard/migration/bootstrap/bugfix), `feedback_loop_count` (escalates at 2), `recovery`, `ticket_id`, `branch_name`, `graph`, `critic_revisions`. Concurrent run lock: `.forge/.lock` (PID + 24h stale timeout).
- **Recovery** (`recovery/`): 7 strategies, budget ceiling 5.5. Highest-severity first. Global retry budget: `total_retries` (default max 10, configurable).
- **Errors** (`error-taxonomy.md`): 22 types, 16-level severity. MCP failures → inline skip + INFO. 3 consecutive transients in 60s → non-recoverable. `BUILD`/`TEST`/`LINT_FAILURE` → orchestrator fix loop.
- **Communication:** Inter-stage via orchestrator stage notes. Quality gate includes previous batch findings (top 20). PREEMPT tracking via `PREEMPT_APPLIED`/`PREEMPT_SKIPPED`.

### Stage contracts & shipping

States: PREFLIGHT → EXPLORING → PLANNING → VALIDATING → IMPLEMENTING → VERIFYING → REVIEWING → DOCUMENTING → SHIPPING → LEARNING. Migration: MIGRATING/PAUSED/CLEANUP/VERIFY. PR rejection → Stage 4 (impl) or Stage 2 (design) via `fg-710-post-run`.

**Evidence-based shipping:** `fg-590-pre-ship-verifier` runs fresh build+test+lint+review → `.forge/evidence.json`. PR builder refuses without `verdict: SHIP`. No "continue anyway" — fix, retry, or abort.

### Supporting systems

Core systems: version detection (PREFLIGHT → `state.json.detected_versions`), convention drift (SHA256 hash comparison), learnings (`learnings/` per-module files), frontend design (`frontend-design-theory.md`), model routing (fast/standard/premium tiers, config: `model_routing.*`), explore cache (`.forge/explore-cache.json`, survives reset), plan cache (`.forge/plan-cache/`, survives reset), context isolation (domain-scoped dedup via `affinity`), token reporting (`state.json.tokens` with cost breakdowns), mutation testing (`fg-510-mutation-analyzer`, config: `mutation_testing.*`), reviewer deliberation (config: `quality_gate.deliberation`), run history store (`.forge/run-history.db`, SQLite FTS5, config: `run_history.*`).

Confidence scoring: two-level — (1) finding confidence (HIGH=1.0x, MEDIUM=0.75x, LOW=0.5x weight multipliers); (2) pipeline confidence (4-dimension: clarity 0.30, familiarity 0.25, complexity 0.20, history 0.25). Gate: HIGH (>=0.7) proceeds, MEDIUM (>=0.4) asks, LOW (<0.4) → `/forge-shape`. Adaptive trust in `.forge/trust.json`. Config: `confidence.*`.

v2.0 features (each has dedicated doc in `shared/`):

| Feature | Config | Key details |
|---|---|---|
| Active knowledge base (F09) | `active_knowledge.*` | Rules auto-promote MEDIUM→HIGH after repeated success |
| Enhanced security (F10) | `security.*` | Supply chain audit, license compliance, runtime policy |
| Living specifications (F05) | `living_specs.*` | Drift detection, `AC-NNN` criteria, spec registry `.forge/specs/index.json` |
| Event-sourced log (F07) | `events.*` | `.forge/events.jsonl`, causal linking |
| Context condensation (F08) | `condensation.*` | Auto-compress completed stage outputs |
| Playbooks (F11) | `playbooks.*` | `.forge/playbooks/` YAML, analytics in `.forge/playbook-analytics.json` |
| Spec inference (F12) | `spec_inference.*` | Function-level specs from bug investigation, categories: `SPEC-INFERENCE-*` |
| Property-based testing (F13) | `property_testing.*` | `fg-515`, categories: `TEST-PROPERTY-*` |
| Flaky test management (F14) | `flaky_tests.*` | Auto-quarantine, excluded from gating |
| Dynamic accessibility (F15) | `accessibility.*` | Playwright tab-order/focus/ARIA, cross-browser |
| i18n validation (F16) | `i18n.*` | Hardcoded strings, RTL, locale. Categories: `I18N-*` |
| Performance regression (F17) | `performance_tracking.*` | `.forge/benchmarks.json`, categories: `PERF-REGRESSION-*` |
| Next-task prediction (F18) | `predictions.*` | 19 pattern rules, `.forge/predictions.json` |
| DX metrics (F19) | `dx_metrics.*` | 10 metrics in `.forge/dx-metrics.json` |
| Monorepo tooling (F20) | `monorepo.*` | Nx/Turborepo affected detection |
| A2A HTTP transport (F21) | `a2a.*` | HTTP + filesystem fallback, token/mTLS auth |
| AI/ML pipelines (F22) | `ml_ops.*` | Categories: `ML-VERSION-*`, `ML-REPRO-*`, `ML-DATA-*`, `ML-PIPELINE-*` |
| Feature flags (F23) | `feature_flags.*` | Categories: `FLAG-STALE`, `FLAG-UNTESTED`, `FLAG-HARDCODED`, `FLAG-CLEANUP` |
| Deployment strategies (F24) | `deployment.*` | Canary/blue-green/rolling, `fg-620-deploy-verifier`, Argo Rollouts |
| Consumer-driven contracts (F25) | `contract_testing.*` | Pact, can-i-deploy gate. Categories: `CONTRACT-PACT-*` |
| Output compression (F26) | `output_compression.*` | 4 levels (verbose/standard/terse/minimal), 20-65% reduction |
| AI quality (F27) | `ai_quality.*` | L1 regex + reviewer guidance for AI-generated bug patterns. Categories: `AI-LOGIC-*`, `AI-PERF-*`, `AI-CONCURRENCY-*`, `AI-SEC-*` |
| Wiki generator | `wiki.*` | `.forge/wiki/`, survives reset |
| Memory discovery | `memory_discovery.*` | Auto-discovered items decay 2x faster, start MEDIUM |
| Background execution | — | `--background`, `.forge/alerts.json` for escalations |
| Automations | `automations.*` | Cron/CI/MCP triggers via `automation-trigger.sh` |
| Visual verification | `visual_verification.*` | Screenshot-based via Playwright MCP |
| LSP integration | `lsp.*` | Compiler-level code analysis |
| Observability | `observability.*` | OTel traces via `forge-otel-export.sh` |
| Data classification | `data_classification.*` | Secret detection and redaction |
| Security posture | — | OWASP ASI01-ASI10 compliance |
| A2A protocol | — | Local filesystem coordination (`.forge/agent-card.json`) |
| Pipeline timeline | — | Per-stage timing via `/forge-insights` |
| Codebase Q&A | `forge_ask.*` | Wiki + graph + explore cache queries |
| Caveman I/O (S01) | `caveman.*` | Input compression + user-facing output modes (lite/full/ultra) |
| Cross-project learnings (F28) | `cross_project.*` | Shared learnings across repos via `shared/cross-project-learnings.md` |
| Run history store (F29) | `run_history.*` | SQLite FTS5 at `.forge/run-history.db`. Written by retrospective, queried by insights/ask/MCP. Schema in `shared/run-history/` |
| MCP server (F30) | `mcp_server.*` | Python stdio MCP server exposing pipeline intelligence to any AI client. 11 tools. Auto-provisioned by `/forge-init` into `.mcp.json` |
| Self-improving playbooks (F31) | `playbooks.*` | Refinement proposals from run data. Auto-apply, rollback. `.forge/playbook-refinements/`. Skill: `/forge-playbook-refine` |

### Deterministic Control Flow

Pipeline control flow follows the formal transition table in `shared/state-transitions.md`. LLM judgment for review/implementation/architecture — NOT state transitions. Decisions logged to `.forge/decisions.jsonl`. Recovery uses circuit breakers. Reviewer conflicts resolved by priority ordering in `shared/agent-communication.md` §3.1.

### Shared scripts (`shared/`)

| Script | Purpose |
|---|---|
| `forge-state.sh` | Executable state machine (57+ transitions) |
| `forge-state-write.sh` | Atomic JSON writes with WAL and `_seq` versioning |
| `forge-token-tracker.sh` | Token budget tracking and ceiling enforcement |
| `forge-linear-sync.sh` | Event-driven Linear sync (audit layer) |
| `forge-sim.sh` | Pipeline simulation harness |
| `forge-timeout.sh` | Pipeline timeout enforcement |
| `forge-compact-check.sh` | Compaction suggestion hook |
| `check-prerequisites.sh` | bash 4+ and python3 validation |
| `check-environment.sh` | Optional tool + integration detection for forge-init |
| `forge-otel-export.sh` | OpenTelemetry trace and metric export |
| `caveman-benchmark.sh` | Token savings measurement for caveman modes |
| `hooks/automation-trigger.sh` | Event-driven automation dispatch (cron, CI, MCP) |

### Mode overlays (`shared/modes/`)

7 pipeline mode overlays: `standard`, `bugfix`, `migration`, `bootstrap`, `testing`, `refactor`, `performance`. Loaded by orchestrator at PREFLIGHT based on `state.mode`.

## Integrations

- **Linear** (optional): Epic/Stories/Tasks at PLAN, status per stage. Disabled by default. MCP failures → graceful degradation (no recovery engine).
- **MCP detection:** Detects Linear, Playwright, Slack, Context7, Figma, Excalidraw, Neo4j. First failure → degraded for run. No MCP required.
- **Cross-repo:** 5-step discovery at `/forge-init`. Contract validation, linked PRs, multi-repo worktrees. Timeout: 30min (configurable). Alphabetical lock ordering. PR failures don't block main PR. Discovery results stored with `detected_via`.

## Knowledge graph

Neo4j dual-purpose: (1) plugin module graph (seed), (2) project codebase graph. Docker-managed, disable with `graph.enabled: false`. Scoped by `project_id` + optional `component`. 8 agents with `neo4j-mcp`: fg-010/020/090/100/102/200/210/400. Pipeline works without Neo4j.

**SQLite code graph** (zero-dependency alternative): Tree-sitter + SQLite at `.forge/code-graph.db`. Built by `shared/graph/build-code-graph.sh`. 15 node types, 17 edge types, all 15 languages. Config: `code_graph.enabled` (default true), `code_graph.backend` (auto/sqlite/neo4j), `code_graph.exclude_patterns`. Survives `/forge-recover reset`.

## Check engine (`shared/checks/`)

4 layers on `Edit`/`Write` operations:
- **L0** (tree-sitter AST, pre-edit via PreToolUse hook): blocks syntactically invalid edits. Config: `check_engine.l0_enabled`, `check_engine.l0_languages`, `check_engine.l0_timeout_ms`.
- **L1** (regex, sub-second, PostToolUse hook): design tokens, animation perf. **L2** (linter adapters). **L3** (AI-driven): deprecation refresh + version compat, version-gated.
- `rules-override.json` extends defaults; `"disabled": true` to suppress. Skip tracking in `.forge/.check-engine-skipped`. `learned-rules-override.json` loaded at L1 (auto-promoted from retrospective, see `shared/learnings/rule-promotion.md`).

**Deprecation registries** (`modules/frameworks/*/known-deprecations.json`): Schema v2 (`pattern`, `replacement`, `package`, `since`, `removed_in`, `applies_from`, `applies_to`, `added`, `addedBy`). Skip when project version < `applies_from`. WARNING if deprecated, CRITICAL if `removed_in` reached.

## Infra testing (`fg-610-infra-deploy-verifier`)

5 tiers: T1 (<10s, static lint), T2 (<60s, container build+trivy), T3 (<5min, ephemeral cluster — **default**), T4 (<5min, contract stubs), T5 (<15min, full integration). Config: `infra.max_verification_tier` (1-5). Findings: `INFRA-HEALTH` (CRITICAL), `INFRA-SMOKE` (WARNING), `INFRA-CONTRACT`/`INFRA-E2E` (CRITICAL), `INFRA-IMAGE` (WARNING/CRITICAL).

## Skills (35 total), hooks, kanban, git

**Skills:** `forge-run` (main entry), `forge-fix`, `forge-init`, `forge-status`, `forge-recover` (diagnose/repair/reset/resume/rollback dispatch), `forge-history`, `forge-shape`, `forge-sprint`, `forge-review` (quick: 3 agents, full: up to 9; loops to score 100), `forge-verify`, `forge-security-audit`, `forge-codebase-health`, `forge-deep-health`, `forge-migration`, `forge-bootstrap`, `forge-deploy`, `forge-graph-init`, `forge-graph-status`, `forge-graph-query`, `forge-graph-rebuild`, `forge-graph-debug` (targeted Neo4j diagnostics), `forge-docs-generate`, `forge-config-validate` (pre-pipeline config check), `forge-abort` (graceful pipeline stop), `forge-profile` (pipeline performance analysis), `forge-automation` (event-driven automation management), `forge-ask` (codebase knowledge query), `forge-insights` (pipeline run analytics), `forge-playbooks` (reusable pipeline recipe management), `forge-compress` (agents/output/status/help dispatch), `forge-help` (interactive skill decision tree), `forge-tour` (5-stop guided onboarding), `forge-config` (interactive config editor with validation), `forge-commit` (terse conventional commit generator), `forge-playbook-refine` (interactive playbook refinement review).

**Hooks** (7): L0 syntax validation on `Edit|Write` (PreToolUse), check engine on `Edit|Write` (PostToolUse), automation-trigger on `Edit|Write` (PostToolUse), checkpoint on `Skill`, feedback capture on `Stop`, compaction check on `Agent`, session-start on `SessionStart`. See `shared/hook-design.md` for execution model and script contract.

**Kanban** (`.forge/tracking/`): File-based board (`backlog/`, `in-progress/`, `review/`, `done/`). Prefix configurable (default `FG`). IDs never reused. Silently skips if uninitialized.

**Git:** Branch `{type}/{ticket}-{slug}` (configurable). Conventional Commits or `project` (auto-detected). **Never:** `Co-Authored-By`, AI attribution, `--no-verify`.

**Init:** `/forge-init` generates project-local plugin with hooks, skills, agents. Respects existing hooks. MCP auto-provisioning at init.

## Adding new modules

### New framework

Create `modules/frameworks/{name}/` with: `conventions.md` (with Dos/Don'ts), `local-template.md`, `forge-config-template.md` (must include `total_retries_max`, `oscillation_tolerance`), `rules-override.json`, `known-deprecations.json` (v2, 5-15 entries). Optional: `variants/`, `testing/`, `scripts/`, `hooks/`. Add `shared/learnings/{name}.md`. Bump `MIN_*` in `tests/lib/module-lists.bash`.

New language → also `modules/languages/{lang}.md` + learnings. New test framework → also `modules/testing/{name}.md` + learnings.

### New layer module

Create `modules/{layer}/{name}.md` (Overview, Architecture, Config, Performance, Security, Testing, Dos, Don'ts). Optional: `.rules-override.json`, `.known-deprecations.json`. Add framework bindings and learnings file.

## Framework gotchas

See `shared/framework-gotchas.md` for non-obvious conventions per framework. Each framework's full conventions are in `modules/frameworks/{name}/conventions.md`.

## Validation

```bash
./tests/run-all.sh                  # Full (~30s)
./tests/run-all.sh structural       # 73+ checks
./tests/run-all.sh unit|contract|scenario
./tests/lib/bats-core/bin/bats tests/unit/scoring.bats  # Single file
```

## Gotchas

### Structural

- Agent `name` must match filename sans `.md`.
- Scripts need `#!/usr/bin/env bash` + `chmod +x`. Graph scripts, `run-linter.sh`, `engine.sh` require **bash 4.0+** (MacOS needs `brew install bash`). All scripts use `_glob_exists()` instead of `compgen -G`.
- `shared/` files are contracts — changes affect all agents/modules. Verify downstream impact.
- Plugin never touches consuming project files. Runtime state → `.forge/`.
- `forge-config.md` auto-tuned by retrospective. Use `<!-- locked -->` fences to protect.
- `.forge/` deletion mid-run = unrecoverable. Use `/forge-recover reset`.
- `explore-cache.json`, `plan-cache/`, `code-graph.db`, `trust.json`, `events.jsonl`, `playbook-analytics.json`, `run-history.db`, and `playbook-refinements/` survive `/forge-recover reset`. Only manual `rm -rf .forge/` removes them.
- `model_routing.enabled` defaults to `true`. Set `enabled: false` in `forge-config.md` to opt out.
- Automation cooldowns prevent trigger loops (minimum interval between identical triggers). Config: `automations.cooldown_seconds` (default 300).
- Background runs write escalations to `.forge/alerts.json` instead of interactive prompts.
- A2A protocol uses local filesystem coordination (`.forge/agent-card.json`), not HTTP. Requires shared filesystem access between repos.
- `.forge/wiki/` survives `/forge-recover reset`. Only manual `rm -rf .forge/` removes it. Wiki is regenerated at PREFLIGHT when `wiki.auto_update` is enabled.
- Auto-discovered PREEMPT items (`source: auto-discovered`) decay 2x faster than normal items. They start at MEDIUM confidence, not HIGH. After 3 successful applications they promote to HIGH.
- **Platform requirements:** Forge requires bash 4.0+ (macOS needs `brew install bash`). PowerShell and CMD are not supported — on Windows, use WSL2 (recommended) or Git Bash (limited). All scripts use `#!/usr/bin/env bash`. Git Bash has known MSYS path translation issues (commit `0ac4874`). Docker features require Docker Desktop with WSL2 backend on Windows.

### Check engine

- Broken `engine.sh` → all edits error. Timeout → skip counter + edit succeeds. Hook scripts validated at install.
- `rules-override.json` extends (not replaces). YAML parsing expects 2-space indent (non-standard → WARNING + fallback).
- Deprecation v1 entries (no `applies_from`) apply universally. Unknown versions → all rules apply.

### PREFLIGHT constraints

See `shared/preflight-constraints.md` for all PREFLIGHT validation rules (scoring thresholds, convergence limits, sprint config, shipping gates, model routing, implementer inner loop, confidence, output compression, AI quality, build graph, cost alerting, eval, context guard, compression eval).

### Pipeline modes

- **Greenfield:** `/forge-init` detects empty projects → Bootstrap/Select stack/Skip.
- **Bootstrap:** Stage 4 skipped. Reduced validation + review. Target = `pass_threshold`.
- **Bugfix:** `fg-020-bug-investigator` → reproduction (max 3) → 4-perspective validation → reduced reviewers. Patterns in `.forge/forge-log.md`.
- **Migration:** All 10 stages. `fg-160-migration-planner` at Stage 2. Stage 4 cycles through MIGRATING, MIGRATION_PAUSED, MIGRATION_CLEANUP, MIGRATION_VERIFY.
- **Dry-run:** PREFLIGHT→VALIDATE only. No worktree/Linear/lock/checkpoints.
- **Autonomous:** `autonomous: true` → auto-selection (logged `[AUTO]`). Never pauses except safety escalations (REGRESSING, E1-E4, unrecoverable CRITICAL).
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
- **Implementer inner loop:** After each TDD cycle, `fg-300-implementer` runs lint on changed files + affected tests (capped at 20 files). Fix cycles tracked as `implementer_fix_cycles` (separate from convergence counters). Disabled via `implementer.inner_loop.enabled: false`.

## Distribution

`plugin.json` (v2.8.0), `marketplace.json`. Hooks in `hooks/hooks.json` only. Install: `/plugin marketplace add quantumbitcz/forge` → `/plugin install forge@quantumbitcz`.

## Governance

`LICENSE` (Proprietary, QuantumBit s.r.o.), `CONTRIBUTING.md`, `SECURITY.md`, `.github/CODEOWNERS` (@quantumbitcz), `.github/release.yml`.
