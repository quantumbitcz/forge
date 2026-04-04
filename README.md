# forge

> Autonomous 10-stage development pipeline for Claude Code. Point it at a requirement and get a tested, reviewed, documented pull request.

Claude Code is powerful, but without structure it makes inconsistent decisions, skips tests, forgets conventions, and produces PRs that need heavy review. **forge** fixes this by orchestrating 32 specialized agents across 10 stages -- from exploration through TDD implementation, multi-perspective quality review, and self-improving retrospectives -- so every run follows the same disciplined process.

## Quick start

```bash
# 1. Install the plugin
/plugin marketplace add quantumbitcz/forge
/plugin install forge@quantumbitcz

# 2. Initialize your project (auto-detects framework)
/forge-init

# 3. Add .forge/ to .gitignore
echo ".forge/" >> .gitignore

# 4. Run it
/forge-run Add user dashboard with activity feed
```

<details>
<summary>Alternative: install as Git submodule</summary>

```bash
git submodule add https://github.com/quantumbitcz/forge.git .claude/plugins/forge
```

Then add to `.claude/settings.json`:

```json
{
  "plugins": [".claude/plugins/forge"]
}
```

</details>

## Key features

- **Worktree isolation** -- Your working tree is never modified. All implementation runs in a git worktree (`.forge/worktree`).
- **Self-healing recovery** -- 7 recovery strategies with weighted budget (ceiling 5.5) handle transient failures, tool issues, and state corruption automatically.
- **3-layer check engine** -- Fires on every Edit/Write. Fast regex patterns (sub-second), framework-aware linters, and AI-driven agents with version-gated deprecation rules.
- **Self-improving** -- Learnings from past runs are proactively applied to future runs via the PREEMPT system. Confidence decay prevents stale learnings from persisting.
- **Adaptive MCP detection** -- Auto-detects Linear, Playwright, Slack, Context7, and Figma at PREFLIGHT. No MCP is required -- the pipeline degrades gracefully.
- **Version-aware deprecations** -- Schema v2 registries with `applies_from` and `removed_in` fields. Rules only fire when the project version matches.
- **Frontend design quality** -- Creative polish, WCAG 2.2 AA audits, design system compliance, and responsive validation across breakpoints.
- **Concurrent run protection** -- Lock file prevents parallel runs. Global retry budget (default 10) prevents unbounded cascades.

### The 10 stages

| # | Stage | What happens |
|---|-------|-------------|
| 0 | Preflight | Load config, detect interrupted runs, detect versions, apply learnings |
| 1 | Explore | Map domain models, tests, and patterns relevant to the requirement |
| 2 | Plan | Risk-assessed implementation plan with stories, tasks, parallel groups |
| 3 | Validate | 7-perspective validation (architecture, security, edge cases, tests, conventions, approach quality, documentation consistency) |
| 4 | Implement | TDD loop per task -- scaffold, write tests (RED), implement (GREEN), refactor |
| 5 | Verify | Build, lint, static analysis, full test suite |
| 6 | Review | Multi-agent quality review with scoring and fix cycles |
| 7 | Docs | Update CLAUDE.md, KDoc/TSDoc on new public interfaces |
| 8 | Ship | Branch, commit, PR with quality gate results |
| 9 | Learn | Retrospective analysis, config tuning, trend tracking |

## Available skills

18 skills provide the user-facing interface to the pipeline and its subsystems.

| Skill | Description |
|-------|-------------|
| `/forge-run` | Main entry point -- runs the full 10-stage pipeline |
| `/forge-init` | Initialize project config files (auto-detects framework module) |
| `/forge-status` | Show current pipeline state, quality score, retry budgets, recovery budget, Linear sync, and detected versions |
| `/forge-reset` | Clear pipeline run state (including lock and skip counter) while preserving accumulated learnings |
| `/forge-rollback` | Safely rollback pipeline changes (4 modes: worktree, post-merge, Linear, state-only) |
| `/forge-history` | View quality score trends, agent effectiveness, and PREEMPT health across runs |
| `/migration` | Plan and execute library/framework migrations (auto-detect versions, explicit versions, `upgrade all`, `check` dry-run, Context7 integration) |
| `/bootstrap-project` | Scaffold a new project from a module template |
| `/deploy` | Trigger deployment workflow via infra-deploy agents (staging, production, preview, rollback, status) |
| `/forge-shape` | Collaboratively shape features into structured specs with epics, stories, and acceptance criteria |
| `/security-audit` | Run module-appropriate security scanners (npm audit, cargo audit, govulncheck, trivy, etc.) |
| `/codebase-health` | Run the check engine in full review mode for a comprehensive health report |
| `/verify` | Quick build + lint + test check without a full pipeline run |
| `/graph-init` | Initialize the Neo4j knowledge graph (Docker-managed, enabled by default) |
| `/graph-status` | Show knowledge graph connection status and node/relationship counts |
| `/graph-query` | Run Cypher queries against the knowledge graph |
| `/graph-rebuild` | Rebuild the knowledge graph from the current codebase |
| `/docs-generate` | Generate or update project documentation (standalone or pipeline mode, coverage reporting, framework-aware) |

## Available modules

21 framework modules under `modules/frameworks/`, 15 language files under `modules/languages/`, 19 testing framework files under `modules/testing/`, and 15 crosscutting layer directories: `modules/databases/`, `modules/persistence/`, `modules/migrations/`, `modules/api-protocols/`, `modules/messaging/`, `modules/caching/`, `modules/search/`, `modules/storage/`, `modules/auth/`, `modules/observability/`, `modules/build-systems/`, `modules/ci-cd/`, `modules/container-orchestration/`, `modules/documentation/`, and `modules/code-quality/`. Each framework module provides `conventions.md`, `local-template.md`, `forge-config-template.md`, `rules-override.json`, and `known-deprecations.json` (schema v2 deprecation registry). Some modules include additional scripts, hooks, variants, or framework-specific binding patterns.

| Framework | Target stack |
|-----------|-------------|
| `spring` | Kotlin/Java with Spring Boot (hexagonal architecture, WebFlux, R2DBC). Variants: `kotlin`, `java` |
| `react` | React + Vite + TypeScript + shadcn/ui. Design tokens, animation & motion conventions |
| `nextjs` | Next.js with App Router, Server/Client Components, Server Actions |
| `sveltekit` | SvelteKit with TypeScript |
| `express` | Express/NestJS with TypeScript |
| `fastapi` | Python with FastAPI and Pydantic |
| `django` | Python with Django + DRF (apps as bounded contexts) |
| `gin` | Go with Gin web framework |
| `go-stdlib` | Go with standard library conventions |
| `axum` | Rust with Axum + Tokio |
| `swiftui` | Swift for iOS/macOS applications (memory safety, SPM) |
| `vapor` | Swift with Vapor server framework |
| `jetpack-compose` | Android with Jetpack Compose + MVVM + Hilt |
| `kotlin-multiplatform` | KMP shared module + platform targets (Ktor, Koin, SQLDelight) |
| `aspnet` | .NET with ASP.NET Core (Clean Architecture, EF Core) |
| `embedded` | C for embedded systems (real-time safety, ISR conventions, RTOS) |
| `k8s` | Kubernetes infrastructure (resource limits, probes, security contexts) |
| `angular` | TypeScript + Angular 17+ (standalone components, signals, NgRx SignalStore) |
| `nestjs` | TypeScript + NestJS (module-based DI, decorators, microservices transport) |
| `vue` | TypeScript + Vue 3 / Nuxt 3 (Composition API, Pinia, server routes) |
| `svelte` | TypeScript + Svelte 5 (runes, standalone SPAs, no SvelteKit) |

All modules include conventions with a Dos/Don'ts section, config templates, check engine rule overrides, and a version-aware deprecation registry (`known-deprecations.json`).

## Integrations

The pipeline auto-detects available MCP servers at PREFLIGHT and adapts its behavior. No integration is required -- each one is optional and the pipeline degrades gracefully when unavailable.

| Integration | What it does | Used by |
|-------------|-------------|---------|
| **Linear** | Creates Epics, Stories, and Tasks during PLAN. Updates ticket statuses per stage. Posts quality findings and recap summaries as comments. Mid-run failures retry once, then degrade silently. | Orchestrator, planner, quality gate, retrospective |
| **Context7** | Documentation lookup for migration guides, breaking changes, and API references. Powers `fg-140-deprecation-refresh` (PREFLIGHT) and `version-compat-reviewer` (REVIEW). | Migration planner, deprecation refresh, version compat reviewer, implementer |
| **Playwright** | Preview/staging deployment validation before merge. Visual regression checks. | Preview validator |
| **Slack** | Notifications and status updates (configured via consuming project). | PR builder, retrospective |
| **Figma** | Design reference and component mapping (configured via consuming project). | Frontend reviewer |

Configure Linear integration in `.claude/forge.local.md` under the `linear:` section (disabled by default).

## Setup details

After running the [Quick start](#quick-start) above, customize your project:

### Configure your project

Open `.claude/forge.local.md` and set:
- `commands.build`, `commands.test`, etc. to match your build tool
- `scaffolder.patterns` to match your directory structure
- `quality_gate` batches and `inline_checks` for your review needs
- `context7_libraries` for the frameworks your project uses

Add `.forge/` to `.gitignore`:

```bash
echo ".forge/" >> .gitignore
```

<details>
<summary>Manual setup (without /forge-init)</summary>

```bash
# Copy the module's local template (replace <module> with your framework)
cp .claude/plugins/forge/modules/frameworks/<module>/local-template.md .claude/forge.local.md
cp .claude/plugins/forge/modules/frameworks/<module>/forge-config-template.md .claude/forge-config.md
touch .claude/forge-log.md
```

</details>

### Usage examples

```bash
# Full pipeline run
/forge-run Add plan comment feature
/forge-run Fix 404 on client group endpoint

# Dry-run (PREFLIGHT through VALIDATE — no worktree, no Linear tickets, no file changes)
/forge-run --dry-run "Add user dashboard"

# Resume from a specific stage
/forge-run "Add plan versioning" --from=implement
```

## How it works

### Three-layer architecture

```
+---------------------------+
|   Project config          |  .claude/forge.local.md (static)
|   (.claude/)              |  .claude/forge-config.md (mutable, auto-tuned)
|                           |  .claude/forge-log.md (learnings + run history)
+---------------------------+
|   Module                  |  modules/ (21 frameworks, 15 languages, 19 testing,
|   (conventions, rules,    |  15 crosscutting layers incl. build-systems,
|    deprecations, scripts) |  ci-cd, container-orchestration, documentation, code-quality)
|                           |  conventions.md, rules-override.json, etc.
+---------------------------+
|   Shared core             |  agents/ (32 pipeline + review agents)
|   (orchestrator, stages,  |  shared/ (contracts, check engine, learnings,
|    scoring, state)        |  recovery, graph, discovery)
|                           |  hooks/ (check engine, checkpoint, feedback capture)
|                           |  skills/ (18 user-facing commands)
+---------------------------+
```

**Resolution order** for parameters: project config (`forge-config.md`) overrides module defaults (`local-template.md`) which override plugin defaults.

### Stage flow

The orchestrator (`fg-100-orchestrator`) drives a linear flow from Preflight through Learn, with retry loops:

- **Plan revision**: Validate returns REVISE, loops back to Plan (max 2 retries)
- **Build/lint fix**: Verify Phase A fails, auto-fixes, and retries (max 3 loops)
- **Test fix**: Verify Phase B fails, dispatches implementer, retries tests (max 2 cycles)
- **Quality fix**: Review score below 100, dispatches implementer, rescores (max 2 cycles)
- **PR rejection**: User rejects PR, feedback captured, re-enters Implement stage

The pipeline pauses and escalates to the user when:
- Risk exceeds the `auto_proceed` threshold
- Validator returns NO-GO
- Max retries are exhausted at any stage

## Configuration

### `forge.local.md` (static project config)

Defines the project's identity and tooling. Checked into git. Rarely changes.

Key sections:
- `components` -- project identity (`language`, `framework`, `variant`, `testing`)
- `commands` -- build, lint, test, format commands
- `scaffolder.patterns` -- file path templates for code generation
- `quality_gate` -- review agent batches and inline checks
- `test_gate` -- test command and analysis agents
- `conventions_file` -- path to module conventions
- `context7_libraries` -- frameworks for documentation prefetch
- `linear` -- Linear integration settings (disabled by default)

### `forge-config.md` (mutable runtime config)

Tunable parameters that the retrospective agent updates after each run. Also checked into git.

Key sections:
- `max_fix_loops`, `max_review_loops` -- retry limits
- `total_retries_max` -- global retry budget ceiling (default 10, range 5-30)
- `oscillation_tolerance` -- score regression tolerance before escalation (default 5, range 0-20)
- `auto_proceed_risk` -- highest risk level for autonomous operation
- `Domain Hotspots` -- frequently problematic domains (auto-populated)
- `Metrics` -- cross-run statistics (total runs, success rate, averages)
- `Auto-Tuning Rules` -- conditions under which the retrospective adjusts parameters

## Testing

The plugin includes a 4-tier test suite covering structural integrity, shell script behavior, document contracts, and multi-script integration.

```bash
# Run all tests (~357 tests, ~30s)
./tests/run-all.sh

# Run individual tiers
./tests/run-all.sh structural   # Plugin integrity (39 checks, no bats needed)
./tests/run-all.sh unit         # Shell script behavior (98 tests)
./tests/run-all.sh contract     # Document contract compliance (151 tests)
./tests/run-all.sh scenario     # Multi-script integration (72 tests)
```

## Agents

32 agents organized by pipeline stage and cross-cutting concerns.

### Pipeline agents (shared)

| Agent                         | Stage        | Role                                                              |
|-------------------------------|--------------|-------------------------------------------------------------------|
| `fg-010-shaper`               | Pre-pipeline | Feature spec shaping (epics, stories, AC)                         |
| `fg-050-project-bootstrapper` | Pre-pipeline | Bootstraps new projects with module scaffolding and config        |
| `fg-100-orchestrator`         | All          | Coordinates the 10-stage lifecycle, manages state and recovery    |
| `fg-130-docs-discoverer`      | 0 Preflight  | Discovers and indexes project documentation                       |
| `fg-140-deprecation-refresh`  | 0 Preflight  | Refreshes `known-deprecations.json` via Context7                  |
| `fg-150-test-bootstrapper`    | 0 Preflight  | Bootstraps test coverage when below threshold                     |
| `fg-160-migration-planner`    | 0 Preflight  | Library/framework migration planning                              |
| `fg-200-planner`              | 2 Plan       | Decomposes requirements into risk-assessed plans with stories and tasks |
| `fg-210-validator`            | 3 Validate   | Validates plans across 7 perspectives, returns GO/REVISE/NO-GO   |
| `fg-250-contract-validator`   | 3 Validate   | Cross-repo API contract breaking change detection                 |
| `fg-300-implementer`          | 4 Implement  | TDD implementation -- tests first (RED), implement (GREEN), refactor |
| `fg-310-scaffolder`           | 4 Implement  | Generates boilerplate with correct structure and TODO markers     |
| `fg-320-frontend-polisher`    | 4 Implement  | Creative frontend polish (animations, responsive, dark mode)      |
| `fg-350-docs-generator`       | 7 Docs       | Generates/updates documentation, ADRs, changelogs, API specs     |
| `fg-400-quality-gate`         | 6 Review     | Multi-batch quality coordinator with scoring and fix cycles       |
| `fg-500-test-gate`            | 5 Verify     | Test execution and coverage analysis coordinator                  |
| `fg-600-pr-builder`           | 8 Ship       | Creates branch, commits, and PR with quality gate results         |
| `fg-650-preview-validator`    | 8 Ship       | Preview deployment validation (Lighthouse, visual regression)     |
| `fg-700-retrospective`        | 9 Learn      | Post-run analysis, learning extraction, config auto-tuning        |
| `fg-710-feedback-capture`     | 9 Learn      | Records user corrections as structured feedback for future runs   |
| `fg-720-recap`                | 9 Learn      | Generates a human-readable summary of the pipeline run            |

### Cross-cutting review agents

| Agent | Role |
|---|---|
| `architecture-reviewer` | Architecture patterns, SRP, DIP, boundaries |
| `security-reviewer` | OWASP, auth, injection, secrets |
| `frontend-reviewer` | Frontend code quality, conventions, framework rules |
| `frontend-design-reviewer` | Design system compliance, visual hierarchy, Figma comparison |
| `frontend-a11y-reviewer` | WCAG 2.2 AA deep audits (contrast, ARIA, focus, touch targets) |
| `frontend-performance-reviewer` | Bundle size, rendering, lazy loading, code splitting |
| `backend-performance-reviewer` | DB queries, caching, algorithms, N+1 |
| `version-compat-reviewer` | Dependency conflicts, language features, runtime API removals |
| `infra-deploy-reviewer` | K8s, Helm, Terraform, Docker configuration |
| `infra-deploy-verifier` | Deployment health verification |
| `docs-consistency-reviewer` | Documentation accuracy, cross-doc consistency, decision/constraint violations |

## Adding a new module

To support a new framework (e.g., `fastapi`):

### 1. Create the directory structure

```
modules/frameworks/fastapi/
  conventions.md              # Agent-readable framework conventions (must include Dos/Don'ts)
  local-template.md           # Project config template (YAML frontmatter + context)
  forge-config-template.md    # Runtime config template (must include total_retries_max, oscillation_tolerance)
  rules-override.json         # Module-specific rule overrides for the check engine
  known-deprecations.json     # Registry of deprecated APIs (schema v2, seed with 5-15 entries)
  scripts/                    # Optional verification scripts (must be executable with shebang)
  hooks/                      # Optional guard hooks (must be executable with shebang)
```

### 2. Create a learnings file

Add `shared/learnings/fastapi.md` to track module-specific learnings across runs. For new languages, also add `shared/learnings/{lang}.md`. For new testing frameworks, also add `shared/learnings/{test-framework}.md`.

### 3. Update test minimum counts

Module lists are auto-discovered from disk via `tests/lib/module-lists.bash`. Bump the corresponding `MIN_*` constant (e.g., `MIN_FRAMEWORKS`) to catch accidental deletions. Skipping this step means the new module is tested but accidental removal goes undetected.

### 4. Wire agents into the local template

Reference the cross-cutting review agents (`architecture-reviewer`, `security-reviewer`, etc.) and any module-specific inline checks in the `quality_gate.batch_N` section of the local template.

### 5. Naming conventions

- Module directory: `modules/frameworks/{name}`, lowercase with hyphens (`fastapi`, `go-stdlib`)
- Review agents: descriptive names without module prefix (`architecture-reviewer`, `security-reviewer`)
- Pipeline agents: `fg-{NNN}-{role}` (shared, not module-specific)
- Scripts: `check-{what}.sh` or `{what}-guard.sh`

## File inventory

<details>
<summary>Full directory structure</summary>

```
forge/
  .claude-plugin/
    plugin.json                         # Plugin manifest (v1.2.0)
    marketplace.json                    # Marketplace catalog for quantumbitcz
  agents/                               # 32 agent definitions (YAML frontmatter + instructions)
    fg-010-shaper.md
    fg-050-project-bootstrapper.md
    fg-100-orchestrator.md
    fg-130-docs-discoverer.md
    fg-140-deprecation-refresh.md
    fg-150-test-bootstrapper.md
    fg-160-migration-planner.md
    fg-200-planner.md
    fg-210-validator.md
    fg-250-contract-validator.md
    fg-300-implementer.md
    fg-310-scaffolder.md
    fg-320-frontend-polisher.md
    fg-400-quality-gate.md
    fg-500-test-gate.md
    fg-600-pr-builder.md
    fg-650-preview-validator.md
    fg-700-retrospective.md
    fg-710-feedback-capture.md
    fg-720-recap.md
    architecture-reviewer.md
    security-reviewer.md
    frontend-reviewer.md
    frontend-design-reviewer.md
    frontend-a11y-reviewer.md
    frontend-performance-reviewer.md
    backend-performance-reviewer.md
    version-compat-reviewer.md
    infra-deploy-reviewer.md
    infra-deploy-verifier.md
    docs-consistency-reviewer.md
  skills/                               # 18 user-facing skills
    bootstrap-project/
    codebase-health/
    deploy/
    docs-generate/
    graph-init/
    graph-query/
    graph-rebuild/
    graph-status/
    migration/
    forge-history/
    forge-init/
    forge-reset/
    forge-rollback/
    forge-run/
    forge-shape/
    forge-status/
    security-audit/
    verify/
  hooks/                                # 3 hooks (registered in hooks.json)
    hooks.json                          #   Hook manifest
    forge-checkpoint.sh                 #   PostToolUse on Skill -- saves checkpoint
    feedback-capture.sh                 #   Stop -- captures user feedback on session exit
  shared/
    agent-communication.md              # Inter-agent data flow contract
    agent-philosophy.md                 # Critical thinking principles for all agents
    error-taxonomy.md                   # 20 standard error types with recovery strategies
    frontend-design-theory.md           # Design theory guardrails (Gestalt, color, typography, motion)
    scoring.md                          # Quality scoring formula and verdict thresholds
    stage-contract.md                   # Stage definitions, entry/exit conditions, data flow
    state-schema.md                     # State schema v1.2.0
    checks/                             # 3-layer generalized check engine
      engine.sh                         #   Main engine script (--hook, --verify, --review modes)
      test-engine.sh                    #   Engine test harness
      output-format.md                  #   Standardized output format spec
      layer-1-fast/                     #   Regex-based pattern matching (sub-second)
        run-patterns.sh                 #     Pattern matching entry point
      layer-2-linter/                   #   Framework-aware linter adapters
        run-linter.sh                   #     Linter dispatch entry point
        adapters/                       #     Per-language linter adapters
        config/                         #     Linter configurations
        defaults/                       #     Default linter settings
      layer-3-agent/                    #   Redirect stubs (agents live in agents/)
        deprecation-refresh.md          #     -> agents/fg-140-deprecation-refresh.md
        version-compat.md               #     -> agents/version-compat-reviewer.md
        known-deprecations/
      examples/                         #   Per-language pattern examples
        c/ go/ java/ kotlin/
        python/ rust/ swift/ typescript/
    discovery/                          # Cross-repo project discovery
      detect-project-type.sh            #   Framework/language auto-detection
      discover-projects.sh              #   Multi-repo discovery
    graph/                              # Knowledge graph (Neo4j, enabled by default)
      schema.md                         #   Node types, relationships, lifecycle
      query-patterns.md                 #   Cypher query templates
      seed.cypher                       #   Pre-computed module relationship seed
      generate-seed.sh                  #   Generates seed.cypher from module data
      canonical-pairings.json           #   Module relationship data
      dependency-map.json               #   Module dependency data
      build-project-graph.sh            #   Build graph from codebase
      enrich-symbols.sh                 #   Enrich graph with symbol analysis
      incremental-update.sh             #   Incremental graph updates
      neo4j-health.sh                   #   Neo4j health checks
      docker-compose.neo4j.yml          #   Docker-managed Neo4j instance
    learnings/                          # Per-module learnings + schemas
      README.md                         #   Learnings system overview
      {module-name}.md                  #   Framework, language, testing, and layer learnings files
      agent-effectiveness-template.md   #   Template for agent performance tracking
      rule-learning-schema.json         #   Check rule evolution tracking
      agent-effectiveness-schema.json   #   Agent performance tracking
    recovery/                           # Recovery engine + strategies
      recovery-engine.md                #   7 strategies, weighted budget (ceiling 5.5)
      strategies/                       #   Individual strategy definitions
        transient-retry.md (0.5)
        tool-diagnosis.md (1.0)
        state-reconstruction.md (1.5)
        agent-reset.md (1.0)
        dependency-health.md (1.0)
        resource-cleanup.md (0.5)
        graceful-stop.md (0.0)
      health-checks/                    #   Pre-stage validation scripts
        pre-stage-health.sh
        dependency-check.sh
  modules/                              # 21 frameworks + 15 languages + 19 testing + 15 crosscutting layers
    frameworks/                         # Per-framework conventions and config
      angular/ aspnet/ axum/ django/ embedded/ express/ fastapi/
      gin/ go-stdlib/ jetpack-compose/ k8s/
      kotlin-multiplatform/ nestjs/ nextjs/ react/ spring/
      sveltekit/ svelte/ swiftui/ vapor/ vue/
    languages/                          # Per-language idioms, type conventions, and baseline rules
    testing/                            # Per-testing-framework generic test patterns
    databases/                          # Database engine best practices
    persistence/                        # ORM/mapping patterns
    migrations/                         # Schema migration tool patterns
    api-protocols/                      # API protocol patterns (REST, GraphQL, gRPC, WebSocket)
    messaging/                          # Event-driven patterns
    caching/                            # Cache strategy patterns
    search/                             # Full-text search patterns
    storage/                            # Object storage patterns
    auth/                               # Authentication/authorization patterns
    observability/                      # Metrics, tracing, and logging patterns
    build-systems/                      # Build tool patterns (Gradle, Maven, CMake, Bazel, etc.)
    ci-cd/                              # CI/CD platform patterns (GitHub Actions, GitLab CI, etc.)
    container-orchestration/            # Container/orchestration patterns (Docker, Helm, ArgoCD, etc.)
    documentation/                      # Documentation conventions (doc structure, ADR patterns, cross-references)
    code-quality/                       # Code quality tooling (~70 tools: linters, formatters, coverage, security scanners)
    (each framework contains: conventions.md, local-template.md,
     forge-config-template.md, rules-override.json,
     known-deprecations.json)
  tests/                                # 4-tier test suite (~357 tests)
    run-all.sh                          #   Test runner (all tiers or individual)
    validate-plugin.sh                  #   Structural validation (no bats needed)
    fixtures/                           #   Test fixture data
    helpers/                            #   Shared test helpers
    lib/                                #   bats-core, bats-assert, bats-support, module-lists.bash
  CLAUDE.md
  CONTRIBUTING.md
  SECURITY.md
  LICENSE
```

</details>

## License

Proprietary -- QuantumBit s.r.o. See [LICENSE](LICENSE).
