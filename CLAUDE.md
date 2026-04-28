# CLAUDE.md

Guidance for Claude Code working in this repo.

## Start Here (5-minute path)

New to forge? Three steps:

1. **Install:** `ln -s $(pwd) /path/to/your-project/.claude/plugins/forge`, then in that project run `/forge "<your first feature description>"`. Forge auto-bootstraps `forge.local.md` on first invocation. See `shared/mcp-provisioning.md` for MCP auto-setup.
2. **First run:** `/forge run --dry-run "add a health endpoint"`. Dry-run only exercises PREFLIGHT → VALIDATE; no worktree, no commits. Confirm the plan looks right, then drop `--dry-run`.
3. **Pick the right skill:** unsure where to start? Run `/forge-ask tour` for the 5-stop guided introduction. Bug? `/forge fix "<description>"`. Quality check? `/forge review --full`. Multiple features? `/forge sprint`. Full skill grammar is in §Skill selection guide below.

Already familiar? Skip to §Architecture.

**Spend predictably:** `cost.ceiling_usd` in `forge-config.md` (default $25/run). Dispatch gate in `fg-100-orchestrator.md` §Cost Governance; helpers `shared/cost_governance.py`; analytics in `fg-700-retrospective.md` §2.7.

---

## What this is

`forge` is a Claude Code plugin (v5.3.0, `quantumbitcz` marketplace / Git submodule). 10-stage autonomous pipeline: Preflight → Brainstorming → Explore → Plan → Validate → Implement (TDD, voting-gated per-task) → Verify (build/test/lint + intent) → Review → Docs → Ship (evidence + intent clearance) → Learn. Entry: `/forge` → `fg-100-orchestrator`.

**Prompt-injection hardening:** External data tiered (Silent/Logged/Confirmed/Blocked) and wrapped in `<untrusted>` envelopes by `hooks/_py/mcp_response_filter.py` before reaching agents. All 51 agents carry the SHA-pinned Untrusted Data Policy header. Contract: `shared/untrusted-envelope.md`. Findings: `SEC-INJECTION-*`.

## Architecture

Layered, top-down resolution:

1. **Project config** — `.claude/forge.local.md`, `forge-config.md`, `forge-log.md` in consuming repo. Repo-root manifest: `README.md`, `CLAUDE.md`, `LICENSE`, `SECURITY.md`, `CONTRIBUTING.md`, `SCORECARD.md` (Phase 8 weekly scorecard).
2. **Module layer** (`modules/`):
   - `languages/` (15), `frameworks/` (24), `testing/` (19) — each with `conventions.md`, `variants/`, framework-binding subdirs (`testing/`, `persistence/`, `messaging/`, …).
   - Domain: `databases/`, `persistence/`, `migrations/`, `api-protocols/`, `messaging/`, `caching/`, `search/`, `storage/`, `auth/`, `observability/`.
   - ML/data: `ml-ops/` (4), `data-pipelines/` (3), `feature-flags/` (3).
   - Tooling: `build-systems/` (9), `ci-cd/` (7), `container-orchestration/` (11), `code-quality/` (~70 tools), `documentation/`.
   - **Composition** (most specific wins): variant > framework-binding > framework > language > code-quality > generic > testing. Algorithm: `shared/composition.md`.
3. **Shared core** — `agents/` (51), `shared/`, `hooks/`, `skills/` (3).
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

Doc-only plugin (no build). Smoke test: symlink → `/forge "<requirement>"` (auto-bootstraps) → `/forge run --dry-run` → `/forge run` → check `.forge/state.json`.

Pipeline-level evals: `tests/evals/pipeline/README.md` (CI-only; local `FORGE_EVAL=1 python -m tests.evals.pipeline.runner --dry-run --no-baseline`).

**Weekly benchmark.** Real-feature solve rate on a user-curated corpus runs weekly (Mon 06:00 UTC) and writes [SCORECARD.md](./SCORECARD.md). See `tests/evals/benchmark/README.md` for operator workflow.

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

Three skills cover the entire surface. Use `/forge` to write, `/forge-ask` to read, `/forge-admin` to manage state.

| Skill | Surface | When to use |
|---|---|---|
| `/forge` | [writes] | Build a feature, fix a bug, deploy, review, commit, migrate, bootstrap, generate docs, run a security audit. Universal entry. Hybrid grammar — explicit verbs win, plain text falls through to the intent classifier. Auto-bootstraps a missing `forge.local.md` on first run. |
| `/forge-ask` | [read-only] | Ask anything about the codebase or pipeline state — wiki, graph, run history, analytics, profile, onboarding tour. Never mutates project state. Subcommands: bare `<question>`, `status`, `history`, `insights`, `profile`, `tour`. |
| `/forge-admin` | [writes] | Manage forge state and configuration — recover, abort, edit config, hand off sessions, manage automations and playbooks, compress agents/output, run knowledge-graph ops, apply playbook refinements. Two-level dispatch: `<area> [<action>]`. |

See each skill's `SKILL.md` body for the full subcommand grammar and flag matrix.

### Getting started flows

```
First time?        /forge-ask tour                              # 5-stop guided introduction
New project:       /forge "<requirement>"                       # auto-bootstraps forge.local.md, then runs the pipeline
Existing project:  /forge review --scope=all                    # codebase audit (read-only)
                   /forge review --scope=all --fix              # iterative cleanup with safety gate
                   /forge "<requirement>"                       # then ship features
Bug fix:           /forge fix "<description or ticket ID>"
Code quality:      /forge review --full                         # changed files
                   /forge review --scope=all                    # whole codebase
Before shipping:   /forge verify                                # build + lint + test
                   /forge review --full                         # full quality gate
Pipeline trouble:  /forge-admin recover diagnose                # read-only triage
                   /forge-admin recover repair                  # fix counters/locks
                   /forge-admin recover resume                  # continue from last checkpoint
Multiple features: /forge sprint                                # parallel orchestration (Linear or manual list)
```

## Agents (51, `agents/*.md`)

**Pipeline** (`fg-NNN-role`):
- **Pre:** 010-shaper (always-on for feature mode; seven-step BRAINSTORMING with one-question-at-a-time, 2-3 approach proposals, sectioned approval gates, transcript mining via F29 FTS5, autonomous degradation), 015-scope-decomposer, 020-bug-investigator (hypothesis register + Bayesian pruning + parallel sub-investigators via 021; fix-gate posterior ≥ 0.75), 021-hypothesis-investigator (Tier-4 sub-investigator dispatched by 020 for hypothesis branching), 050-bootstrapper. **Sprint:** 090.
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

`/forge "<request>"` auto-classifies intent and routes via `shared/intent-classification.md`. Explicit verbs (`run|fix|sprint|review|verify|deploy|commit|migrate|bootstrap|docs|audit`) win; plain text falls through to the classifier. The classifier's `vague` outcome (signal-count < 2) defaults to `run` mode (which then enters BRAINSTORMING). The `<50 words missing 3+ of (actors, entities, surface, criteria)` shaper threshold is **removed** — BRAINSTORMING is always-on for feature mode (opt out via `brainstorm.enabled: false`). Prefixes (`bugfix:`, `migrate:`, `bootstrap:`) and flags (`--parallel`) override. Multi-feature detected via fast scan / deep post-EXPLORE → `fg-015` → `fg-090`. Frontend design preview via superpowers visual companion at PLAN (graceful degradation). Config: `routing.*`, `scope.*`, `brainstorm.*`, `model_routing.*`, `explore.*`, `plan_cache.*`.

## Core contracts

**Scoring** (`scoring.md`): `score = max(0, 100 − 20·CRIT − 5·WARN − 2·INFO)`. PASS ≥80, CONCERNS 60-79, FAIL <60 or unresolved CRITICAL. 149 categories in `shared/checks/category-registry.json`. Key wildcards: `ARCH-*`, `SEC-*`, `PERF-*`, `TEST-*`, `CONV-*`, `DOC-*`, `QUAL-*`, `SCOUT-*` (excluded from score), `A11Y-*`, `DEP-*`, `INFRA-*`, `AI-{LOGIC,PERF,CONCURRENCY,SEC}-*`, `REFLECT-*`, `COST-*`. Dedup key: `(component, file, line, category)`. Convergence counters: `verify_fix_count`, `test_cycles`, `quality_cycles` (inner), `phase_iterations` (per-phase), `total_iterations` (cumulative). Separate: `implementer_fix_cycles` (does NOT count toward convergence). Timed-out reviewers: INFO → WARNING. 7 validation perspectives.

**State / recovery / errors:** State v2.0.0 in `.forge/` (gitignored). Checkpoints per task (CAS DAG `.forge/runs/<id>/checkpoints/`). Key fields: `mode` (standard/migration/bootstrap/bugfix), `feedback_loop_count` (escalates at 2), `recovery`, `ticket_id`, `branch_name`, `graph`, `plan_judge_loops`, `impl_judge_loops`, `judge_verdicts`, `consistency_*`, `cost`. Lock: `.forge/.lock` (PID + 24h stale). Recovery: 7 strategies, severity ceiling 5.5, `total_retries` budget (default 10). Errors: 22 types, 16-level severity. MCP failures → inline INFO. 3 transients in 60s → non-recoverable. `BUILD/TEST/LINT_FAILURE` → orchestrator fix loop.

**Stages:** PREFLIGHT → BRAINSTORMING → EXPLORING → PLANNING → VALIDATING → IMPLEMENTING → VERIFYING → REVIEWING → DOCUMENTING → SHIPPING → LEARNING. BRAINSTORMING is feature-mode only (skipped in bugfix/migration/bootstrap modes, on `--from=<post-brainstorm>` resume, or with `--spec <well-formed-path>`); see `agents/fg-010-shaper.md` for the seven-step pattern. Migration: MIGRATING/PAUSED/CLEANUP/VERIFY. PR rejection routes to Stage 4 (impl) or Stage 2 (design) via `fg-710`. **Evidence-based shipping:** `fg-590` runs fresh build+test+lint+review → `.forge/evidence.json`; PR builder refuses without `verdict: SHIP`. No "continue anyway".

**Deterministic control flow:** Transition table in `shared/state-transitions.md`. LLM judgment for review/impl/architecture — NOT transitions. Decisions logged to `.forge/decisions.jsonl`. Reviewer conflicts resolved by `shared/agent-communication.md` §3.1 priority.

### Pattern parity (with superpowers, no runtime dependency)

Twelve functional superpowers patterns are mirrored in-tree by forge agents. Forge does **not** require the superpowers plugin at runtime — patterns are ported into agent prompts and shared helpers under this repository.

| # | Superpowers skill | Forge agent / mechanism | Treatment |
|---|---|---|---|
| 1 | `brainstorming` | `fg-010-shaper` (always-on for feature mode) | Full rewrite, seven-step pattern |
| 2 | `writing-plans` | `fg-200-planner` | Full rewrite; per-task TDD scaffold; embedded `shared/prompts/implementer-prompt.md` and `shared/prompts/spec-reviewer-prompt.md` |
| 3 | `requesting-code-review` | `fg-400-quality-gate` + reviewers `fg-410..fg-419` | Prose report alongside findings JSON; cross-reviewer consistency voting |
| 4 | `receiving-code-review` | `fg-710-post-run` | Per-comment defense check (actionable / wrong / preference); multi-VCS adapters under `shared/platform_adapters/` |
| 5 | `systematic-debugging` | `fg-020-bug-investigator` + `fg-021-hypothesis-investigator` | Hypothesis register; Bayesian pruning; fix-gate posterior ≥ 0.75; parallel sub-investigators |
| 6 | `finishing-a-development-branch` | `fg-600-pr-builder` | `AskUserQuestion`-driven merge/PR/cleanup dialog; cleanup checklist |
| 7 | `test-driven-development` | `fg-300-implementer` | Polish: test-must-fail-first assertion |
| 8 | `verification-before-completion` | `fg-590-pre-ship-verifier` | Polish: `evidence.json` structural assertion |
| 9 | `subagent-driven-development` | `fg-100-orchestrator` | Polish: post-task checkpoint structural test |
| 10 | `dispatching-parallel-agents` | `fg-100-orchestrator` | Polish: single tool-use parallel-dispatch test |
| 11 | `executing-plans` | `fg-100-orchestrator` | Polish: per-3-task review checkpoint |
| 12 | `using-git-worktrees` | `fg-101-worktree-manager` | Polish: stale-worktree detection (`worktree.stale_after_days`, default 30) |

**Beyond-superpowers extensions** (forge-specific, exploit multi-agent architecture):
- **Cross-reviewer consistency voting** — ≥3 reviewers agreeing on a dedup key promotes confidence to HIGH.
- **Transcript mining** — `fg-010-shaper` queries the F29 run-history-store FTS5 index for similar features and pre-loads question patterns.
- **Hypothesis branching** — `fg-020-bug-investigator` dispatches up to 3 sub-investigators in parallel, prunes by Bayesian posterior, refuses to fix below the gate threshold.
- **Structured PR-finishing dialog** — `fg-600-pr-builder` uses `AskUserQuestion` for the merge/PR/cleanup decision; autonomous mode honors `pr_builder.default_strategy` (default `open-pr-draft`).

Two superpowers patterns are out of scope: `writing-skills` (forge does not author skills at runtime) and `using-superpowers` (plugin entry skill, no forge analogue).

## Features

45+ optional capabilities (cost governance, judge veto, speculative branches, self-consistency, repo-map PageRank, run history, MCP server, playbooks, property-based tests, flaky management, accessibility/i18n/perf regression, A2A, deployment strategies, contracts, AI quality, output compression, wiki, handoff, …). Per-feature config keys, IDs (F05-F44), categories, and activation state: **`shared/feature-matrix.md`** (auto-regen). Lifecycle: 90d unused → flagged, 180d → removal proposal (`shared/feature-lifecycle.md`).

<!-- FEATURE_MATRIX_START -->
| Feature | Config | Key details |
|---|---|---|
| Living specifications (F05) | `living_specs.*` | Spec-as-code; AC drift detection feeds INTENT-* findings. |
| Event-sourced log (F07) | `events.*` | `.forge/events.jsonl`; replay-friendly; survives reset. |
| Context condensation (F08) | `condensation.*` | Per-stage prompt compaction; complements output compression. |
| Active knowledge base (F09) | `active_knowledge.*` | Wiki + graph + explore cache + docs index; powers /forge-ask. |
| Enhanced security (F10) | `security.*` | Module-appropriate scanners; injection-hardened MCP envelope. |
| Playbooks (F11) | `playbooks.*` | Reusable recipes under `playbooks/`; analytics in `.forge/playbook-analytics.json`. |
| Spec inference (F12) | `spec_inference.*` | Heuristic AC extraction when shaper output is sparse. |
| Property-based testing (F13) | `property_testing.*` | `fg-515-property-test`; framework-aware adapters. |
| Flaky test management (F14) | `flaky_tests.*` | Quarantine, retry-budget, and root-cause classification. |
| Dynamic accessibility (F15) | `accessibility.*` | A11Y-* findings via `fg-413-frontend` (a11y mode). |
| i18n validation (F16) | `i18n.*` | Default-on; missing-key + locale-fallback checks. |
| Performance regression (F17) | `performance_tracking.*` | PERF-REGRESSION-* findings; baseline cached in `.forge/`. |
| Next-task prediction (F18) | `predictions.*` | Suggests follow-up tasks from run-history patterns. |
| DX metrics (F19) | `dx_metrics.*` | Stage timing + agent effectiveness; surfaced via /forge-ask insights. |
| Monorepo tooling (F20) | `monorepo.*` | Per-`components` config; build-graph dependency ordering. |
| A2A protocol (F21) | `a2a.*` | Local filesystem agent-card; cross-repo coordination. |
| AI/ML pipelines (F22) | `ml_ops.*` | `modules/ml-ops/`; feature-store + model-registry awareness. |
| Feature flags (F23) | `feature_flags.*` | `modules/feature-flags/`; rollout-aware checks. |
| Deployment strategies (F24) | `deployment.*` | Canary / blue-green / rolling; `fg-610-infra-deploy-verifier`. |
| Consumer-driven contracts (F25) | `contract_testing.*` | `fg-250-contract-validator`; provider/consumer split. |
| Output compression (F26) | `output_compression.*` | Per-stage verbosity (off / lite / full / ultra). |
| AI quality (F27) | `ai_quality.*` | AI-LOGIC / AI-PERF / AI-CONCURRENCY / AI-SEC findings. |
| Cross-project learnings (F28) | `cross_project.*` | Shared learnings across repos; decay-aware promotion. |
| Run history store (F29) | `run_history.*` | SQLite at `.forge/run-history.db`; FTS5 transcript index. |
| MCP server (F30) | `mcp_server.*` | Auto-provisioned by auto-bootstrap (or /forge-admin config wizard) into .mcp.json. |
| Self-improving playbooks (F31) | `playbooks.refinement.*` | Skill: /forge-admin refine. Proposals reviewed before apply. |
| Implementer reflection (judges) (F32) | `plan.judge.*`, `implementer.reflection.*` | `fg-205` plan-judge + `fg-301` impl-judge; binding REVISE; 2-loop bound. |
| Self-consistency voting (F33) | `consistency.*` | N=3 majority on validator + PR-rejection classification. |
| Session handoff (F34) | `handoff.*` | Skill: /forge-admin handoff. Transfers run state to fresh CC session. |
| Intent verification gate (F35) | `intent_verification.*` | `fg-540-intent-verifier` at end of Stage 5 VERIFY; `fg-590` hard-SHIP-gates on 0 INTENT-MISSED + verified_pct >= strict_ac_required_pct. Default enabled. |
| Implementer voting (F36) | `impl_voting.*` | Confidence-gated N=2 sampling; `fg-302-diff-judge` AST tiebreak. Default enabled; cost-skip when <30% budget remains. |
| BRAINSTORMING (F37) | `brainstorm.*` | Always-on for feature mode; `enabled: false` to disable. Seven-step pattern in `fg-010-shaper`. Spec dir `docs/superpowers/specs/` (configurable via `brainstorm.spec_dir`). State enum `BRAINSTORMING` in `state-schema.md`. |
| Transcript mining (F38) | `brainstorm.transcript_mining.*` | F29 FTS5-backed historical context for `fg-010-shaper`. `top_k` default 3 (range 1-10); `max_chars` default 4000. Writes `.forge/brainstorm-transcripts/<run_id>.jsonl`. |
| Cross-reviewer consistency voting (F39) | `quality_gate.consistency_promotion.*` | >= threshold reviewer agreement (default 3, range 2-9) on a dedup key promotes confidence to HIGH (1.0x weight). Logged as `consistency_promoted: true` on the finding. |
| Defense-check feedback handling (F40) | `post_run.defense_*` | `fg-710-post-run` per-comment verdict: actionable / wrong / preference. Defense responses posted via platform adapter. State: `state.feedback_decisions[]`; mirror at `.forge/runs/<run_id>/feedback-decisions.jsonl`. Only `actionable` increments `feedback_loop_count`. |
| Hypothesis branching for bugs (F41) | `bug.hypothesis_branching.*` | Up to 3 parallel sub-investigators via `fg-021-hypothesis-investigator`. Bayesian pruning. Fix-gate threshold `bug.fix_gate_threshold` (default 0.75, range 0.50-0.95). State: `state.bug.hypotheses[]`. |
| Multi-VCS platform abstraction (F42) | `platform.*` | GitHub / GitLab / Bitbucket / Gitea/Forgejo. Detection at PREFLIGHT via `shared/platform-detect.py`; cached in `state.platform`. Adapters under `shared/platform_adapters/`. Pure Python (urllib.request); cross-platform. |
| Structured PR finishing (F43) | `pr_builder.*` | `fg-600-pr-builder` AskUserQuestion dialog with five options: open-pr / open-pr-draft / direct-push / stash / abandon. Cleanup checklist runs after the chosen strategy. Autonomous default: open-pr-draft. |
| Stale-worktree detection (F44) | `worktree.stale_after_days` | `fg-101-worktree-manager` flags worktrees older than the threshold (default 30, range 1-365). Finding category `WORKTREE-STALE` (WARNING). |
| Wiki generator | `wiki.*` | Markdown wiki under `.forge/wiki/`; survives reset. |
| Memory discovery | (auto) | Indexes `.claude/projects/.../memory/MEMORY.md`; cross-session context. |
| Background execution | (auto) | Headless runs write escalations to `.forge/alerts.json`; no interactive prompts. |
| Automations | `automations.*` | Cron / CI / MCP triggers via `hooks/automation_trigger.py`; cooldowns prevent loops. |
| Visual verification | (frontend) | Superpowers visual companion at PLAN; graceful degradation if MCP absent. |
| LSP integration | (auto) | Tree-sitter + LSP-aware checks in L0/L1 layers. |
| Observability | `observability.*` | OTel GenAI semconv emitter; `forge.cost.*` + per-stage spans. |
| Data classification | (auto) | PII-aware redaction in event log + handoff bundles. |
| Security posture | (auto) | Injection-hardened MCP envelope; SHA-pinned untrusted-data policy. |
| Pipeline timeline | (auto) | Per-stage timing via /forge-ask insights. |
| Codebase Q&A | (auto) | /forge-ask answers from wiki + graph + explore cache + docs index. |
| Caveman I/O | `output_compression.*` | Aggressive token reduction modes for cost-sensitive runs. |
| Repo-map PageRank | `code_graph.prompt_compaction.*` | Centrality x recency x keyword overlap; ~30-50% token savings on 100/200/300 prompts. |
| Speculative plan branches | `speculation.*` | Parallel candidate plans cached in `.forge/plans/candidates/`. |
| Docs integrity | (auto) | Lychee link-checking; fenced code blocks excluded. |
<!-- FEATURE_MATRIX_END -->

Cross-cutting subsystems used by most features:
- **Confidence** (`confidence.*`): finding HIGH/MED/LOW (1.0/0.75/0.5x); pipeline 4-dim (clarity 0.30, familiarity 0.25, complexity 0.20, history 0.25). Gate: ≥0.7 proceed, ≥0.4 ask, <0.4 → BRAINSTORMING (handled by `fg-010-shaper`). Trust state in `.forge/trust.json`.
- **Repo-map PageRank** (`code_graph.prompt_compaction.*`, opt-in): `hooks/_py/repomap.py` ranks files by centrality × recency × keyword overlap. `{{REPO_MAP_PACK}}` replaces dir listings in 100/200/300 prompts (~30-50% token savings). Cache: `.forge/ranked-files-cache.json`. Reference: `shared/graph/pagerank-sql.md`.
- **Cost governance** (`cost.*`): USD ceiling, dispatch-gate projection, soft throttle (80/90% in implementer §5.3b emits `COST-THROTTLE-IMPL`). Dynamic tier downgrade with hardcoded SAFETY_CRITICAL list (210/250/411/412/414/419/500/505/506/590) — never silently skipped. Incidents: `.forge/cost-incidents/<ts>.json`. OTel: `forge.cost.*`.
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
- **Cross-repo:** 5-step discovery on auto-bootstrap (or explicit `/forge bootstrap`). Contract validation, linked PRs, multi-repo worktrees. Timeout 30min, alphabetical lock ordering, PR failures don't block main PR.

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

## Skills (3 total), hooks, kanban, git

**Skills:** Three top-level skills cover all functionality:

- `/forge` — write surface. Universal entry; hybrid verb grammar (`run`, `fix`, `sprint`, `review`, `verify`, `deploy`, `commit`, `migrate`, `bootstrap`, `docs`, `audit`); plain-text fallthrough routes via `shared/intent-classification.md`; auto-bootstraps a missing `forge.local.md` on first invocation.
- `/forge-ask` — read-only surface. Default action is codebase Q&A via wiki + graph + explore cache + docs index. Subcommands: `status`, `history`, `insights`, `profile`, `tour`.
- `/forge-admin` — state management surface. Two-level subcommand dispatch: `recover`, `abort`, `config`, `handoff`, `automation`, `playbooks`, `compress`, `graph`, `refine`.

Each skill's `SKILL.md` body documents the full subcommand grammar, flag matrix, and dispatch table.

**Hooks** (6 entries in `hooks.json`, 6 Python entry scripts; design contract in `shared/hook-design.md`):
- L0 syntax validation: PreToolUse `Edit|Write` → `pre_tool_use.py`.
- Check engine + automation trigger: PostToolUse `Edit|Write` → `post_tool_use.py` (delegates to `_py.check_engine.engine` + `automation_trigger`).
- Skill checkpoint: PostToolUse `Skill` → `post_tool_use_skill.py`.
- Compaction check: PostToolUse `Agent` → `post_tool_use_agent.py`.
- Feedback capture: Stop → `stop.py`.
- Session priming: SessionStart → `session_start.py`.

**Kanban** (`.forge/tracking/`): file-based board (`backlog/`, `in-progress/`, `review/`, `done/`). Prefix `FG` (configurable). IDs never reused. Skips silently if uninitialized.

**Git:** branch `{type}/{ticket}-{slug}` (configurable). Conventional Commits or `project` style auto-detected. **Never:** `Co-Authored-By`, AI attribution, `--no-verify`.

**Init:** No explicit init skill. The first `/forge` invocation in a project missing `.claude/forge.local.md` auto-bootstraps via `shared/bootstrap-detect.py`. Detection prompts the user with detected stack defaults and offers `[proceed]`/`[open wizard]`/`[cancel]`. Autonomous mode skips the prompt and writes defaults silently. MCP auto-provisioning runs as part of bootstrap.

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
- `.forge/` deletion mid-run = unrecoverable; use `/forge-admin recover reset`. **Survives reset:** `explore-cache.json`, `plan-cache/`, `code-graph.db`, `trust.json`, `events.jsonl`, `playbook-analytics.json`, `playbook-refinements/`, `run-history.db`, `consistency-cache.jsonl`, `plans/candidates/`, `runs/<id>/handoffs/`, `progress/`, `run-history-trends.json`, `wiki/`, `.hook-failures.jsonl[*.gz]`, `brainstorm-transcripts/`, `runs/<id>/feedback-decisions.jsonl`. Only manual `rm -rf .forge/` removes them.
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
- **Greenfield:** `/forge` on an empty project detects no recognizable stack → offer `/forge bootstrap <stack>` or `/forge-admin config wizard`. No silent half-init.
- **Bootstrap:** Stage 4 skipped. Reduced validation + review. Target = `pass_threshold`. Triggered by `/forge bootstrap <stack>` or `bootstrap:` prefix.
- **Bugfix:** `/forge fix "<description>"` or `bugfix:` prefix. Skips BRAINSTORMING. `fg-020-bug-investigator` runs reproduction (max 3) → hypothesis register (up to 3) → optional parallel sub-investigators (`fg-021-hypothesis-investigator`) → Bayesian pruning → fix-gate (posterior ≥ `bug.fix_gate_threshold`, default 0.75). 4-perspective validation. Reduced reviewers. Patterns in `.forge/forge-log.md`.
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
- Worktree created at PREFLIGHT (not IMPLEMENT). Exceptions: `--dry-run`, auto-bootstrap on first `/forge` invocation, `/forge bootstrap <stack>`. Branch from kanban ticket ID. Stale-worktree detection flags worktrees older than `worktree.stale_after_days` (default 30).
- Parallel tasks: scaffolders serial → conflict detect → implementers parallel. Shared files auto-serialized.
- Feedback loop: same PR rejection 2+ times → escalate options. `feedback_loop_count` incremented by orchestrator. **Only "actionable" feedback (per `fg-710-post-run` defense check) increments the counter** — feedback marked "wrong" (defended) or "preference" (acknowledged) does not.
- Framework bindings EXTEND generic layers. `go-stdlib` / `framework: null` → language + testing only. `k8s` → `language: null`.
- `components` = per-service (monorepo). `modules` = per-repo (multi-repo). Both can coexist.
- **Versions:** never use training-data versions; always search at runtime.
- **Test counts:** auto-discovered via `module-lists.bash`; bump `MIN_*` when adding modules.
- **Implementer inner loop:** after each TDD cycle, lint changed files + affected tests (cap 20). Tracked as `implementer_fix_cycles` (separate from convergence). Disable: `implementer.inner_loop.enabled: false`.

## Distribution & governance

`.claude-plugin/plugin.json` (v5.3.0), `marketplace.json`. Hooks live only in `hooks/hooks.json`. Install: `/plugin marketplace add quantumbitcz/forge` → `/plugin install forge@quantumbitcz`.

`LICENSE` (Proprietary, QuantumBit s.r.o.), `CONTRIBUTING.md`, `SECURITY.md`, `.github/CODEOWNERS` (@quantumbitcz), `.github/release.yml`.
