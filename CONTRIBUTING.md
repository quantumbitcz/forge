# Contributing to dev-pipeline

Guidelines for contributing to the dev-pipeline Claude Code plugin.

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

feat(agents): add pl-350-migration-checker agent
fix(hooks): correct checkpoint timestamp format
chore(react-vite): update known-deprecations.json
docs(shared): clarify scoring deduplication rules
```

Common types: `feat`, `fix`, `chore`, `docs`, `refactor`

Common scopes: `agents`, `shared`, `hooks`, `skills`, `kotlin-spring`, `react-vite`, `infra-k8s`, or any module name

## What You Should Know

### Agent files require YAML frontmatter

Every agent in `agents/` must have frontmatter with `name` (matching filename without `.md`), `description`, and `tools` list. The orchestrator uses these fields to dispatch agents.

### Pipeline agents vs module agents

- **Pipeline agents** (`pl-{NNN}-{role}`) are shared across all modules. They handle stage orchestration.
- **Cross-cutting review agents** use descriptive names without a module prefix (e.g., `architecture-reviewer`, `security-reviewer`, `frontend-reviewer`). They are wired into the quality gate and work across modules.

### Skills are the user-facing entry points

Users interact via `/pipeline-run`, `/pipeline-init`, `/bootstrap-project`, `/deploy`, and other skills. Skills live in `skills/{name}/SKILL.md` with YAML frontmatter.

### State is local and gitignored

All pipeline state lives in `.pipeline/` in the consuming project, never in this repo. See `shared/state-schema.md` for the full schema.

## Making Changes

### Adding a new pipeline agent

1. Create `agents/pl-{NNN}-{role}.md` with YAML frontmatter:
   ```yaml
   ---
   name: pl-{NNN}-{role}
   description: One-line description of the agent's purpose
   tools: [Read, Write, Edit, Grep, Glob, Bash, Agent]
   ---
   ```
2. Write the agent's system prompt (instructions, inputs, outputs, constraints)
3. Wire it into `pl-100-orchestrator.md` at the appropriate stage
4. Update `shared/stage-contract.md` if the agent changes stage behavior
5. Update `README.md` agent table

### Adding a new module

1. Create the directory structure:
   ```
   modules/{name}/
     conventions.md              # Agent-readable framework conventions (must include Dos/Don'ts)
     local-template.md           # Project config template (YAML frontmatter)
     pipeline-config-template.md # Runtime config template
     rules-override.json         # Module-specific check engine overrides
     known-deprecations.json     # Registry of deprecated APIs (seed with 5-15 entries)
     scripts/                    # Optional verification scripts
     hooks/                      # Optional guard hooks
   ```
2. Create `shared/learnings/{name}.md` for per-module learnings accumulation
3. Review agents are cross-cutting (shared) and new modules typically do not need new agents unless they have unique review needs. If a new agent is required, use a descriptive name (e.g., `embedded-memory-reviewer`)
4. Wire review agents into the local template's `quality_gate` batches
5. Add the module to `README.md` under "Available modules" and update any modules list references
6. Update `CLAUDE.md` under "Module specifics"

### Adding a new skill

1. Create `skills/{skill-name}/SKILL.md` with YAML frontmatter
2. Skills should be thin launchers that dispatch agents or run inline checks
3. Update `README.md` if the skill is user-facing

### Modifying hooks

1. Hooks are registered in `hooks/hooks.json` -- update the manifest if adding a new hook
2. Three hooks are currently registered: the check engine (`PostToolUse` on `Edit|Write`), the pipeline checkpoint (`PostToolUse` on `Skill`), and feedback capture (`Stop`)
3. Hook scripts must be executable (`chmod +x`) with a shebang line
4. Module guard hooks live in `modules/{name}/hooks/` and are referenced from the local template

### Modifying shared references

The `shared/` directory contains contracts and subsystems consumed by all agents:

**Contracts:**
- `scoring.md` -- quality scoring formula (changing this affects all review agents)
- `stage-contract.md` -- stage definitions (changing this affects the orchestrator and all stage agents)
- `state-schema.md` -- JSON schemas (changing this affects state reading/writing across the pipeline)

**Subsystems:**
- `checks/` -- 3-layer check engine that runs automated validations on file edits
- `learnings/` -- per-module learnings accumulated from pipeline runs
- `recovery/` -- recovery engine with strategies and health checks for pipeline resilience

> Changes to shared contracts are high-impact. Verify that all agents referencing the changed contract still behave correctly. Changes to subsystems should be tested with `shared/checks/engine.sh --dry-run`.

## Naming Conventions

| Component | Pattern | Example |
|-----------|---------|---------|
| Module directory | lowercase-with-hyphens | `python-fastapi` |
| Pipeline agent | `pl-{NNN}-{role}` | `pl-300-implementer` |
| Review agent | `{descriptive-name}` | `architecture-reviewer`, `security-reviewer` |
| Skill directory | lowercase-with-hyphens | `pipeline-status` |
| Health check script | `{what}-check.sh` | `pre-stage-health.sh`, `dependency-check.sh` |

## Pull Request Process

1. Create a branch and make your changes
2. Verify agent frontmatter is valid YAML
3. Verify scripts are executable and have shebang lines
4. Run `shared/checks/engine.sh --dry-run` to verify check engine configuration
5. Open a PR with a clear description using the PR template
6. Get at least one review from a team member

## Questions?

Read the `shared/` references and existing agent files first. If you're unsure about a change, open a draft PR to discuss.
