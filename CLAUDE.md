# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`forge` is a Claude Code plugin (v1.10.0, installable from the `quantumbitcz` marketplace or as a Git submodule). It orchestrates a 10-stage autonomous development pipeline: Preflight → Explore → Plan → Validate → Implement (TDD) → Verify → Review → Docs → Ship → Learn. The entry point is the `/forge-run` skill which dispatches `fg-100-orchestrator`.

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
3. **Shared core** (`agents/`, `shared/`, `hooks/`, `skills/`) — the pipeline engine: 40 agents, check engine, recovery system, scoring, discovery (`shared/discovery/`), knowledge graph (`shared/graph/`), and frontend design theory.

Parameter resolution: `forge-config.md` > `forge.local.md` > plugin hardcoded defaults.

Runtime dispatch: orchestrator loads the target agent's `.md` as subagent system prompt, passes stage notes as the task, collects the return as stage output. Agent `.md` size directly impacts token cost per dispatch.

## Quick start

```bash
./tests/validate-plugin.sh          # 51 structural checks, ~2s
./tests/run-all.sh                  # Full test suite, ~30s

# To test in a consuming project
ln -s "$(pwd)" /path/to/project/.claude/plugins/forge
cd /path/to/project && claude       # then run /forge-init
```

**First-time contributor?** Read `shared/agent-philosophy.md` first, then pick any agent `.md` to understand prompt structure. Run `./tests/validate-plugin.sh` after every change.

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
| State persistence  | `shared/state-schema.md` (v1.4.0 JSON schema)                    |
| Error handling     | `shared/error-taxonomy.md` + `shared/recovery/recovery-engine.md` |
| Agent design       | `shared/agent-philosophy.md` + `shared/agent-communication.md`    |
| Graph schema       | `shared/graph/schema.md` (node types, relationships, lifecycle)   |
| Token management   | `shared/agent-defaults.md` (shared constraints) + `shared/logging-rules.md` (cross-cutting logging) |
| Convergence loop | `shared/convergence-engine.md` (three-phase iteration: correctness, perfection, evidence) |
| Shipping evidence | `shared/verification-evidence.md` (evidence artifact schema, verdict rules) |
| Kanban tracking  | `shared/tracking/tracking-schema.md` (ticket format, board structure, archival)  |
| Git conventions  | `shared/git-conventions.md` (branches, commits, hook detection)        |
| MCP provisioning | `shared/mcp-provisioning.md` (auto-install rules, credential config) |
| Version resolution | `shared/version-resolution.md` (never hardcode versions) |
| UI patterns      | `shared/agent-ui.md` (AskUserQuestion, TaskCreate, plan mode)     |
| Sprint orchestration | `shared/sprint-state-schema.md` (sprint state, per-run isolation)  |
| Intent classification | `shared/intent-classification.md` (routing rules, signal definitions)   |

## Key conventions

### Agents (40 total, in `agents/*.md`)

**Pipeline agents** (`fg-{NNN}-{role}` naming):
- Pre-pipeline: `fg-010-shaper`, `fg-015-scope-decomposer`, `fg-020-bug-investigator`, `fg-050-project-bootstrapper`
- Sprint orchestration: `fg-090-sprint-orchestrator`
- Orchestration: `fg-100-orchestrator` (coordinator — dispatches all others, never writes code)
- Orchestrator helpers: `fg-101-worktree-manager`, `fg-102-conflict-resolver`, `fg-103-cross-repo-coordinator`
- Preflight: `fg-130-docs-discoverer`, `fg-140-deprecation-refresh`, `fg-150-test-bootstrapper`, `fg-160-migration-planner`
- Plan/Validate: `fg-200-planner`, `fg-210-validator`, `fg-250-contract-validator`
- Implement: `fg-300-implementer`, `fg-310-scaffolder`, `fg-320-frontend-polisher` (conditional on `frontend_polish.enabled`)
- Docs (Stage 7): `fg-350-docs-generator`
- Verify/Review: `fg-400-quality-gate`, `fg-500-test-gate`
- Ship: `fg-590-pre-ship-verifier`, `fg-600-pr-builder`, `fg-650-preview-validator`, `infra-deploy-verifier` (conditional on k8s/infra)
- Learn: `fg-700-retrospective`, `fg-710-feedback-capture`, `fg-720-recap`

**Review agents** (11, dispatched by quality gate): `architecture-reviewer`, `security-reviewer`, `code-quality-reviewer`, `frontend-reviewer`, `frontend-design-reviewer`, `frontend-a11y-reviewer`, `frontend-performance-reviewer`, `backend-performance-reviewer`, `version-compat-reviewer`, `infra-deploy-reviewer`, `docs-consistency-reviewer`.

**Agent file rules:**
- **YAML frontmatter required:** `name` (must match filename without `.md`), `description`, `tools`.
  - Dispatch agents **must** include `Agent` in tools list.
  - Orchestrator wraps every dispatch with `TaskCreate`/`TaskUpdate` for real-time progress visibility.
  - Multi-option choices **must** use `AskUserQuestion` with structured options — never `Options: (1)...` or `(y/n)`.
  - Planning agents use `EnterPlanMode`/`ExitPlanMode` for user approval — skip in autonomous/replanning.
- YAML frontmatter `ui:` section declares interactive capabilities: `tasks` (TaskCreate/TaskUpdate), `ask` (AskUserQuestion), `plan_mode` (EnterPlanMode/ExitPlanMode). Omitting `ui:` entirely = all false (Tier 4). Structural test `ui-frontmatter-consistency.bats` enforces that `ui:` declarations match `tools:` list. See `shared/agent-ui.md` for patterns.
- Agent UI tiers: Tier 1 (tasks+ask+plan_mode): shaper, scope-decomposer, planner, migration planner, bootstrapper, sprint orchestrator. Tier 2 (tasks+ask): orchestrator, bug investigator, quality gate, test gate, PR builder, cross-repo coordinator. Tier 3 (tasks only): implementer, frontend polisher, retrospective, docs discoverer, deprecation refresh, preview validator, pre-ship verifier, infra verifier, scaffolder, docs generator, contract validator, test bootstrapper. Tier 4 (no UI): all 11 reviewers, validator, feedback capture, recap, worktree manager, conflict resolver.
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
- **Description tiering:** Agent descriptions use a three-tier compression strategy to minimize system prompt token usage (~1k total, down from ~15.4k). Tier 1 (entry-point, 6 agents): short description + 1 example. Tier 2 (reviewers, 11 agents): single-line, no examples. Tier 3 (internal, 23 agents): minimal single-line, no examples. Full agent capability is in the `.md` body (loaded at dispatch time), not the description.

### Universal Routing & Auto-Decomposition

- **Universal routing:** `/forge-run` auto-classifies intent (bugfix/migration/bootstrap/multi-feature/vague/standard) and routes to the correct agent. Vague detection includes a **feature completeness check**: requirements under 50 words missing 3+ of (actors, entities, surface, criteria) are routed to `fg-010-shaper` for shaping first. Explicit prefixes (`bugfix:`, `migrate:`, `bootstrap:`) and flags (`--sprint`, `--parallel`) override classification. Config: `routing.auto_classify`, `routing.vague_threshold` in `forge-config.md`. See `shared/intent-classification.md`.
- **Auto-decomposition:** Multi-feature requirements detected via fast scan (text analysis in forge-run) or deep scan (post-EXPLORE domain analysis in orchestrator). Triggers `fg-015-scope-decomposer` → `fg-090-sprint-orchestrator`. Config: `scope.auto_decompose`, `scope.decomposition_threshold`, `scope.fast_scan` in `forge-config.md`.
- **Visual design preview:** Frontend features optionally present design alternatives via superpowers visual companion during PLAN stage (fg-200). Detected at PREFLIGHT (`state.json.integrations.visual_companion`). Config: `frontend_preview.enabled`, `frontend_preview.auto_open_browser`, `frontend_preview.keep_alive_for_polish` in `forge.local.md`. Graceful degradation: text-only if superpowers unavailable or `autonomous: true`.

### Core contracts (in `shared/`)

Read source files for full details. Key facts:

- **Scoring** (`scoring.md`):
  - Formula: `max(0, 100 - 20*CRITICAL - 5*WARNING - 2*INFO)`. PASS >= 80, CONCERNS 60-79, FAIL < 60 or any CRITICAL remaining after convergence exhaustion.
  - 19 shared categories — 16 wildcard prefixes (`ARCH-*`, `SEC-*`, `PERF-*`, `FE-PERF-*`, `TEST-*`, `CONV-*`, `DOC-*`, `QUAL-*`, `APPROACH-*`, `SCOUT-*`, `A11Y-*`, `DEPS-*`, `COMPAT-*`, `CONTRACT-*`, `STRUCT-*`, `INFRA-*`) + 3 discrete codes (`REVIEW-GAP`, `DESIGN-TOKEN`, `DESIGN-MOTION`). Agent-specific categories (`BE-PERF-*`, `FE-*`) in their agents.
  - Deduplication: key is `(component, file, line, category)` — same issue in different components not deduplicated. Sub-bands (95-99, 80-94, 60-79, <60) guide Linear granularity.
  - Convergence: three-phase iteration (correctness → perfection → safety gate → evidence). Global `max_iterations` checked before inner caps. Oscillation tolerance configurable (default 5 pts). See `shared/convergence-engine.md`.
  - SCOUT-* findings: excluded from score by quality gate, stripped by orchestrator before implementer dispatch (two-point filtering).
  - Five iteration counters: `verify_fix_count` (Phase A), `test_cycles` (Phase 1B), `quality_cycles` (Phase 2) inner-loop; `phase_iterations` (per-phase, resets); `total_iterations` (cumulative, never resets).
  - Timed-out security/architecture reviewers: coverage gap upgraded INFO → WARNING.
  - 7 validation perspectives: architecture, security, edge_cases, test_strategy, conventions, approach_quality, documentation_consistency.
- **Stage contracts** (`stage-contract.md`): Entry/exit conditions per stage. States: PREFLIGHT → EXPLORING → PLANNING → VALIDATING → IMPLEMENTING → VERIFYING → REVIEWING → DOCUMENTING → SHIPPING → LEARNING. Migration states: MIGRATING, MIGRATION_PAUSED, MIGRATION_CLEANUP, MIGRATION_VERIFY. PR rejection routes to Stage 4 (impl feedback) or Stage 2 (design feedback) via `fg-710-feedback-capture`.
- **State schema** (`state-schema.md`): Version **1.4.0**. State in `.forge/` (gitignored). Checkpoints per task.
  - Corrupted counters recovered from checkpoints — fallback uses configured maximum (conservative), not zero.
  - Key fields: `mode` (standard/migration/bootstrap/bugfix), `feedback_loop_count` (escalates at 2), `documentation.discovery_error`, `abort_reason`, `recovery` (failures, recoveries, degraded_capabilities), `ticket_id`, `branch_name`, `tracking_dir`, `graph` (update state).
- **Recovery** (`recovery/`): 7 strategies, weighted budget ceiling 5.5 (extremes: graceful-stop 0.0/free, state-reconstruction 1.5/costliest). Budget resets at PREFLIGHT of each new `/forge-run`. In sprint mode, each feature's orchestrator has its own independent budget. Multi-error ordering: highest-severity recoverable first. See `recovery-engine.md`.
- **Error taxonomy** (`error-taxonomy.md`): 22 types (incl. `CONTEXT_OVERFLOW`), 16-level severity priority. MCP failures handled inline (skip + INFO), NOT by recovery engine. 3 consecutive transient-retry failures for same endpoint within 60s → reclassified as non-recoverable. `BUILD_FAILURE`/`TEST_FAILURE`/`LINT_FAILURE` are code-level errors handled by the orchestrator fix loop, not the recovery engine.
- **Agent communication** (`agent-communication.md`): Inter-stage data flows through orchestrator via stage notes. Agents cannot write state or message the user directly.
  - Coordinator agents (fg-400, fg-500, fg-600, fg-200, fg-310) **can** dispatch sub-agents within their stage (distinct from inter-stage communication).
  - Quality gate includes previous batch findings (top 20) to reduce duplicates. PREEMPT tracking via `PREEMPT_APPLIED`/`PREEMPT_SKIPPED` markers.
- **Frontend design** (`frontend-design-theory.md`): Gestalt, visual hierarchy, color theory, typography, 8pt grid, motion — shared by all frontend agents.
- **Learnings** (`learnings/`): Per-module files (frameworks, languages, testing frameworks, crosscutting layers) + JSON schemas (`rule-learning-schema.json`, `agent-effectiveness-schema.json`) for tracking check rule evolution and agent performance.
- **Version detection:** PREFLIGHT detects dependency versions from manifest files (build.gradle.kts, package.json, go.mod, etc.) → `state.json.detected_versions`. Enables version-gated deprecation rules.
- **Convention drift:** Detected mid-run via per-section SHA256 hash comparison. Agents only react to changes in their relevant section.
- **Global retry budget:** Cumulative `total_retries` counter (default max: 10, configurable). Prevents unbounded cascades.
- **Concurrent run lock:** `.forge/.lock` with PID check + 24h stale timeout.
- **Evidence-based shipping:** `fg-590-pre-ship-verifier` runs fresh build+test+lint+review after DOCS, writes `.forge/evidence.json`. PR builder refuses to create PR without `verdict: SHIP`. No "continue anyway" option anywhere — only fix, keep trying, or abort. See `shared/verification-evidence.md`.

### Integrations

- **Linear** (optional): Epic/Stories/Tasks during PLAN, status updates per stage. Configured via `linear:` in `forge.local.md` (disabled by default). Failures retry once then degrade gracefully — recovery engine NOT invoked for MCP failures.
- **MCP detection**: `forge-run` detects available MCPs (Linear, Playwright, Slack, Context7, Figma). First failure marks MCP as degraded for the run. No MCP required.
- **Cross-repo**: 5-step discovery during `/forge-init`. Contract validation (`fg-250-contract-validator`), linked PRs, multi-repo worktrees during runs. State in `state.json.cross_repo`. Configurable via `discovery:` section.

### Knowledge Graph (`graph:` in `forge.local.md`)

Neo4j-based dual-purpose knowledge graph: (1) static plugin module relationship graph (pre-computed seed), (2) dynamic consuming project codebase graph (files, imports, classes, dependencies). Enables impact analysis, convention stack resolution, gap detection, and recommendation queries via Cypher.

- **Setup:** Docker-managed in `.forge/`, accessed via Neo4j MCP. Container: `forge-neo4j` (configurable via `graph.neo4j_container_name` or `NEO4J_CONTAINER`). Disable with `graph.enabled: false`. See `shared/graph/schema.md` and `shared/graph/query-patterns.md`.
- **Scoping:** All `Project*`/`Doc*` nodes scoped by `project_id` (git remote origin) + optional `component`. Multiple projects share one instance. `/graph-rebuild` only deletes current project.
- **Agent access:** 5 agents with direct `neo4j-mcp`: fg-010-shaper, fg-020-bug-investigator, fg-200-planner, fg-210-validator, fg-400-quality-gate.
- **Doc nodes:** `DocFile`, `DocSection`, `DocDecision`, `DocConstraint`, `DocDiagram` — used by fg-130/fg-350 for coverage tracking.
- **Query patterns:** 14 (Bug Hotspots), 15 (Test Coverage) for bugfix risk. 19 (Cross-Feature File Overlap), 20 (Cross-Repo Dependency Graph) for sprint independence.
- **Auto-updates:** post-IMPLEMENT, post-VERIFY, pre-REVIEW via `update-project-graph.sh`. Tracked in `state.json.graph`.
- **Graceful degradation:** Pipeline works normally without Neo4j. State schema version: **1.4.0**.

### Check engine (`shared/checks/`)

3-layer engine triggered on every `Edit`/`Write` via PostToolUse hook:
- **Layer 1** (`layer-1-fast/`): regex patterns, sub-second. Enforces design tokens (hex/rgb detection) and animation performance.
- **Layer 2** (`layer-2-linter/`): framework-aware linter adapters.
- **Layer 3** (`layer-3-agent/`): AI-driven — `fg-140-deprecation-refresh` (PREFLIGHT) and `version-compat-reviewer` (REVIEW). Not triggered by `engine.sh`. Version-gated: rules only fire when project version >= `applies_from`.
- Modules customize via `rules-override.json` (extends shared defaults; use `"disabled": true` to suppress).
- Skip tracking: timeouts increment `.forge/.check-engine-skipped`, reported in VERIFY. Output format in `output-format.md`.

### Deprecation registries (`modules/frameworks/*/known-deprecations.json`)

**Schema v2**: `pattern`, `replacement`, `package`, `since`, `removed_in`, `applies_from`, `applies_to`, `added`, `addedBy`. Rules skip when project version < `applies_from`. Severity: WARNING if deprecated, CRITICAL if `removed_in` reached. Auto-updated by `fg-140-deprecation-refresh` during PREFLIGHT.

### Infra testing (`infra-deploy-verifier`)

5-tier verification system for infrastructure changes:
- **Tier 1** (<10s): Static validation — helm lint, kubectl dry-run, Dockerfile syntax.
- **Tier 2** (<60s): Container validation — docker build, compose health check, trivy scan.
- **Tier 3** (<5min): Isolated cluster — kind/k3d ephemeral cluster, helm install, pod readiness, smoke tests.
- **Tier 4** (<5min): Contract testing — infra + stub containers (auto-generated from OpenAPI spec or health-only), DNS/routing/config validation, user scripts from `tests/infra/contract/`.
- **Tier 5** (<15min): Full stack integration — infra + real service images from registry or local build (`image_source: registry | build | auto`), end-to-end connectivity, DB migration validation, user scripts from `tests/infra/integration/`.

Default: Tier 3. Configure via `infra.max_verification_tier` (1-5). Graceful degradation: missing tools skip tiers, pipeline continues. Findings: `INFRA-HEALTH` (CRITICAL), `INFRA-SMOKE` (WARNING), `INFRA-CONTRACT` (CRITICAL), `INFRA-E2E` (CRITICAL), `INFRA-IMAGE` (WARNING/CRITICAL). User scenario tests live in `tests/infra/` — see `modules/frameworks/k8s/conventions.md`.

### Skills (21 in `skills/`)

`forge-run` (main entry — accepts `--ticket FG-001`, bare ticket ID shorthand, or `bugfix:` prefix), `forge-fix` (bugfix entry — accepts ticket ID, Linear issue, or plain description), `forge-init`, `forge-status`, `forge-reset`, `forge-rollback`, `forge-history`, `forge-shape`, `forge-sprint` (parallel multi-feature entry — accepts `--sprint`/`--parallel` with feature list), `verify`, `security-audit`, `codebase-health`, `deep-health` (iterative investigation + fix + review loop — dispatches forge review agents, fixes all findings including minor, commits per iteration, loops until clean), `migration`, `bootstrap-project`, `deploy`, `graph-init`, `graph-status`, `graph-query`, `graph-rebuild`, `docs-generate`. Frontend commands (`fe-check-theme`, `fe-design-review`, etc.) live in the consuming project, not here.

### Hooks (`hooks/hooks.json`)

3 hooks: check engine on `Edit|Write`, checkpoint on `Skill`, feedback capture on `Stop`.

### Kanban Tracking (`.forge/tracking/`)

File-based kanban board. Tickets in `backlog/`, `in-progress/`, `review/`, `done/` with YAML frontmatter. Counter in `counter.json`. Board summary in `board.md` (auto-generated). Ticket IDs used in branch names. See `shared/tracking/tracking-schema.md` for schema and `shared/tracking/tracking-ops.sh` for operations.

Configurable prefix in `forge.local.md`: `tracking.prefix: "WP"`. Default: `FG`. IDs never reused.

Stage integration: shaper creates tickets → orchestrator moves through statuses → PR builder updates PR URL → retrospective closes tickets. Graceful degradation: all kanban operations silently skip if tracking not initialized.

### Git Conventions (`shared/git-conventions.md`)

Branch naming: `{type}/{ticket}-{slug}` (configurable via `git:` in `forge.local.md`). Commit format: Conventional Commits by default, or `project` if existing hooks detected during `/forge-init`. Hook detection scans for Husky, commitlint, Lefthook, pre-commit, Commitizen — adopts existing conventions, never overrides.

**Never in commits:** `Co-Authored-By`, AI attribution, `--no-verify`.

### Init Automation (`.claude/plugins/project-tools/`)

`/forge-init` generates a project-local plugin with hooks (commit-msg-guard, branch-name-guard), skills (/run-tests, /build, /lint, /deploy), and agents (commit-reviewer). Respects existing project hooks — never overrides. MCP auto-provisioning installs missing servers (Neo4j, Playwright) at init time. See `forge-init/SKILL.md` Phase 6d and `shared/mcp-provisioning.md`.

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
./tests/run-all.sh structural       # 51 checks, no bats needed
./tests/run-all.sh unit             # 11 test files
./tests/run-all.sh contract         # 31 test files
./tests/run-all.sh scenario         # 12 test files
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

# Test specific agent or test category
./tests/lib/bats-core/bin/bats tests/structural/agent-frontmatter.bats  # All agent structure checks
./tests/lib/bats-core/bin/bats tests/contract/                          # All contract tests
```

## Gotchas

### Structural rules

- Agent `name` in frontmatter **must** match filename without `.md` — orchestrator dispatch depends on it.
- Scripts need shebang (`#!/usr/bin/env bash`) and `chmod +x` — hooks fail silently without this. Graph scripts (`build-project-graph.sh`, `incremental-update.sh`, `enrich-symbols.sh`, `generate-seed.sh`), `run-linter.sh`, and `engine.sh` require **bash 4.0+** for associative arrays and regex capture groups. macOS ships bash 3.2 — developers need `brew install bash`. The four graph scripts guard with `require_bash4()` from `shared/platform.sh`; `run-linter.sh` and `engine.sh` use inline version checks (do not source `platform.sh` for performance). `engine.sh` uses a portable `_glob_exists()` helper instead of `compgen -G` for glob matching.
- `shared/` files are contracts — changing `scoring.md`, `stage-contract.md`, `state-schema.md`, or `frontend-design-theory.md` affects all agents/modules. Verify downstream impact.
- The plugin never touches consuming project files. Runtime state goes to `.forge/`.
- `forge-config.md` is auto-tuned by retrospective — manual edits may be overwritten. Wrap parameters in `<!-- locked -->` / `<!-- /locked -->` fences to protect them from auto-tuning.
- `.forge/` directory is gitignored and assumed present by pipeline. Deleting it mid-run causes unrecoverable state loss — use `/forge-reset` instead.

### Worktree enforcement

Worktree created at PREFLIGHT (Stage 0), not IMPLEMENT (Stage 4). All forge workflows use `.forge/worktree`. Only exceptions: `--dry-run` and `/forge-init`. Branch name uses ticket ID from kanban tracking. See `shared/stage-contract.md` Cross-Cutting Constraints.

### Check engine

- If `engine.sh` is broken/non-executable, all edits trigger hook errors. On timeout, skip counter increments but edit succeeds. Hook scripts are validated at plugin installation (shebang + executable permission checks in `validate-plugin.sh`).
- `rules-override.json` extends (not replaces) shared defaults. Use `"disabled": true` to suppress.
- `engine.sh` multi-component YAML parsing expects 2-space indentation (component names at 2-space, path/framework at 4-space). Non-standard indentation (tabs, 4-space) now emits a WARNING to stderr and falls back to single-component detection. Forge-generated templates always use 2-space.
- `known-deprecations.json` v1 entries (without `applies_from`) apply universally (backward compatible). Unknown project versions → all rules apply.

### PREFLIGHT constraints

- Scoring: `critical_weight >= 10`, `warning_weight >= 1`, `warning_weight > info_weight`, `info_weight >= 0`, `pass_threshold >= 60`, `concerns_threshold >= 40`, `concerns_threshold < pass_threshold`, `pass_threshold - concerns_threshold >= 10`, `oscillation_tolerance` 0-20. Global retry budget: `total_retries_max` 5-30.
- Convergence: `max_iterations` 3-20, `plateau_threshold` 0-10, `plateau_patience` 1-5, `target_score` >= `pass_threshold` and <= 100.
- Sprint: `sprint.poll_interval_seconds` 10-120 (default: 30), `sprint.dependency_timeout_minutes` 5-180 (default: 60).
- Tracking: `tracking.archive_after_days` 30-365 or 0 to disable (default: 90).
- Scope: `scope.decomposition_threshold` 2-10 (default: 3). Routing: `routing.vague_threshold` low/medium/high (default: medium).
- Shipping: `shipping.min_score` >= `pass_threshold` AND <= 100 (default: 100), `shipping.evidence_max_age_minutes` 5-60 (default: 30).

### Pipeline modes

- **Greenfield projects:** `/forge-init` detects empty projects and offers three paths: Bootstrap (dispatch `fg-050-project-bootstrapper`), Select stack manually (choose from available frameworks), or Skip. Unknown/null detection on non-empty projects also triggers manual framework selection. See `forge-init` SKILL.md Greenfield Detection section.
- **Bootstrap mode:** Stage 4 (IMPLEMENT) is skipped — all files created by bootstrapper in Stage 2. Stage 3 uses bootstrap-scoped validation (no conventions check, no Challenge Brief required). Stage 6 uses reduced reviewer set (`architecture-reviewer` + `security-reviewer` + `code-quality-reviewer`). Quality target is `pass_threshold`, not 100.
- **Bugfix mode:** `/forge-fix` or `/forge-run bugfix: <description>`. Stage 1 dispatches `fg-020-bug-investigator` (INVESTIGATE), Stage 2 continues with reproduction (max 3 attempts). Stage 3 validates with 4 bugfix perspectives (root cause validity, fix scope, regression risk, test coverage). Stage 6 uses reduced reviewer batch (`architecture-reviewer` + `security-reviewer` + `code-quality-reviewer`, plus `frontend-reviewer` if frontend files changed). Stage 9 tracks bug patterns in `.forge/forge-log.md`. Bugfix state fields: `bugfix.source`, `bugfix.reproduction.*`, `bugfix.root_cause.*`. See `stage-contract.md` Bugfix Mode section.
- **Migration mode:** All 10 stages run. Stage 2 uses `fg-160-migration-planner`. Stage 4 cycles through migration-specific states (`MIGRATING`, `MIGRATION_PAUSED`, `MIGRATION_CLEANUP`, `MIGRATION_VERIFY`). See `stage-contract.md` Migration Mode section.
- `--dry-run` runs PREFLIGHT→VALIDATE only. No worktree, no Linear, no file changes. No `.forge/.lock`, no checkpoint files, no `lastCheckpoint` updates.
- **Autonomous mode:** `autonomous: true` in `forge-config.md` replaces all AskUserQuestion with auto-selection (logged with `[AUTO]` prefix). Plans auto-approved after validator passes. Tasks still created. Pipeline never pauses except on unrecoverable CRITICAL errors.
- **Sprint mode:** `/forge-run --sprint` or `/forge-run --parallel "A" "B" "C"`. Dispatches `fg-090-sprint-orchestrator`.
  - Decomposition: analyzes independence via `fg-102-conflict-resolver`, dispatches parallel `fg-100-orchestrator` per feature.
  - Isolation: `.forge/runs/{feature-id}/` for state, `.forge/worktrees/{feature-id}/` for worktrees. Shared Neo4j for cross-feature conflict detection.
  - Cross-repo: contract producers execute before consumers. State in `.forge/sprint-state.json`.
  - Polling: every 30s (configurable via `sprint.poll_interval_seconds`). Conflict `serialize` = first completes SHIP before second enters IMPLEMENT.
  - `waiting` repos pause until resolved or `sprint.dependency_timeout_minutes` (default: 60) expires. See `shared/sprint-state-schema.md`.

### Convergence & review

- PREEMPT confidence decay: 10 domain-matched unused runs → HIGH → MEDIUM → LOW → ARCHIVED. 1 false positive = 3 unused runs. Archived items are not loaded at PREFLIGHT.
- **Convergence safety gate restart:** Resets `phase_iterations`, `plateau_count`, `last_score_delta`, `convergence_state` to initial values. Does NOT reset `total_iterations` or `score_history`. After restart, the first perfection cycle (phase_iterations = 0) is exempt from plateau counting — it establishes a new baseline. See `convergence-engine.md` safety_gate section.
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

### Version resolution

Agents must NEVER use dependency versions from training data. Always search the internet for latest compatible version at runtime. See `shared/version-resolution.md`.

### Testing

- **Test module counts:** Module lists are auto-discovered from disk via `tests/lib/module-lists.bash`. Minimum count guards (e.g., `MIN_FRAMEWORKS=21`) catch accidental deletions. When intentionally adding modules, bump the corresponding `MIN_*` constant in `module-lists.bash`.

## Plugin distribution (`.claude-plugin/`)

- `plugin.json` — manifest (v1.10.0). `marketplace.json` — catalog for `quantumbitcz`.
- Hooks in `hooks/hooks.json` only (NOT in plugin.json).
- Install: `/plugin marketplace add quantumbitcz/forge` then `/plugin install forge@quantumbitcz`.

## Governance

- `LICENSE` — Proprietary (QuantumBit s.r.o.)
- `CONTRIBUTING.md` — How to add modules, agents, hooks, skills
- `SECURITY.md` — Vulnerability reporting and plugin security practices
- `.github/CODEOWNERS` — Auto-assigns `@quantumbitcz` to all PRs
- `.github/release.yml` — Auto-generated release notes by PR label
