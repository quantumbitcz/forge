# Changelog

All notable changes to the Forge plugin are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

## [4.0.0] - 2026-04-27

### Breaking

- Renamed `fg-205-planning-critic` → `fg-205-plan-judge` with binding REVISE authority.
- Renamed `fg-301-implementer-critic` → `fg-301-implementer-judge` with binding REVISE authority.
- State schema bumped v1.x → v2.0.0 (coordinated with Phases 6 and 7). Fields `critic_revisions` and `implementer_reflection_cycles` removed; replaced by `plan_judge_loops` (int), `impl_judge_loops` (object keyed by task_id), `judge_verdicts[]` (array of {judge_id, verdict, dispatch_seq, timestamp}).
- Stage 6 REVIEW migrated from batched-dispatch-with-dedup-hints to Agent Teams pattern (shared findings store at `.forge/runs/<run_id>/findings/<reviewer>.jsonl`, append-only, read-peers-before-write).
- `shared/agent-communication.md` Shared Findings Context section deleted; replaced by Findings Store Protocol reference.
- fg-400-quality-gate §5.2 (inter-batch dedup hints / "previous batch findings" / "top 20" prose) deleted — fg-400 still dispatches reviewers in parallel fan-out, but dedup is now read-time per the Findings Store Protocol (`shared/findings-store.md`). Reviewer registry §20 shrunk to a 3-line reference; orchestrator injects the registry slice into the Stage 6 dispatch payload (`fg-100` SS6.1a) and fg-400 forwards it verbatim into each reviewer's prompt.
- v1.x state.json files are auto-invalidated on version mismatch (no migration shim, per `feedback_no_backcompat`).

## [3.10.0] - 2026-04-27

Phase 4 of the A+ roadmap (Learnings Dispatch Loop) ships. The learning database becomes an active prompt-time input: relevant learnings inject into agent prompts at PLAN/IMPLEMENT/REVIEW, then reinforce via marker-protocol parsing at LEARN.

### Added

- **Phase 4: Learnings Dispatch Loop**
  - **Foundation modules:**
    - `hooks/_py/memory_decay.py` — `pre_fp_base` snapshot, `apply_vindication()` for bit-exact restore, `archival_floor()` returning `(bool, reason)`. New constants: SPARSE_THRESHOLD, MAX_DELTA_T_DAYS, ARCHIVAL_CONFIDENCE_FLOOR, ARCHIVAL_IDLE_DAYS, VINDICATE_FALLBACK_FACTOR.
    - `hooks/_py/agent_role_map.py` — frozen 12-entry MappingProxyType (fg-200, fg-300, fg-400, 9 reviewers). `role_for_agent()` API.
    - `hooks/_py/learnings_selector.py` — frozen `LearningItem` dataclass + `select_for_dispatch()` with role/domain/recency/cross-project ranking and id-ascending tiebreak.
    - `hooks/_py/otel_attributes.py` — 5 `FORGE_LEARNING_*` constants + `FORGE_AGENT_NAME` registered in UNBOUNDED/BOUNDED_ATTRS.
  - **Schema migration:** v1 → v2 across 292 learning files in `shared/learnings/`. Migration script removed after successful application (no shim, per "no back-compat" rule).
  - **I/O stack:** `learnings_io.py` (parser, `_body_slice` scoped past frontmatter, matches `id="X"` HTML anchors), `learnings_format.py` (`## Relevant Learnings` block renderer + `_sanitize` strips control bytes), `learnings_markers.py` (line-anchored parser for LEARNING_APPLIED / LEARNING_FP / LEARNING_VINDICATED), `learnings_writeback.py` (applies markers + archival floor with idempotent updates).
  - **Orchestrator dispatch seam:** `agents/fg-100-orchestrator.md` §0.6.1 builds dispatch context, wraps the rendered block in `<untrusted source="learnings">` envelope before concatenating into the agent prompt. Cache invalidation at LEARN stage.
  - **12 agent prompts** — fg-200, fg-300, fg-400, and the nine reviewers (fg-410..414, fg-416..419) gain `## Learnings Injection` sections describing how they consume the injected block and emit reinforcement markers.
  - **Tests:** structural decay-singleton bats; orchestrator-seam contract bats; cache-invalidation contract bats; integration test exercising the full loop; sanitization hardening tests; `_body_slice` smoke test against real spring.md (204 items render real prose, zero empty bodies).
  - **Documentation:** `decay.md` (explicit formulas + §10 Vindication), `learnings/README.md` (§Read Path), `cross-project-learnings.md` (§Selector Interaction), `observability.md` (forge.learning.* events + attributes), `agent-communication.md` (§Learning Markers parallel to §PREEMPT), `CLAUDE.md` (Phase 4 read path summary).

### Changed

- `state.learnings_cache` field documented in `shared/state-schema-fields.md`.
- `_body_slice` rewritten — was matching anchors inside YAML frontmatter, leaking schema text into rendered prompts. Now scoped past frontmatter and aligned with the `<a id="X">` migration convention.
- `body_ref` values normalized to bare ids (no `#` prefix) across 28 learning files; legacy `#X` form still tolerated.
- `bats` contract tests use `python3` explicitly (cross-platform).

### Process

30 plan tasks across 28 implementation commits. Code review via `superpowers:requesting-code-review` found 3 critical / 6 important / 8 minor. All 17 issues fixed across 10 follow-up commits before release. Critical #1+#2 (`_body_slice` broken end-to-end) caught before any agent dispatch saw malformed payloads. Phase 1-3 ACs re-verified (in scope) — no regressions.

## [3.9.0] - 2026-04-27

Phase 3 of the A+ roadmap (Correctness Proofs) ships. Closes 4 correctness gaps with proof-grade infrastructure.

### Added

- **Phase 3: Correctness Proofs**
  - **Convergence engine `>=` boundary fix:** flipped strict `>` to `>=` in `shared/convergence_engine_sim.py` and `shared/python/state_transitions.py`. Off-by-one bug fix that under-counted plateau iterations. 4 new boundary tests in `tests/unit/test_convergence_engine_sim.py` (16 tests pass total). Documentation aligned in `convergence-engine.md`, `state-transitions.md` rows 37/C9, `convergence-examples.md` (Scenarios 5+6), CLAUDE.md.
  - **End-to-end dry-run smoke harness** at `tests/e2e/dry-run-smoke.py` — symlinks plugin into a temp project (Windows junction fallback), runs forge through PREFLIGHT→VALIDATE only, verifies state.json shape. `--self-test` negative control. Exit-77 SKIP semantics for env-level failures. Cross-OS `e2e:` job in `.github/workflows/test.yml`. Fixture: `tests/e2e/fixtures/ts-vitest/`.
  - **State-transitions sensitivity probe** at `tests/mutation/state_transitions.py` (renamed from "mutation testing" to clarify semantics — flips bats scenario assertions via MUTATE_ROW env var; not classical source mutation). Negative-control baseline run per seed row. 5 seed rows. Canary fixtures + tests. New `mutation:` CI job. Schema test pins REPORT.md columns.
  - **Scenario coverage reporter** at `tests/scenario/report_coverage.py` — walks `# Covers:` headers, generates `tests/scenario/COVERAGE.md` matrix vs `state-transitions.md` rows. Tightened table parser (gates on canonical headers only). Python 3.10+ pinned. New `coverage:` CI job with **T-* hard gate at 60%** (current: 86.3%, well above). Backfilled `# Covers:` headers across the entire scenario suite (T-* coverage 19.6% → 86.3%).
  - **Pathlib-only enforcement** extended to all 3 new Phase 3 harnesses.
  - **`tests/README.md`** — 8-tier matrix + regen workflow.
  - **`README.md`** — testing tier matrix added.

### Changed

- `tests/scenario/oscillation.bats` test 5 tolerance bumped 20 → 21 to reflect post-`>=` boundary semantics (delta=-20 now equals tolerance=20 → REGRESSING; tolerance=21 preserves "very permissive" intent).
- 51 existing scenario `.bats` files gained `# Covers:` headers (4 explicitly enumerate every T-/C-/E-/D-/R- row; 47 are placeholder pending follow-up).
- `tests/validate-plugin.sh` Phase 3 harness check now prints stderr on parse failure (was silenced).

### Process

29 plan tasks landed across 11 implementation commits. Code review via `superpowers:requesting-code-review` found 2 critical / 7 important / 11 minor. All 20 issues fixed across 14 follow-up commits before release. Phase 1 + Phase 2 ACs re-verified after Phase 3 fixes (in scope of mutation harness changes) — no regressions.

## [3.8.0] - 2026-04-27

Phase 2 of the A+ roadmap (Contract Enforcement) ships. Closes 5 contract and hygiene gaps.

### Added

- **Phase 2: Contract Enforcement**
  - 5 pytest contract tests under `tests/contract/test_*.py` — `ui_frontmatter_required`, `skill_grammar`, `fg100_size_budget`, `feature_matrix_freshness`, `skill_inventory`. 207+ assertions enforcing structural contracts that bats can't easily express.
  - **Universal `ui:` frontmatter:** all 48 fg-* agents now carry explicit `ui:` blocks (13 missing agents added; Tier-4-by-omission no longer accepted).
  - **Skill grammar contract:** `shared/skill-grammar.md` defines strict skill `ui:` block shape (`{tasks, ask, plan_mode}`); 8 skills migrated from shorthand. §4 accepts both `## Subcommands` and `## Subcommand dispatch` headings.
  - **Feature activation matrix:** `shared/feature-matrix.md` (30-row activation table, sentinel-fenced), `shared/feature-lifecycle.md` (90/180-day deprecation policy), `shared/feature_matrix_generator.py` (idempotent regenerator), `shared/feature_deprecation_check.py` (180-day removal-PR proposer), `shared/run-history/migrations/002-feature-usage.sql`. `agents/fg-700-retrospective.md` aggregates feature_usage. `agents/fg-100-orchestrator.md` emits `feature_used` events into `.forge/events.jsonl`.
  - **fg-100-orchestrator size budget:** `tests/contract/test_fg100_size_budget.py` enforces a 1800-line ceiling. `shared/agent-philosophy.md` adds the authoring rule.
  - **pyproject test extras:** `pip install -e ".[test]"` brings `pydantic>=2.0`, `pyyaml>=6.0`, `pytest>=8.0`. CI installs via this group; `tests/run-all.sh` dispatches pytest after bats in `contract` and `all` tiers.

### Changed

- **`/forge-help` skill DELETED.** LLM routing handles skill discovery. Skills count: 29 → 28. References scrubbed across CLAUDE.md, README.md, skill-contract.md, forge-config/tour skills, tests.
- **`/forge-verify --config` subcommand DELETED.** Folded into `/forge-status` (Config validation summary section). 10 stale references swept across CLAUDE.md (3), README.md, and 6 SKILL.md files.
- **`/forge-status` extended:** absorbs config validation + recent hook failures sections. `/forge-recover diagnose` embeds `/forge-status --json`.
- **`forge-sprint` skill:** drops `EnterPlanMode`/`ExitPlanMode` from `allowed-tools` (was inconsistent with `ui.plan_mode: false`).
- **`feature_usage.run_id` column:** gains `REFERENCES runs(id) ON DELETE CASCADE` (matches rest of run-history schema).

### Removed

- `skills/forge-help/` (directory)
- `tests/unit/skill-execution/decision-tree-refs.bats` (all 7 tests referenced forge-help)
- `/forge-verify --config` subcommand
- Phase 1 contradictory bats assertion `every Tier-4 agent omits ui:` (rewritten to `every fg-*.md agent has explicit ui: block`).

### Process

29 plan tasks landed across 7 implementation commits. Code review via `superpowers:requesting-code-review` found 4 critical / 6 important / 13 minor. All 23 issues fixed across 9 follow-up commits before release. Phase 1 ACs re-verified after Phase 2 fixes — no regressions. 2429 contract tests pass; 19 structural bats pass.

## [3.7.0] - 2026-04-27

Phase 1 of the A+ roadmap (Truth & Observability) ships. Closes four credibility gaps: Windows is now a real first-class CI target, every hook crash gets a durable JSONL audit trail, every module is tagged with a truthful support tier, and a cat/jq/Get-Content-readable live-run surface is live. Plus the cross-verification prerequisite edits coordinating the 13-plan ship train (`SHIP_ORDER.md`).

### Added

- **Phase 1: Truth & Observability** — Windows install helper (`install.ps1`);
  bash helper (`install.sh`) supersedes `ln -s`; `shared/check-environment.sh`
  ported to `shared/check_environment.py`; `tests/run-all.ps1` + `run-all.cmd`
  wrappers; new CI jobs `test-windows-pwsh-structural` and `test-windows-cmd`.
  `hooks/_py/failure_log.py` + `hooks/_py/progress.py` — every hook entry
  wraps `main()` and appends to `.forge/.hook-failures.jsonl` (renamed from
  `.log`; no shim). `SessionStart` rotates archives (gzip at 7 d, delete at
  30 d). `post_tool_use_agent.py` rewrites `.forge/progress/status.json`
  atomically on every subagent completion. `fg-700-retrospective` generates
  `.forge/run-history-trends.json` (last 30 runs + last 10 hook failures).
  Support-tier badge system: `docs/support-tiers.md`, generator
  `tests/lib/derive_support_tiers.py`, drift gate in `docs-integrity.yml`.
  `/forge-status` gains a `--- live ---` section. `shared/observability.md`
  gains `§Local inspection` recipes for bash/pwsh/cmd.
- **5 new pipeline agents** (opt-in via `agents.*` config schema):
  - `fg-143-observability-bootstrap` (PREFLIGHT Tier-3) — auto-wires OTel exporter when `observability_bootstrap.enabled=true`.
  - `fg-155-i18n-validator` (PREFLIGHT Tier-3) — hardcoded-string / RTL / locale checks; default-enabled.
  - `fg-506-migration-verifier` (VERIFY, migration mode only) — cycles MIGRATING/PAUSED/CLEANUP/VERIFY.
  - `fg-555-resilience-tester` (VERIFY Tier-3, opt-in) — chaos/fault-injection on changed surface.
  - `fg-414-license-reviewer` (split from `fg-417`) — license-compliance finding surface distinct from CVE/compat.
- **`trigger:` expression grammar** and evaluator contract (`shared/agent-communication.md`) — declarative predicate for conditional dispatch.
- **`shared/agents.md`** — consolidates agent model, tier table, dispatch graph, and registry (supersedes the deleted `agent-model.md`, `agent-registry.md`, and narrow parts of `agent-communication.md`).
- **`shared/learnings-index.md`** and `docs.learnings_index.auto_update` config key — retrospective auto-regenerates the index when `true` (default); CI `docs-integrity` workflow enforces freshness regardless.
- **Start Here (5-minute path)** block at the top of `CLAUDE.md` — install / first-run / skill-selection on-ramp.
- **`docs-integrity` CI workflow** (`.github/workflows/docs-integrity.yml`) — strict lychee, anchor check, ADR validator, 600-line ceiling, framework-count guard.
- **`{{REPO_MAP_PACK}}` placeholder** injected into `fg-100-orchestrator`, `fg-200-planner`, and `fg-300-implementer` prompts — replaces full directory listings with PageRank-ranked file packs (30-50% token saving when `code_graph.prompt_compaction.enabled=true`, default OFF).
- **Repo-map A/B eval scenario** and compaction workflow — 20-run graduation gate before default-on consideration.
- **Speculative dispatch section** in `fg-100-orchestrator` — full behavioral contract for when Branch Mode fires.
- **Speculation eval corpus + CI gates** — quality, token, and precision regression guards on speculation.
- **`state.json.plan_candidates` + `speculation.*` fields** — candidate persistence and selection audit.

### Changed

- **`shared/state-schema.md` split** into overview (355L) + `state-schema-fields.md` (1133L, exempt from 600L ceiling). No content change; the two files supersede the former 1461L monolith.
- **Agent docs consolidation** — `shared/agent-communication.md` narrowed to inter-agent messaging; `agent-model.md`, `agent-registry.md`, and `agent-tiers.md` deleted (content merged into `shared/agents.md`).
- **Dead-link sweep** — pre-existing broken links fixed; lychee switched to strict mode.
- **`fg-413-frontend-reviewer` slimmed** to ≤400 lines; frontend-performance findings delegated to `fg-416-performance-reviewer`.
- **`fg-417-dependency-reviewer` split**: license-compliance moved to `fg-414`; `fg-417` now scoped to CVEs / version conflicts / transitive compatibility.
- CLAUDE.md hook count corrected (7 → 6); Agent model row added to Key entry points.

### Fixed

- `.github/workflows/` — `contents: read` permissions added to three workflows lacking an explicit permission block.
- `opentelemetry.io/docs/specs/semconv/*` flake — ignored in `.lycheeignore` (GitHub runners surface intermittent 403s).
- bats-core submodule refreshed to latest tag.

## [3.6.0] — 2026-04-21 — Session Handoff (F34)

Structured, portable session handoff system preserving forge run state across Claude Code session boundaries. Deterministic Python writer (no LLM call), thin projection over existing `.forge/state.json` and F08 retention tags.

### Added

- **`/forge-handoff` skill** — `write`/`list`/`show`/`resume`/`search` subcommands for managing session handoffs (`skills/forge-handoff/SKILL.md`).
- **`hooks/_py/handoff/` package** — `config`, `frontmatter`, `sections`, `redaction`, `writer`, `resumer`, `alerts`, `triggers`, `milestones`, `search`, `auto_memory`, `cli` (12 modules, all deterministic).
- **State-handoff tracking** — `state.json.handoff.*` sub-object (`last_written_at`, `last_path`, `chain`, per-level trigger counters, `suppressed_by_rate_limit`).
- **Trigger levels** — soft (50% default) / hard (70% default) / milestone (stage transitions) / terminal (SHIP/ABORT/FAIL) / manual. Autonomous mode: write-and-continue, never pauses.
- **`CONTEXT_CRITICAL` safety escalation** — interactive-mode-only pause at hard threshold; documented in `shared/error-taxonomy.md`.
- **Compact-check hook integration** — `hooks/_py/check_engine/compact_check.py` dispatches handoff writer at threshold while preserving legacy stderr hint.
- **MCP server tools** (F30 extension) — `forge_list_handoffs(run_id)` + `forge_get_handoff(path)` expose handoff chains to any MCP client.
- **Auto-memory promotion** — top HIGH-confidence PREEMPTs + user-decision statements auto-flow to `~/.claude/projects/<hash>/memory/` on terminal handoffs.
- **FTS5 search** over all handoffs via `run-history.db` (`handoff_fts` virtual table), with freetext phrase-quote escaping to prevent syntax-error crashes.
- **Chain rotation** — past `handoff.chain_limit` (default 50), oldest handoffs move to `handoffs/archive/` silently.
- **`ADR-0012`** — session handoff as a thin state projection, not an LLM summarisation.
- **3 scenario bats tests** in `tests/scenario/handoff-*.bats` + 78 Python unit/integration tests in `hooks/_py/tests/test_handoff_*.py`.

### Changed

- **State schema bumped 1.9.0 → 1.10.0** with new `handoff.*` sub-object (clean cut per no-backcompat policy).
- **`CLAUDE.md`** — adds F34 Feature row, `/forge-handoff` skill selection row, `.forge/runs/<id>/handoffs/` added to `/forge-recover reset` survivors list.
- **`.claude-plugin/plugin.json`** → 3.6.0.
- **`.claude-plugin/marketplace.json`** → 3.6.0 (lockstep with plugin).

### Configuration

- New `handoff.*` config block (see `shared/preflight-constraints.md`): `enabled`, `soft_threshold_pct`, `hard_threshold_pct`, `min_interval_minutes`, `autonomous_mode`, `auto_on_ship`, `auto_on_escalation`, `chain_limit`, `auto_memory_promotion`, `mcp_expose`.

## [3.5.0] — 2026-04-20 — Speculative Plan Branches

Branch-mode planner dispatches 2-3 candidate plans in parallel for MEDIUM-confidence ambiguous requirements, validates each, and selects the highest-scored.

### Added

- **`fg-200-planner` Branch Mode** — N=2-5 parallel candidate invocations with distinct exploration seeds when `speculation.enabled=true` and confidence gate fires MEDIUM (`plans/candidates/` per-run persistence with FIFO eviction).
- **Speculation CLI** (`hooks/_py/speculation/`) — `derive-seed`, `estimate-cost`, `diversity`, `selection`, `winner` subcommands drive candidate generation, cost-aware gating, and tie-break.
- **`plan-cache` schema v2.0** — candidate set + winner tracking; survives `/forge-recover reset`.
- **Repo-map PageRank** (`hooks/_py/repomap.py`) — biased PageRank with recency + keyword-overlap re-ranking, token-budgeted pack assembly, LRU cache (`.forge/ranked-files-cache.json`). `code_graph.prompt_compaction.*` config block. CLI subcommands: `rank`, `pack`, `stats`.
- **`state.json.prompt_compaction`** block records ranked-file hit rate and token savings per stage.
- **`shared/graph/pagerank-sql.md`** — PageRank algorithm reference with SQLite DDL and worked example.
- **`shared/` grouped index** — logical groupings for 80+ shared docs.

### Changed

- `.claude-plugin/plugin.json` → 3.5.0.

## [3.4.0] — 2026-04-20 — OTel GenAI Semconv + Skill Consolidation + Time-Travel Checkpoints

Three major feature streams converged in a single version bump: OpenTelemetry GenAI Semantic Conventions for observability, skill consolidation (35 → 28), and the content-addressable checkpoint DAG.

### Breaking — OTel

- **OTel exporter rewritten in Python.** `shared/forge-otel-export.sh` is **removed**. Use `python -m hooks._py.otel_cli replay ...` for post-hoc export from the event log. Live emission happens automatically via `hooks/_py/otel.py` when `observability.otel.enabled=true`.
- **Attribute rename** — legacy custom names removed; semconv replacements:
  - `tokens_in` → `gen_ai.tokens.input`
  - `tokens_out` → `gen_ai.tokens.output`
  - `agent` → `gen_ai.agent.name`
  - `model` → `gen_ai.request.model`
  - `findings_count` → `forge.findings.count`

  Rebuild dashboards keyed on the old names.
- **Config keys removed.** Replace `observability.export` and `observability.otel_endpoint` with the nested `observability.otel.*` form documented in `shared/observability.md`. `telemetry.export_status` is no longer written to `state.json`.

### Breaking — Skill Consolidation

Seven top-level skills have been removed and their capabilities folded into three unified skills. Skill count: 35 → 28.

| Removed                 | Use instead                              |
|-------------------------|------------------------------------------|
| /forge-codebase-health  | /forge-review --scope=all                |
| /forge-deep-health      | /forge-review --scope=all --fix          |
| /forge-graph-status     | /forge-graph status                      |
| /forge-graph-query      | /forge-graph query <cypher>              |
| /forge-graph-rebuild    | /forge-graph rebuild                     |
| /forge-graph-debug      | /forge-graph debug                       |
| /forge-config-validate  | /forge-verify --config                   |

`/forge-review --scope=all --fix` presents an `AskUserQuestion` safety gate before the first commit unless `autonomous: true` or `--yes`. Subcommand dispatch pattern documented in `shared/skill-subcommand-pattern.md`.

### Breaking — Time-Travel

- **State schema 1.8.0 → 1.9.0.** The linear `.forge/checkpoint-{storyId}.json` format is replaced by a content-addressable DAG under `.forge/runs/<run_id>/checkpoints/`. Orchestrators on v1.9.0+ refuse to proceed on pre-1.9.0 state; run `/forge-recover reset` to migrate (no automatic upgrade — formats are not compatible).

### Added — OTel

- OTel GenAI Semantic Conventions (2026) span emission per pipeline, stage, and agent dispatch (`hooks/_py/otel.py`).
- W3C Trace Context propagation to subagent dispatches via `TRACEPARENT` (`otel.dispatch_env`).
- `ParentBased(TraceIdRatioBased)` sampler — subagent decisions inherit the root. Inbound `sampled=0` is respected (child emits nothing).
- `otel.replay()` — authoritative recovery path from `.forge/events.jsonl`. Live streaming via `BatchSpanProcessor` is best-effort; replay is the source of truth.
- Optional OpenInference compatibility mirror (`observability.otel.openinference_compat: true`) — emits `openinference.span.kind=AGENT`, `llm.token_count.{prompt,completion,total}`, `llm.model_name`, `agent.name` alongside `gen_ai.*` for Arize-heavy backends.
- Pinned semconv schema (`shared/schemas/otel-genai-v1.json`) + CI validator (`tests/unit/otel_semconv_validator.py`).
- CI workflow `.github/workflows/otel.yml` — Docker collector sidecar, semconv conformance test, replay parity job, and disabled-overhead guard (<1ms/stage when `enabled=false`, no `opentelemetry.*` imports).
- `observability.otel.*` PREFLIGHT constraints (`shared/preflight-constraints.md`).
- `[otel]` optional dependency group in `pyproject.toml` — `pip install forge-plugin[otel]` pulls `opentelemetry-api>=1.30.0`, `opentelemetry-sdk>=1.30.0`, `opentelemetry-exporter-otlp>=1.30.0`, `jsonschema>=4.0.0`.
- Orchestrator OTel instrumentation contract documented in `agents/fg-100-orchestrator.md`.

### Added — Time-Travel

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

### Added — Skill Consolidation tests

- `tests/structural/skill-consolidation.bats` — 16 assertions locking in skill count, expected names, removed names, subcommand-dispatch sections, `--json` schema_version, CLAUDE.md "(28 total)" header, and a `validate-config.sh` read-only regression guard.
- `tests/lib/module-lists.bash` — `DISCOVERED_SKILLS`, `MIN_SKILLS=28`, and `EXPECTED_SKILL_NAMES` fixture (28 entries).

### Added — eval harnesses

- Self-consistency voting — eval datasets + harness + CI gates.
- 5 reflection eval scenarios + structural validator.
- Ebbinghaus decay — docs sweep + frontmatter stamping + eval harness.
- Learnings-index generator + initial index; convergence-engine cleanup + anchor-map CSV.

### Changed — Skill Consolidation

- `CLAUDE.md` Skills paragraph rewritten for the 28-skill baseline; getting-started flows updated.
- `skills/forge-help/SKILL.md` rewritten — ASCII decision tree replaces tier tables; `--json` envelope bumps to `schema_version: "2"`; new Migration table.
- `shared/skill-contract.md` §4 Skill categorization rebased to the consolidated baseline (10 read-only + 18 writes = 28).
- `README.md`, `shared/graph/{schema,schema-versioning}.md`, `shared/graph/enrich-symbols.sh`, `shared/recovery/health-checks/dependency-check.sh`, `skills/forge-init/SKILL.md` — every `/forge-graph-*` and `/forge-config-validate` reference rewritten to the new `<sub>` form.

### Changed — Time-Travel

- `shared/state-schema.md` — `## § Checkpoints` section replaced with CAS DAG layout; deprecated `## checkpoint-{storyId}.json` section retained for reference only.
- `shared/state-transitions.md` — added `REWINDING` pseudo-state rows and a `§ Rewind transitions` section.
- `skills/forge-recover/SKILL.md` — subcommand table, flags, exit-codes block, examples, and dispatch prose extended for rewind + list-checkpoints.
- `CLAUDE.md` — state-schema version bumped from v1.6.0 → v1.9.0 in the key-entry-points table and state overview.

### Changed — Infra

- GitHub Actions workflows migrated to `actions/checkout@v6`.

### Fixed

- Untrusted Data Policy header injected into `fg-301-implementer-critic` (missed in the original injection-hardening sweep).

### Cardinality budget

Span names use only bounded attributes (`gen_ai.agent.name`, `gen_ai.request.model`, `gen_ai.operation.name`, `forge.stage`, `forge.mode`). Unbounded values (`forge.run_id`, `gen_ai.agent.id`, `gen_ai.tool.call.id`) appear as attributes only, never in span names. See `shared/observability.md` for the full table.

## [3.3.0] — 2026-04-20 — Implementer Reflection (Chain-of-Verification)

Fresh-context critic (`fg-301-implementer-critic`) inserted between GREEN and REFACTOR in `fg-300`'s TDD loop catches diffs that pass tests but fail to satisfy test intent (hardcoded returns, over-narrow conditionals, swallowed branches).

### Added

- **`fg-301-implementer-critic`** — Tier-4 fresh-context sub-subagent dispatched between GREEN and REFACTOR. Receives only (task description, test code, implementation diff) — no access to implementer reasoning, PREEMPT items, conventions stack, or scaffolder output.
- **`implementer.reflection.*` config block** — `enabled`, `max_cycles` (default 2), `fresh_context`.
- **Per-task `implementer_reflection_cycles` counter** in `state.json` — parallel to `implementer_fix_cycles`; does NOT feed into convergence counters, `total_retries`, or `total_iterations`.
- **New scoring categories** — `REFLECT-DIVERGENCE`, `REFLECT-HARDCODED-RETURN`, `REFLECT-OVER-NARROW`, `REFLECT-MISSING-BRANCH`. After 2 REVISE verdicts on the same task the critic escalates to `REFLECT-DIVERGENCE` (WARNING) and continues to REFACTOR so the reviewer panel gets a chance.
- **Model routing** — critic uses `fast` tier.
- **Self-consistency voting foundation** — dispatch bridge + state schema bump.
- **Ebbinghaus memory decay foundation** — agent edits + legacy-field removal.
- **Time-travel checkpoints foundation** (Tasks 1-4).
- **Speculative plan branches foundation** (Tasks 1-3).
- **Repo-map PageRank foundation** (Tasks 1-4).
- **New framework modules** — Rails, Swift structured concurrency, and Laravel. `MIN_FRAMEWORKS` raised from 22 to 24 with structural guards.

### Fixed

- `engine.sh` — bypass timeout+lock+ERR-trap silent-exit paths in operator modes (fixes silent failure on hook invocation edge cases).

### Changed

- `.claude-plugin/plugin.json` → 3.3.0.

## [3.2.0] — 2026-04-20 — Prompt Injection Hardening

Four-tier trust model (Silent / Logged / Confirmed / Blocked) wraps every piece of external data consumed by the 48 forge agents inside `<untrusted source="..." ...>` XML envelopes. A mandatory system-level Untrusted Data Policy header is injected into every agent, treating envelope contents as **data, never instructions**. Regex detection layer flags and quarantines likely-injection payloads before reaching any agent.

### Breaking

- **Every agent `.md` now carries the SHA-pinned Untrusted Data Policy header.** Hand-editing the header breaks the SHA pin — use `./tools/apply-untrusted-header.sh` for any header change.
- **MCP tool responses (Linear, Slack, Figma, Playwright, Context7, Neo4j, GitHub), wiki content, explore-cache JSON, cross-project learnings, and documentation-discovery output** are now filtered through `hooks/_py/mcp_response_filter.py` and wrapped in `<untrusted>` envelopes before reaching any agent.

### Added

- **`shared/untrusted-envelope.md`** — canonical XML envelope contract (`<untrusted source="..." trust_tier="..." ...>...</untrusted>`).
- **`shared/prompt-injection-patterns.json`** — curated regex library for four-tier detection.
- **`SEC-INJECTION-*` scoring categories** — findings distinguish Silent / Logged / Confirmed / Blocked severity.
- **`hooks/_py/mcp_response_filter.py`** — every external data source tiered and envelope-wrapped at the hook boundary.
- **`./tools/apply-untrusted-header.sh`** — SHA-pinned header application tool (hand-editing breaks the pin).
- **Skill consolidation foundation** (Tasks 1-3).
- **Documentation architecture foundation** — ADR scaffolding + 11 seed records.
- **Agent layer foundation** — `ui:` frontmatter trim + `trigger:` scaffolding.
- **Flask framework module** (first of four new frameworks).
- **OTel GenAI semconv foundation** (Tasks 1-4).
- **Residual bash audit scripts** ported to Python.

### Changed

- `.claude-plugin/plugin.json` → 3.2.0.

## [3.1.0] — 2026-04-19 — Cross-Platform Python Hooks

All 7 forge hooks, the check engine, and the critical `shared/*.sh` scripts ported to Python 3.10+ stdlib-only. The bash 4+ requirement is dropped; `windows-latest` is now a first-class CI target.

### Breaking

- **Bash 4+ no longer required.** Python 3.10+ is the only hard prerequisite for hook execution. A handful of developer-only simulation harnesses under `shared/` remain in bash (e.g., `shared/convergence-engine-sim.sh`) but are bash-3.2 compatible and do not run in hook paths.
- **`bash`-isms removed** — here-strings (`<<<`), process substitution (`< <(...)`), associative arrays (`declare -A`) that broke Git Bash 3.2 and MSYS/MinGW are gone from all hook-reachable code.

### Added

- **`hooks/_py/` Python package** — 6 hook entry scripts (`pre_tool_use.py`, `post_tool_use.py`, `post_tool_use_skill.py`, `post_tool_use_agent.py`, `stop.py`, `session_start.py`) + check engine (`_py.check_engine`), automation trigger (`_py.check_engine.automation_trigger`), and compact check.
- **`shared/python/`** — `state_init.py`, `guard_parser.py`, `state_transitions.py` (full transition table), `state_migrate.py` (v1.5.0 → v1.6.0 migration).
- **`check_prerequisites.py`** — Python 3.10+ validation for `/forge-init`.
- **`windows-latest` CI matrix** — full `unit | contract | scenario` jobs now run on Windows Git Bash (previously `structural`-only).
- **`shared/platform-support.md`** — cross-platform guidance (macOS / Linux / Windows Git Bash / WSL2 / PowerShell).
- **Pipeline evaluation harness** (`tests/evals/pipeline/`) — CI-only evals with 5 suite definitions (lite/25, convergence/10, cost/5, compression/5, smoke/5), 30 fixture stubs across 5 languages, baseline save/compare with regression detection.

### Changed

- `.claude-plugin/plugin.json` → 3.1.0.

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
- Log rotation for the hook failure log and `.forge/forge.log`

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
