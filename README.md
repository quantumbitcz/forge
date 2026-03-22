# dev-pipeline

Reusable autonomous development pipeline for Claude Code.

A Claude Code plugin that orchestrates a 10-stage development pipeline with framework-specific modules. Point it at a feature, bugfix, or refactor and it handles exploration, planning, implementation (TDD), verification, quality review, documentation, PR creation, and self-improvement -- fully autonomously.

## What this is

`dev-pipeline` is a shared plugin installable from the `quantumbitcz` marketplace. It provides:

- A **pipeline orchestrator** that coordinates 10 stages from requirement to pull request
- **Framework modules** with conventions, review agents, scaffolder patterns, and verification scripts
- **Self-improving infrastructure** that tracks metrics, extracts learnings, and auto-tunes parameters across runs

### The 10 stages

| # | Stage | What happens |
|---|-------|-------------|
| 0 | Preflight | Load config, detect interrupted runs, apply learnings |
| 1 | Explore | Map domain models, tests, and patterns relevant to the requirement |
| 2 | Plan | Risk-assessed implementation plan with stories, tasks, parallel groups |
| 3 | Validate | 5-perspective validation (architecture, security, edge cases, tests, conventions) |
| 4 | Implement | TDD loop per task -- scaffold, write tests (RED), implement (GREEN), refactor |
| 5 | Verify | Build, lint, static analysis, full test suite |
| 6 | Review | Multi-agent quality review with scoring and fix cycles |
| 7 | Docs | Update CLAUDE.md, KDoc/TSDoc on new public interfaces |
| 8 | Ship | Branch, commit, PR with quality gate results |
| 9 | Learn | Retrospective analysis, config tuning, trend tracking |

## Available modules

12 framework modules. Each module provides `conventions.md`, `local-template.md`, `pipeline-config-template.md`, and `rules-override.json`. Some modules include additional scripts, hooks, or tooling.

### kotlin-spring

For hexagonal architecture (ports & adapters) projects using Kotlin, Spring Boot, WebFlux, and R2DBC.

Additional includes:
- Verification handled by the shared check engine via `rules-override.json` (pattern rules for hexagonal boundaries, type conventions, file size thresholds)

### react-vite

For React + Vite + TypeScript + shadcn/ui projects.

Additional includes:
- `known-deprecations.json` -- self-updating registry of deprecated APIs
- Suggested project commands documented in `conventions.md`: `fe-check-theme`, `fe-design-review`, `fe-react-doctor`, `fe-dark-mode-check` (live in consuming project's `.claude/commands/`, not in this plugin)

### Other modules

| Module              | Target stack                             |
|---------------------|------------------------------------------|
| `c-embedded`        | C for embedded systems                   |
| `go-stdlib`         | Go with standard library conventions     |
| `infra-k8s`         | Kubernetes infrastructure and deployment |
| `java-spring`       | Java with Spring Boot                    |
| `python-fastapi`    | Python with FastAPI                      |
| `rust-axum`         | Rust with Axum web framework             |
| `swift-ios`         | Swift for iOS applications               |
| `swift-vapor`       | Swift with Vapor server framework        |
| `typescript-node`   | TypeScript with Node.js                  |
| `typescript-svelte` | TypeScript with SvelteKit |

## Quick setup

### 1. Install from marketplace

```bash
# Add the marketplace (one-time)
/plugin marketplace add quantumbitcz/dev-pipeline

# Install the plugin
/plugin install dev-pipeline@quantumbitcz
```

Or use the interactive plugin manager: `/plugin` → Discover tab → select `dev-pipeline`.

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
|   Module                  |  modules/ (12 framework modules)
|   (conventions, rules,    |  conventions.md, rules-override.json
|    scripts, templates)    |  local-template.md, pipeline-config-template.md
+---------------------------+
|   Shared core             |  agents/pl-*.md (pipeline agents)
|   (orchestrator, stages,  |  shared/ (contracts, check engine, learnings, recovery)
|    scoring, state)        |  hooks/ (check engine hook, checkpoint, feedback capture)
|                           |  skills/ (pipeline-run, pipeline-init, deploy, verify, etc.)
+---------------------------+
```

**Resolution order** for parameters: project config (`pipeline-config.md`) overrides module defaults (`local-template.md`) which override plugin defaults.

### Stage flow

The orchestrator (`pl-100-orchestrator`) drives a linear flow from Preflight through Learn, with retry loops:

- **Plan revision**: Validate returns REVISE, loops back to Plan (max 2 retries)
- **Build/lint fix**: Verify Phase A fails, auto-fixes and retries (max 3 loops)
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

### `pipeline-config.md` (mutable runtime config)

Tunable parameters that the retrospective agent updates after each run. Also checked into git.

Key sections:
- `max_fix_loops`, `max_review_loops` -- retry limits
- `auto_proceed_risk` -- highest risk level for autonomous operation
- `Domain Hotspots` -- frequently problematic domains (auto-populated)
- `Metrics` -- cross-run statistics (total runs, success rate, averages)
- `Auto-Tuning Rules` -- conditions under which the retrospective adjusts parameters

## Adding a new module

To support a new framework (e.g., `python-fastapi`):

### 1. Create the directory structure

```
modules/python-fastapi/
  conventions.md              # Agent-readable conventions for the framework
  local-template.md           # Project config template (YAML frontmatter + context)
  pipeline-config-template.md # Runtime config template
  rules-override.json         # Module-specific rule overrides for the check engine
  scripts/                    # Optional verification scripts (must be executable with shebang)
  hooks/                      # Optional guard hooks (must be executable with shebang)
```

### 2. Create a learnings file

Add `shared/learnings/python-fastapi.md` to track module-specific learnings across runs.

### 3. Wire agents into the local template

Reference the cross-cutting review agents (`architecture-reviewer`, `security-reviewer`, etc.) and any module-specific inline checks in the `quality_gate.batch_N` section of the local template.

### 4. Naming conventions

- Module directory: lowercase with hyphens (`python-fastapi`)
- Review agents: descriptive names without module prefix (`architecture-reviewer`, `security-reviewer`)
- Pipeline agents: `pl-{NNN}-{role}` (shared, not module-specific)
- Scripts: `check-{what}.sh` or `{what}-guard.sh`

## Agents

23 agents organized by pipeline stage and cross-cutting concerns.

### Pipeline agents (shared)

| Agent                         | Stage        | Role                                                              |
|-------------------------------|--------------|-------------------------------------------------------------------|
| `pl-050-project-bootstrapper` | 0 Preflight  | Bootstraps new projects with module scaffolding and config        |
| `pl-100-orchestrator`         | All          | Coordinates the 10-stage lifecycle, manages state and recovery    |
| `pl-150-test-bootstrapper`    | 4 Implement  | Sets up test infrastructure and frameworks for new projects       |
| `pl-160-migration-planner`    | 2 Plan       | Plans data and schema migrations as part of implementation        |
| `pl-200-planner`              | 2 Plan       | Decomposes requirements into risk-assessed plans with stories and tasks |
| `pl-210-validator`            | 3 Validate   | Validates plans across 5 perspectives, returns GO/REVISE/NO-GO   |
| `pl-250-contract-validator`   | 3 Validate   | Validates API contracts and interface compatibility               |
| `pl-300-implementer`          | 4 Implement  | TDD implementation -- tests first (RED), implement (GREEN), refactor |
| `pl-310-scaffolder`           | 4 Implement  | Generates boilerplate with correct structure and TODO markers     |
| `pl-400-quality-gate`         | 6 Review     | Multi-batch quality coordinator with scoring and fix cycles       |
| `pl-500-test-gate`            | 5 Verify     | Test execution and coverage analysis coordinator                  |
| `pl-600-pr-builder`           | 8 Ship       | Creates branch, commits, and PR with quality gate results         |
| `pl-650-preview-validator`    | 8 Ship       | Validates preview/staging deployments before merge                |
| `pl-700-retrospective`        | 9 Learn      | Post-run analysis, learning extraction, config auto-tuning        |
| `pl-710-feedback-capture`     | 9 Learn      | Records user corrections as structured feedback for future runs   |
| `pl-720-recap`                | 9 Learn      | Generates a human-readable summary of the pipeline run            |

### Cross-cutting review agents

| Agent | Role |
|---|---|
| `architecture-reviewer` | Detects architecture pattern and reviews for compliance violations |
| `security-reviewer` | Reviews code for security vulnerabilities across all languages and frameworks |
| `frontend-reviewer` | Reviews frontend code for quality, conventions, accessibility, performance |
| `infra-deploy-reviewer` | Reviews infrastructure and deployment configurations |
| `infra-deploy-verifier` | Verifies infrastructure deployments and health checks |
| `backend-performance-reviewer` | Reviews backend code for performance issues and optimization opportunities |
| `frontend-performance-reviewer` | Reviews frontend code for performance, bundle size, and rendering efficiency |

## File inventory

```
dev-pipeline/
  .claude-plugin/plugin.json  # Plugin manifest (registers hooks.json)
  agents/                     # 23 agent definitions (YAML frontmatter + instructions)
  skills/                     # 12 universal skills (pipeline-run, pipeline-init, verify, deploy, security-audit, etc.)
  hooks/                      # hooks.json + 2 hook scripts (pipeline-checkpoint.sh, feedback-capture.sh)
  shared/
    scoring.md, stage-contract.md, state-schema.md  # Contracts
    checks/                   # 3-layer generalized check engine (engine.sh, patterns, linters, agents)
    learnings/                # Per-module learnings, rule + effectiveness schemas
    recovery/                 # Recovery engine + 7 strategies + health checks
  modules/                    # 12 framework modules (conventions, templates, rules-override each)
    kotlin-spring/
    react-vite/               # + known-deprecations.json
```
