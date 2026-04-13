# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`forge` is a Claude Code plugin (v2.2.0, `quantumbitcz` marketplace / Git submodule). 10-stage autonomous pipeline: Preflight → Explore → Plan → Validate → Implement (TDD) → Verify → Review → Docs → Ship → Learn. Entry: `/forge-run` → `fg-100-orchestrator`.

## Architecture

Layered, resolution top-down:

1. **Project config** (`.claude/forge.local.md`, `.claude/forge-config.md`, `.claude/forge-log.md`) — per-project settings in consuming repo.
2. **Module layer** (`modules/`):
   - `languages/` (15): kotlin, java, typescript, python, go, rust, swift, c, csharp, ruby, php, dart, elixir, scala, cpp
   - `frameworks/` (21): spring, react, fastapi, axum, swiftui, vapor, express, sveltekit, k8s, embedded, go-stdlib, aspnet, django, nextjs, gin, jetpack-compose, kotlin-multiplatform, angular, nestjs, vue, svelte — each with `conventions.md`, config files, `variants/`, and subdirectory bindings (`testing/`, `persistence/`, `messaging/`, etc.)
   - `testing/` (19): kotest, junit5, vitest, jest, pytest, go-testing, xctest, rust-test, xunit-nunit, testcontainers, playwright, cypress, cucumber, k6, detox, rspec, phpunit, exunit, scalatest
   - `databases/`, `persistence/`, `migrations/`, `api-protocols/`, `messaging/`, `caching/`, `search/`, `storage/`, `auth/`, `observability/` — domain-specific best practices
   - `ml-ops/` (4): mlflow, dvc, wandb, sagemaker — ML experiment tracking, model registry, data version control
   - `data-pipelines/` (3): airflow, dagster, dbt — data orchestration and transformation
   - `feature-flags/` (3): conventions + launchdarkly, unleash — feature flag lifecycle and provider patterns
   - `build-systems/` (9), `ci-cd/` (7), `container-orchestration/` (11) — tooling patterns
   - `documentation/` — doc conventions. `code-quality/` — ~70 tool files (linters, formatters, coverage, doc generators, security scanners, mutation testing)
   - **Composition order** (most specific wins): variant > framework-binding > framework > language > code-quality > generic-layer > testing. The composition algorithm is documented in `shared/composition.md`. When convention stacks are resolved at PREFLIGHT, files are loaded in this order with later files overriding earlier ones for conflicting rules.
3. **Shared core** (`agents/`, `shared/`, `hooks/`, `skills/`) — 42 agents, check engine, recovery, scoring, discovery, knowledge graph, frontend design theory.

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
| Graph (Neo4j) | `shared/graph/schema.md` |
| Graph (SQLite) | `shared/graph/code-graph-schema.sql` |
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
| Agent registry | `shared/agent-registry.md` |
| MCP detection | `shared/mcp-detection.md` |
| Learnings | `shared/learnings/README.md` |
| Memory discovery | `shared/learnings/memory-discovery.md` |
| Checkpoints | `shared/state-schema.md` §checkpoint-{storyId}.json |
| Model routing | `shared/model-routing.md` |
| Explore cache | `shared/explore-cache.md` |
| Plan cache | `shared/plan-cache.md` |
| Visual verification | `shared/visual-verification.md` |
| LSP integration | `shared/lsp-integration.md` |
| Observability | `shared/observability.md` |
| Data classification | `shared/data-classification.md` |
| Security posture | `shared/security-posture.md` |
| Automations | `shared/automations.md` |
| Background execution | `shared/background-execution.md` |
| A2A protocol | `shared/a2a-protocol.md` |
| Confidence scoring | `shared/confidence-scoring.md` |
| Composition order | `shared/composition.md` |
| Living specifications | `shared/living-specifications.md` |
| Spec inference | `shared/spec-inference.md` |
| Accessibility automation | `shared/accessibility-automation.md` |
| i18n validation | `shared/i18n-validation.md` |
| Performance regression | `shared/performance-regression.md` |
| Next-task prediction | `shared/next-task-prediction.md` |
| DX metrics | `shared/dx-metrics.md` |
| Monorepo integration | `shared/monorepo-integration.md` |
| Feature flag management | `shared/feature-flag-management.md` |
| A2A HTTP transport | `shared/a2a-http-transport.md` |
| Deployment strategies | `shared/deployment-strategies.md` |
| Consumer-driven contracts | `shared/consumer-driven-contracts.md` |
| Output compression | `shared/output-compression.md` |

## Skill selection guide

| Intent | Skill | Notes |
|---|---|---|
| Build a feature | `/forge-run` | Full 10-stage pipeline |
| Fix a bug | `/forge-fix` | Root cause investigation + targeted fix |
| Shape a vague idea | `/forge-shape` | Collaborative spec refinement |
| Review changed files | `/forge-review` | Quick (3 agents) or full (9 agents) |
| Review entire codebase | `/codebase-health` | Read-only analysis, no fixes |
| Fix all codebase issues | `/deep-health` | Iterative fix loop until clean |
| Quick build+lint+test | `/verify` | No pipeline, just check commands |
| Security scan | `/security-audit` | Module-appropriate vulnerability scanners |
| Pipeline broken? | `/forge-diagnose` | Read-only diagnostic, then `/repair-state` to fix |
| Resume aborted run | `/forge-resume` | Continues from last checkpoint |
| Start fresh | `/forge-reset` | Clears state, preserves learnings |
| Multiple features | `/forge-sprint` | Parallel orchestration |
| Generate docs | `/docs-generate` | README, ADRs, API specs, changelogs |
| Deploy | `/deploy` | Staging, production, preview, rollback |
| Migrate framework | `/migration` | Library/framework version upgrades |
| Ask about codebase | `/forge-ask` | Wiki, graph, explore cache, docs index |
| Pipeline analytics | `/forge-insights` | Quality, cost, convergence, memory trends |
| Reusable recipes | `/forge-playbooks` | Create, list, run, analyze pipeline playbooks |

### Getting started flows

```
New project:       /forge-init → /config-validate → /verify → /forge-run <requirement>
Existing project:  /forge-init → /codebase-health → /deep-health → /forge-run <requirement>
Bug fix:           /forge-fix <description or ticket ID>
Code quality:      /forge-review --full  (changed files) or /codebase-health (all files)
Before shipping:   /verify → /forge-review --full
Pipeline trouble:  /forge-diagnose → /repair-state (if needed) → /forge-resume
Multiple features: /forge-sprint (reads from Linear or manual list)
```

## Agents (41 total, `agents/*.md`)

**Pipeline** (`fg-{NNN}-{role}`):
- Pre-pipeline: `fg-010-shaper`, `fg-015-scope-decomposer`, `fg-020-bug-investigator`, `fg-050-project-bootstrapper`
- Sprint: `fg-090-sprint-orchestrator`
- Core: `fg-100-orchestrator` (coordinator, never writes code), helpers: `fg-101-worktree-manager`, `fg-102-conflict-resolver`, `fg-103-cross-repo-coordinator`
- Preflight: `fg-130-docs-discoverer`, `fg-135-wiki-generator`, `fg-140-deprecation-refresh`, `fg-150-test-bootstrapper`, `fg-160-migration-planner`
- Plan/Validate: `fg-200-planner`, `fg-210-validator`, `fg-250-contract-validator`
- Implement: `fg-300-implementer` (TDD + inner-loop lint/test validation per task), `fg-310-scaffolder`, `fg-320-frontend-polisher` (conditional on `frontend_polish.enabled`)
- Docs: `fg-350-docs-generator`
- Verify/Review: `fg-400-quality-gate`, `fg-505-build-verifier`, `fg-500-test-gate`, `fg-510-mutation-analyzer`, `fg-515-property-test-generator` (conditional on `property_testing.enabled`)
- Ship: `fg-590-pre-ship-verifier`, `fg-600-pr-builder`, `fg-620-deploy-verifier` (conditional on deployment strategy), `fg-650-preview-validator`, `fg-610-infra-deploy-verifier` (conditional on k8s/infra)
- Learn: `fg-700-retrospective`, `fg-710-post-run`

**Review** (9, via quality gate): `fg-410-code-reviewer`, `fg-411-security-reviewer`, `fg-412-architecture-reviewer`, `fg-413-frontend-reviewer` (supports modes: full/conventions-only/a11y-only/performance-only), `fg-416-backend-performance-reviewer`, `fg-417-version-compat-reviewer`, `fg-418-docs-consistency-reviewer`, `fg-419-infra-deploy-reviewer`, `fg-420-dependency-reviewer`.

### Agent rules

- **Frontmatter required:** `name` (must match filename sans `.md`), `description`, `tools`. Dispatch agents must include `Agent`.
- **UI:** `AskUserQuestion` for multi-option choices (never `Options: (1)...`). `EnterPlanMode`/`ExitPlanMode` for planning (skip in autonomous/replanning). `TaskCreate`/`TaskUpdate` wraps every dispatch.
- **UI tiers:** Tier 1 (tasks+ask+plan): shaper, scope-decomposer, planner, migration planner, bootstrapper, sprint orchestrator. Tier 2 (tasks+ask): orchestrator, bug investigator, quality gate, test gate, PR builder, cross-repo coordinator, post-run. Tier 3 (tasks): implementer, frontend polisher, retrospective, docs discoverer, deprecation refresh, preview validator, pre-ship verifier, infra verifier, scaffolder, docs generator, contract validator, test bootstrapper, build-verifier, property-test-generator, deploy-verifier. Tier 4 (none): all reviewers (fg-410 through fg-420), mutation analyzer, validator, worktree manager, conflict resolver.
- **`ui:` frontmatter** declares capabilities; enforced by `ui-frontmatter-consistency.bats`.
- **Config:** `components:` in `forge.local.md` — core: `language:`, `framework:`, `variant:`, `testing:`. Framework-specific: `web`, `persistence` (distinct from crosscutting `modules/persistence/`). Optional crosscutting: `database`, `migrations`, `api_protocol`, `messaging`, `caching`, `search`, `storage`, `auth`, `observability`, `build_system`, `ci`, `container`, `orchestrator`, `documentation`, `code_quality` (list type, supports object form with external ruleset), `ml_ops`, `data_pipeline`, `feature_flags`. Multi-service: entries with `path:`. Documentation config: `documentation:` section controls generation.
- **`mode_config:`** defines per-stage agent selection and mode overlays. `mode_config.stages` maps each pipeline stage to its default agent. `mode_config.mode_overlays` overrides specific stages per pipeline mode (bugfix, migration, bootstrap). Resolution: overlay > stage default > hardcoded fallback.
- **Worktree:** All impl in `.forge/worktree`. User's tree never modified. Branch collision → epoch suffix.
- **Challenge Brief required** in every plan. Validator returns REVISE if missing.
- **APPROACH-*/DOC-* findings:** APPROACH scored as INFO (-2), escalated at 3+ recurrences. DOC ranges CRITICAL→WARNING→INFO.
- **Token management:** Agent `.md` = subagent system prompt (every line = tokens). Constraints compressed with reference to `shared/agent-defaults.md`. Output format references `shared/checks/output-format.md`. Convention stack soft cap: 12 files/component. Module overviews max 15 lines. Output compression (`shared/output-compression.md`) sets per-stage verbosity levels to reduce output tokens.
- **Description tiering:** Tier 1 (entry, 6): description + example. Tier 2 (reviewers, 9): single-line. Tier 3 (internal, 22): minimal. Full capability in `.md` body.

### Routing & decomposition

- `/forge-run` auto-classifies intent and routes. Requirements <50 words missing 3+ of (actors, entities, surface, criteria) → shaper. Prefixes (`bugfix:`, `migrate:`, `bootstrap:`) and flags (`--sprint`, `--parallel`) override. Config: `routing.*`, `scope.*` in `forge-config.md`.
- Multi-feature detected via fast scan (text) or deep scan (post-EXPLORE). Triggers `fg-015-scope-decomposer` → `fg-090-sprint-orchestrator`.
- Frontend design preview via superpowers visual companion during PLAN (optional, graceful degradation).
- Additional `forge-config.md` sections: `model_routing:` (tiered model selection), `explore:` (explore cache settings), `plan_cache:` (plan reuse settings).

## Core contracts

### Scoring (`scoring.md`)

Formula: `max(0, 100 - 20×CRITICAL - 5×WARNING - 2×INFO)`. PASS ≥80, CONCERNS 60-79, FAIL <60 or unresolved CRITICAL. 83 shared categories (23 wildcard prefixes + 60 discrete). See `shared/checks/category-registry.json` for the full list. Key wildcards: `ARCH-*`, `SEC-*`, `PERF-*`, `TEST-*`, `CONV-*`, `DOC-*`, `QUAL-*`, `SCOUT-*`, `A11Y-*`, `DEP-*`, `INFRA-*`, `SPEC-DRIFT-*`, `PERF-REGRESSION-*`, `ML-VERSION-*`, `ML-REPRO-*`, `ML-DATA-*`, `ML-PIPELINE-*`. Key discrete: `REVIEW-GAP`, `DESIGN-TOKEN`, `DESIGN-MOTION`, `TEST-FLAKY`, `TEST-QUARANTINE`, `SEC-MCP-UNAUTHORIZED`, `SEC-CLOUD-CRED`, `SEC-CACHE-TAMPER`, `SPEC-INFERENCE-LOW`, `SPEC-INFERENCE-CONFLICT`, `TEST-PROPERTY-INVARIANT`, `TEST-PROPERTY-ROUNDTRIP`, `TEST-PROPERTY-IDEMPOTENT`, `TEST-PROPERTY-METAMORPHIC`, `TEST-PROPERTY-COMMUTATIVE`, `TEST-PROPERTY-MONOTONIC`, `FLAG-STALE`, `FLAG-UNTESTED`, `FLAG-HARDCODED`, `FLAG-CLEANUP`. Dedup key: `(component, file, line, category)`. SCOUT-* excluded from score (two-point filtering). 5 convergence counters: `verify_fix_count`, `test_cycles`, `quality_cycles` (inner-loop); `phase_iterations` (per-phase, resets); `total_iterations` (cumulative). Separate: `implementer_fix_cycles` (inner-loop quick verification within Stage 4, does NOT feed into convergence counters or `total_retries`). Timed-out reviewers: INFO → WARNING. 7 validation perspectives.

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
- **Model routing** (`model-routing.md`): Tiered model selection per agent (fast/standard/premium). Config: `model_routing.*` in `forge-config.md`. Enabled by default with curated tier assignments (9 fast, 17 standard, 14 premium).
- **Explore cache** (`explore-cache.md`): Incremental codebase indexing across runs. `.forge/explore-cache.json`. Survives `/forge-reset`.
- **Plan cache** (`plan-cache.md`): Keyword-based plan reuse for similar requirements. `.forge/plan-cache/`. Survives `/forge-reset`.
- **Context isolation**: Domain-scoped dedup hints via `affinity` field in `category-registry.json`. Each reviewer only sees findings from its domain.
- **Token reporting**: Extended `state.json.tokens` with per-stage/agent/model breakdowns and `cost.estimated_cost_usd`.
- **Mutation testing** (`fg-510-mutation-analyzer`): LLM-generated targeted mutants for changed code. Dispatched by test gate after tests pass. Config: `mutation_testing.*`.
- **Reviewer deliberation**: Conflicting reviewers debate findings before quality gate synthesis. Disabled by default. Config: `quality_gate.deliberation`.
- **Confidence scoring** (`confidence-scoring.md`): Two-level system: (1) finding confidence (HIGH/MEDIUM/LOW per finding) affects scoring weight — multipliers: HIGH=1.0x, MEDIUM=0.75x, LOW=0.5x, fractional deductions rounded to nearest integer, LOW findings excluded from fix cycles; (2) pipeline confidence — 4-dimension weighted algorithm (clarity 0.30, familiarity 0.25, complexity 0.20, history 0.25) computes overall confidence at PLAN. Gate: HIGH (>=0.7) proceeds, MEDIUM (>=0.4) asks confirmation, LOW (<0.4) suggests `/forge-shape`. Adaptive trust model in `.forge/trust.json` (per-developer, not committed). Zero token cost. Config: `confidence.*`.
- **Visual verification** (`visual-verification.md`): Screenshot-based UI verification via Playwright MCP. Config: `visual_verification.*`.
- **LSP integration** (`lsp-integration.md`): Compiler-level code analysis via Language Server Protocol. Config: `lsp.*`.
- **Observability** (`observability.md`): OTel traces and metrics for pipeline execution. Exported via `forge-otel-export.sh`. Config: `observability.*`.
- **Data classification** (`data-classification.md`): Secret detection and redaction in pipeline outputs. Prevents accidental credential leaks. Config: `data_classification.*`.
- **Security posture** (`security-posture.md`): OWASP Agentic Security (ASI01-ASI10) compliance checks. Validates tool use, prompt injection resistance, and privilege boundaries.
- **Event-driven automations** (`automations.md`): Cron-scheduled, CI-triggered, and MCP-initiated pipeline runs. Managed via `automation-trigger.sh`. Config: `automations.*`.
- **Background execution** (`background-execution.md`): `--background` flag for headless pipeline runs. Progress via `.forge/progress/` artifacts. Escalations written to `.forge/alerts.json`.
- **A2A protocol** (`a2a-protocol.md`): Agent-to-Agent cross-repo coordination via local filesystem (not HTTP). Enables multi-repo pipeline orchestration with shared state.
- **Wiki generator** (`fg-135-wiki-generator`): Auto-generates `.forge/wiki/` from codebase analysis at PREFLIGHT. Covers architecture, API surface, data model, module map. Survives `/forge-reset`. Config: `wiki.*`.
- **Memory discovery** (`shared/learnings/memory-discovery.md`): Retrospective auto-discovers codebase patterns across runs. Items start at MEDIUM confidence with `source: auto-discovered`, promote to HIGH after 3 successful applications, decay 2x faster than normal. Config: `memory_discovery.*`.
- **Pipeline timeline** (`fg-710-post-run`): Per-stage timing, cost breakdown, and convergence trends across runs. Accessible via `/forge-insights`.
- **Codebase Q&A** (`forge-ask`): Natural language queries against wiki, graph, explore cache, and docs index. Supports deep mode for multi-source synthesis. Config: `forge_ask.*`.
- **Insights dashboard** (`forge-insights`): Quality trends, cost analysis, convergence patterns, and memory effectiveness across pipeline runs.
- **Active knowledge base** (v2.0, F09): Learned rules evolve across runs with confidence tracking. Rules auto-promote from MEDIUM to HIGH after repeated successful application. Feeds into confidence familiarity dimension. Config: `active_knowledge.*`.
- **Enhanced security** (v2.0, F10): Extended security analysis with supply chain auditing, license compliance, and runtime policy enforcement. Config: `security.*`.
- **Flaky test management** (v2.0, F14): Automatic detection and quarantine of flaky tests. Tracks test stability across runs with statistical confidence. Flaky tests excluded from gating decisions. Config: `flaky_tests.*`.
- **Context condensation** (v2.0, F08): Automatic context compression for long-running pipelines. Reduces token consumption by summarizing completed stage outputs. Config: `condensation.*`.
- **Living specifications** (v2.0, F05): Drift detection between structured specs and implementation. Specs carry machine-parseable `AC-NNN` acceptance criteria. Quality gate detects drift at REVIEW, retrospective proposes updates at LEARN. Spec registry at `.forge/specs/index.json`. Config: `living_specs.*`.
- **Event-sourced pipeline log** (v2.0, F07): Unified append-only event log at `.forge/events.jsonl`. Captures all pipeline events with causal linking (parent_id chains). Subsumes `decisions.jsonl` and `progress/timeline.jsonl` as filtered views. Config: `events.*`.
- **Playbooks** (v2.0, F11): Reusable pipeline recipes for common workflows. Defined in `.forge/playbooks/` as YAML. Usage analytics tracked in `.forge/playbook-analytics.json`. Managed via `/forge-playbooks`. Config: `playbooks.*`.
- **Spec inference** (v2.0, F12): Function-level specification extraction during bug investigation. `fg-020-bug-investigator` synthesizes `{Location, Specification}` pairs from docstrings, tests, callers, naming, and types. Confidence scoring (HIGH/MEDIUM/LOW) based on evidence source agreement. Passed to implementer via stage notes. Finding categories: `SPEC-INFERENCE-LOW` (INFO), `SPEC-INFERENCE-CONFLICT` (WARNING). Config: `spec_inference.*`.
- **Property-based testing** (v2.0, F13): Optional `fg-515-property-test-generator` dispatched by test gate after standard tests pass. Infers function properties (invariants, round-trips, idempotence, metamorphic, commutativity, monotonicity) and generates framework-appropriate PBT tests (Hypothesis, jqwik, fast-check, proptest, gopter, etc.). Dependency check runs before code generation. Finding categories: `TEST-PROPERTY-*`. Config: `property_testing.*`.
- **Dynamic accessibility** (v2.0, F15): Enhanced `fg-413-frontend-reviewer` with Playwright-driven tab-order verification, focus visibility audit, keyboard-only navigation, ARIA completeness. Optional cross-browser testing (Chromium/Firefox/WebKit pixel diff). Config: `accessibility.*`.
- **i18n validation** (v2.0, F16): Hardcoded string detection for React/Angular/Vue/Swift/Android, RTL CSS violations, locale formatting. Module: `modules/code-quality/i18n-validation/`. Finding categories: `I18N-*`. Config: `i18n.*`.
- **Performance regression tracking** (v2.0, F17): Benchmark store (`.forge/benchmarks.json`) tracking build time, test duration, bundle size across runs. Rolling average comparison at REVIEW. Finding categories: `PERF-REGRESSION-*`. Config: `performance_tracking.*`.
- **Next-task prediction** (v2.0, F18): `fg-710-post-run` analyzes changes and predicts follow-up tasks using 19 pattern rules + graph queries. Accuracy tracking in `.forge/predictions.json`. Config: `predictions.*`.
- **DX metrics** (v2.0, F19): 10 developer experience metrics (cycle time, first-attempt success, cost-per-feature, convergence efficiency, etc.) in `.forge/dx-metrics.json`. Sprint burndown support. Config: `dx_metrics.*`.
- **Monorepo tooling** (v2.0, F20): Nx and Turborepo modules with affected detection, scoped testing/building. Auto-detection at PREFLIGHT from `nx.json` or `turbo.json`. Config: `monorepo.*`.
- **AI/ML pipeline support** (v2.0, F22): ML-ops modules (mlflow, dvc, wandb, sagemaker) and data pipeline modules (airflow, dagster, dbt) with convention enforcement, L1 pattern rules, and auto-detection at PREFLIGHT. Finding categories: `ML-VERSION-*`, `ML-REPRO-*`, `ML-DATA-*`, `ML-PIPELINE-*`. Config: `ml_ops.*`.
- **Feature flag management** (v2.0, F23): Feature flag lifecycle management with stale flag detection, dual-path testing verification, and deploy-time flag state checks. Provider modules: LaunchDarkly, Unleash. Finding categories: `FLAG-STALE`, `FLAG-UNTESTED`, `FLAG-HARDCODED`, `FLAG-CLEANUP`. Config: `feature_flags.*`.
- **A2A HTTP transport** (v2.0, F21): HTTP transport alongside filesystem for cross-machine A2A coordination. Agent cards served via HTTP, task submission/polling, token/mTLS auth. Falls back to filesystem transparently. Config: `a2a.*`.
- **Deployment strategies** (v2.0, F24): Canary (step-based traffic progression), blue-green (parallel environments), and rolling deployment strategies with metric-based promotion/rollback. New `fg-620-deploy-verifier` agent. Argo Rollouts integration. Finding categories: `DEPLOY-*`. Config: `deployment.*`.
- **Output compression** (v2.0, F26): Per-stage output verbosity system (4 levels: verbose/standard/terse/minimal). Reduces inter-agent output tokens by 20-65% via system prompt injection. Auto-clarity safety valve suspends compression for security warnings, user-facing content, and coordinator structured output. Retrospective detects drift. Config: `output_compression.*`.
- **Consumer-driven contracts** (v2.0, F25): Pact integration for consumer-driven contract testing. Broker/local/A2A pact sources. Can-i-deploy gate at SHIPPING. Alternative frameworks: Specmatic, Spring Cloud Contract. Finding categories: `CONTRACT-PACT-*`. Config: `contract_testing.*`.

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
| `forge-otel-export.sh` | OpenTelemetry trace and metric export |
| `hooks/automation-trigger.sh` | Event-driven automation dispatch (cron, CI, MCP) |

### Mode overlays (`shared/modes/`)

7 pipeline mode overlays: `standard`, `bugfix`, `migration`, `bootstrap`, `testing`, `refactor`, `performance`. Loaded by orchestrator at PREFLIGHT based on `state.mode`. Each overlay defines phase-specific adjustments (skip conditions, reduced thresholds, extra agents).

## Integrations

- **Linear** (optional): Epic/Stories/Tasks at PLAN, status per stage. Disabled by default. MCP failures → graceful degradation (no recovery engine).
- **MCP detection:** Detects Linear, Playwright, Slack, Context7, Figma, Excalidraw, Neo4j. First failure → degraded for run. No MCP required.
- **Cross-repo:** 5-step discovery at `/forge-init`. Contract validation, linked PRs, multi-repo worktrees. Timeout: 30min (configurable). Alphabetical lock ordering. PR failures don't block main PR. Discovery results stored with `detected_via`.

## Knowledge graph

Neo4j dual-purpose: (1) plugin module graph (seed), (2) project codebase graph. Docker-managed, disable with `graph.enabled: false`. Scoped by `project_id` (git remote) + optional `component`. 8 agents with `neo4j-mcp`: fg-010/020/090/100/102/200/210/400. Doc nodes for coverage tracking. Auto-updates post-IMPLEMENT/VERIFY/pre-REVIEW. Pipeline works without Neo4j. Query patterns: Bug Hotspots (14), Test Coverage (15), Cross-Feature Overlap (19), Cross-Repo Deps (20).

**SQLite code graph** (zero-dependency alternative): Tree-sitter + SQLite at `.forge/code-graph.db`. Built by `shared/graph/build-code-graph.sh`, queried via `shared/graph/code-graph-query.sh`, incrementally updated by `shared/graph/incremental-code-graph.sh`. Supports all 15 languages. 15 node types (File, Module, Class, Interface, Function, Method, Variable, Import, Export, Type, Enum, Constant, Decorator, Test, Fixture) and 17 edge types. Coexists with Neo4j: when Neo4j is available it remains primary; SQLite provides structural code intelligence when Neo4j is unavailable. Config: `code_graph.enabled` (default true), `code_graph.backend` (auto/sqlite/neo4j), `code_graph.exclude_patterns`. `code-graph.db` survives `/forge-reset`.

## Check engine (`shared/checks/`)

4 layers on `Edit`/`Write` operations:
- **L0** (tree-sitter AST, pre-edit via PreToolUse hook): blocks syntactically invalid edits before file is modified. Graceful degradation when tree-sitter is not installed. Config: `check_engine.l0_enabled`, `check_engine.l0_languages`, `check_engine.l0_timeout_ms`. Scripts in `shared/checks/l0-syntax/`.
- **L1** (regex, sub-second, PostToolUse hook): design tokens, animation perf. **L2** (linter adapters). **L3** (AI-driven, not in `engine.sh`): deprecation refresh + version compat, version-gated.
- `rules-override.json` extends defaults; `"disabled": true` to suppress. Skip tracking in `.forge/.check-engine-skipped`.

**Deprecation registries** (`modules/frameworks/*/known-deprecations.json`): Schema v2 (`pattern`, `replacement`, `package`, `since`, `removed_in`, `applies_from`, `applies_to`, `added`, `addedBy`). Skip when project version < `applies_from`. WARNING if deprecated, CRITICAL if `removed_in` reached. Auto-updated at PREFLIGHT.

## Infra testing (`fg-610-infra-deploy-verifier`)

5 tiers: T1 (<10s, static lint), T2 (<60s, container build+trivy), T3 (<5min, ephemeral cluster — **default**), T4 (<5min, contract stubs), T5 (<15min, full integration). Config: `infra.max_verification_tier` (1-5). Missing tools skip tiers. Findings: `INFRA-HEALTH` (CRITICAL), `INFRA-SMOKE` (WARNING), `INFRA-CONTRACT`/`INFRA-E2E` (CRITICAL), `INFRA-IMAGE` (WARNING/CRITICAL).

## Skills (33 total), hooks, kanban, git

**Skills:** `forge-run` (main entry), `forge-fix`, `forge-init`, `forge-status`, `forge-reset`, `forge-rollback`, `forge-history`, `forge-shape`, `forge-sprint`, `forge-review` (quick: 3 agents, full: up to 9; loops to score 100), `verify`, `security-audit`, `codebase-health`, `deep-health`, `migration`, `bootstrap-project`, `deploy`, `graph-init`, `graph-status`, `graph-query`, `graph-rebuild`, `graph-debug` (targeted Neo4j diagnostics), `docs-generate`, `forge-diagnose` (read-only diagnostic), `repair-state` (targeted state.json fixes), `config-validate` (pre-pipeline config check), `forge-abort` (graceful pipeline stop), `forge-resume` (resume from checkpoint), `forge-profile` (pipeline performance analysis), `forge-automation` (event-driven automation management), `forge-ask` (codebase knowledge query), `forge-insights` (pipeline run analytics), `forge-playbooks` (reusable pipeline recipe management).

**Hooks** (5): L0 syntax validation on `Edit|Write` (PreToolUse), check engine on `Edit|Write` (PostToolUse), checkpoint on `Skill`, feedback capture on `Stop`, compaction check on `Agent`.

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
- `explore-cache.json`, `plan-cache/`, `code-graph.db`, `trust.json`, `events.jsonl`, and `playbook-analytics.json` survive `/forge-reset`. Only manual `rm -rf .forge/` removes them.
- `model_routing.enabled` defaults to `true`. When disabled, no `model` parameter is passed to Agent dispatches. Set `enabled: false` in `forge-config.md` to opt out.
- Automation cooldowns prevent trigger loops (minimum interval between identical triggers). Config: `automations.cooldown_seconds` (default 300).
- Background runs write escalations to `.forge/alerts.json` instead of interactive prompts. Poll or watch this file for CRITICAL findings.
- A2A protocol uses local filesystem coordination (`.forge/agent-card.json`), not HTTP. Requires shared filesystem access between repos.
- `.forge/wiki/` survives `/forge-reset`. Only manual `rm -rf .forge/` removes it. Wiki is regenerated at PREFLIGHT when `wiki.auto_update` is enabled.
- Auto-discovered PREEMPT items (`source: auto-discovered`) decay 2x faster than normal items. They start at MEDIUM confidence, not HIGH. After 3 successful applications they promote to HIGH.

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
- Model routing: `model_routing.default_tier` must be `fast`, `standard`, or `premium`. Agent IDs in overrides validated against `agent-registry.md`.
- Implementer inner loop: `implementer.inner_loop.enabled` (boolean, default `true`), `implementer.inner_loop.max_fix_cycles` 1-5 (default 3), `implementer.inner_loop.affected_test_cap` 5-50 (default 20).
- Confidence: `confidence.planning_gate` (boolean, default `true`), `confidence.autonomous_threshold` 0.3-0.95 (default 0.7), `confidence.pause_threshold` 0.1-0.7 (default 0.4), `confidence.initial_trust` 0.0-1.0 (default 0.5). `autonomous_threshold` must be > `pause_threshold` (gap >= 0.1). Weights must sum to 1.0 (+/- 0.01).
- Output compression: `output_compression.enabled` (boolean, default `true`), `output_compression.default_level` must be `verbose`, `standard`, `terse`, or `minimal` (default `terse`), `output_compression.per_stage` keys must match 10 stage names, `output_compression.auto_clarity` (boolean, default `true`).

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
- **Implementer inner loop:** After each TDD cycle, `fg-300-implementer` runs lint on changed files + affected tests (explore cache / graph / directory heuristic, capped at 20 files). Fix cycles tracked as `implementer_fix_cycles` (separate from convergence counters). Disabled via `implementer.inner_loop.enabled: false`. Budget exhaustion logs remaining issues for VERIFY to catch.

## Distribution

`plugin.json` (v2.2.0), `marketplace.json`. Hooks in `hooks/hooks.json` only. Install: `/plugin marketplace add quantumbitcz/forge` → `/plugin install forge@quantumbitcz`.

## Governance

`LICENSE` (Proprietary, QuantumBit s.r.o.), `CONTRIBUTING.md`, `SECURITY.md`, `.github/CODEOWNERS` (@quantumbitcz), `.github/release.yml`.
