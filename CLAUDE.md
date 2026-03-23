# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`dev-pipeline` is a Claude Code plugin (v1.0.0, installable from the `quantumbitcz` marketplace or as a Git submodule). It orchestrates a 10-stage autonomous development pipeline: Preflight → Explore → Plan → Validate → Implement (TDD) → Verify → Review → Docs → Ship → Learn. The entry point is the `/pipeline-run` skill which dispatches `pl-100-orchestrator`.

## Architecture

Three-layer design with resolution flowing top-down:

1. **Project config** (`.claude/dev-pipeline.local.md`, `.claude/pipeline-config.md`, `.claude/pipeline-log.md`) — per-project settings, mutable runtime params, and accumulated learnings. Lives in the consuming repo, not here.
2. **Module layer** (`modules/`) — framework-specific conventions, templates, rule overrides, and optional module-specific tooling. 12 modules: c-embedded, go-stdlib, infra-k8s, java-spring, kotlin-spring, python-fastapi, react-vite, rust-axum, swift-ios, swift-vapor, typescript-node, typescript-svelte.
3. **Shared core** (`agents/pl-*.md`, `shared/`, `hooks/`, `skills/`) — the pipeline engine itself.

Parameter resolution: `pipeline-config.md` > `dev-pipeline.local.md` > plugin hardcoded defaults.

## Development workflow

This is a documentation-only plugin (no build step). To test changes:

1. Install locally: symlink or clone into `.claude/plugins/` of a test project
2. Run `/pipeline-init` in the test project to generate config files
3. Run `/pipeline-run --dry-run <requirement>` to verify PREFLIGHT through VALIDATE
4. Run `/pipeline-run <requirement>` for a full end-to-end test
5. Check `.pipeline/state.json` and stage notes for correct behavior

### CI validation

Run the validation commands from the [Validation](#validation) section in CI to catch structural issues:

```bash
# CI smoke test: verify plugin structure is intact
set -e
# All agents have valid frontmatter
test "$(grep -l '^name:' agents/*.md | wc -l)" -ge 20
# All modules have required files
for m in modules/*/; do
  ls "$m"{conventions.md,local-template.md,pipeline-config-template.md,rules-override.json,known-deprecations.json} > /dev/null
done
# All scripts are executable
test -z "$(find modules/ hooks/ shared/ -name '*.sh' ! -perm -111 2>/dev/null)"
# known-deprecations are schema v2
grep -q '"version": 1,' modules/*/known-deprecations.json && exit 1 || true
echo "Plugin structure OK"
```

## Key conventions

### Agent files (`agents/*.md`)
- YAML frontmatter is required: `name` (must match filename without `.md`), `description`. The `tools` list is required for cross-cutting review agents; pipeline agents inherit tools from the orchestrator's dispatch.
- Pipeline agents use `pl-{NNN}-{role}` naming (e.g., `pl-300-implementer`).
- Cross-cutting review agents use descriptive names without module prefix: `architecture-reviewer`, `security-reviewer`, `frontend-reviewer`, `frontend-performance-reviewer`, `backend-performance-reviewer`, `infra-deploy-reviewer`, `infra-deploy-verifier`.
- The orchestrator (`pl-100-orchestrator`) never writes code itself — it dispatches specialized agents per stage.
- The recap agent (`pl-720-recap`) generates a human-readable summary of each pipeline run during Stage 9 (LEARN), after the retrospective.
- **Worktree isolation:** All implementation runs in a git worktree (`.pipeline/worktree`). The user's working tree is never modified during pipeline execution. Branch collision is detected at creation time (epoch suffix fallback).

### Stage contracts (`shared/stage-contract.md`)
- Every stage has defined entry conditions, exit conditions, and data flow. Agents must comply with the contract.
- State transitions tracked in `.pipeline/state.json` with `story_state` values: PREFLIGHT, EXPLORING, PLANNING, VALIDATING, IMPLEMENTING, VERIFYING, REVIEWING, DOCUMENTING, SHIPPING, LEARNING. Migration-specific states: MIGRATING, MIGRATION_PAUSED, MIGRATION_CLEANUP, MIGRATION_VERIFY.
- **Feedback classification:** PR rejection routes to Stage 4 (implementation feedback) or Stage 2 (design feedback) based on `pl-710-feedback-capture` classification.
- **Global retry budget:** All retry loops share a cumulative `total_retries` counter (default max: 10, configurable). Prevents unbounded retry cascades.

### Quality scoring (`shared/scoring.md`)
- Unified formula across all review agents: `100 - 20*CRITICAL - 5*WARNING - 2*INFO`.
- Verdict thresholds: PASS (score >= 80), CONCERNS (60-79), FAIL (< 60 or any CRITICAL remaining).
- `SCOUT-*` findings track Boy Scout improvements (no point deduction, tracked for reporting).
- Score sub-bands (95-99, 80-94, 60-79, <60) guide Linear documentation granularity.
- **Oscillation tolerance:** Score regressions within `oscillation_tolerance` (default: 5 points) allow one more cycle. Second consecutive dip escalates immediately. Configurable per-project in `pipeline-config.md`.
- **Critical agent gap:** If a security/architecture reviewer times out, the coverage gap finding is upgraded from INFO to WARNING (-5 instead of -2).

### State and recovery (`shared/state-schema.md`, `shared/recovery/`)
- State schema version: **1.3**. Migration chain: 1.1 → 1.2 → 1.3 (forward-compatible, applied by recovery engine).
- Pipeline state lives in `.pipeline/` (gitignored, local only). Checkpoints are saved after each task for resume-on-interrupt.
- **Concurrent run lock:** `.pipeline/.lock` prevents two pipeline runs on the same project. Stale detection via PID check + 24-hour timeout.
- **Version detection:** PREFLIGHT detects project dependency versions from manifest files (build.gradle.kts, package.json, go.mod, etc.) and stores in `state.json.detected_versions`. Enables version-aware deprecation rule gating.
- PREEMPT system: learnings from `pipeline-log.md` are proactively applied to matching domain areas in new runs. Hit counts tracked via `preempt_items_status` in state.json. Confidence decay: 10 domain-matched unused runs → demotion (HIGH → MEDIUM → LOW → ARCHIVED). False positives accelerate decay (1 FP = 3 unused runs).
- **Recovery engine** (`shared/recovery/recovery-engine.md`) with 7 strategies and **weighted budget**: transient-retry (0.5), tool-diagnosis (1.0), state-reconstruction (1.5), agent-reset (1.0), dependency-health (1.0), resource-cleanup (0.5), graceful-stop (0.0). Budget ceiling: 5.0 total weight. Warning at 80%.
- **State reconstruction:** Corrupted state counters are recovered from checkpoint artifacts and stage notes. Fallback uses configured maximum (conservative), not zero.
- Health checks (`shared/recovery/health-checks/`) run pre-stage dependency and environment validation.

### Linear Integration (optional)
- If Linear MCP is available, the pipeline creates an Epic with Stories and Tasks during PLAN, updates ticket statuses per stage, and posts quality findings and recap summaries as comments.
- Configured via `linear:` section in `dev-pipeline.local.md` (disabled by default).
- **Mid-run resilience:** Linear failures retry once (3s delay), then degrade gracefully. Failed operations tracked in `state.json.linear_sync`. Recovery engine is NOT invoked for MCP failures.
- Graceful degradation: pipeline runs without Linear when MCP is unavailable.

### Adaptive MCP Detection
- PREFLIGHT detects available MCPs (Linear, Playwright, Slack, Context7, Figma) by checking tool availability.
- Each agent uses MCPs relevant to its stage (e.g., Playwright for preview validation, Context7 for documentation lookup and migration guides).
- **Mid-run health:** First MCP failure marks it as degraded for the rest of the run. Subsequent dispatches skip it without timeout delays.
- No MCP is required. The pipeline adapts to whatever the user has installed and suggests missing optional MCPs.

### Check engine (`shared/checks/`)
- 3-layer generalized check engine triggered on every `Edit`/`Write` via PostToolUse hook.
- **Layer 1 — Fast patterns** (`layer-1-fast/`): regex-based pattern matching, sub-second.
- **Layer 2 — Linter** (`layer-2-linter/`): framework-aware linter adapters with configurable defaults.
- **Layer 3 — Agent** (`layer-3-agent/`): AI-driven deprecation refresh and version compatibility checks. **Version-gated:** rules only fire when project version >= `applies_from` in the deprecation entry.
- Modules customize checks via `rules-override.json` (per-module overrides of shared defaults).
- **Skip tracking:** If the hook times out, a counter in `.pipeline/.check-engine-skipped` is incremented. VERIFY Phase A reads and reports the count.
- Output format standardized in `output-format.md`.

### Deprecation registries (`modules/*/known-deprecations.json`)
- **Schema v2** with version-aware fields: `pattern`, `replacement`, `package`, `since`, `removed_in`, `applies_from`, `applies_to`, `added`, `addedBy`.
- `applies_from`: minimum project version where the rule triggers. `removed_in`: version where the API was removed (null if only deprecated). `applies_to`: upper bound (usually `"*"`).
- Rules are skipped when project version < `applies_from`. Severity: WARNING if deprecated, CRITICAL if `removed_in` reached. Unknown project versions → conservative (all rules apply).
- Auto-updated by the deprecation-refresh agent during PREFLIGHT via Context7 and package registries.

### Learnings (`shared/learnings/`)
- Per-module learnings files (e.g., `kotlin-spring.md`, `react-vite.md`) — accumulated patterns from past runs.
- JSON schemas: `rule-learning-schema.json` (check rule evolution), `agent-effectiveness-schema.json` (agent performance tracking).

### Error taxonomy (`shared/error-taxonomy.md`)
- 15 standard error types (TOOL_FAILURE, BUILD_FAILURE, TEST_FAILURE, etc.) with recovery strategies.
- **Severity ordering:** 12-level priority for multi-error aggregation (CONFIG_INVALID highest, PATTERN_MISSING lowest).
- **MCP handling:** MCP_UNAVAILABLE is handled inline by agents (skip + log INFO), NOT by the recovery engine.
- **Network permanence:** 3 consecutive transient-retry failures for the same endpoint within 60s → reclassify as non-recoverable, stop consuming budget.
- Agents classify errors before reporting to the orchestrator or recovery engine. Pre-classified errors skip heuristic classification.

### Agent communication (`shared/agent-communication.md`)
- All inter-agent data flows through the orchestrator via stage notes.
- Agents are isolated — they cannot dispatch other agents, write state, or message the user.
- The quality gate includes previous batch findings (capped at top 20 by severity) when dispatching subsequent batches to reduce duplicate work. Timed-out agents are listed so subsequent batches can compensate for coverage gaps.
- **PREEMPT tracking:** Implementers write `PREEMPT_APPLIED` / `PREEMPT_SKIPPED` markers in stage notes. On task retries, only the last attempt's markers are used.

### Skills (`skills/`)
- `pipeline-run` — the main entry point, thin launcher for the orchestrator.
- `pipeline-init` — initializes `.claude/dev-pipeline.local.md` and `.claude/pipeline-config.md` for a consuming project.
- `pipeline-status` — shows current pipeline state, quality score, retry budgets, recovery budget, Linear sync, and detected versions.
- `pipeline-reset` — clears pipeline run state (including lock and skip counter) while preserving accumulated learnings.
- `verify` — quick build + lint + test check without a full pipeline run.
- `security-audit` — runs module-appropriate security scanners and reports vulnerabilities.
- `codebase-health` — runs the check engine in full review mode for a comprehensive health report.
- `migration` — plans and executes library/framework migrations via `pl-160-migration-planner`. Supports auto-detection (`/migration upgrade Spring Boot`), explicit versions, `upgrade all`, and `check` (dry-run). Uses Context7 for breaking change analysis.
- `bootstrap-project` — scaffolds a new project from a module template via `pl-050-project-bootstrapper`.
- `deploy` — triggers deployment workflow via `infra-deploy-*` agents.
- `pipeline-history` — view quality score trends, agent effectiveness, and run metrics across pipeline runs.
- `pipeline-rollback` — safely rollback pipeline changes (worktree, merge, Linear, state). Detects preconditions before offering modes.
- Frontend-specific commands (`fe-check-theme`, `fe-design-review`, `fe-dark-mode-check`, `fe-react-doctor`) are project-level — they live in the consuming project's `.claude/commands/`, not in this plugin. See `modules/react-vite/conventions.md` for descriptions.

### Hooks (`hooks/hooks.json`)
- **Check engine** — PostToolUse on `Edit|Write`; runs `shared/checks/engine.sh --hook` (layer 1-2 fast checks on every file change). On timeout: increments skip counter, exits 0 (never blocks edits).
- `pipeline-checkpoint.sh` — PostToolUse on `Skill`; saves checkpoint after each Skill execution.
- `feedback-capture.sh` — Stop hook; captures user feedback on session exit.

## Adding a new module

Create `modules/{name}/` with:
- `conventions.md` — agent-readable framework conventions (must include Dos/Don'ts section)
- `local-template.md` — project config template (YAML frontmatter)
- `pipeline-config-template.md` — mutable runtime params template (must include `total_retries_max` and `oscillation_tolerance`)
- `rules-override.json` — module-specific overrides for the shared check engine (pattern rules, linter config)
- `known-deprecations.json` — registry of deprecated APIs in schema v2 (`applies_from`, `removed_in`, `applies_to` fields required). Seed with 5-15 ecosystem-specific entries. Auto-updated by deprecation-refresh agent.
- Optional: `scripts/check-*.sh` (verification), `hooks/*-guard.sh` (PostToolUse guards)

Add a learnings file at `shared/learnings/{name}.md`. Wire the module into the local template's `quality_gate` batches.

## Module specifics

All 12 modules follow the same structure (`conventions.md`, `local-template.md`, `pipeline-config-template.md`, `rules-override.json`, `known-deprecations.json`). Each `conventions.md` includes a Dos/Don'ts section with language/framework-specific best practices. Detailed notes below for modules with non-obvious conventions:

### kotlin-spring
- Hexagonal architecture: sealed interface hierarchy (`XxxPersisted`, `XxxNotPersisted`, `XxxId`), ports & adapters pattern.
- Core uses Kotlin types (`kotlin.uuid.Uuid`, `kotlinx.datetime.Instant`); persistence layer uses Java types.
- Reactive stack: WebFlux + R2DBC + CoroutineCrudRepository.
- `@Transactional` on use case impls only, never on adapters. R2DBC UPDATE sets all columns — use `@Query` for partial updates.

### react-vite
- Typography via inline `style={{ fontSize }}`, not Tailwind `text-*` classes.
- Colors via theme tokens (`bg-background`, `text-foreground`), never hardcoded hex.
- Check engine enforces: theme tokens, function size (~30 lines), file size (~400 lines, prefer ~200 per component), import order, no deprecated APIs.
- Error Boundaries required around route-level components. State management: server data in TanStack Query/SWR, not useState.

### c-embedded
- Real-time safety: no `malloc`/`printf`/`float` in ISR handlers, maximum 10us ISR duration.
- `volatile` for all ISR-shared variables. RTOS: message queues for inter-task communication, mutexes with priority inheritance.

### infra-k8s
- All containers: resource requests AND limits, readiness + liveness probes, non-root `securityContext`.
- Pin image tags to SHA digests in production. Observability: Prometheus metrics, structured JSON logging, OpenTelemetry tracing.

### swift-ios
- Memory safety: `[weak self]` in stored closures, delegates as `weak var`. Prefer `struct` for data models, `actor` for thread-safe state.
- SPM preferred over CocoaPods. Pin to exact versions for releases.

## Validation

### Full test suite

```bash
# Run all tests (~172 tests, ~30s)
./tests/run-all.sh

# Run individual tiers
./tests/run-all.sh structural   # Plugin integrity (25 checks, no bats needed)
./tests/run-all.sh unit         # Shell script behavior (73 tests)
./tests/run-all.sh contract     # Document contract compliance (35 tests)
./tests/run-all.sh scenario     # Multi-script integration (39 tests)
```

### Manual checks

To verify changes:

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
for m in modules/*/; do echo "=== $m ==="; ls "$m"{conventions.md,local-template.md,pipeline-config-template.md,rules-override.json,known-deprecations.json} 2>&1; done

# Verify known-deprecations are schema v2
grep '"version"' modules/*/known-deprecations.json

# Verify Linear config in all module templates
for m in modules/*/local-template.md; do grep -q "linear:" "$m" || echo "MISSING linear: $m"; done

# Verify all agents have Forbidden Actions section
grep -l "Forbidden Actions" agents/*.md | wc -l

# Verify pipeline-config templates have new fields
for m in modules/*/pipeline-config-template.md; do grep -q "total_retries_max" "$m" || echo "MISSING total_retries_max: $m"; done
```

## Gotchas

- Agent `name` in frontmatter **must** match the filename without `.md` — the orchestrator uses it for dispatch.
- Scripts must have a shebang (`#!/usr/bin/env bash`) and be `chmod +x` — hooks fail silently without this.
- `shared/` files are contracts: changing `scoring.md`, `stage-contract.md`, or `state-schema.md` affects all agents and modules. Verify downstream impact before editing. State schema changes require a new version and migration path.
- The plugin itself never touches consuming project files at development time. All runtime state goes to `.pipeline/` in the consuming repo.
- `pipeline-config.md` is auto-tuned by the retrospective agent — manual edits may be overwritten after a run.
- The check engine hook fires on every `Edit`/`Write` — if `shared/checks/engine.sh` is broken or non-executable, all file edits will trigger hook errors. On timeout, skip counter increments but edit succeeds.
- `rules-override.json` in modules extends (not replaces) shared check defaults. Use `"disabled": true` to suppress a shared rule, not deletion.
- The scoring formula is customizable per-project via `pipeline-config.md`. Constraints enforced at PREFLIGHT: `critical_weight >= 10`, `pass_threshold >= 60`, `oscillation_tolerance` 0-20, `total_retries_max` 5-30.
- PREEMPT items decay in confidence if unused for 10+ domain-matched runs: HIGH → MEDIUM → LOW → ARCHIVED. False positives accelerate decay. Archived items are not loaded at PREFLIGHT.
- The orchestrator enforces parallel task conflict detection at IMPLEMENT time — scaffolders run serially first, then conflict detection, then implementers in parallel. Tasks sharing files are automatically serialized into sub-groups.
- Convention drift is detected mid-run via per-section SHA256 hash comparison. Agents only react to changes in their relevant section.
- `--dry-run` flag runs PREFLIGHT through VALIDATE without entering IMPLEMENT. No worktree, no Linear tickets, no file changes.
- `known-deprecations.json` uses schema v2 — entries without `applies_from`/`removed_in`/`applies_to` are treated as v1 and apply universally (backward compatible).
- Version detection may fail partially for old projects or unusual build configurations. Unknown versions → all rules apply (conservative default).
- Concurrent pipeline runs on the same project are blocked by `.pipeline/.lock`. Stale locks (>24h or dead PID) are automatically cleaned.

## Plugin distribution (`.claude-plugin/`)

- `plugin.json` — plugin manifest (v1.0.0). Name, version, description, author, license, category, keywords.
- `marketplace.json` — marketplace catalog for the `quantumbitcz` marketplace. Lists `dev-pipeline` with source `"./"`.
- Hooks are auto-discovered from `hooks/hooks.json` (3 hooks: check engine on Edit/Write, checkpoint on Skill, feedback on Stop). The `plugin.json` has NO hooks field — hooks live exclusively in `hooks/hooks.json`.
- Install: `/plugin marketplace add quantumbitcz/dev-pipeline` then `/plugin install dev-pipeline@quantumbitcz`.

## Governance

- `LICENSE` — Proprietary (QuantumBit s.r.o.)
- `CONTRIBUTING.md` — How to add modules, agents, hooks, skills
- `SECURITY.md` — Vulnerability reporting and plugin security practices
- `.github/CODEOWNERS` — Auto-assigns `@quantumbitcz` to all PRs
- `.github/release.yml` — Auto-generated release notes by PR label
