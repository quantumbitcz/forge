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

Common scopes: `agents`, `shared`, `hooks`, `skills`, `kotlin-spring`, `react-vite`, module name for new modules

## What You Should Know

### Agent files require YAML frontmatter

Every agent in `agents/` must have frontmatter with `name` (matching filename without `.md`), `description`, and `tools` list. The orchestrator uses these fields to dispatch agents.

### Pipeline agents vs module agents

- **Pipeline agents** (`pl-{NNN}-{role}`) are shared across all modules. They handle stage orchestration.
- **Module agents** (e.g., `be-*`, `fe-*`) are framework-specific reviewers wired into the quality gate.

### Skills are the user-facing entry points

Users interact via `/pipeline-run` and `/fe-*` skills. Skills live in `skills/{name}/SKILL.md` with YAML frontmatter.

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
     conventions.md              # Agent-readable framework conventions
     local-template.md           # Project config template (YAML frontmatter)
     pipeline-config-template.md # Runtime config template
     scripts/                    # Optional verification scripts
     hooks/                      # Optional guard hooks
   ```
2. Create module-specific agents in `agents/` with a short prefix (e.g., `py-` for python-fastapi)
3. Wire agents into the local template's `quality_gate` batches
4. Add the module to `README.md` under "Available modules"
5. Update `CLAUDE.md` under "Module specifics"

### Adding a new skill

1. Create `skills/{skill-name}/SKILL.md` with YAML frontmatter
2. Skills should be thin launchers that dispatch agents or run inline checks
3. Update `README.md` if the skill is user-facing

### Modifying hooks

1. Hooks are registered in `plugin.json` -- update the manifest if adding a new hook
2. Hook scripts must be executable (`chmod +x`) with a shebang line
3. Module guard hooks live in `modules/{name}/hooks/` and are referenced from the local template

### Modifying shared references

The three files in `shared/` are contracts consumed by all agents:
- `scoring.md` -- quality scoring formula (changing this affects all review agents)
- `stage-contract.md` -- stage definitions (changing this affects the orchestrator and all stage agents)
- `state-schema.md` -- JSON schemas (changing this affects state reading/writing across the pipeline)

> Changes to shared references are high-impact. Verify that all agents referencing the changed contract still behave correctly.

## Naming Conventions

| Component | Pattern | Example |
|-----------|---------|---------|
| Module directory | lowercase-with-hyphens | `python-fastapi` |
| Pipeline agent | `pl-{NNN}-{role}` | `pl-300-implementer` |
| Module agent | `{prefix}-{role}` | `frontend-reviewer` |
| Skill directory | lowercase-with-hyphens | `fe-check-theme` |
| Verification script | `check-{what}.sh` | `check-antipatterns.sh` |
| Guard hook | `{what}-guard.sh` | `theme-guard.sh` |

## Pull Request Process

1. Create a branch and make your changes
2. Verify agent frontmatter is valid YAML
3. Verify scripts are executable and have shebang lines
4. Open a PR with a clear description using the PR template
5. Get at least one review from a team member

## Questions?

Read the `shared/` references and existing agent files first. If you're unsure about a change, open a draft PR to discuss.
