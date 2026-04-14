# Changelog

All notable changes to the Forge plugin are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [2.6.0] - 2026-04-14

### Added
- **Environment Health Check:** New `shared/check-environment.sh` script probes for optional CLI tools (jq, docker, tree-sitter, gh, sqlite3) and outputs structured JSON via Python. `/forge-init` now displays a categorized dashboard (required/recommended/optional tools + MCP integrations) with platform-specific install suggestions during Phase 1.1
- **Caveman Benchmark:** New `shared/caveman-benchmark.sh` measures estimated token savings across lite/full/ultra modes. `/forge-caveman benchmark [file]` subcommand for on-demand measurement
- **Dynamic Reviewer Scaling:** Quality gate (`fg-400`) now scales reviewer count by change scope: <50 lines dispatches batch 1 only, 50-500 dispatches all batches, >500 emits `APPROACH-SCOPE | INFO` splitting suggestion. Override with `quality_gate.force_full_review: true`
- **Forge-Help 3-Tier Structure:** Reorganized from flat A-G categories into Essential (7 skills) / Power User (12) / Advanced (20) tiers with "Similar Skills" disambiguation table
- **Platform Troubleshooting:** `/forge-tour` now includes platform-specific setup instructions for WSL2, Git Bash, macOS, and Linux
- **Windows Long Path Guard:** Worktree manager (`fg-101`) detects Windows filesystem paths and enables `core.longpaths`, truncates branch slugs over 200 chars
- **Cross-Reference Network:** Added See Also sections to `convergence-engine.md`, `scoring.md`, `agent-philosophy.md` with bidirectional links
- **PREEMPT Auto-Discovery Rules:** Formalized auto-discovered item decay (MEDIUM start, 2x faster decay, archive at decay_score >= 5, promote after 3 successes)
- **Structural Validation Tests:** `skill-descriptions.bats` (5 tests), `doc-cross-references` (5 tests), 3 new portability checks in `platform-portability.bats`
- **Regression Tests:** `deprecated-python-api.bats` (3 tests), `automation-cooldown.bats` (4 tests), `caveman-benchmark.bats` (5 tests), `check-environment.bats` (10 tests)

### Changed
- Caveman auto-activation default changed from `full` to `lite` (safer compression — keeps grammar and articles). Manual `/forge-caveman` invocation still defaults to `full`. Updated `session-start.sh`, `config-schema.json`, skill docs
- 11 skill descriptions rewritten for better trigger accuracy: forge-fix, forge-shape, forge-diagnose, forge-config, forge-config-validate, forge-compress, forge-automation, forge-bootstrap, forge-graph-init, forge-repair-state, forge-rollback
- Module documentation examples updated to use non-deprecated `datetime.now(timezone.utc)`: cassandra.md, pulsar.md, oauth2.md
- Documented PowerShell incompatibility and platform requirements in CLAUDE.md structural gotchas

### Fixed
- **Critical:** Automation cooldown never fired — `automation-trigger.sh` wrote timestamp as `'ts'` but cooldown reader looked for `'timestamp'`. `KeyError` silently swallowed by `except` clause
- Deprecated `datetime.utcnow()` replaced with `datetime.now(timezone.utc)` + `ImportError` fallback in `automation-trigger.sh`, `session-start.sh`, `feedback-capture.sh`
- Deprecated `datetime.utcfromtimestamp()` replaced with `datetime.fromtimestamp(ts, tz=timezone.utc)` + fallback in `session-start.sh`
- Deprecated `datetime.datetime.utcnow()` replaced with `datetime.datetime.now(datetime.timezone.utc)` + `AttributeError` fallback in `forge-event.sh`

## [2.5.0] - 2026-04-14

### Added
- **Cross-Platform Hardening:** `fcntl`→`msvcrt` fallback for Windows Git Bash, full TMPDIR/TMP/TEMP cascade, multi-platform `check-prerequisites.sh`, `shared/platform-support.md`, `platform.windows_mode` config, cross-platform CI matrix (MacOS, Ubuntu, Windows Git Bash)
- **Build System Intelligence:** `build-system-resolver.sh` introspects Maven, Gradle, npm/pnpm/yarn, Go, Cargo, .NET with heuristic fallback. `module-boundary-map.sh` discovers multi-module project boundaries. Module-aware import resolution with confidence tagging (resolved/module-inferred/heuristic). Build graph quality metrics in state.json
- **Compression & Caveman Alignment:** Unified compression eval harness (`benchmarks/compression-eval.sh`), post-compression validation (`shared/compression-validation.py`) with 8 structural checks, caveman statusline badge `[STATUS: CAVEMAN]`, enhanced SessionStart auto-injection with full compression rule blocks, research references (arXiv:2604.00025)
- **Eval & Benchmarking Framework:** `evals/pipeline/` with eval-runner, 5 suite definitions (lite/25, convergence/10, cost/5, compression/5, smoke/5), 30 fixture stubs across 5 languages, baseline save/compare with regression detection, CI workflow for automated eval
- **Observability & Cost Management:** `cost-alerting.sh` with multi-threshold budget alerting (50/75/90/100%), `context-guard.sh` for quality-focused condensation at 30K tokens, E8 orchestrator intercept (advisory before hard ESCALATED), per-stage cost reporting, model routing cost optimization, enhanced forge-insights Category 3
- **AI-Aware Code Quality:** 4 new wildcard categories (AI-LOGIC-*, AI-PERF-*, AI-CONCURRENCY-*, AI-SEC-*) with 26 discrete sub-categories, 15 L1 regex patterns across 15 language files, cross-category dedup rule for AI-*/non-AI-* overlap, SCOUT-AI learning loop, reviewer guidance for fg-410/fg-411/fg-416
- `shared/agent-role-hierarchy.md` — complete dispatch graph and tier definitions for all 41 agents
- `shared/tracking/ticket-format.md` — FG-NNN ticket format documentation
- `shared/hook-design.md` — hook execution model, ordering, and script contract
- `allowed-tools:` frontmatter on all 40 skills

### Changed
- 15 skills renamed to `forge-*` prefix: bootstrap-project→forge-bootstrap, codebase-health→forge-codebase-health, config-validate→forge-config-validate, deep-health→forge-deep-health, deploy→forge-deploy, docs-generate→forge-docs-generate, graph-debug→forge-graph-debug, graph-init→forge-graph-init, graph-query→forge-graph-query, graph-rebuild→forge-graph-rebuild, graph-status→forge-graph-status, migration→forge-migration, repair-state→forge-repair-state, security-audit→forge-security-audit, verify→forge-verify
- All cross-references updated across 90+ files (skills, agents, CLAUDE.md, README.md, CONTRIBUTING.md, shared docs, tests)
- Category registry expanded from 83 to 87 entries (23→27 wildcard prefixes)
- `/forge-deep-health` now documents fg-413 reviewer modes (full/conventions-only/a11y-only/performance-only)

### Deprecated
- `--sprint` and `--parallel` flags on `/forge-run` — use `/forge-sprint` instead

### Fixed
- `fcntl` import in `tracking-ops.sh` now uses try/except with msvcrt fallback (Windows compatibility)
- Incomplete `/tmp` cascade in `platform.sh:484` (`TMPDIR:-/tmp` → `TMPDIR:-${TMP:-${TEMP:-/tmp}}`)
- `BASH_SOURCE[0]` for path resolution in sourceable graph scripts
- Context-guard config parsing fallback when PyYAML unavailable

## [2.4.0] - 2026-04-14

### Added
- SessionStart hook — auto-activates caveman mode, displays forge status and unacknowledged alerts at session start
- `/forge-commit` skill — terse conventional commit message generator (<=50 char subject, why over what)
- `/forge-compression-help` skill — quick reference card for all compression features
- Next.js App Router variant (`modules/frameworks/nextjs/variants/app-router.md`)
- Agent eval suite (`tests/evals/`) — 41 canonical input/expected pairs for all 8 review agents with convention-coverage checks
- Compression benchmarks (`benchmarks/`) — input compression measurement via programmatic rules, output compression 3-arm eval harness
- Graph schema versioning (`shared/graph/schema-versioning.md`) with migration infrastructure
- 9 new scenario tests: oscillation, recovery budget exhaustion, safety gate, cross-repo, multi-framework composition, nested errors, mode transitions, feedback loop, preview gating
- 57 hook and skill behavioral tests (L0 syntax, check engine, feedback capture, checkpoint, automation trigger, compact check, skill integration)
- Compression semantic integrity tests (verify compressed files preserve category codes, severities, frontmatter, code blocks)
- Cross-reference audit tests (validate markdown links, orchestrator agent references)
- Module overview length enforcement test (15-line soft cap)
- Deprecation migration examples in DEPRECATIONS.md (before/after for all active deprecations)
- Terse review format with text markers `[CRIT]`/`[WARN]`/`[INFO]`/`[PASS]` in forge-review
- Natural language trigger documentation for caveman mode
- `token_pricing` config section for overridable model pricing
- Log rotation for `.hook-failures.log` and `.forge/forge.log`

### Changed
- React TypeScript variant extended with generic components, context typing, strict TypeScript patterns
- Angular TypeScript variant extended with standalone components, signals, built-in control flow, `@defer`
- Vue TypeScript variant extended with typed slots, typed refs, composable patterns
- Django Python variant extended with Python 3.10+ patterns (match statements, async views, Django 5.0+ features)
- Composition engine documents variant selection rules (explicit config > language matching)
- Skill count 38 → 40, hook count 6 → 7
- `MIN_UNIT_TESTS` guard bumped to 93, `MIN_SCENARIO_TESTS` to 40
- Structural check count 51 → 73+
- CLAUDE.md and README.md updated with all new skills, hooks, and test counts

### Fixed
- Race condition in WAL recovery (`forge-state-write.sh`) — mkdir-based lock before concurrent recovery
- WAL truncation race — moved inside write lock scope, cleanup on failure
- Token tracker retry without backoff — exponential backoff with jitter (5 retries)
- Non-atomic compact counter (`forge-compact-check.sh`) — mkdir-based lock
- Datetime format inconsistency — Z suffix added to all timestamp fallback paths
- Model detection substring collision (`forge-token-tracker.sh`) — longest-match-first pattern list
- MacOS `sed` compatibility in `derive_project_id()` — replaced non-greedy `+?` with two-step sed

## [1.16.0] - 2026-04-12

### Changed
- CI test tiers run in parallel via matrix strategy (structural → unit/contract/scenario concurrent)
- `fail-fast: false` ensures all tiers report independently — no hidden failures

### Fixed
- Skip mkdir lock contention test when flock is available (platform-dependent CI failure)

## [1.15.0] - 2026-04-12

### Added
- Skill selection guide in CLAUDE.md for intent→skill routing
- Architecture diagram in README.md (pipeline flow + module resolution)
- Troubleshooting section in README.md (10 common issues with fixes)
- Checkpoint schema reference in CLAUDE.md key entry points (`shared/state-schema.md` §checkpoint)
- Autonomous mode decision documentation in convergence-engine.md
- Cross-references: stage-contract→agent-communication (2K budget), agent-registry tier legend
- Learnings/ and checkpoint-schema references in CLAUDE.md key entry points
- 9 missing skills added to README.md skill table (29 total)
- `portable_timeout` wrapper in run-linter.sh for adapter timeout enforcement
- State validation guard in forge-checkpoint.sh hook
- New test files: hook-failure-scenarios.bats, recovery-burndown.bats, concurrent-state-access.bats
- PREEMPT items populated across 19 framework learnings files

### Fixed
- README.md skill count updated from 25 to 29
- Test framework binding mismatches resolved (angular, express, nestjs)
- 8 skill descriptions improved with "when to use" triggering context

### Changed
- CLAUDE.md updated from 25 to 29 skills with selection guide
- forge-checkpoint.sh validates state.json structure before atomic update

## [1.13.0] - 2026-04-12

### Added
- Skill routing guide (`shared/skill-routing-guide.md`) for canonical intent→skill mapping
- 3 new skills: `/forge-abort`, `/forge-resume`, `/forge-profile`
- Prerequisite checks for 7 skills (forge-run, forge-fix, forge-review, codebase-health, deep-health, graph-status, graph-query)
- `autonomous` field in state schema for fully autonomous pipeline runs
- Transition lock (`FD 201`) in `forge-state.sh` for concurrent transition safety
- Token tracker retry on stale `_seq` with up to 3 re-read/recompute attempts
- `phase_iterations >= 2` guard on convergence rows C8/C10 (first-cycle exemption)
- Row C10a: baseline-exempt plateau handling for first 2 convergence cycles
- Mode overlay → transition interaction documentation in `state-transitions.md`
- Recovery budget ↔ total retries independence documentation
- `smoothed_delta` scoping to current-phase scores after safety gate restart
- 80+ new BATS tests (state transitions per-row, convergence engine advanced)
- Hook failure visibility in session summary (`feedback-capture.sh`)
- Small file skip heuristic in engine.sh hook mode (files < 5 lines)

### Fixed
- Bash 3.2 compatibility: replaced `(( ))` arithmetic with `[ -lt ]` in engine.sh
- FD 200 leak in engine.sh: added cleanup in `handle_skip()` and EXIT trap
- `return 1` → `exit 1` in `platform.sh` `atomic_increment()` subshell
- `forge-checkpoint.sh` silent crash: removed blanket `{ } 2>/dev/null`, added type guard
- `forge-compact-check.sh` race condition: added flock-based fallback
- `feedback-capture.sh`: replaced bare `except:` with specific types, f-strings with `.format()`
- `scoring.md` effective_target formula aligned with `convergence-engine.md` (added `max(pass_threshold, ...)` floor)
- Error JSON output to stderr in `forge-state.sh` transition errors
- Signal trap for temp file cleanup in `forge-state.sh`
- Token tracker string interpolation: shell vars replaced with `sys.argv`
- fg-300 test file modification contradiction resolved with decision table
- fg-160 plan mode contradiction resolved with 3 clear contexts

### Changed
- 8 skill descriptions updated for routing clarity and disambiguation
- CLAUDE.md skill count updated from 25 to 28

## [1.12.0] - 2026-04-10

### Added
- Explicit `ui:` blocks on fg-410, fg-412, fg-420 for spec 1.7 completeness
- 3 new diagnostic skills

### Fixed
- Comprehensive code review findings (C1-C4, I1-I7, S1)
- Phase C code review findings (C1, I1-I7, S2-S5)
