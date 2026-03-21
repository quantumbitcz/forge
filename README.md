# dev-pipeline

Reusable autonomous development pipeline for Claude Code.

A Claude Code plugin that orchestrates a 10-stage development pipeline with framework-specific modules. Point it at a feature, bugfix, or refactor and it handles exploration, planning, implementation (TDD), verification, quality review, documentation, PR creation, and self-improvement -- fully autonomously.

## What this is

`dev-pipeline` is a shared plugin that any project can install as a Git submodule. It provides:

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

### kotlin-spring

For hexagonal architecture (ports & adapters) projects using Kotlin, Spring Boot, WebFlux, and R2DBC.

Includes:
- `conventions.md` -- curated architecture and naming rules for agent consumption
- `local-template.md` -- project config template with Gradle commands, scaffolder patterns (domain model, use case, port, adapter, controller, migration, test), and quality gate batches
- `pipeline-config-template.md` -- mutable runtime parameters template
- Verification scripts: `check-antipatterns.sh` (double-bang, framework imports in core), `check-core-boundary.sh` (hexagonal layer violations), `check-file-size.sh` (files over threshold)
- Review agents: `be-hex-reviewer`, `be-security-reviewer`

### react-vite

For React + Vite + TypeScript + shadcn/ui projects.

Includes:
- `conventions.md` -- typography scale, theming rules, component patterns for agent consumption
- `local-template.md` -- project config template with Bun/Vite commands, scaffolder patterns (component, hook, API module, types, test), and quality gate batches with accessibility and type design reviewers
- `pipeline-config-template.md` -- mutable runtime parameters template
- Guard hooks: `theme-guard.sh`, `function-size-guard.sh`, `file-size-guard.sh`, `import-order-guard.sh`, `deprecation-guard.sh`
- `known-deprecations.json` -- self-updating registry of deprecated APIs
- Review agents: `fe-code-reviewer`, `fe-deprecation-scanner`
- Inline check skills: `/fe-check-theme`, `/fe-design-review`, `/fe-react-doctor`, `/fe-dark-mode-check`

## Quick setup

### 1. Add the plugin as a submodule

```bash
git submodule add https://github.com/quantumbitcz/dev-pipeline.git .claude/plugins/dev-pipeline
```

### 2. Copy the module's local template

```bash
# For Kotlin/Spring:
cp .claude/plugins/dev-pipeline/modules/kotlin-spring/local-template.md .claude/dev-pipeline.local.md

# For React/Vite:
cp .claude/plugins/dev-pipeline/modules/react-vite/local-template.md .claude/dev-pipeline.local.md
```

### 3. Copy the pipeline config template

```bash
# For Kotlin/Spring:
cp .claude/plugins/dev-pipeline/modules/kotlin-spring/pipeline-config-template.md .claude/pipeline-config.md

# For React/Vite:
cp .claude/plugins/dev-pipeline/modules/react-vite/pipeline-config-template.md .claude/pipeline-config.md
```

### 4. Create the pipeline log

```bash
touch .claude/pipeline-log.md
```

### 5. Edit the local config

Open `.claude/dev-pipeline.local.md` and customize:
- `commands.build`, `commands.test`, etc. to match your project's build tool and module names
- `scaffolder.patterns` to match your project's directory structure
- `quality_gate` batches and `inline_checks` for your review needs
- `context7_libraries` for the frameworks your project uses

### 6. Wire hooks in settings

Add the plugin to your `.claude/settings.json`:

```json
{
  "plugins": [".claude/plugins/dev-pipeline"]
}
```

### 7. Add `.pipeline/` to `.gitignore`

```bash
echo ".pipeline/" >> .gitignore
```

### 8. Run it

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
|   Module                  |  modules/{kotlin-spring,react-vite}/
|   (conventions, agents,   |  conventions.md, scripts/, hooks/
|    scripts, templates)    |  local-template.md, pipeline-config-template.md
+---------------------------+
|   Shared core             |  agents/pl-*.md (pipeline agents)
|   (orchestrator, stages,  |  shared/ (scoring, state schema, stage contract)
|    scoring, state)        |  hooks/ (checkpoint, feedback capture)
|                           |  skills/pipeline-run/ (entry point)
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
  scripts/                    # Optional verification scripts (must be executable with shebang)
  hooks/                      # Optional guard hooks (must be executable with shebang)
```

### 2. Create module-specific agents

Place them in `agents/` with a module prefix:

```
agents/py-code-reviewer.md    # py- prefix for python-fastapi
agents/py-type-checker.md
```

Agent files must have YAML frontmatter with `name` (matching filename without `.md`), `description`, and `tools` fields.

### 3. Wire agents into the local template

Reference your agents in the `quality_gate.batch_N` section and any `inline_checks` in the local template.

### 4. Naming conventions

- Module directory: lowercase with hyphens (`python-fastapi`)
- Module agents: short prefix + hyphen + role (`py-code-reviewer`)
- Pipeline agents: `pl-{NNN}-{role}` (shared, not module-specific)
- Scripts: `check-{what}.sh` or `{what}-guard.sh`

## Agents

14 agents organized by pipeline stage and module affiliation.

### Pipeline agents (shared)

| Agent | Stage | Role |
|-------|-------|------|
| `pl-100-orchestrator` | All | Coordinates the 10-stage lifecycle, manages state and recovery |
| `pl-200-planner` | 2 Plan | Decomposes requirements into risk-assessed plans with stories and tasks |
| `pl-210-validator` | 3 Validate | Validates plans across 5 perspectives, returns GO/REVISE/NO-GO |
| `pl-300-implementer` | 4 Implement | TDD implementation -- tests first (RED), implement (GREEN), refactor |
| `pl-310-scaffolder` | 4 Implement | Generates boilerplate with correct structure and TODO markers |
| `pl-400-quality-gate` | 6 Review | Multi-batch quality coordinator with scoring and fix cycles |
| `pl-500-test-gate` | 5 Verify | Test execution and coverage analysis coordinator |
| `pl-600-pr-builder` | 8 Ship | Creates branch, commits, and PR with quality gate results |
| `pl-700-retrospective` | 9 Learn | Post-run analysis, learning extraction, config auto-tuning |
| `pl-710-feedback-capture` | 9 Learn | Records user corrections as structured feedback for future runs |

### Module agents

| Agent | Module | Role |
|-------|--------|------|
| `be-hex-reviewer` | kotlin-spring | Reviews for hexagonal architecture violations |
| `be-security-reviewer` | kotlin-spring | Reviews for auth, injection, and data exposure issues |
| `fe-code-reviewer` | react-vite | Reviews against frontend conventions and security patterns |
| `fe-deprecation-scanner` | react-vite | Finds and fixes deprecated API usages, self-updating registry |

## File inventory

```
dev-pipeline/
  plugin.json                 # Plugin manifest (hooks: checkpoint + feedback capture)
  agents/                     # 14 agent definitions (YAML frontmatter + instructions)
  skills/                     # 5 skills (pipeline-run + 4 fe-* inline checks)
  hooks/                      # 2 shared hooks (pipeline-checkpoint.sh, feedback-capture.sh)
  shared/                     # 3 reference docs (scoring.md, state-schema.md, stage-contract.md)
  modules/
    kotlin-spring/            # 3 scripts, 2 templates, conventions (6 files)
    react-vite/               # 5 hooks, 2 templates, conventions, deprecation registry (9 files)
```

Total: 44 files.
