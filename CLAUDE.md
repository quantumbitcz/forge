# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`dev-pipeline` is a Claude Code plugin (v1.0.0, installable from the `quantumbitcz` marketplace or as a Git submodule). It orchestrates a 10-stage autonomous development pipeline: Preflight → Explore → Plan → Validate → Implement (TDD) → Verify → Review → Docs → Ship → Learn. The entry point is the `/pipeline-run` skill which dispatches `pl-100-orchestrator`.

## Architecture

Three-layer design with resolution flowing top-down:

1. **Project config** (`.claude/dev-pipeline.local.md`, `.claude/pipeline-config.md`, `.claude/pipeline-log.md`) — per-project settings, mutable runtime params, and accumulated learnings. Lives in the consuming repo, not here.
2. **Module layer** (`modules/`) — three sublayers for convention composition:
   - `modules/languages/` — 9 language files (kotlin, java, typescript, python, go, rust, swift, c, csharp): language-level idioms, type conventions, and baseline rules.
   - `modules/frameworks/` — 17 framework directories (spring, react, fastapi, axum, swiftui, vapor, express, sveltekit, k8s, embedded, go-stdlib, aspnet, django, nextjs, gin, jetpack-compose, kotlin-multiplatform), each with `conventions.md`, config files, `variants/` for language-specific overrides, and `testing/` for framework-specific test patterns.
   - `modules/testing/` — 11 generic testing framework files (kotest, junit5, vitest, jest, pytest, go-testing, xctest, rust-test, xunit-nunit, testcontainers, playwright).
   Convention composition order (most specific wins): variant > framework-testing > framework > language > testing.
3. **Shared core** (`agents/pl-*.md`, `shared/`, `hooks/`, `skills/`) — the pipeline engine itself.

Parameter resolution: `pipeline-config.md` > `dev-pipeline.local.md` > plugin hardcoded defaults.

## Quick start

```bash
# Verify everything is intact after cloning
./tests/validate-plugin.sh          # 27 structural checks, ~2s
./tests/run-all.sh                  # Full test suite, ~30s

# To test in a consuming project
ln -s "$(pwd)" /path/to/project/.claude/plugins/dev-pipeline
cd /path/to/project && claude       # then run /pipeline-init
```

## Development workflow

This is a documentation-only plugin (no build step). To test changes:

1. Install locally: symlink or clone into `.claude/plugins/` of a test project
2. Run `/pipeline-init` in the test project to generate config files
3. Run `/pipeline-run --dry-run <requirement>` to verify PREFLIGHT through VALIDATE
4. Run `/pipeline-run <requirement>` for a full end-to-end test
5. Check `.pipeline/state.json` and stage notes for correct behavior

### CI validation

```bash
# Option 1: Full structural validation (recommended)
./tests/validate-plugin.sh    # 27 checks, ~2s

# Option 2: Inline smoke test for minimal CI
set -e
test "$(grep -l '^name:' agents/*.md | wc -l)" -ge 25
for m in modules/frameworks/*/; do
  ls "$m"{conventions.md,local-template.md,pipeline-config-template.md,rules-override.json,known-deprecations.json} > /dev/null
done
test "$(ls modules/languages/*.md | wc -l)" -ge 9
test "$(ls modules/testing/*.md | wc -l)" -ge 11
test -z "$(find modules/ hooks/ shared/ -name '*.sh' ! -perm -111 2>/dev/null)"
grep -q '"version": 1,' modules/frameworks/*/known-deprecations.json && exit 1 || true
echo "Plugin structure OK"
```

## Key conventions

### Agent inventory (29 agents)

| Agent | Stage | Role |
|-------|-------|------|
| `pl-010-shaper` | Pre-pipeline | Feature spec shaping (epics, stories, AC) |
| `pl-050-project-bootstrapper` | Pre-pipeline | New project scaffolding from module template |
| `pl-100-orchestrator` | All | Coordinator — dispatches all other agents |
| `pl-140-deprecation-refresh` | 0 PREFLIGHT | Refreshes `known-deprecations.json` via Context7 |
| `pl-150-test-bootstrapper` | 0 PREFLIGHT | Bootstraps test coverage when below threshold |
| `pl-160-migration-planner` | 0 PREFLIGHT | Library/framework migration planning |
| `pl-200-planner` | 2 PLAN | Implementation planning with Challenge Brief |
| `pl-210-validator` | 3 VALIDATE | Plan validation (6 perspectives) |
| `pl-250-contract-validator` | 3 VALIDATE | Cross-repo API contract breaking change detection |
| `pl-300-implementer` | 4 IMPLEMENT | TDD implementation (RED → GREEN → REFACTOR) |
| `pl-310-scaffolder` | 4 IMPLEMENT | File structure scaffolding before implementation |
| `pl-320-frontend-polisher` | 4 IMPLEMENT | Creative frontend polish (animations, responsive, dark mode) |
| `pl-400-quality-gate` | 6 REVIEW | Multi-batch review coordinator, scoring, verdicts |
| `pl-500-test-gate` | 5 VERIFY | Test execution and analysis coordinator |
| `pl-600-pr-builder` | 8 SHIP | PR creation with linked cross-repo PRs |
| `pl-650-preview-validator` | 8 SHIP | Preview deployment validation (Lighthouse, visual regression) |
| `pl-700-retrospective` | 9 LEARN | Post-run analysis, convention evolution, learnings |
| `pl-710-feedback-capture` | 9 LEARN | User feedback recording on session exit |
| `pl-720-recap` | 9 LEARN | Human-readable run summary |
| `architecture-reviewer` | 6 REVIEW | Architecture patterns, SRP, DIP, boundaries |
| `security-reviewer` | 6 REVIEW | OWASP, auth, injection, secrets |
| `frontend-reviewer` | 6 REVIEW | Frontend code quality, conventions, framework rules |
| `frontend-design-reviewer` | 6 REVIEW | Design system compliance, visual hierarchy, Figma comparison |
| `frontend-a11y-reviewer` | 6 REVIEW | WCAG 2.2 AA deep audits (contrast, ARIA, focus, touch targets) |
| `frontend-performance-reviewer` | 6 REVIEW | Bundle size, rendering, lazy loading, code splitting |
| `backend-performance-reviewer` | 6 REVIEW | DB queries, caching, algorithms, N+1 |
| `version-compat-reviewer` | 6 REVIEW | Dependency conflicts, language features, runtime API removals |
| `infra-deploy-reviewer` | 6 REVIEW | K8s, Helm, Terraform, Docker configuration |
| `infra-deploy-verifier` | 8 SHIP | Deployment health verification |

### Agent files (`agents/*.md`)
- YAML frontmatter is required: `name` (must match filename without `.md`), `description`, `tools`. The `tools` list defines which tools the agent can use when dispatched — agents that dispatch other agents (orchestrator, quality-gate, test-gate) **must** include `Agent` in their tools list.
- Project module configuration uses a `components:` structure in `dev-pipeline.local.md` with `language:`, `framework:`, `variant:`, and `testing:` fields (replaces the old flat `module:` field). PREFLIGHT reads this to determine which convention layers to load.
- Pipeline agents use `pl-{NNN}-{role}` naming (e.g., `pl-300-implementer`).
- Cross-cutting review agents use descriptive names without module prefix: `architecture-reviewer`, `security-reviewer`, `frontend-reviewer`, `frontend-performance-reviewer`, `backend-performance-reviewer`, `infra-deploy-reviewer`, `infra-deploy-verifier`, `version-compat-reviewer`, `frontend-design-reviewer`, `frontend-a11y-reviewer`.
- The orchestrator (`pl-100-orchestrator`) never writes code itself — it dispatches specialized agents per stage.
- The recap agent (`pl-720-recap`) generates a human-readable summary of each pipeline run during Stage 9 (LEARN), after the retrospective.
- **Worktree isolation:** All implementation runs in a git worktree (`.pipeline/worktree`). The user's working tree is never modified during pipeline execution. Branch collision is detected at creation time (epoch suffix fallback).
- **Critical thinking:** All agents reference `shared/agent-philosophy.md` — shared principles for challenging assumptions, considering alternatives, and seeking disconfirming evidence.
- **Challenge Brief:** The planner (`pl-200-planner`) must produce a Challenge Brief section in every plan, documenting the considered alternative approaches and justification for the chosen one. The validator (`pl-210-validator`) returns REVISE if the Challenge Brief is missing.
- **Approach quality:** `APPROACH-*` is a finding category for solution quality issues (suboptimal pattern, unnecessary complexity, missed simplification). Scored as INFO (-2). Recurring APPROACH findings (3+ times) are escalated to convention rules by the retrospective.

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
- State schema version: **1.0.0** (semver). Version 1.0.0 is a clean break — old state files from previous schema versions are incompatible; use `/pipeline-reset` to clear them.
- Pipeline state lives in `.pipeline/` (gitignored, local only). Checkpoints are saved after each task for resume-on-interrupt.
- **Concurrent run lock:** `.pipeline/.lock` prevents two pipeline runs on the same project. Stale detection via PID check + 24-hour timeout.
- **Version detection:** PREFLIGHT detects project dependency versions from manifest files (build.gradle.kts, package.json, go.mod, etc.) and stores in `state.json.detected_versions`. Enables version-aware deprecation rule gating.
- PREEMPT system: learnings from `pipeline-log.md` are proactively applied to matching domain areas in new runs. Hit counts tracked via `preempt_items_status` in state.json. Confidence decay: 10 domain-matched unused runs → demotion (HIGH → MEDIUM → LOW → ARCHIVED). False positives accelerate decay (1 FP = 3 unused runs).
- **Recovery engine** (`shared/recovery/recovery-engine.md`) with 7 strategies and **weighted budget**: transient-retry (0.5), tool-diagnosis (1.0), state-reconstruction (1.5), agent-reset (1.0), dependency-health (1.0), resource-cleanup (0.5), graceful-stop (0.0). Budget ceiling: 5.0 total weight. Warning at 80%.
- **State reconstruction:** Corrupted state counters are recovered from checkpoint artifacts and stage notes. Fallback uses configured maximum (conservative), not zero.
- Health checks (`shared/recovery/health-checks/`) run pre-stage dependency and environment validation.
- **Cross-repo state:** `state.json.cross_repo` tracks per-project worktrees and status when `related_projects` is configured. Each entry contains `path`, `branch`, `status` (implementing | complete | failed), `files_changed`, and `pr_url`. Cleaned up by `/pipeline-rollback` or `/pipeline-reset`.

### Linear Integration (optional)
- If Linear MCP is available, the pipeline creates an Epic with Stories and Tasks during PLAN, updates ticket statuses per stage, and posts quality findings and recap summaries as comments.
- Configured via `linear:` section in `dev-pipeline.local.md` (disabled by default).
- **Mid-run resilience:** Linear failures retry once (3s delay), then degrade gracefully. Failed operations tracked in `state.json.linear_sync`. Recovery engine is NOT invoked for MCP failures.
- Graceful degradation: pipeline runs without Linear when MCP is unavailable.

### Adaptive MCP Detection
- The `pipeline-run` skill detects available MCPs (Linear, Playwright, Slack, Context7, Figma) in the main session context and passes results to the orchestrator via the dispatch prompt. Fallback: orchestrator reads `.mcp.json` directly.
- Each agent uses MCPs relevant to its stage (e.g., Playwright for preview validation, Context7 for documentation lookup and migration guides).
- **Mid-run health:** First MCP failure marks it as degraded for the rest of the run. Subsequent dispatches skip it without timeout delays.
- No MCP is required. The pipeline adapts to whatever the user has installed and suggests missing optional MCPs.

### Cross-Repo Discovery
- During `/pipeline-init`, a 5-step discovery chain finds related projects (frontend, infra, mobile) automatically.
- Discovery chain: in-project references → sibling directory scan → IDE project directories → GitHub org scan → user prompt.
- Results stored in `dev-pipeline.local.md` under `related_projects:` with path, repo, framework, and detection method.
- Configurable via `discovery:` section: `enabled`, `scan_depth` (1-4), `confirmation_required`.
- During pipeline runs: `pl-250-contract-validator` diffs API specs cross-repo (dispatched conditionally during VALIDATE when plan touches contracts), PR builder creates linked PRs, orchestrator manages multi-repo worktrees.
- Cross-repo state tracked in `state.json.cross_repo` — one entry per related project with `path`, `branch`, `status`, `files_changed`, and `pr_url`.

### Frontend design (`shared/frontend-design-theory.md`)
- Design theory guardrails shared by all frontend agents: Gestalt principles, visual hierarchy, color theory (60/30/10 rule), typography rules, 8pt spacing grid, motion principles, and anti-AI guardrails.
- `pl-320-frontend-polisher` runs after `pl-300-implementer` for frontend component tasks (conditional on `frontend_polish.enabled`). Adds animations, micro-interactions, responsive polish, dark mode refinement. Does NOT change business logic or break tests.
- `frontend-design-reviewer` evaluates design system compliance, visual hierarchy, spatial composition, responsive behavior (375px/768px/1280px), dark mode, and optional Figma MCP comparison during REVIEW.
- `frontend-a11y-reviewer` performs deep WCAG 2.2 AA audits: color contrast analysis, ARIA tree validation, focus management, touch targets, screen reader compatibility during REVIEW.
- Convention files for React, NextJS, and SvelteKit include Animation & Motion and Multi-Viewport Design sections.
- Check engine Layer 1 patterns enforce design tokens (hardcoded hex/rgb detection) and animation performance (layout property animation, prefers-reduced-motion hints).

### Check engine (`shared/checks/`)
- 3-layer generalized check engine triggered on every `Edit`/`Write` via PostToolUse hook.
- **Layer 1 — Fast patterns** (`layer-1-fast/`): regex-based pattern matching, sub-second.
- **Layer 2 — Linter** (`layer-2-linter/`): framework-aware linter adapters with configurable defaults.
- **Layer 3 — Agent** (`layer-3-agent/`): AI-driven checks dispatched by the orchestrator and quality gate (not by `engine.sh`). Two agents: `pl-140-deprecation-refresh` (refreshes `known-deprecations.json` during PREFLIGHT via Context7 and package registries) and `version-compat-reviewer` (analyzes dependency conflicts, language feature compatibility, and runtime API removals — dispatched by the orchestrator during REVIEW after quality gate batches complete). **Version-gated:** deprecation rules only fire when project version >= `applies_from` in the deprecation entry.
- Modules customize checks via `rules-override.json` (per-module overrides of shared defaults).
- **Skip tracking:** If the hook times out, a counter in `.pipeline/.check-engine-skipped` is incremented. VERIFY Phase A reads and reports the count.
- Output format standardized in `output-format.md`.

### Deprecation registries (`modules/frameworks/*/known-deprecations.json`)
- **Schema v2** with version-aware fields: `pattern`, `replacement`, `package`, `since`, `removed_in`, `applies_from`, `applies_to`, `added`, `addedBy`.
- `applies_from`: minimum project version where the rule triggers. `removed_in`: version where the API was removed (null if only deprecated). `applies_to`: upper bound (usually `"*"`).
- Rules are skipped when project version < `applies_from`. Severity: WARNING if deprecated, CRITICAL if `removed_in` reached. Unknown project versions → conservative (all rules apply).
- Auto-updated by `pl-140-deprecation-refresh` during PREFLIGHT via Context7 and package registries (conditional on Context7 availability and detected versions).

### Learnings (`shared/learnings/`)
- Per-framework learnings files (e.g., `spring.md`, `react.md`) — accumulated patterns from past runs.
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
- `pipeline-init` — initializes `.claude/dev-pipeline.local.md` and `.claude/pipeline-config.md` for a consuming project. Runs the 5-step cross-repo discovery chain to populate `related_projects:` automatically.
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
- `pipeline-shape` — collaboratively shapes features into structured specs with epics, stories, and acceptance criteria via `pl-010-shaper`. Produces `.pipeline/specs/` files consumable by `pipeline-run --spec`.
- Frontend-specific commands (`fe-check-theme`, `fe-design-review`, `fe-dark-mode-check`, `fe-react-doctor`) are project-level — they live in the consuming project's `.claude/commands/`, not in this plugin. See `modules/frameworks/react/conventions.md` for descriptions.

### Hooks (`hooks/hooks.json`)
- **Check engine** — PostToolUse on `Edit|Write`; runs `shared/checks/engine.sh --hook` (layer 1-2 fast checks on every file change). On timeout: increments skip counter, exits 0 (never blocks edits).
- `pipeline-checkpoint.sh` — PostToolUse on `Skill`; saves checkpoint after each Skill execution.
- `feedback-capture.sh` — Stop hook; captures user feedback on session exit.

## Adding a new framework

Create `modules/frameworks/{name}/` with:
- `conventions.md` — agent-readable framework conventions (must include Dos/Don'ts section)
- `local-template.md` — project config template (YAML frontmatter, using `components:` structure)
- `pipeline-config-template.md` — mutable runtime params template (must include `total_retries_max` and `oscillation_tolerance`)
- `rules-override.json` — framework-specific overrides for the shared check engine (pattern rules, linter config)
- `known-deprecations.json` — registry of deprecated APIs in schema v2 (`applies_from`, `removed_in`, `applies_to` fields required). Seed with 5-15 ecosystem-specific entries. Auto-updated by `pl-140-deprecation-refresh`.
- Optional: `variants/{language}.md` — language-specific convention overrides (e.g., `variants/kotlin.md` under the spring framework)
- Optional: `testing/{test-framework}.md` — framework-specific test patterns that extend the generic testing file
- Optional: `scripts/check-*.sh` (verification), `hooks/*-guard.sh` (PostToolUse guards)

Add a learnings file at `shared/learnings/{name}.md`. Wire the framework into the local template's `quality_gate` batches.

**If adding a new language** (not just a framework), also create `modules/languages/{lang}.md` with language-level idioms, type conventions, and baseline rules.

**If adding a new testing framework**, also create `modules/testing/{test-framework}.md` with generic (framework-agnostic) test patterns for that testing tool.

## Module specifics

All 17 frameworks follow the same base structure under `modules/frameworks/{name}/` (`conventions.md`, `local-template.md`, `pipeline-config-template.md`, `rules-override.json`, `known-deprecations.json`). Each `conventions.md` includes a Dos/Don'ts section with framework-specific best practices. Language-level conventions live in `modules/languages/{lang}.md` and are composed on top of the framework layer at runtime. Detailed notes below for frameworks with non-obvious conventions:

### spring (`modules/frameworks/spring/`)
- Kotlin variant (`variants/kotlin.md`): hexagonal architecture with sealed interface hierarchy (`XxxPersisted`, `XxxNotPersisted`, `XxxId`), ports & adapters pattern.
- Kotlin variant: core uses Kotlin types (`kotlin.uuid.Uuid`, `kotlinx.datetime.Instant`); persistence layer uses Java types.
- Reactive stack: WebFlux + R2DBC + CoroutineCrudRepository.
- `@Transactional` on use case impls only, never on adapters. R2DBC UPDATE sets all columns — use `@Query` for partial updates.

### react (`modules/frameworks/react/`)
- Typography via inline `style={{ fontSize }}`, not Tailwind `text-*` classes.
- Colors via theme tokens (`bg-background`, `text-foreground`), never hardcoded hex.
- Check engine enforces: theme tokens, function size (~30 lines), file size (~400 lines, prefer ~200 per component), import order, no deprecated APIs.
- Error Boundaries required around route-level components. State management: server data in TanStack Query/SWR, not useState.

### embedded (`modules/frameworks/embedded/`)
- Real-time safety: no `malloc`/`printf`/`float` in ISR handlers, maximum 10us ISR duration.
- `volatile` for all ISR-shared variables. RTOS: message queues for inter-task communication, mutexes with priority inheritance.

### k8s (`modules/frameworks/k8s/`)
- `language: null` — infra framework with no language layer loaded.
- All containers: resource requests AND limits, readiness + liveness probes, non-root `securityContext`.
- Pin image tags to SHA digests in production. Observability: Prometheus metrics, structured JSON logging, OpenTelemetry tracing.

### swiftui (`modules/frameworks/swiftui/`)
- Memory safety: `[weak self]` in stored closures, delegates as `weak var`. Prefer `struct` for data models, `actor` for thread-safe state.
- SPM preferred over CocoaPods. Pin to exact versions for releases.

### Other frameworks (standard patterns, see their `conventions.md` for details)

| Framework | Architecture | Testing |
|-----------|-------------|---------|
| aspnet | Clean Architecture: Controllers → Services → Repositories, EF Core | xUnit + FluentAssertions |
| django | MTV + DRF: apps as bounded contexts, Django ORM | pytest + factory_boy |
| nextjs | App Router, Server/Client Components, Server Actions | Vitest + Playwright |
| gin | Handler → Service → Repository, middleware chains, interface DI | Go testing + testify |
| jetpack-compose | MVVM: Composables → ViewModels → Repositories, Hilt DI | Compose testing + Robolectric |
| kotlin-multiplatform | Shared `commonMain` + platform modules, Ktor Client, Koin DI | Kotest in commonTest |

## Validation

### Full test suite

```bash
# Run all tests (~30s)
./tests/run-all.sh

# Run individual tiers
./tests/run-all.sh structural   # Plugin integrity (27 checks, no bats needed)
./tests/run-all.sh unit         # Shell script behavior (8 test files)
./tests/run-all.sh contract     # Document contract compliance (11 test files)
./tests/run-all.sh scenario     # Multi-script integration (7 test files)
```

### Manual checks

Most checks are covered by `./tests/validate-plugin.sh`. These additional checks are useful when debugging:

```bash
# List all agents with descriptions
grep -A1 "^name:" agents/*.md

# Dry-run the check engine
shared/checks/engine.sh --dry-run

# Verify Linear config in all framework templates
for m in modules/frameworks/*/local-template.md; do grep -q "linear:" "$m" || echo "MISSING: $m"; done

# Verify pipeline-config templates have required fields
for m in modules/frameworks/*/pipeline-config-template.md; do grep -q "total_retries_max" "$m" || echo "MISSING: $m"; done

# Verify all agents have Forbidden Actions section
grep -L "Forbidden Actions" agents/*.md
```

## Gotchas

- Agent `name` in frontmatter **must** match the filename without `.md` — the orchestrator uses it for dispatch.
- Scripts must have a shebang (`#!/usr/bin/env bash`) and be `chmod +x` — hooks fail silently without this.
- `shared/` files are contracts: changing `scoring.md`, `stage-contract.md`, `state-schema.md`, or `frontend-design-theory.md` affects all agents and modules. Verify downstream impact before editing. State schema changes bump the semver version; because 1.0.0 is a clean break, incompatible old state files must be cleared with `/pipeline-reset`.
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
- Convention composition order is: variant > framework-testing > framework > language > testing. The most specific layer wins on any conflicting rule.
- Framework-less projects (`framework: go-stdlib` or `framework: null` in `components:`): skip the framework and variant layers. Only language + testing conventions are loaded.
- Infra frameworks (`k8s`): `language: null` — no language layer is loaded. Only the framework layer applies.
- The `components:` structure in `dev-pipeline.local.md` (`language:`, `framework:`, `variant:`, `testing:`) replaces the old flat `module:` field. Old `module:` configs are not supported.
- Framework-level `testing/` files (e.g., `modules/frameworks/spring/testing/kotest.md`) EXTEND the generic `modules/testing/kotest.md` — they add framework-specific patterns on top, they do not replace the generic file.
- Cross-repo worktrees use alphabetical lock ordering to prevent deadlocks when multiple related projects are modified simultaneously.
- Cross-repo PR failures don't block the main PR — main repo changes are always preserved. Failed cross-repo PRs are logged in `state.json.cross_repo` with `status: failed`.
- Discovery results are stored with `detected_via` for audit trail — re-run `/pipeline-init` to refresh if related projects change.

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
