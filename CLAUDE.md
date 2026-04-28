# CLAUDE.md

Guidance for Claude Code working in this repo.

## Start Here (5-minute path)

1. **Install:** `ln -s $(pwd) /path/to/your-project/.claude/plugins/forge`, then in that project run `/forge`. MCP auto-setup: `shared/mcp-provisioning.md`.
2. **First run:** `/forge run --dry-run "<requirement>"` — exercises PREFLIGHT → VALIDATE only. Confirm the plan, then drop `--dry-run`.
3. **Pick the right skill:** see §Skill selection guide. When in doubt, ask Claude — it routes from your description.

Already familiar? Skip to §Architecture.

**Spend predictably:** `cost.ceiling_usd` in `forge-config.md` (default $25/run). Dispatch gate in `fg-100-orchestrator.md` §Cost Governance; helpers `shared/cost_governance.py`; analytics in `fg-700-retrospective.md` §2.7.

---

## What this is

`forge` is a Claude Code plugin (v5.1.0, `quantumbitcz` marketplace / Git submodule). 10-stage autonomous pipeline: Preflight → Explore → Plan → Validate → Implement (TDD, voting-gated per-task) → Verify (build/test/lint + intent) → Review → Docs → Ship (evidence + intent clearance) → Learn. Entry: `/forge run` → `fg-100-orchestrator`.

**Prompt-injection hardening:** External data tiered (Silent/Logged/Confirmed/Blocked) and wrapped in `<untrusted>` envelopes by `hooks/_py/mcp_response_filter.py` before reaching agents. All 50 agents carry the SHA-pinned Untrusted Data Policy header. Contract: `shared/untrusted-envelope.md`. Findings: `SEC-INJECTION-*`.

## Architecture

Layered, top-down resolution:

1. **Project config** — `.claude/forge.local.md`, `forge-config.md`, `forge-log.md` in consuming repo.
2. **Module layer** (`modules/`):
   - `languages/` (15), `frameworks/` (24), `testing/` (19) — each with `conventions.md`, `variants/`, framework-binding subdirs (`testing/`, `persistence/`, `messaging/`, …).
   - Domain: `databases/`, `persistence/`, `migrations/`, `api-protocols/`, `messaging/`, `caching/`, `search/`, `storage/`, `auth/`, `observability/`.
   - ML/data: `ml-ops/` (4), `data-pipelines/` (3), `feature-flags/` (3).
   - Tooling: `build-systems/` (9), `ci-cd/` (7), `container-orchestration/` (11), `code-quality/` (~70 tools), `documentation/`.
   - **Composition** (most specific wins): variant > framework-binding > framework > language > code-quality > generic > testing. Algorithm: `shared/composition.md`.
3. **Shared core** — `agents/` (50), `shared/`, `hooks/`, `skills/` (28).
4. **MCP interface** — `shared/mcp-server/`, optional Python stdio server exposing `.forge/` data. Read-only, requires Python 3.10+.

**Resolution:** `forge-config.md` > `forge.local.md` > plugin defaults. Orchestrator loads agent `.md` as subagent system prompt — every line costs tokens.

## Setup, validation, install

```bash
./tests/validate-plugin.sh          # 73+ structural checks, ~2s
./tests/run-all.sh                  # Full suite, ~30s
./tests/run-all.sh structural|unit|contract|scenario   # Subset
./tests/lib/bats-core/bin/bats tests/unit/scoring.bats # Single file

./install.sh                        # macOS/Linux (WSL too)
powershell -ExecutionPolicy Bypass -File install.ps1   # Windows native
```

Doc-only plugin (no build). Smoke test: symlink → `/forge` → `/forge run --dry-run` → `/forge run` → check `.forge/state.json`.

Pipeline-level evals: `tests/evals/pipeline/README.md` (CI-only; local `FORGE_EVAL=1 python -m tests.evals.pipeline.runner --dry-run --no-baseline`).

**First-time?** Read `shared/agent-philosophy.md`. Run `validate-plugin.sh` after every change.

## Key entry points

| Topic | File |
|---|---|
| Pipeline flow | `shared/stage-contract.md` |
| Orchestrator | `agents/fg-100-orchestrator.md` |
| Scoring | `shared/scoring.md` |
| State (v2.0.0) | `shared/state-schema.md` (fields: `shared/state-schema-fields.md`; no migration shims, old state auto-invalidates) |
| Errors / recovery | `shared/error-taxonomy.md` + `shared/recovery/recovery-engine.md` |
| Agents (registry, dispatch, tiers) | `shared/agents.md` |
| Agent design | `shared/agent-philosophy.md` + `shared/agent-communication.md` |
| Graph (Neo4j / SQLite) | `shared/graph/schema.md` / `shared/graph/code-graph-schema.sql` |
| Convergence | `shared/convergence-engine.md` (worked examples: `convergence-examples.md`) |
| State machine | `shared/state-transitions.md` |
| Model routing | `shared/model-routing.md` |
| Confidence | `shared/confidence-scoring.md` |
| I/O compression | `shared/output-compression.md`, `shared/input-compression.md` |
| Learnings (selector / decay / promotion) | `hooks/_py/learnings_selector.py`, `shared/learnings/decay.md`, `learnings/rule-promotion.md` |
| PREFLIGHT constraints | `shared/preflight-constraints.md` |
| Framework gotchas | `shared/framework-gotchas.md` |
| Skill contract | `shared/skill-contract.md` |
| Findings store | `shared/findings-store.md` |
| Feature matrix (auto) | `shared/feature-matrix.md` (regen: `python shared/feature_matrix_generator.py`) |
| AskUserQuestion patterns | `shared/ask-user-question-patterns.md` |
| Agent colors / UI tiers | `shared/agent-colors.md`, `shared/agent-ui.md` |

For further docs (~85 files): `ls shared/` and `ls shared/learnings/`. Discovery is cheap; this index covers the load-bearing ones.

## Skill selection guide

| Intent | Skill | Notes |
|---|---|---|
| Build a feature | `/forge run` | Full 10-stage pipeline |
| Fix a bug | `/forge fix` | Root-cause + targeted fix |
| Shape a vague idea | `/forge run` | Collaborative spec refinement |
| Review changed files | `/forge review` | `--scope=changed` default; `--full` = 8 agents |
| Audit / fix whole codebase | `/forge review --scope=all [--fix]` | `--fix` is iterative; AskUserQuestion gate unless `autonomous: true` or `--yes` |
| Build/lint/test only | `/forge verify` | `--build` default; `--all` adds config validation |
| Validate config | `/forge-ask status` | Includes config validation summary |
| Graph ops | `/forge-admin graph {init,status,query,rebuild,debug}` | `query` is read-only Cypher |
| Security scan | `/forge audit` | Module-appropriate scanners |
| Recovery | `/forge-admin recover {diagnose,repair,reset,resume,rollback}` | `reset` preserves learnings/caches |
| Multiple features | `/forge sprint` | Parallel orchestration |
| Generate docs | `/forge docs` | README, ADRs, API specs, changelogs |
| Deploy / migrate | `/forge deploy`, `/forge migrate` | Strategies + framework upgrades |
| Codebase Q&A | `/forge-ask` | Wiki + graph + explore cache + docs |
| Analytics | `/forge-ask insights`, `/forge-ask history`, `/forge-ask profile` | Quality, cost, trends, perf |
| Playbooks | `/forge-admin playbooks`, `/forge-admin refine` | Reusable recipes + refinement review |
| Compress | `/forge-admin compress {agents,output,status,help}` | Token reduction |
| Quick commit | `/forge commit` | Conventional commit from staged changes |
| Onboarding | `/forge-ask tour` | 5-stop introduction |
| Edit config | `/forge-admin config` | Interactive editor with validation |
| Session handoff | `/forge-admin handoff` | Transfer run state to a fresh CC session |
| Stop pipeline | `/forge-admin abort` | Graceful (state preserved for resume) |
| Bootstrap | `/forge bootstrap` | Greenfield scaffold |
| Automations | `/forge-admin automation` | Cron/CI/MCP triggers |

### Getting started flows

```
First time?        /forge-ask tour
New project:       /forge → /forge-ask status → /forge verify → /forge run <req>
Existing project:  /forge → /forge review --scope=all [--fix] → /forge run <req>
Bug fix:           /forge fix <description or ticket>
Pre-ship:          /forge verify → /forge review --full
Pipeline trouble:  /forge-admin recover diagnose → repair (if needed) → resume
Sprint:            /forge sprint  (Linear cycle or manual list)
```

## Agents (50, `agents/*.md`)

**Pipeline** (`fg-NNN-role`):
- **Pre:** 010-shaper, 015-scope-decomposer, 020-bug-investigator, 050-bootstrapper. **Sprint:** 090.
- **Core:** 100-orchestrator (coordinator, never writes code) + helpers 101-worktree, 102-conflict, 103-cross-repo.
- **Preflight:** 130-docs-discoverer, 135-wiki, 140-deprecation, 143-observability *, 150-test-bootstrapper, 155-i18n *, 160-migration-planner.
- **Plan/Validate:** 200-planner, 205-plan-judge (binding REVISE), 210-validator, 250-contract-validator.
- **Implement:** 300-implementer (TDD + inner-loop lint/test), 301-implementer-judge (fresh-context binding-veto, 2-loop bound), 302-diff-judge (F36 voting tiebreak via structural AST diff), 310-scaffolder, 320-frontend-polisher *.
- **Verify:** 400-quality-gate, 500-test-gate, 505-build-verifier, 506-migration-verifier †, 510-mutation, 515-property-test *, 540-intent-verifier (F35, end of Stage 5 VERIFY), 555-resilience *.
- **Ship/Docs:** 350-docs, 590-pre-ship, 600-pr-builder, 610-infra-deploy *, 620-deploy-verifier *, 650-preview.
- **Learn:** 700-retrospective, 710-post-run.
- *= conditional on config flag; † = migration mode only.

**Review** (9, via quality gate, Agent Teams pattern; shared findings store `.forge/runs/<id>/findings/<reviewer>.jsonl`): 410-code, 411-security, 412-arch, 413-frontend (modes: full/conventions/a11y; perf delegated to 416), 414-license, 416-perf, 417-deps, 418-docs-consistency, 419-infra-deploy. Reviewer count scales by change scope: <50 lines = batch 1; 50-500 = all; >500 = all + splitting note.

### Agent rules

- **Frontmatter:** `name` (must match filename), `description`, `tools`. Dispatch agents include `Agent`. `ui:` declares capabilities (enforced by `ui-frontmatter-consistency.bats`).
- **UI tiers** (full list in `shared/agents.md#dispatch`): T1 (tasks+ask+plan_mode) — shapers, planner, bootstrapper. T2 (tasks+ask) — orchestrator, validator, gates, PR builder, post-run. T3 (tasks) — implementer, scaffolder, polishers, verifiers, scientific generators. T4 (none) — all reviewers, judges, helpers. **No implicit T4 by omission.**
- **Patterns:** `AskUserQuestion` for multi-option choices (never "Options: (1)…"). `EnterPlanMode`/`ExitPlanMode` for planning (skipped in autonomous/replanning). `TaskCreate`/`TaskUpdate` wraps every dispatch; three-level nesting (stage → substage → leaf) with agent color dots.
- **Config (`components:` in `forge.local.md`):** Core `language` / `framework` / `variant` / `testing`. Framework-specific `web`, `persistence`. Optional crosscutting: `database`, `migrations`, `api_protocol`, `messaging`, `caching`, `search`, `storage`, `auth`, `observability`, `build_system`, `ci`, `container`, `orchestrator`, `documentation`, `code_quality` (list, supports object form), `ml_ops`, `data_pipeline`, `feature_flags`. Multi-service: entries with `path:`. `mode_config:` overlay > stage default > hardcoded fallback.
- **Worktree:** All impl in `.forge/worktree`. User's tree never modified. Branch collision → epoch suffix.
- **Challenge Brief required** in every plan; validator returns REVISE if missing.
- **Findings:** APPROACH-* scored INFO (-2), escalates at 3+ recurrences. DOC-* ranges CRITICAL→WARNING→INFO.
- **Token discipline:** Agent `.md` = subagent system prompt. Constraints reference `shared/agent-defaults.md`; output format → `shared/checks/output-format.md`. Convention stack soft cap 12 files/component, module overviews ≤15 lines. Output compression sets per-stage verbosity.

### Routing & decomposition

`/forge run` auto-classifies. Requirements <50 words missing 3+ of (actors, entities, surface, criteria) → shaper. Prefixes (`bugfix:`, `migrate:`, `bootstrap:`) and flags (`--sprint` deprecated → `/forge sprint`, `--parallel`) override. Multi-feature detected via fast scan / deep post-EXPLORE → `fg-015` → `fg-090`. Frontend design preview via superpowers visual companion at PLAN (graceful degradation). Config: `routing.*`, `scope.*`, `model_routing.*`, `explore.*`, `plan_cache.*`.

## Core contracts

**Scoring** (`scoring.md`): `score = max(0, 100 − 20·CRIT − 5·WARN − 2·INFO)`. PASS ≥80, CONCERNS 60-79, FAIL <60 or unresolved CRITICAL. 92 categories (28 wildcards + 64 discrete) in `shared/checks/category-registry.json`. Key wildcards: `ARCH-*`, `SEC-*`, `PERF-*`, `TEST-*`, `CONV-*`, `DOC-*`, `QUAL-*`, `SCOUT-*` (excluded from score), `A11Y-*`, `DEP-*`, `INFRA-*`, `AI-{LOGIC,PERF,CONCURRENCY,SEC}-*`, `REFLECT-*`, `COST-*`. Dedup key: `(component, file, line, category)`. Convergence counters: `verify_fix_count`, `test_cycles`, `quality_cycles` (inner), `phase_iterations` (per-phase), `total_iterations` (cumulative). Separate: `implementer_fix_cycles` (does NOT count toward convergence). Timed-out reviewers: INFO → WARNING. 7 validation perspectives.

**State / recovery / errors:** State v2.0.0 in `.forge/` (gitignored). Checkpoints per task (CAS DAG `.forge/runs/<id>/checkpoints/`). Key fields: `mode` (standard/migration/bootstrap/bugfix), `feedback_loop_count` (escalates at 2), `recovery`, `ticket_id`, `branch_name`, `graph`, `plan_judge_loops`, `impl_judge_loops`, `judge_verdicts`, `consistency_*`, `cost`. Lock: `.forge/.lock` (PID + 24h stale). Recovery: 7 strategies, severity ceiling 5.5, `total_retries` budget (default 10). Errors: 22 types, 16-level severity. MCP failures → inline INFO. 3 transients in 60s → non-recoverable. `BUILD/TEST/LINT_FAILURE` → orchestrator fix loop.

**Stages:** PREFLIGHT → EXPLORING → PLANNING → VALIDATING → IMPLEMENTING → VERIFYING → REVIEWING → DOCUMENTING → SHIPPING → LEARNING. Migration: MIGRATING/PAUSED/CLEANUP/VERIFY. PR rejection routes to Stage 4 (impl) or Stage 2 (design) via `fg-710`. **Evidence-based shipping:** `fg-590` runs fresh build+test+lint+review → `.forge/evidence.json`; PR builder refuses without `verdict: SHIP`. No "continue anyway".

**Deterministic control flow:** Transition table in `shared/state-transitions.md`. LLM judgment for review/impl/architecture — NOT transitions. Decisions logged to `.forge/decisions.jsonl`. Reviewer conflicts resolved by `shared/agent-communication.md` §3.1 priority.

## Features

35+ optional capabilities (cost governance, judge veto, speculative branches, self-consistency, repo-map PageRank, run history, MCP server, playbooks, property-based tests, flaky management, accessibility/i18n/perf regression, A2A, deployment strategies, contracts, AI quality, output compression, wiki, handoff, …). Per-feature config keys, IDs (F05-F35), categories, and activation state: **`shared/feature-matrix.md`** (auto-regen). Lifecycle: 90d unused → flagged, 180d → removal proposal (`shared/feature-lifecycle.md`).

Cross-cutting subsystems used by most features:
- **Confidence** (`confidence.*`): finding HIGH/MED/LOW (1.0/0.75/0.5x); pipeline 4-dim (clarity 0.30, familiarity 0.25, complexity 0.20, history 0.25). Gate: ≥0.7 proceed, ≥0.4 ask, <0.4 → `/forge run`. Trust state in `.forge/trust.json`.
- **Repo-map PageRank** (`code_graph.prompt_compaction.*`, opt-in): `hooks/_py/repomap.py` ranks files by centrality × recency × keyword overlap. `{{REPO_MAP_PACK}}` replaces dir listings in 100/200/300 prompts (~30-50% token savings). Cache: `.forge/ranked-files-cache.json`. Reference: `shared/graph/pagerank-sql.md`.
- **Cost governance** (`cost.*`, F35): USD ceiling, dispatch-gate projection, soft throttle (80/90% in implementer §5.3b emits `COST-THROTTLE-IMPL`). Dynamic tier downgrade with hardcoded SAFETY_CRITICAL list (210/250/411/412/414/419/500/505/506/590) — never silently skipped. Incidents: `.forge/cost-incidents/<ts>.json`. OTel: `forge.cost.*`.
- **Judges** (F32, `plan.judge.*`, `implementer.reflection.*`): `fg-205` (plan-scoped) and `fg-301` (per-task) issue binding REVISE. 2-loop bound; 3rd REVISE → AskUserQuestion (interactive) or auto-abort (autonomous). Categories: `REFLECT-*`, `JUDGE-TIMEOUT`.
- **Self-consistency voting** (F33, `consistency.*`): N=3 majority + soft tiebreak on shaper intent, `INCONCLUSIVE` validator verdicts, PR-rejection classification. Cache `.forge/consistency-cache.jsonl` survives reset.
- **Intent Verification Gate** (F35, `intent_verification.*`): `fg-540-intent-verifier` at end of Stage 5 VERIFY; fresh-context probes each AC; `fg-590` hard-SHIP-gates on 0 INTENT-MISSED + `verified_pct >= strict_ac_required_pct`. Default `enabled: true`, `strict_ac_required_pct: 100`. Categories: `INTENT-MISSED`, `INTENT-PARTIAL`, `INTENT-AMBIGUOUS`, `INTENT-UNVERIFIABLE`, `INTENT-CONTRACT-VIOLATION`.
- **Implementer Voting** (F36, `impl_voting.*`): confidence-gated N=2 sampling on LOW-confidence, risk-tagged, or regression-adjacent tasks. `fg-302-diff-judge` compares via structural AST diff. Tiebreak on DIVERGES. Cost-skip when `<30%` budget remains. Default `enabled: true`, `trigger_on_confidence_below: 0.4`, `trigger_on_risk_tags: ["high"]`, `skip_if_budget_remaining_below_pct: 30`.

## Shared scripts (`shared/`)

| Script | Purpose |
|---|---|
| `forge-state.sh` | Executable state machine (57+ transitions) |
| `forge-state-write.sh` | Atomic JSON writes (WAL + `_seq`) |
| `forge-token-tracker.sh` | Token budget + ceiling enforcement |
| `forge-linear-sync.sh` | Event-driven Linear audit layer |
| `forge-sim.sh`, `forge-timeout.sh`, `forge-compact-check.sh` | Sim, timeout, compaction-suggest |
| `check_prerequisites.py`, `check-environment.sh` | Python 3.10+ + tool detection |
| `hooks/_py/otel.py` | OTel GenAI semconv emitter (live + `replay`, authoritative) |
| `hooks/automation_trigger.py` | Cron / CI / MCP automation dispatch |

**Mode overlays** (`shared/modes/`): `standard`, `bugfix`, `migration`, `bootstrap`, `testing`, `refactor`, `performance`. Loaded at PREFLIGHT from `state.mode`.

## Integrations

- **Linear** (optional, off by default): Epic/Stories/Tasks at PLAN, status per stage. MCP failure → graceful degradation.
- **MCP detection:** Linear, Playwright, Slack, Context7, Figma, Excalidraw, Neo4j. First failure → degraded for run. None required.
- **Cross-repo:** 5-step discovery at `/forge`. Contract validation, linked PRs, multi-repo worktrees. Timeout 30min, alphabetical lock ordering, PR failures don't block main PR.

## Knowledge graph

Two backends:
- **Neo4j** (Docker, opt-out via `graph.enabled: false`): plugin module graph + project codebase graph. Scoped by `project_id` + optional `component`. 8 agents have `neo4j-mcp` (010/020/090/100/102/200/210/400). Pipeline works without it.
- **SQLite code graph** (zero-dep, `code_graph.enabled: true` default): tree-sitter + SQLite at `.forge/code-graph.db` via `shared/graph/build-code-graph.sh`. 15 node types, 17 edge types, all 15 languages. `code_graph.backend: auto/sqlite/neo4j`. Survives reset.

## Check engine (`shared/checks/`)

4 layers on `Edit`/`Write`:
- **L0** (tree-sitter AST, PreToolUse): blocks invalid syntax. Config: `check_engine.l0_*`.
- **L1** (regex, sub-second, PostToolUse): tokens, animation perf.
- **L2** (linter adapters).
- **L3** (AI, version-gated): deprecation refresh + version compat.

`rules-override.json` extends defaults (`"disabled": true` to suppress). Skips tracked at `.forge/.check-engine-skipped`. `learned-rules-override.json` auto-promoted from retrospective (`shared/learnings/rule-promotion.md`).

**Deprecation registries** (`modules/frameworks/*/known-deprecations.json`, schema v2): fields `pattern`, `replacement`, `package`, `since`, `removed_in`, `applies_from`, `applies_to`, `added`, `addedBy`. Skip when project version < `applies_from`. WARNING if deprecated, CRITICAL if `removed_in` reached.

## Infra testing (`fg-610-infra-deploy-verifier`)

5 tiers, configurable via `infra.max_verification_tier`: T1 (<10s, lint), T2 (<60s, container+trivy), **T3 default** (<5min, ephemeral cluster), T4 (<5min, contract stubs), T5 (<15min, full integration). Findings: `INFRA-HEALTH/E2E/CONTRACT` (CRITICAL), `INFRA-SMOKE/IMAGE` (WARNING).

## Skills, hooks, kanban, git

**Skills (28):** see Skill selection guide table above for command surface; full list `ls skills/`. Each ships with manifest in `skills/<name>/SKILL.md`.

**Hooks** (6 entries in `hooks.json`, 6 Python entry scripts; design contract in `shared/hook-design.md`):
- L0 syntax validation: PreToolUse `Edit|Write` → `pre_tool_use.py`.
- Check engine + automation trigger: PostToolUse `Edit|Write` → `post_tool_use.py` (delegates to `_py.check_engine.engine` + `automation_trigger`).
- Skill checkpoint: PostToolUse `Skill` → `post_tool_use_skill.py`.
- Compaction check: PostToolUse `Agent` → `post_tool_use_agent.py`.
- Feedback capture: Stop → `stop.py`.
- Session priming: SessionStart → `session_start.py`.

**Kanban** (`.forge/tracking/`): file-based board (`backlog/`, `in-progress/`, `review/`, `done/`). Prefix `FG` (configurable). IDs never reused. Skips silently if uninitialized.

**Git:** branch `{type}/{ticket}-{slug}` (configurable). Conventional Commits or `project` style auto-detected. **Never:** `Co-Authored-By`, AI attribution, `--no-verify`.

**Init:** `/forge` generates project-local plugin (hooks, skills, agents). Respects existing hooks. MCP auto-provisioning at init.

## Adding new modules

**New framework** — `modules/frameworks/{name}/` with: `conventions.md` (Dos/Don'ts), `local-template.md`, `forge-config-template.md` (must include `total_retries_max`, `oscillation_tolerance`), `rules-override.json`, `known-deprecations.json` (v2, 5-15 entries). Optional: `variants/`, `testing/`, `scripts/`, `hooks/`. Add `shared/learnings/{name}.md`. Bump `MIN_*` in `tests/lib/module-lists.bash`.

**New language / test framework** — also create `modules/{languages,testing}/{name}.md` + learnings file.

**New layer module** — `modules/{layer}/{name}.md` (Overview / Architecture / Config / Performance / Security / Testing / Dos / Don'ts). Optional `.rules-override.json`, `.known-deprecations.json`. Add framework bindings + learnings.

## Gotchas

**Structural**
- Agent `name` must match filename. Scripts need `#!/usr/bin/env bash` + `chmod +x`. Bash 4.0+ required (macOS: `brew install bash`); use `_glob_exists()` not `compgen -G`.
- `shared/` files are contracts — verify downstream impact on changes.
- Plugin never touches consuming-project files; runtime state always in `.forge/`.
- `forge-config.md` auto-tuned by retrospective; `<!-- locked -->` fences protect sections.
- `.forge/` deletion mid-run = unrecoverable; use `/forge-admin recover reset`. **Survives reset:** `explore-cache.json`, `plan-cache/`, `code-graph.db`, `trust.json`, `events.jsonl`, `playbook-analytics.json`, `playbook-refinements/`, `run-history.db`, `consistency-cache.jsonl`, `plans/candidates/`, `runs/<id>/handoffs/`, `progress/`, `run-history-trends.json`, `wiki/`, `.hook-failures.jsonl[*.gz]`. Only manual `rm -rf .forge/` removes them.
- Background runs write escalations to `.forge/alerts.json` (no interactive prompts).
- A2A protocol uses local filesystem (`.forge/agent-card.json`), not HTTP — needs shared FS between repos.
- Auto-discovered PREEMPT items decay 2× faster, start at MEDIUM, promote to HIGH after 3 successful applications.
- Automation cooldowns prevent loops (`automations.cooldown_seconds`, default 300).
- **Platform:** Python 3.10+. Full CI on macOS / Linux / Windows (Git Bash). Smoke CI on Windows PowerShell 7 (`tests/run-all.ps1`) and CMD (`tests/run-all.cmd`, structural+unit only). Installers: `install.sh` / `install.ps1`. WSL2 = Linux. A few dev-only sim harnesses stay bash-3.2 compatible (e.g. `convergence-engine-sim.sh`) and never run in hooks.

**Check engine**
- Broken `engine.sh` → all edits error. Timeout → skip counter increments + edit succeeds.
- `rules-override.json` extends (not replaces). YAML wants 2-space indent (otherwise WARNING + fallback).
- Deprecation v1 entries (no `applies_from`) apply universally. Unknown versions → all rules apply.

**PREFLIGHT** — see `shared/preflight-constraints.md` for all validation rules (scoring, convergence, sprint, shipping gates, model routing, implementer inner loop, confidence, output compression, AI quality, build graph, cost, eval, context guard).

**Pipeline modes**
- **Greenfield:** `/forge` on empty project → Bootstrap / Select stack / Skip.
- **Bootstrap:** Stage 4 skipped; reduced validation+review; target `pass_threshold`.
- **Bugfix:** `fg-020` → reproduction (max 3) → 4-perspective validation → reduced reviewers. Patterns in `.forge/forge-log.md`.
- **Migration:** all 10 stages; `fg-160` at Stage 2; Stage 4 cycles MIGRATING/PAUSED/CLEANUP/VERIFY.
- **Dry-run:** PREFLIGHT→VALIDATE only. No worktree/Linear/lock/checkpoints.
- **Autonomous** (`autonomous: true`): auto-selection logged `[AUTO]`. Never pauses except safety escalations (REGRESSING, E1-E4, unrecoverable CRITICAL). Cost-ceiling breach: try `cost_governance.downgrade_tier()` first, fall back to `abort_to_ship` if downgrade would drop a SAFETY_CRITICAL agent or already at `fast`. Decision logged `COST-ESCALATION-AUTO` + incident file. **AskUserQuestion is never invoked for cost in autonomous mode.**
- **Sprint:** `--sprint` / `--parallel`. Independence analysis → parallel orchestrators. Isolation: `.forge/runs/{id}/` + `.forge/worktrees/{id}/`. Serial = SHIP completes before second starts IMPLEMENT.

**Convergence & review**
- PREEMPT decay: time-aware Ebbinghaus per `shared/learnings/decay.md` (half-lives: auto-discovered 14d, cross-project 30d, canonical 90d; 0.95 ceiling; false positive drops base by 20%).
- Safety gate restart resets phase state, NOT `total_iterations`/`score_history`. First cycle exempt from plateau.
- PLATEAUED: ≥pass_threshold → safety gate. CONCERNS → escalate. FAIL → recommend abort.
- REGRESSING fires when `abs(delta) >= oscillation_tolerance` (inclusive). At the floor we escalate — asymmetric with `scoring.md` Consecutive Dip Rule (`<= tolerance = warn-continue`) because the inner quality-gate loop tolerates one same-tolerance dip per cycle while the outer convergence loop cannot. Worked scenarios: `convergence-examples.md` §5–6.
- Preview gating: FAIL blocks Stage 8. Fix loop max `preview.max_fix_loops`. Exhaustion → user choice.

**Implementation**
- Worktree created at PREFLIGHT (not IMPLEMENT). Exceptions: `--dry-run`, `/forge`. Branch from kanban ticket ID.
- Parallel tasks: scaffolders serial → conflict detect → implementers parallel. Shared files auto-serialized.
- Same PR rejection 2+ times → escalate options. `feedback_loop_count` incremented by orchestrator.
- Framework bindings EXTEND generic layers. `go-stdlib` / `framework: null` → language + testing only. `k8s` → `language: null`.
- `components` = per-service (monorepo). `modules` = per-repo (multi-repo). Both can coexist.
- **Versions:** never use training-data versions; always search at runtime.
- **Test counts:** auto-discovered via `module-lists.bash`; bump `MIN_*` when adding modules.
- **Implementer inner loop:** after each TDD cycle, lint changed files + affected tests (cap 20). Tracked as `implementer_fix_cycles` (separate from convergence). Disable: `implementer.inner_loop.enabled: false`.

## Distribution & governance

`.claude-plugin/plugin.json` (v4.1.0), `marketplace.json`. Hooks live only in `hooks/hooks.json`. Install: `/plugin marketplace add quantumbitcz/forge` → `/plugin install forge@quantumbitcz`.

`LICENSE` (Proprietary, QuantumBit s.r.o.), `CONTRIBUTING.md`, `SECURITY.md`, `.github/CODEOWNERS` (@quantumbitcz), `.github/release.yml`.
