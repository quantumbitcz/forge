# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`dev-pipeline` is a Claude Code plugin (installed as a Git submodule at `.claude/plugins/dev-pipeline`). It orchestrates a 10-stage autonomous development pipeline: Preflight → Explore → Plan → Validate → Implement (TDD) → Verify → Review → Docs → Ship → Learn. The entry point is the `/pipeline-run` skill which dispatches `pl-100-orchestrator`.

## Architecture

Three-layer design with resolution flowing top-down:

1. **Project config** (`.claude/dev-pipeline.local.md`, `.claude/pipeline-config.md`, `.claude/pipeline-log.md`) — per-project settings, mutable runtime params, and accumulated learnings. Lives in the consuming repo, not here.
2. **Module layer** (`modules/{kotlin-spring,react-vite}/`) — framework-specific conventions, templates, scripts, hooks, and review agents.
3. **Shared core** (`agents/pl-*.md`, `shared/`, `hooks/`, `skills/`) — the pipeline engine itself.

Parameter resolution: `pipeline-config.md` > `dev-pipeline.local.md` > plugin hardcoded defaults.

## Key conventions

### Agent files (`agents/*.md`)
- YAML frontmatter is required: `name` (must match filename without `.md`), `description`, `tools` list.
- Pipeline agents use `pl-{NNN}-{role}` naming. Module agents use a short prefix: `be-` (kotlin-spring), `fe-` (react-vite).
- The orchestrator (`pl-100-orchestrator`) never writes code itself — it dispatches specialized agents per stage.

### Stage contracts (`shared/stage-contract.md`)
- Every stage has defined entry conditions, exit conditions, and data flow. Agents must comply with the contract.
- State transitions tracked in `.pipeline/state.json` with `story_state` values: PREFLIGHT, EXPLORING, PLANNING, VALIDATING, IMPLEMENTING, VERIFYING, REVIEWING, DOCUMENTING, SHIPPING, LEARNING.

### Quality scoring (`shared/scoring.md`)
- Unified formula across all review agents: `100 - 20*CRITICAL - 5*WARNING - 2*INFO`.
- Verdict thresholds: PASS (score >= threshold), CONCERNS (score >= threshold - margin), FAIL (below).

### State and recovery (`shared/state-schema.md`)
- Pipeline state lives in `.pipeline/` (gitignored, local only). Checkpoints are saved after each task for resume-on-interrupt.
- PREEMPT system: learnings from `pipeline-log.md` are proactively applied to matching domain areas in new runs.

### Skills (`skills/`)
- `pipeline-run/SKILL.md` — the main entry point, thin launcher for the orchestrator.
- `fe-*` skills — inline frontend checks (theme tokens, dark mode, design system, React best practices). React-vite module only.

### Hooks (`hooks/`)
- `pipeline-checkpoint.sh` — PostToolUse hook; saves checkpoint after each Skill execution.
- `feedback-capture.sh` — Stop hook; captures user feedback on session exit.

## Adding a new module

Create `modules/{name}/` with:
- `conventions.md` — agent-readable framework conventions
- `local-template.md` — project config template (YAML frontmatter)
- `pipeline-config-template.md` — mutable runtime params template
- Optional: `scripts/check-*.sh` (verification), `hooks/*-guard.sh` (guards)

Create module agents in `agents/` with a short prefix (e.g., `py-` for python-fastapi). Wire them into the local template's `quality_gate` batches.

## Module specifics

### kotlin-spring
- Hexagonal architecture: sealed interface hierarchy (`XxxPersisted`, `XxxNotPersisted`, `XxxId`), ports & adapters pattern.
- Core uses Kotlin types (`kotlin.uuid.Uuid`, `kotlinx.datetime.Instant`); persistence layer uses Java types.
- Reactive stack: WebFlux + R2DBC + CoroutineCrudRepository.
- Verification scripts: `check-antipatterns.sh`, `check-core-boundary.sh`, `check-file-size.sh`.

### react-vite
- Typography via inline `style={{ fontSize }}`, not Tailwind `text-*` classes.
- Colors via theme tokens (`bg-background`, `text-foreground`), never hardcoded hex.
- Guard hooks enforce: theme tokens, function size (~30 lines), file size (~400 lines), import order, no deprecated APIs.
- `known-deprecations.json` is a self-updating registry maintained by `fe-deprecation-scanner`.

## Validation

This is a documentation-only plugin (no build step). To verify changes:

```bash
# Check agent frontmatter is valid YAML
head -5 agents/*.md

# Verify scripts are executable
find modules/ hooks/ -name "*.sh" ! -perm -111

# List all agents and their descriptions
grep -A1 "^name:" agents/*.md
```

## Gotchas

- Agent `name` in frontmatter **must** match the filename without `.md` — the orchestrator uses it for dispatch.
- Scripts must have a shebang (`#!/usr/bin/env bash`) and be `chmod +x` — hooks fail silently without this.
- `shared/` files are contracts: changing `scoring.md`, `stage-contract.md`, or `state-schema.md` affects all agents and modules. Verify downstream impact before editing.
- The plugin itself never touches consuming project files at development time. All runtime state goes to `.pipeline/` in the consuming repo.
- `pipeline-config.md` is auto-tuned by the retrospective agent — manual edits may be overwritten after a run.

## Plugin manifest (`plugin.json`)

Registers two hooks only: `PostToolUse` (checkpoint on Skill use) and `Stop` (feedback capture). No custom commands — the `/pipeline-run` skill is the user-facing entry point.

## Governance

- `LICENSE` — Proprietary (QuantumBit s.r.o.)
- `CONTRIBUTING.md` — How to add modules, agents, hooks, skills
- `SECURITY.md` — Vulnerability reporting and plugin security practices
- `.github/CODEOWNERS` — Auto-assigns `@quantumbitcz` to all PRs
- `.github/release.yml` — Auto-generated release notes by PR label
