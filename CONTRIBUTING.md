# Contributing to forge

Guidelines for contributing to the forge Claude Code plugin.

## Getting Started

1. Clone the repository
2. Read `CLAUDE.md` for architecture overview and conventions
3. Read `shared/stage-contract.md` to understand the 10-stage pipeline flow
4. Read `shared/scoring.md` for quality scoring rules

## Branch Strategy

- **`master`** is the stable branch -- consuming projects pull from it via submodule
- Create feature branches from `master` for all changes
- Open a pull request for review before merging

> **Never push directly to `master`** -- downstream projects depend on it.

## Commit Messages

Follow [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<scope>): <description>

feat(agents): add fg-350-migration-checker agent
fix(hooks): correct checkpoint timestamp format
chore(react): update known-deprecations.json
docs(shared): clarify scoring deduplication rules
```

Common types: `feat`, `fix`, `chore`, `docs`, `refactor`

Common scopes: `agents`, `shared`, `hooks`, `skills`, `spring`, `react`, `k8s`, or any module name

## What You Should Know

### Agent files require YAML frontmatter

Every agent in `agents/` must have frontmatter with `name` (matching filename without `.md`) and `description`. The `tools` list is required for cross-cutting review agents; pipeline agents inherit tools from the orchestrator's dispatch. The orchestrator uses these fields to dispatch agents.

### Pipeline agents vs module agents

- **Pipeline agents** (`fg-{NNN}-{role}`) are shared across all modules. They handle stage orchestration.
- **Cross-cutting review agents** use descriptive names without a module prefix (e.g., `fg-410-code-reviewer`, `fg-411-security-reviewer`, `fg-413-frontend-reviewer`). They are wired into the quality gate and work across modules.
- **Bugfix agent** (`fg-020-bug-investigator`) is a pre-pipeline agent dispatched exclusively in bugfix mode (via `/forge fix` or `/forge run bugfix: <description>`). It performs root cause investigation and populates `state.json` bugfix fields before the standard pipeline stages run. When adding features to the bugfix workflow, start from `fg-020-bug-investigator.md` and the `stage-contract.md` Bugfix Mode section.

### Skills are the user-facing entry points

Users interact via `/forge run`, `/forge fix`, `/forge`, `/forge bootstrap`, `/forge deploy`, and other skills. Skills live in `skills/{name}/SKILL.md` with YAML frontmatter.

### State is local and gitignored

All pipeline state lives in `.forge/` in the consuming project, never in this repo. See `shared/state-schema.md` for the full schema (currently v1.5.0).

## Making Changes

### Adding a new pipeline agent

1. Create `agents/fg-{NNN}-{role}.md` with YAML frontmatter:
   ```yaml
   ---
   name: fg-{NNN}-{role}
   description: One-line description of the agent's purpose
   tools: [Read, Write, Edit, Grep, Glob, Bash, Agent]
   ---
   ```
2. Write the agent's system prompt (instructions, inputs, outputs, constraints)
3. Wire it into the orchestrator (`fg-100-orchestrator.md`) at the appropriate stage
4. Update `shared/stage-contract.md` if the agent changes stage behavior
5. Update `README.md` agent table

### Adding a new module

1. Create the directory structure:
   ```
   modules/frameworks/{name}/
     conventions.md              # Agent-readable framework conventions (must include Dos/Don'ts)
     local-template.md           # Project config template (YAML frontmatter, using components: structure)
     forge-config-template.md    # Runtime config template (must include total_retries_max, oscillation_tolerance, and convergence section)
     rules-override.json         # Module-specific check engine overrides
     known-deprecations.json     # Registry of deprecated APIs (schema v2 with applies_from/removed_in/applies_to fields, seed with 5-15 entries)
     variants/{language}.md      # Optional language-specific overrides
     testing/{test-framework}.md # Optional testing framework bindings
     scripts/                    # Optional verification scripts
     hooks/                      # Optional guard hooks
   ```
2. Create `shared/learnings/{name}.md` for per-module learnings accumulation. For new languages, also add `shared/learnings/{lang}.md`. For new testing frameworks, also add `shared/learnings/{test-framework}.md`.
3. Review agents are cross-cutting (shared) and new modules typically do not need new agents unless they have unique review needs. If a new agent is required, use a descriptive name (e.g., `embedded-memory-reviewer`)
4. Wire review agents into the local template's `quality_gate` batches
5. Update test minimum counts: bump the corresponding `MIN_*` constant in `tests/lib/module-lists.bash` (module lists are auto-discovered from disk)
6. Add the module to `README.md` under "Available modules" and update any modules list references
7. Update `CLAUDE.md` under "Module specifics"

### Adding a new layer module (database, persistence, messaging, etc.)

1. Create `modules/{layer}/{name}.md` with the required structure (Overview, Architecture Patterns, Configuration, Performance, Security, Testing, Dos, Don'ts).
2. Optionally add `{name}.rules-override.json` and `{name}.known-deprecations.json` alongside the `.md` file.
3. Create framework bindings: `modules/frameworks/{fw}/{layer}/{name}.md` for each applicable framework.
4. Add `shared/learnings/{name}.md` for per-layer learnings.
5. Run `./tests/run-all.sh` to verify structural integrity.

### Adding a new code-quality module

1. Create `modules/code-quality/{name}.md` with the standard structure (Overview, Configuration, Rules, Performance, Security, Dos, Don'ts).
2. YAML frontmatter is required with these fields:
   ```yaml
   ---
   name: {name}
   categories: [{category}]   # e.g., [linter], [formatter], [coverage], [security-scanner]
   languages: [{lang}]         # list of target languages, or [all]
   exclusive_group: {group}    # optional — tools in the same group are mutually exclusive
   ---
   ```
3. Add `shared/learnings/{name}.md` for per-tool learnings.
4. Bump `MIN_CODE_QUALITY` in `tests/lib/module-lists.bash` if needed.

### Adding a new skill

1. Create `skills/{skill-name}/SKILL.md` with YAML frontmatter
2. Skills should be thin launchers that dispatch agents or run inline checks
3. Update `README.md` if the skill is user-facing

### Adding documentation bindings

1. Create `modules/frameworks/{name}/documentation/conventions.md` with framework-specific documentation rules
2. Optionally add `templates/` subdirectory with framework-specific templates
3. Update `shared/learnings/{name}.md` with documentation generation effectiveness tracking
4. Verify: `[ -f modules/frameworks/{name}/documentation/conventions.md ] && echo "OK"`

### Modifying hooks

1. Hooks are registered in `hooks/hooks.json` -- update the manifest if adding a new hook
2. Three hooks are currently registered: the check engine (`PostToolUse` on `Edit|Write`), the forge checkpoint (`PostToolUse` on `Skill`), and feedback capture (`Stop`)
3. Hook scripts must be executable (`chmod +x`) with a shebang line
4. Module guard hooks live in `modules/frameworks/{name}/hooks/` and are referenced from the local template

### Modifying shared references

The `shared/` directory contains contracts and subsystems consumed by all agents:

**Contracts:**
- `scoring.md` -- quality scoring formula (changing this affects all review agents)
- `stage-contract.md` -- stage definitions (changing this affects the orchestrator and all stage agents)
- `state-schema.md` -- JSON schemas (changing this affects state reading/writing across the pipeline)

**Subsystems:**
- `checks/` -- 3-layer check engine that runs automated validations on file edits
- `discovery/` -- cross-repo project discovery and project type detection
- `graph/` -- Neo4j knowledge graph builder, enricher, and query patterns (opt-in)
- `learnings/` -- per-module learnings accumulated from pipeline runs
- `mcp-provisioning.md` -- rules for auto-installing missing MCP servers (Neo4j, Playwright) at init time. Agents must not assume MCPs are pre-installed.
- `recovery/` -- recovery engine with strategies and health checks for pipeline resilience
- `version-resolution.md` -- constraint: agents must NEVER use dependency versions from training data. Always search the internet for the latest compatible version at runtime.

> Changes to shared contracts are high-impact. Verify that all agents referencing the changed contract still behave correctly. Changes to subsystems should be tested with `shared/checks/engine.sh --verify --project-root . --files-changed <file>`.

## Naming Conventions

| Component | Pattern | Example |
|-----------|---------|---------|
| Module directory | `modules/frameworks/{name}` | `fastapi`, `go-stdlib` |
| Pipeline agent | `fg-{NNN}-{role}` | `fg-300-implementer` |
| Review agent | `{descriptive-name}` | `fg-410-code-reviewer`, `fg-411-security-reviewer` |
| Skill directory | lowercase-with-hyphens | `forge-admin` |
| Health check script | `{what}-check.sh` | `pre-stage-health.sh`, `dependency-check.sh` |

## Pull Request Process

1. Create a branch and make your changes
2. Run the structural checks and the full test suite:
   ```bash
   ./tests/validate-plugin.sh          # Quick structural checks (~2s)
   ./tests/run-all.sh                  # Full test suite (~30s)
   ```
3. Verify agent frontmatter is valid YAML
4. Verify scripts are executable and have shebang lines
5. Run `shared/checks/engine.sh --verify --project-root . --files-changed <changed-file>` to verify check engine configuration
6. Open a PR with a clear description using the PR template
7. Get at least one review from a team member

## Kanban Tracking

The kanban tracking system lives in `shared/tracking/`. The shell library `tracking-ops.sh` provides ticket CRUD functions used by agents. The schema is documented in `tracking-schema.md`.

When adding new agent integration points that should update ticket status, use the functions from `tracking-ops.sh` and follow the transition table in `fg-100-orchestrator.md`.

## Git Conventions

Branch naming and commit format rules are in `shared/git-conventions.md`. The `/forge` skill detects existing project hooks — see Phase 2a in `forge-init/SKILL.md`.

When modifying commit or branch naming behavior, update both `shared/git-conventions.md` and the consuming agents (`fg-100-orchestrator.md`, `fg-600-pr-builder.md`).

## Questions?

Read the `shared/` references and existing agent files first. If you're unsure about a change, open a draft PR to discuss.
