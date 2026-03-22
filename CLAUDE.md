# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`dev-pipeline` is a Claude Code plugin (installable from the `quantumbitcz` marketplace or as a Git submodule). It orchestrates a 10-stage autonomous development pipeline: Preflight → Explore → Plan → Validate → Implement (TDD) → Verify → Review → Docs → Ship → Learn. The entry point is the `/pipeline-run` skill which dispatches `pl-100-orchestrator`.

## Architecture

Three-layer design with resolution flowing top-down:

1. **Project config** (`.claude/dev-pipeline.local.md`, `.claude/pipeline-config.md`, `.claude/pipeline-log.md`) — per-project settings, mutable runtime params, and accumulated learnings. Lives in the consuming repo, not here.
2. **Module layer** (`modules/`) — framework-specific conventions, templates, scripts, hooks, and rule overrides. 12 modules: c-embedded, go-stdlib, infra-k8s, java-spring, kotlin-spring, python-fastapi, react-vite, rust-axum, swift-ios, swift-vapor, typescript-node, typescript-svelte.
3. **Shared core** (`agents/pl-*.md`, `shared/`, `hooks/`, `skills/`) — the pipeline engine itself.

Parameter resolution: `pipeline-config.md` > `dev-pipeline.local.md` > plugin hardcoded defaults.

## Key conventions

### Agent files (`agents/*.md`)
- YAML frontmatter is required: `name` (must match filename without `.md`), `description`, `tools` list.
- Pipeline agents use `pl-{NNN}-{role}` naming (e.g., `pl-300-implementer`).
- Cross-cutting review agents use descriptive names without module prefix: `architecture-reviewer`, `security-reviewer`, `frontend-reviewer`, `frontend-performance-reviewer`, `backend-performance-reviewer`, `infra-deploy-reviewer`, `infra-deploy-verifier`.
- The orchestrator (`pl-100-orchestrator`) never writes code itself — it dispatches specialized agents per stage.
- The recap agent (`pl-720-recap`) generates a human-readable summary of each pipeline run during Stage 9 (LEARN), after the retrospective.
- **Worktree isolation:** All implementation runs in a git worktree (`.pipeline/worktree`). The user's working tree is never modified during pipeline execution.

### Stage contracts (`shared/stage-contract.md`)
- Every stage has defined entry conditions, exit conditions, and data flow. Agents must comply with the contract.
- State transitions tracked in `.pipeline/state.json` with `story_state` values: PREFLIGHT, EXPLORING, PLANNING, VALIDATING, IMPLEMENTING, VERIFYING, REVIEWING, DOCUMENTING, SHIPPING, LEARNING.

### Quality scoring (`shared/scoring.md`)
- Unified formula across all review agents: `100 - 20*CRITICAL - 5*WARNING - 2*INFO`.
- Verdict thresholds: PASS (score >= threshold), CONCERNS (score >= threshold - margin), FAIL (below).
- `SCOUT-*` findings track Boy Scout improvements (no point deduction, tracked for reporting).
- Score sub-bands (95-99, 80-94, 60-79, <60) guide Linear documentation granularity.

### State and recovery (`shared/state-schema.md`, `shared/recovery/`)
- Pipeline state lives in `.pipeline/` (gitignored, local only). Checkpoints are saved after each task for resume-on-interrupt.
- PREEMPT system: learnings from `pipeline-log.md` are proactively applied to matching domain areas in new runs.
- Recovery engine (`shared/recovery/recovery-engine.md`) with 7 strategies: transient-retry, state-reconstruction, agent-reset, tool-diagnosis, dependency-health, resource-cleanup, graceful-stop.
- Health checks (`shared/recovery/health-checks/`) run pre-stage dependency and environment validation.

### Linear Integration (optional)
- If Linear MCP is available, the pipeline creates an Epic with Stories and Tasks during PLAN, updates ticket statuses per stage, and posts quality findings and recap summaries as comments.
- Configured via `linear:` section in `dev-pipeline.local.md` (disabled by default).
- Graceful degradation: pipeline runs without Linear when MCP is unavailable.

### Adaptive MCP Detection
- PREFLIGHT detects available MCPs (Linear, Playwright, Slack, Context7, Figma) by checking tool availability.
- Each agent uses MCPs relevant to its stage (e.g., Playwright for preview validation, Context7 for documentation lookup).
- No MCP is required. The pipeline adapts to whatever the user has installed and suggests missing optional MCPs.

### Check engine (`shared/checks/`)
- 3-layer generalized check engine triggered on every `Edit`/`Write` via PostToolUse hook.
- **Layer 1 — Fast patterns** (`layer-1-fast/`): regex-based pattern matching, sub-second.
- **Layer 2 — Linter** (`layer-2-linter/`): framework-aware linter adapters with configurable defaults.
- **Layer 3 — Agent** (`layer-3-agent/`): AI-driven deprecation refresh and version compatibility checks.
- Modules customize checks via `rules-override.json` (per-module overrides of shared defaults).
- Output format standardized in `output-format.md`.

### Learnings (`shared/learnings/`)
- Per-module learnings files (e.g., `kotlin-spring.md`, `react-vite.md`) — accumulated patterns from past runs.
- JSON schemas: `rule-learning-schema.json` (check rule evolution), `agent-effectiveness-schema.json` (agent performance tracking).

### Error taxonomy (`shared/error-taxonomy.md`)
- 15 standard error types (TOOL_FAILURE, BUILD_FAILURE, TEST_FAILURE, etc.) with recovery strategies.
- Agents classify errors before reporting to the orchestrator or recovery engine.
- Pre-classified errors skip heuristic classification in the recovery engine.

### Agent communication (`shared/agent-communication.md`)
- All inter-agent data flows through the orchestrator via stage notes.
- Agents are isolated — they cannot dispatch other agents, write state, or message the user.
- The quality gate includes previous batch findings when dispatching subsequent batches to reduce duplicate work.

### Skills (`skills/`)
- `pipeline-run` — the main entry point, thin launcher for the orchestrator.
- `pipeline-init` — initializes `.claude/dev-pipeline.local.md` and `.claude/pipeline-config.md` for a consuming project.
- `pipeline-status` — shows current pipeline state, last run results, quality score, and Linear tracking.
- `pipeline-reset` — clears pipeline run state while preserving accumulated learnings.
- `verify` — quick build + lint + test check without a full pipeline run.
- `security-audit` — runs module-appropriate security scanners and reports vulnerabilities.
- `codebase-health` — runs the check engine in full review mode for a comprehensive health report.
- `migration` — plans and executes library/framework migrations via `pl-160-migration-planner`.
- `bootstrap-project` — scaffolds a new project from a module template via `pl-050-project-bootstrapper`.
- `deploy` — triggers deployment workflow via `infra-deploy-*` agents.
- `pipeline-history` — view quality score trends, agent effectiveness, and run metrics across pipeline runs.
- `pipeline-rollback` — safely rollback pipeline changes (worktree, merge, Linear, state).
- `fe-*` skills (`fe-check-theme`, `fe-dark-mode-check`, `fe-design-review`, `fe-react-doctor`) — inline frontend checks. React-vite module only.

### Hooks (`hooks/hooks.json`)
- **Check engine** — PostToolUse on `Edit|Write`; runs `shared/checks/engine.sh --hook` (layer 1–2 fast checks on every file change).
- `pipeline-checkpoint.sh` — PostToolUse on `Skill`; saves checkpoint after each Skill execution.
- `feedback-capture.sh` — Stop hook; captures user feedback on session exit.

## Adding a new module

Create `modules/{name}/` with:
- `conventions.md` — agent-readable framework conventions
- `local-template.md` — project config template (YAML frontmatter)
- `pipeline-config-template.md` — mutable runtime params template
- `rules-override.json` — module-specific overrides for the shared check engine (pattern rules, linter config)
- Optional: `scripts/check-*.sh` (verification), `hooks/*-guard.sh` (PostToolUse guards)

Add a learnings file at `shared/learnings/{name}.md`. Wire the module into the local template's `quality_gate` batches.

## Module specifics

All 12 modules follow the same structure (`conventions.md`, `local-template.md`, `pipeline-config-template.md`, `rules-override.json`). Detailed notes below for modules with non-obvious conventions:

### kotlin-spring
- Hexagonal architecture: sealed interface hierarchy (`XxxPersisted`, `XxxNotPersisted`, `XxxId`), ports & adapters pattern.
- Core uses Kotlin types (`kotlin.uuid.Uuid`, `kotlinx.datetime.Instant`); persistence layer uses Java types.
- Reactive stack: WebFlux + R2DBC + CoroutineCrudRepository.

### react-vite
- Typography via inline `style={{ fontSize }}`, not Tailwind `text-*` classes.
- Colors via theme tokens (`bg-background`, `text-foreground`), never hardcoded hex.
- Check engine enforces: theme tokens, function size (~30 lines), file size (~400 lines), import order, no deprecated APIs.
- `known-deprecations.json` is a self-updating registry maintained by the check engine's deprecation layer.

## Validation

This is a documentation-only plugin (no build step). To verify changes:

```bash
# Check agent frontmatter is valid YAML
head -5 agents/*.md

# Verify scripts are executable
find modules/ hooks/ shared/ -name "*.sh" ! -perm -111

# List all agents and their descriptions
grep -A1 "^name:" agents/*.md

# Dry-run the check engine
shared/checks/engine.sh --dry-run

# Verify all modules have required files
for m in modules/*/; do echo "=== $m ==="; ls "$m"{conventions.md,local-template.md,pipeline-config-template.md,rules-override.json} 2>&1; done

# Verify Linear config in all module templates
for m in modules/*/local-template.md; do grep -q "linear:" "$m" || echo "MISSING linear: $m"; done

# Verify all agents have Forbidden Actions section
grep -l "Forbidden Actions" agents/*.md | wc -l
```

## Gotchas

- Agent `name` in frontmatter **must** match the filename without `.md` — the orchestrator uses it for dispatch.
- Scripts must have a shebang (`#!/usr/bin/env bash`) and be `chmod +x` — hooks fail silently without this.
- `shared/` files are contracts: changing `scoring.md`, `stage-contract.md`, or `state-schema.md` affects all agents and modules. Verify downstream impact before editing.
- The plugin itself never touches consuming project files at development time. All runtime state goes to `.pipeline/` in the consuming repo.
- `pipeline-config.md` is auto-tuned by the retrospective agent — manual edits may be overwritten after a run.
- The check engine hook fires on every `Edit`/`Write` — if `shared/checks/engine.sh` is broken or non-executable, all file edits will trigger hook errors.
- `rules-override.json` in modules extends (not replaces) shared check defaults. Use `"disabled": true` to suppress a shared rule, not deletion.
- The scoring formula is customizable per-project via `pipeline-config.md`. Constraints enforced at PREFLIGHT — see `shared/scoring.md`.
- PREEMPT items decay in confidence if unused for 10+ runs: HIGH → MEDIUM → LOW → ARCHIVED. Archived items are not loaded at PREFLIGHT.
- The orchestrator enforces parallel task conflict detection at IMPLEMENT time — tasks sharing files are automatically serialized.
- Convention drift is detected mid-run via SHA256 hash comparison. Agents log WARNING if conventions change but continue with the newer version.
- `--dry-run` flag runs PREFLIGHT through VALIDATE without entering IMPLEMENT. No worktree, no Linear tickets, no file changes.

## Plugin distribution (`.claude-plugin/`)

- `plugin.json` — plugin manifest (name, version, description, author, license, category, keywords).
- `marketplace.json` — marketplace catalog for the `quantumbitcz` marketplace. Lists `dev-pipeline` with source `"./"`.
- Hook registration lives in `hooks/hooks.json` (3 hooks: check engine on Edit/Write, checkpoint on Skill, feedback on Stop).
- Install: `/plugin marketplace add quantumbitcz/dev-pipeline` then `/plugin install dev-pipeline@quantumbitcz`.

## Governance

- `LICENSE` — Proprietary (QuantumBit s.r.o.)
- `CONTRIBUTING.md` — How to add modules, agents, hooks, skills
- `SECURITY.md` — Vulnerability reporting and plugin security practices
- `.github/CODEOWNERS` — Auto-assigns `@quantumbitcz` to all PRs
- `.github/release.yml` — Auto-generated release notes by PR label
