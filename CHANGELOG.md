# Changelog

All notable changes to the Forge plugin are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased] — Phase 05: Skill Consolidation

### Breaking changes (Phase 05 — skill consolidation)

Seven top-level skills have been removed and their capabilities folded into three unified skills. The skill count is now 28 (down from 35).

| Removed                 | Use instead                              |
|-------------------------|------------------------------------------|
| /forge-codebase-health  | /forge-review --scope=all                |
| /forge-deep-health      | /forge-review --scope=all --fix          |
| /forge-graph-status     | /forge-graph status                      |
| /forge-graph-query      | /forge-graph query <cypher>              |
| /forge-graph-rebuild    | /forge-graph rebuild                     |
| /forge-graph-debug      | /forge-graph debug                       |
| /forge-config-validate  | /forge-verify --config                   |

New: `/forge-review --scope=all --fix` presents an `AskUserQuestion` safety gate before the first commit, unless `autonomous: true` in config or `--yes` is passed. This preserves the safety posture that the standalone `/forge-deep-health` had by virtue of requiring deliberate invocation.

Subcommand dispatch pattern documented in `shared/skill-subcommand-pattern.md`.

### Changed

- `CLAUDE.md` Skills paragraph rewritten for the 28-skill baseline; getting-started flows updated.
- `skills/forge-help/SKILL.md` rewritten — ASCII decision tree replaces tier tables; `--json` envelope bumps to `schema_version: "2"`; new Migration (Phase 05) table.
- `shared/skill-contract.md` §4 Skill categorization rebased to the Phase 05 baseline (10 read-only + 18 writes = 28).
- `README.md`, `shared/graph/{schema,schema-versioning}.md`, `shared/graph/enrich-symbols.sh`, `shared/recovery/health-checks/dependency-check.sh`, `skills/forge-init/SKILL.md` — every `/forge-graph-*` and `/forge-config-validate` reference rewritten to the new `<sub>` form.

### Added

- `tests/structural/skill-consolidation.bats` — 16 assertions locking in skill count, expected names, removed names, subcommand-dispatch sections, `--json` schema_version, CLAUDE.md "(28 total)" header, and a `validate-config.sh` read-only regression guard.
- `tests/lib/module-lists.bash` — `DISCOVERED_SKILLS`, `MIN_SKILLS=28`, and `EXPECTED_SKILL_NAMES` fixture (28 entries).

## [Unreleased] — Phase 14: Time-Travel Checkpoints

### Breaking changes

- **State schema 1.8.0 → 1.9.0.** The linear `.forge/checkpoint-{storyId}.json` checkpoint format is replaced by a content-addressable DAG under `.forge/runs/<run_id>/checkpoints/`. Orchestrators on v1.9.0+ refuse to proceed on pre-1.9.0 state; run `/forge-recover reset` to migrate (no automatic upgrade — the on-disk format is not compatible).

### Added

- `hooks/_py/time_travel/` Python package — CAS checkpoint store (`cas.py`), atomic rewind protocol with per-run `.rewind-tx/` (`restore.py`), GC policy with HEAD-path protection (`gc.py`), and `RewoundEvent` schema (`events.py`).
- `hooks/_py/time_travel/__main__.py` CLI — invoked as `python3 -m hooks._py.time_travel <op>`; supports `list-checkpoints`, `rewind`, `repair`, `gc`. Exit codes 5/6/7 distinguish dirty-worktree, unknown-id, and tx-collision aborts.
- `/forge-recover rewind --to=<id> [--force]` — time-travel to any prior checkpoint with an atomic four-tuple restore (state, worktree, events, memory).
- `/forge-recover list-checkpoints [--json]` — render the checkpoint DAG with HEAD marked.
- Orchestrator `recovery_op: rewind|list-checkpoints` routing (`agents/fg-100-orchestrator.md` §Recovery op dispatch).
- Orchestrator-start crash repair contract: every active run invokes `python3 -m hooks._py.time_travel repair` to roll forward or discard a half-finished rewind tx.
- Pseudo-state `REWINDING` in `shared/state-transitions.md` — appears only in `events.jsonl` `StateTransitionEvent` pairs that bracket a rewind op; never persists to `state.story_state`.
- `recovery.time_travel.*` config block (`enabled`, `retention_days`, `max_checkpoints_per_run`, `require_clean_worktree`, `compression`, `preserve_legacy`).
- `state.json.checkpoints` (append-only audit array) and `state.json.head_checkpoint` (mirrors on-disk `HEAD`).
- `shared/recovery/time-travel.md` — full protocol spec (CAS layout, atomic 5-step restore, crash repair, DAG semantics, GC policy, failure modes).
- `tests/evals/time-travel/` — bats eval harness covering round-trip, dedup, dirty-worktree abort, crash-mid-rewind repair (rollback + roll-forward), tree-DAG golden output, and rewind-then-replay convergence.
- `tests/run-all.sh` — new `time-travel` tier; the `all` and `eval` tiers now also pick up `tests/evals/time-travel/*.bats` when present.

### Changed

- `shared/state-schema.md` — `## § Checkpoints` section replaced with CAS DAG layout; deprecated `## checkpoint-{storyId}.json` section retained for reference only.
- `shared/state-transitions.md` — added `REWINDING` pseudo-state rows and a `§ Rewind transitions` section.
- `skills/forge-recover/SKILL.md` — subcommand table, flags, exit-codes block, examples, and dispatch prose extended for rewind + list-checkpoints.
- `CLAUDE.md` — state-schema version bumped from v1.6.0 → v1.9.0 in the key-entry-points table and state overview.

## [3.0.0] — 2026-04-16

### Breaking changes

- **Removed 7 skills** (no aliases). See `DEPRECATIONS.md` for the migration table.
  - `/forge-diagnose`, `/forge-repair-state`, `/forge-reset`, `/forge-resume`, `/forge-rollback` → `/forge-recover <subcommand>`
  - `/forge-caveman`, `/forge-compression-help` → `/forge-compress <subcommand>`
- Skill count: 41 → 35.
- Every SKILL.md description now prefixed with `[read-only]` or `[writes]` badge.
- Every agent frontmatter now requires explicit `ui: { tasks, ask, plan_mode }` block — implicit Tier-4-by-omission no longer accepted.
- `ui: { tier: N }` shortcut removed in `fg-135`, `fg-510`, `fg-515`.
- `fg-210-validator` promoted Tier 4 → Tier 2 (frontmatter + tools only; behavior unchanged in this release).
- 22 agents received a new `color:` assignment to satisfy cluster-scoped uniqueness.

### Added

- `/forge-recover` skill with 5 subcommands.
- `shared/skill-contract.md` — authoritative skill-surface contract.
- `shared/agent-colors.md` — cluster-scoped color map (42 agents).
- `shared/ask-user-question-patterns.md` — canonical UX patterns.
- 14 Tier 1/2 agents now carry concrete `AskUserQuestion` JSON examples.
- `--help` on every skill; `--dry-run` on every mutating skill; `--json` on every read-only skill.
- Standard exit codes 0–4 documented in `shared/skill-contract.md`.
- `/forge-help --json` output mode.
- `shared/state-schema.md`: `recovery_op` field on orchestrator input payload (schema 1.6.0 → 1.7.0).
- `agents/fg-100-orchestrator.md`: §Recovery op dispatch section.
- `tests/contract/skill-contract.bats`: 8 new assertions.
- `tests/contract/ui-frontmatter-consistency.bats`: 5 new assertions.
- `tests/unit/skill-execution/forge-recover-integration.bats`: SKILL.md surface check.

### Changed

- `/forge-compress` rewritten from single-verb → 4-subcommand (`agents|output <mode>|status|help`).
- `/forge-help` augmented: existing 3-tier taxonomy preserved; added `[read-only]`/`[writes]` badges and `--json` output.
- `tests/unit/caveman-modes.bats` renamed and rewritten → `tests/unit/compress-output-modes.bats`.
- 24 `shared/*.md` references swept from old skill names to new.
- `shared/agent-ui.md`: "Omitting ui: means Tier 4" language removed.
- `shared/agent-role-hierarchy.md`: `fg-205` added; `fg-210` promoted.

### Removed

- `tests/structural/ui-frontmatter-consistency.bats` (duplicate of contract/ copy).
- `tests/unit/skill-execution/forge-compression-help.bats` (skill deleted).

### Migration notes

- All removed skills have direct replacements in the Breaking Changes list.
- No config changes required.
- Agents with new colors render differently in kanban — expected cosmetic change only.

## [2.8.0] - 2026-04-16

### Added
- **F29 Run History Store:** SQLite FTS5 database at `.forge/run-history.db` stores every pipeline run with queryable outcomes, learnings, and agent performance. Schema DDL in `shared/run-history/`, written by `fg-700-retrospective`, queried by `/forge-insights`, `/forge-ask`, and the MCP server. Config: `run_history.*` (enabled, retention_days, fts_enabled). Preflight validation rejects invalid retention ranges. Survives `/forge-recover reset`
- **F30 Forge MCP Server:** Python stdio MCP server in `shared/mcp-server/` exposes pipeline intelligence to any MCP-capable AI client (Claude Desktop, other agents). 11 tools covering runs, learnings, playbooks, scoring trends, agent stats, and wiki queries. Auto-provisioned by `/forge-init` into project `.mcp.json`. WAL-mode SQLite reads, `safe_json` decorator on every tool for graceful degradation on corrupt/missing files. Optional (requires Python 3.10+). Config: `mcp_server.*`
- **F31 Self-Improving Playbooks:** Retrospective analyzes run outcomes and proposes playbook refinements (stage reordering, agent swaps, threshold tuning). JSON schema in `shared/playbooks/refinement-proposal.schema.json`. Orchestrator auto-applies high-confidence refinements at PREFLIGHT with `playbook_pre_refine_version` snapshot for rollback. Proposals stored in `.forge/playbook-refinements/`. New skill `/forge-playbook-refine` for interactive review/apply/reject. Analytics tracked in `.forge/playbook-analytics.json`
- Contract tests for run-history schema, MCP server structure and integration, and playbook refinement proposals (including deferred-status coverage)

### Changed
- `fg-100-orchestrator` gained a PREFLIGHT playbook-refinement step with version-snapshot rollback
- `fg-700-retrospective` now writes a run record to the history store and analyzes outcomes for playbook refinement proposals
- `/forge-init` detects Python 3.10+ and provisions MCP server entry in `.mcp.json` when available
- CLAUDE.md adds F29/F30/F31 to the v2.0 features table and lists `/forge-playbook-refine` in the skill selection guide
- `shared/state-schema.md` registers `run-history.db` and `playbook-refinements/` as survivors of `/forge-recover reset`

### Fixed
- MCP server corrupt-file handling: `safe_json` decorator returns structured error responses instead of crashing when `.forge/` JSON is malformed or absent
- MCP server SQLite reads now use WAL mode to avoid locking conflicts with concurrent retrospective writes
- Field name mismatches and `version_history` population resolved in MCP server response shapes
- Retrospective `retention_days` preflight validator now enforces the documented 1-365 range
- Run-history schema test on macOS: strip the entire FTS5 block (macOS-shipped SQLite lacks FTS5) instead of a partial strip that left dangling syntax
- CI: skip-guard FTS5 tests when SQLite lacks the extension; skill-quality 'Use when' clause restored on new skills

### Performance
- CI bats test execution parallelized across CPU cores via xargs-based batching (~2-3x wall-clock reduction on GitHub-hosted runners)

## [2.7.0] - 2026-04-15

### Added
- **Python Extraction:** Embedded Python in `forge-state.sh` extracted into `shared/python/state_init.py`, `guard_parser.py`, and `state_transitions.py` (full transition table). Shell scripts now call out to versioned Python modules for testability
- **State Schema Migration Engine:** `state_migrate.py` performs the v1.5.0 → v1.6.0 migration (circuit-breaker tracking, planning-critic counter, schema-migration history). Integrated into `forge-state.sh`
- **Planning Critic:** New `fg-205-planning-critic` agent reviews plans for feasibility, risk gaps, and scope issues before validation
- **Circuit Breaker Flapping Detection:** Recovery engine now detects and handles circuit breakers that toggle repeatedly; dedup cap removed (unbounded dedup with size-cap safeguards)
- **Epsilon-Aware Score Comparison:** Helpers for floating-point score equality with documented epsilon semantics; simplified unfixable-INFO formula
- **Context-Aware PREEMPT Decay:** PREEMPT items now decay based on context-match signal strength; cross-project learnings shared via `shared/cross-project-learnings.md`
- **Mermaid Architecture Diagrams:** Pipeline, agents, and state-machine diagrams in `docs/architecture/`
- **Structural Tests:** ui-frontmatter consistency, architecture diagram validation, behavioral tests for 10 previously undertested agents
- `shared/preflight-constraints.md` and `shared/framework-gotchas.md` extracted from CLAUDE.md to keep the root doc lean

### Changed
- State schema bumped to v1.6.0 with documented checkpoint persistence lifecycle and size caps on unbounded state fields
- WAL recovery made atomic via double-check locking
- `FORGE_PYTHON` variable replaces hardcoded `python3` across all shell scripts; exported from `platform.sh`
- `detect_os` now returns `wsl` for WSL environments; bash version warning surfaced on session start
- Sleep-based timeout fallback for hooks on systems without `timeout`/`gtimeout`
- Temp dir cascade standardized (`TMPDIR:-${TMP:-${TEMP:-/tmp}}`) across all shell scripts
- `ui:` frontmatter added to 10 skills; caveman description corrected
- Redundant `skill-routing-guide.md` deleted (content absorbed into `/forge-help`)

### Fixed
- CI test failures from the v2.7.0 upgrade resolved across three follow-up commits

## [2.6.1] - 2026-04-15

### Fixed
- Skill descriptions for `forge-automation`, `forge-config-validate`, and `forge-graph-init` now include the required 'Use when' trigger clause, fixing `skill-quality` contract test failure

## [2.6.0] - 2026-04-14

### Added
- **Environment Health Check:** New `shared/check-environment.sh` script probes for optional CLI tools (jq, docker, tree-sitter, gh, sqlite3) and outputs structured JSON via Python. `/forge-init` now displays a categorized dashboard (required/recommended/optional tools + MCP integrations) with platform-specific install suggestions during Phase 1.1
- **Caveman Benchmark:** New `shared/caveman-benchmark.sh` measures estimated token savings across lite/full/ultra modes. `/forge-compress output benchmark [file]` subcommand for on-demand measurement
- **Dynamic Reviewer Scaling:** Quality gate (`fg-400`) now scales reviewer count by change scope: <50 lines dispatches batch 1 only, 50-500 dispatches all batches, >500 emits `APPROACH-SCOPE | INFO` splitting suggestion. Override with `quality_gate.force_full_review: true`
- **Forge-Help 3-Tier Structure:** Reorganized from flat A-G categories into Essential (7 skills) / Power User (12) / Advanced (20) tiers with "Similar Skills" disambiguation table
- **Platform Troubleshooting:** `/forge-tour` now includes platform-specific setup instructions for WSL2, Git Bash, macOS, and Linux
- **Windows Long Path Guard:** Worktree manager (`fg-101`) detects Windows filesystem paths and enables `core.longpaths`, truncates branch slugs over 200 chars
- **Cross-Reference Network:** Added See Also sections to `convergence-engine.md`, `scoring.md`, `agent-philosophy.md` with bidirectional links
- **PREEMPT Auto-Discovery Rules:** Formalized auto-discovered item decay (MEDIUM start, 2x faster decay, archive at decay_score >= 5, promote after 3 successes)
- **Structural Validation Tests:** `skill-descriptions.bats` (5 tests), `doc-cross-references` (5 tests), 3 new portability checks in `platform-portability.bats`
- **Regression Tests:** `deprecated-python-api.bats` (3 tests), `automation-cooldown.bats` (4 tests), `caveman-benchmark.bats` (5 tests), `check-environment.bats` (10 tests)

### Changed
- Caveman auto-activation default changed from `full` to `lite` (safer compression — keeps grammar and articles). Manual `/forge-compress output` invocation still defaults to `full`. Updated `session-start.sh`, `config-schema.json`, skill docs
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
- 15 skills renamed to `forge-*` prefix: bootstrap-project→forge-bootstrap, codebase-health→forge-codebase-health, config-validate→forge-config-validate, deep-health→forge-deep-health, deploy→forge-deploy, docs-generate→forge-docs-generate, graph-debug→forge-graph-debug, graph-init→forge-graph-init, graph-query→forge-graph-query, graph-rebuild→forge-graph-rebuild, graph-status→forge-graph-status, migration→forge-migration, repair-state→forge-recover repair (consolidated in 3.0.0), security-audit→forge-security-audit, verify→forge-verify
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
- `/forge-compress help` skill — quick reference card for all compression features
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
- 3 new skills: `/forge-abort`, `/forge-recover resume`, `/forge-profile`
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
