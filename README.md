# dev-pipeline

Reusable autonomous development pipeline for Claude Code.

A Claude Code plugin that orchestrates a 10-stage development pipeline with framework-specific modules. Point it at a feature, bugfix, or refactor, and it handles exploration, planning, implementation (TDD), verification, quality review, documentation, PR creation, and self-improvement -- fully autonomously.

## What this is

`dev-pipeline` is a shared plugin (v1.0.0) installable from the `quantumbitcz` marketplace. It provides:

- A **pipeline orchestrator** that coordinates 10 stages from requirement to pull request
- **Framework modules** with conventions, review agents, scaffolder patterns, deprecation registries, and verification scripts
- **Self-improving infrastructure** that tracks metrics, extracts learnings, and auto-tunes parameters across runs

## Key features

- **Worktree isolation** -- All implementation runs in a git worktree (`.pipeline/worktree`). Your working tree is never modified during pipeline execution.
- **Self-healing recovery** -- 7 recovery strategies with weighted budget (transient-retry, tool-diagnosis, state-reconstruction, agent-reset, dependency-health, resource-cleanup, graceful-stop). Budget ceiling: 5.0 total weight.
- **3-layer check engine** -- Fires on every Edit/Write via PostToolUse hook. Layer 1: fast regex patterns (sub-second). Layer 2: framework-aware linters. Layer 3: AI-driven agents dispatched by the orchestrator (`pl-140-deprecation-refresh` during PREFLIGHT, `version-compat-reviewer` during REVIEW) with version-gated rules.
- **PREEMPT system** -- Learnings from past runs are proactively applied to matching domains in new runs. Confidence decay prevents stale learnings from persisting.
- **Adaptive MCP detection** -- Auto-detects available MCPs (Linear, Playwright, Slack, Context7, Figma) at PREFLIGHT and adapts behavior per stage. No MCP is required.
- **Version-aware deprecation rules** -- Schema v2 registries with `applies_from`, `removed_in`, and `applies_to` fields. Rules only fire when the project version matches.
- **Concurrent run protection** -- `.pipeline/.lock` prevents parallel pipeline runs on the same project. Stale locks are auto-cleaned via PID check and 24-hour timeout.
- **Global retry budget** -- All retry loops share a cumulative counter (configurable max, default 10) to prevent unbounded retry cascades.
- **Frontend design quality** -- Creative polish agent (`pl-320-frontend-polisher`) adds animations, micro-interactions, and visual refinement after implementation. Design review (`frontend-design-reviewer`) and accessibility review (`frontend-a11y-reviewer`) validate design system compliance, responsive behavior (375px/768px/1280px), dark mode, WCAG 2.2 AA, and visual coherence. Design theory guardrails (`shared/frontend-design-theory.md`) encode Gestalt principles, visual hierarchy, color theory, typography, spacing, motion, and anti-AI-look standards.

### The 10 stages

| # | Stage | What happens |
|---|-------|-------------|
| 0 | Preflight | Load config, detect interrupted runs, detect versions, apply learnings |
| 1 | Explore | Map domain models, tests, and patterns relevant to the requirement |
| 2 | Plan | Risk-assessed implementation plan with stories, tasks, parallel groups |
| 3 | Validate | 6-perspective validation (architecture, security, edge cases, tests, conventions, approach quality) |
| 4 | Implement | TDD loop per task -- scaffold, write tests (RED), implement (GREEN), refactor |
| 5 | Verify | Build, lint, static analysis, full test suite |
| 6 | Review | Multi-agent quality review with scoring and fix cycles |
| 7 | Docs | Update CLAUDE.md, KDoc/TSDoc on new public interfaces |
| 8 | Ship | Branch, commit, PR with quality gate results |
| 9 | Learn | Retrospective analysis, config tuning, trend tracking |

## Available skills

13 skills provide the user-facing interface to the pipeline and its subsystems.

| Skill | Description |
|-------|-------------|
| `/pipeline-run` | Main entry point -- runs the full 10-stage pipeline |
| `/pipeline-init` | Initialize project config files (auto-detects framework module) |
| `/pipeline-status` | Show current pipeline state, quality score, retry budgets, recovery budget, Linear sync, and detected versions |
| `/pipeline-reset` | Clear pipeline run state (including lock and skip counter) while preserving accumulated learnings |
| `/pipeline-rollback` | Safely rollback pipeline changes (4 modes: worktree, post-merge, Linear, state-only) |
| `/pipeline-history` | View quality score trends, agent effectiveness, and PREEMPT health across runs |
| `/migration` | Plan and execute library/framework migrations (auto-detect versions, explicit versions, `upgrade all`, `check` dry-run, Context7 integration) |
| `/bootstrap-project` | Scaffold a new project from a module template |
| `/deploy` | Trigger deployment workflow via infra-deploy agents (staging, production, preview, rollback, status) |
| `/pipeline-shape` | Collaboratively shape features into structured specs with epics, stories, and acceptance criteria |
| `/security-audit` | Run module-appropriate security scanners (npm audit, cargo audit, govulncheck, trivy, etc.) |
| `/codebase-health` | Run the check engine in full review mode for a comprehensive health report |
| `/verify` | Quick build + lint + test check without a full pipeline run |

## Available modules

17 framework modules under `modules/frameworks/`, 9 language files under `modules/languages/`, and 11 testing framework files under `modules/testing/`. Each framework module provides `conventions.md`, `local-template.md`, `pipeline-config-template.md`, `rules-override.json`, and `known-deprecations.json` (schema v2 deprecation registry). Some modules include additional scripts, hooks, variants, or framework-specific testing patterns.

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

All modules include conventions with a Dos/Don'ts section, config templates, check engine rule overrides, and a version-aware deprecation registry (`known-deprecations.json`).

## Integrations

The pipeline auto-detects available MCP servers at PREFLIGHT and adapts its behavior. No integration is required -- each one is optional and the pipeline degrades gracefully when unavailable.

| Integration | What it does | Used by |
|-------------|-------------|---------|
| **Linear** | Creates Epics, Stories, and Tasks during PLAN. Updates ticket statuses per stage. Posts quality findings and recap summaries as comments. Mid-run failures retry once, then degrade silently. | Orchestrator, planner, quality gate, retrospective |
| **Context7** | Documentation lookup for migration guides, breaking changes, and API references. Powers `pl-140-deprecation-refresh` (PREFLIGHT) and `version-compat-reviewer` (REVIEW). | Migration planner, deprecation refresh, version compat reviewer, implementer |
| **Playwright** | Preview/staging deployment validation before merge. Visual regression checks. | Preview validator |
| **Slack** | Notifications and status updates (configured via consuming project). | PR builder, retrospective |
| **Figma** | Design reference and component mapping (configured via consuming project). | Frontend reviewer |

Configure Linear integration in `.claude/dev-pipeline.local.md` under the `linear:` section (disabled by default).

## Quick setup

### 1. Install from marketplace

```bash
# Add the marketplace (one-time)
/plugin marketplace add quantumbitcz/dev-pipeline

# Install the plugin
/plugin install dev-pipeline@quantumbitcz
```

Or use the interactive plugin manager: `/plugin` -> Discover tab -> select `dev-pipeline`.

<details>
<summary>Alternative: install as Git submodule</summary>

```bash
git submodule add https://github.com/quantumbitcz/dev-pipeline.git .claude/plugins/dev-pipeline
```

Then add to `.claude/settings.json`:

```json
{
  "plugins": [".claude/plugins/dev-pipeline"]
}
```

</details>

### 2. Initialize project config

```bash
/pipeline-init
```

This creates `.claude/dev-pipeline.local.md`, `.claude/pipeline-config.md`, and `.claude/pipeline-log.md` for your project. It auto-detects the framework module.

<details>
<summary>Manual setup (if you prefer)</summary>

```bash
# Copy the module's local template (replace <module> with your framework)
cp .claude/plugins/dev-pipeline/modules/<module>/local-template.md .claude/dev-pipeline.local.md
cp .claude/plugins/dev-pipeline/modules/<module>/pipeline-config-template.md .claude/pipeline-config.md
touch .claude/pipeline-log.md
```

</details>

### 3. Edit the local config

Open `.claude/dev-pipeline.local.md` and customize:
- `commands.build`, `commands.test`, etc. to match your project's build tool
- `scaffolder.patterns` to match your project's directory structure
- `quality_gate` batches and `inline_checks` for your review needs
- `context7_libraries` for the frameworks your project uses

### 4. Add `.pipeline/` to `.gitignore`

```bash
echo ".pipeline/" >> .gitignore
```

### 5. Run it

```bash
/pipeline-run Add plan comment feature
/pipeline-run Fix 404 on client group endpoint
/pipeline-run Refactor booking validation
```

Dry-run (PREFLIGHT through VALIDATE without implementation -- no worktree, no Linear tickets, no file changes):

```bash
/pipeline-run --dry-run "Add user dashboard"
```

Resume from a specific stage:

```bash
/pipeline-run "Add plan versioning" --from=implement
```

## How it works

### Three-layer architecture

```
+---------------------------+
|   Project config          |  .claude/dev-pipeline.local.md (static)
|   (.claude/)              |  .claude/pipeline-config.md (mutable, auto-tuned)
|                           |  .claude/pipeline-log.md (learnings + run history)
+---------------------------+
|   Module                  |  modules/ (17 framework modules)
|   (conventions, rules,    |  conventions.md, rules-override.json
|    deprecations, scripts) |  known-deprecations.json, local-template.md
|                           |  pipeline-config-template.md
+---------------------------+
|   Shared core             |  agents/pl-*.md (pipeline agents)
|   (orchestrator, stages,  |  shared/ (contracts, check engine, learnings, recovery)
|    scoring, state)        |  hooks/ (check engine, checkpoint, feedback capture)
|                           |  skills/ (12 user-facing commands)
+---------------------------+
```

**Resolution order** for parameters: project config (`pipeline-config.md`) overrides module defaults (`local-template.md`) which override plugin defaults.

### Stage flow

The orchestrator (`pl-100-orchestrator`) drives a linear flow from Preflight through Learn, with retry loops:

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

### `dev-pipeline.local.md` (static project config)

Defines the project's identity and tooling. Checked into git. Rarely changes.

Key sections:
- `project_type` / `framework` / `module` -- project identity
- `commands` -- build, lint, test, format commands
- `scaffolder.patterns` -- file path templates for code generation
- `quality_gate` -- review agent batches and inline checks
- `test_gate` -- test command and analysis agents
- `conventions_file` -- path to module conventions
- `context7_libraries` -- frameworks for documentation prefetch
- `linear` -- Linear integration settings (disabled by default)

### `pipeline-config.md` (mutable runtime config)

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
# Run all tests (~233 tests, ~30s)
./tests/run-all.sh

# Run individual tiers
./tests/run-all.sh structural   # Plugin integrity (25 checks, no bats needed)
./tests/run-all.sh unit         # Shell script behavior (82 tests)
./tests/run-all.sh contract     # Document contract compliance (87 tests)
./tests/run-all.sh scenario     # Multi-script integration (39 tests)
```

## Agents

29 agents organized by pipeline stage and cross-cutting concerns.

### Pipeline agents (shared)

| Agent                         | Stage        | Role                                                              |
|-------------------------------|--------------|-------------------------------------------------------------------|
| `pl-010-shaper`               | Pre-pipeline | Feature spec shaping (epics, stories, AC)                         |
| `pl-050-project-bootstrapper` | 0 Preflight  | Bootstraps new projects with module scaffolding and config        |
| `pl-100-orchestrator`         | All          | Coordinates the 10-stage lifecycle, manages state and recovery    |
| `pl-140-deprecation-refresh`  | 0 Preflight  | Refreshes `known-deprecations.json` via Context7                  |
| `pl-150-test-bootstrapper`    | 0 Preflight  | Bootstraps test coverage when below threshold                     |
| `pl-160-migration-planner`    | 0 Preflight  | Library/framework migration planning                              |
| `pl-200-planner`              | 2 Plan       | Decomposes requirements into risk-assessed plans with stories and tasks |
| `pl-210-validator`            | 3 Validate   | Validates plans across 6 perspectives, returns GO/REVISE/NO-GO   |
| `pl-250-contract-validator`   | 3 Validate   | Cross-repo API contract breaking change detection                 |
| `pl-300-implementer`          | 4 Implement  | TDD implementation -- tests first (RED), implement (GREEN), refactor |
| `pl-310-scaffolder`           | 4 Implement  | Generates boilerplate with correct structure and TODO markers     |
| `pl-320-frontend-polisher`    | 4 Implement  | Creative frontend polish (animations, responsive, dark mode)      |
| `pl-400-quality-gate`         | 6 Review     | Multi-batch quality coordinator with scoring and fix cycles       |
| `pl-500-test-gate`            | 5 Verify     | Test execution and coverage analysis coordinator                  |
| `pl-600-pr-builder`           | 8 Ship       | Creates branch, commits, and PR with quality gate results         |
| `pl-650-preview-validator`    | 8 Ship       | Preview deployment validation (Lighthouse, visual regression)     |
| `pl-700-retrospective`        | 9 Learn      | Post-run analysis, learning extraction, config auto-tuning        |
| `pl-710-feedback-capture`     | 9 Learn      | Records user corrections as structured feedback for future runs   |
| `pl-720-recap`                | 9 Learn      | Generates a human-readable summary of the pipeline run            |

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

## Adding a new module

To support a new framework (e.g., `fastapi`):

### 1. Create the directory structure

```
modules/frameworks/fastapi/
  conventions.md              # Agent-readable framework conventions (must include Dos/Don'ts)
  local-template.md           # Project config template (YAML frontmatter + context)
  pipeline-config-template.md # Runtime config template (must include total_retries_max, oscillation_tolerance)
  rules-override.json         # Module-specific rule overrides for the check engine
  known-deprecations.json     # Registry of deprecated APIs (schema v2, seed with 5-15 entries)
  scripts/                    # Optional verification scripts (must be executable with shebang)
  hooks/                      # Optional guard hooks (must be executable with shebang)
```

### 2. Create a learnings file

Add `shared/learnings/fastapi.md` to track module-specific learnings across runs.

### 3. Wire agents into the local template

Reference the cross-cutting review agents (`architecture-reviewer`, `security-reviewer`, etc.) and any module-specific inline checks in the `quality_gate.batch_N` section of the local template.

### 4. Naming conventions

- Module directory: `modules/frameworks/{name}`, lowercase with hyphens (`fastapi`, `go-stdlib`)
- Review agents: descriptive names without module prefix (`architecture-reviewer`, `security-reviewer`)
- Pipeline agents: `pl-{NNN}-{role}` (shared, not module-specific)
- Scripts: `check-{what}.sh` or `{what}-guard.sh`

## File inventory

<details>
<summary>Full directory structure</summary>

```
dev-pipeline/
  .claude-plugin/
    plugin.json                         # Plugin manifest (v1.0.0)
    marketplace.json                    # Marketplace catalog for quantumbitcz
  agents/                               # 29 agent definitions (YAML frontmatter + instructions)
    pl-010-shaper.md
    pl-050-project-bootstrapper.md
    pl-100-orchestrator.md
    pl-140-deprecation-refresh.md
    pl-150-test-bootstrapper.md
    pl-160-migration-planner.md
    pl-200-planner.md
    pl-210-validator.md
    pl-250-contract-validator.md
    pl-300-implementer.md
    pl-310-scaffolder.md
    pl-320-frontend-polisher.md
    pl-400-quality-gate.md
    pl-500-test-gate.md
    pl-600-pr-builder.md
    pl-650-preview-validator.md
    pl-700-retrospective.md
    pl-710-feedback-capture.md
    pl-720-recap.md
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
  skills/                               # 13 user-facing skills
    bootstrap-project/
    codebase-health/
    deploy/
    migration/
    pipeline-history/
    pipeline-init/
    pipeline-reset/
    pipeline-rollback/
    pipeline-run/
    pipeline-shape/
    pipeline-status/
    security-audit/
    verify/
  hooks/                                # 3 hooks (registered in hooks.json)
    hooks.json                          #   Hook manifest
    pipeline-checkpoint.sh              #   PostToolUse on Skill -- saves checkpoint
    feedback-capture.sh                 #   Stop -- captures user feedback on session exit
  shared/
    agent-communication.md              # Inter-agent data flow contract
    agent-philosophy.md                 # Critical thinking principles for all agents
    error-taxonomy.md                   # 15 standard error types with recovery strategies
    frontend-design-theory.md           # Design theory guardrails (Gestalt, color, typography, motion)
    scoring.md                          # Quality scoring formula and verdict thresholds
    stage-contract.md                   # Stage definitions, entry/exit conditions, data flow
    state-schema.md                     # State schema v1.0.0 (clean break from prior versions)
    checks/                             # 3-layer generalized check engine
      engine.sh                         #   Main engine script (--hook mode, --dry-run mode)
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
        deprecation-refresh.md          #     -> agents/pl-140-deprecation-refresh.md
        version-compat.md               #     -> agents/version-compat-reviewer.md
        known-deprecations/
      examples/                         #   Per-language pattern examples
        c/ go/ java/ kotlin/
        python/ rust/ swift/ typescript/
    learnings/                          # Per-module learnings + schemas
      README.md                         #   Learnings system overview
      {framework-name}.md               #   17+ framework learnings files
      agent-effectiveness-template.md   #   Template for agent performance tracking
      rule-learning-schema.json         #   Check rule evolution tracking
      agent-effectiveness-schema.json   #   Agent performance tracking
    recovery/                           # Recovery engine + strategies
      recovery-engine.md                #   7 strategies, weighted budget (ceiling 5.0)
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
  modules/                              # 17 framework modules + 9 languages + 11 testing
    frameworks/                         # Per-framework conventions and config
      aspnet/ axum/ django/ embedded/ express/ fastapi/
      gin/ go-stdlib/ jetpack-compose/ k8s/
      kotlin-multiplatform/ nextjs/ react/ spring/
      sveltekit/ swiftui/ vapor/
    languages/                          # Per-language deprecation registries
    testing/                            # Per-testing-framework deprecation registries
    (each framework contains: conventions.md, local-template.md,
     pipeline-config-template.md, rules-override.json,
     known-deprecations.json)
  tests/                                # 4-tier test suite (~233 tests)
    run-all.sh                          #   Test runner (all tiers or individual)
    validate-plugin.sh                  #   Structural validation (no bats needed)
    fixtures/                           #   Test fixture data
    helpers/                            #   Shared test helpers
    lib/                                #   bats-core, bats-assert, bats-support
  CLAUDE.md
  CONTRIBUTING.md
  SECURITY.md
  LICENSE
```

</details>

## License

Proprietary -- QuantumBit s.r.o. See [LICENSE](LICENSE).
