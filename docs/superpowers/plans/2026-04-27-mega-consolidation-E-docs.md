# Forge Mega-Consolidation — Phase E: Documentation Rollup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Update CLAUDE.md and README.md to reflect the new three-skill surface, BRAINSTORMING stage, all five pattern-parity uplifts, and four beyond-superpowers enhancements. Regenerate the feature matrix block inside CLAUDE.md.

**Architecture:** Two atomic doc commits. E1 is prose updates to existing top-level docs; E2 is a regenerated machine-block bounded by sentinels. No code changes, no test additions.

**Tech Stack:** Markdown only.

**Spec reference:** `docs/superpowers/specs/2026-04-27-skill-consolidation-design.md` commit 660dbef7. The full spec is the input.

---

## Cross-phase context

Phase E ships **last** in the train. It depends on every prior phase having shipped:

- **Phase A** (commits A1–A6) — helpers (`shared/ac-extractor.py`, `shared/bootstrap-detect.py`, `shared/platform-detect.py`), preflight constraints, intent classification, state schema bump (BRAINSTORMING enum + `state.brainstorm`/`state.bug`/`state.feedback_decisions`/`state.platform`).
- **Phase B** (commits B1–B13) — three new skills (`/forge`, `/forge-ask`, `/forge-admin`), atomic deletion of 28 retired skills, callsite rewiring across docs/tests/agents/shared/modules/manifests, structural enforcement tests.
- **Phase C** (commits C1–C2) — `fg-010-shaper` rewrite (seven-step BRAINSTORMING + transcript mining) and `fg-100-orchestrator` BRAINSTORMING dispatch + PREFLIGHT platform-detection wiring.
- **Phase D** (commits D1–D9) — five uplifts (planner, reviewer pipeline, post-run, bug investigator, PR builder), strong-agent polish (TDD, verifier, orchestrator, worktree manager), four beyond-superpowers improvements (consistency voting, transcript mining, hypothesis branching, structured PR-finishing dialog), new agent file `fg-021-hypothesis-investigator`.

Phase E emits two doc commits, no test additions, no code changes. It is therefore the lowest-risk phase. Reverting either commit reverts only documentation drift; the runtime is unaffected.

**Reference files (read in this order before starting):**

1. `/Users/denissajnar/IdeaProjects/forge/docs/superpowers/specs/2026-04-27-skill-consolidation-design.md` (the full spec)
2. `/Users/denissajnar/IdeaProjects/forge/CLAUDE.md` (current state — 408 lines)
3. `/Users/denissajnar/IdeaProjects/forge/README.md` (current state — 284 lines)
4. `/Users/denissajnar/IdeaProjects/forge/docs/superpowers/specs/2026-04-22-phase-2-contract-enforcement-design.md` (FEATURE_MATRIX sentinel contract for E2)

**Important:** AC-S005 (no retired skill names anywhere except the explicit allowlist file) is structurally enforced by `tests/structural/skill-references-allowlist.txt` already added in B13. E1 must not reintroduce any retired skill name into CLAUDE.md or README.md. The grep step on each task is a fast local sanity check — the authoritative test runs in CI.

---

## Task E1: Mega update to `CLAUDE.md` and `README.md`

**Risk:** low

**Files modified:**
- `CLAUDE.md`
- `README.md`

**ACs covered:** none directly. Implicitly verifies AC-S005 (no retired skill names) on the two top-level docs. Authoritative AC-S005 test is owned by B13.

### TDD steps

- [ ] **Step 1 — Read starting state.** Read both files in full to capture current section structure and identify every retired skill reference. Build a mental list of sections that need rewriting.

  **Ground-truth state at spec date (2026-04-27):**
  - `CLAUDE.md` is 408 lines. Header reads `## Agents (50 total, agents/*.md)` (line 140) — Phase 7 added `fg-302-diff-judge` (F36) and `fg-540-intent-verifier` (F35) bringing the pre-Phase-D total to 50. Feature matrix runs lines 210-254 (the table opens at the `| Feature | Config | Key details |` header).
  - `README.md` is 284 lines. Agent badge reads `agents-42` (stale by 8: actual file count is 50 before Phase D, 51 after). Skill badge reads `skills-35`.
  - Phase D (D6) adds exactly one new agent file: `agents/fg-021-hypothesis-investigator.md`. Pre-Phase-D file count is 50; post-Phase-D is **51**. Both numbers must be reflected. (The earlier draft of this plan said 48 → 49; that is corrected to 50 → 51 here because Phase 7 shipped fg-302 and fg-540 between the plan-draft date and the implementation date.)
  - Phase D, B12, and B5 do NOT modify the "Start Here" section, "What this is", "Quick start" bash, "Development workflow", or "Confidence scoring" line — those updates are owned by E1 and are listed below as Steps 1a-1e.

- [ ] **Step 1a — Update `CLAUDE.md` "Start Here (5-minute path)" section (currently ~lines 5-21).** Rewrite to use the new three-skill surface. Replacement block:

  ```markdown
  ## Start Here (5-minute path)

  New to forge? Three steps:

  1. **Install:** `ln -s $(pwd) /path/to/your-project/.claude/plugins/forge`,
     then in that project run `/forge "<your first feature description>"`.
     Forge auto-bootstraps `forge.local.md` on first invocation. See
     `shared/mcp-provisioning.md` for MCP auto-setup.
  2. **First run:** `/forge run --dry-run "add a health endpoint"`. Dry-run only
     exercises PREFLIGHT → VALIDATE; no worktree, no commits. Confirm the plan
     looks right, then drop `--dry-run`.
  3. **Pick the right skill:** unsure where to start? Run `/forge-ask tour` for
     the 5-stop guided introduction. Bug? `/forge fix "<description>"`. Quality
     check? `/forge review --full`. Multiple features? `/forge sprint`. Full
     skill grammar is in §Skill selection guide below.

  Already familiar? Skip to §Architecture.
  ```

- [ ] **Step 1b — Update `CLAUDE.md` "What this is" section (currently ~line 25).** Replace the line ending `Entry: /forge-run → fg-100-orchestrator.`:

  ```markdown
  `forge` is a Claude Code plugin (v3.6.0, `quantumbitcz` marketplace / Git submodule). 10-stage autonomous pipeline: Preflight → Brainstorming → Explore → Plan → Validate → Implement (TDD) → Verify → Review → Docs → Ship → Learn. Entry: `/forge` → `fg-100-orchestrator`.
  ```

- [ ] **Step 1c — Update `CLAUDE.md` "Quick start" bash block (currently ~lines 48-56).** Replace the local-install hint:

  ```bash
  ./tests/validate-plugin.sh          # 73+ structural checks, ~2s
  ./tests/run-all.sh                  # Full test suite, ~30s
  ln -s "$(pwd)" /path/to/project/.claude/plugins/forge  # Local install, then /forge "<requirement>"
  ```

  And replace the trailing prose line "First-time? Read `shared/agent-philosophy.md` first..." with:

  ```markdown
  **First-time?** Read `shared/agent-philosophy.md` first. Run `validate-plugin.sh` after every change.
  ```

  (No skill-name change in the trailing prose; only the bash comment changes. Verify with grep after the edit.)

- [ ] **Step 1d — Update `CLAUDE.md` "Development workflow" section (currently ~line 60).** Replace:

  ```markdown
  Doc-only plugin (no build). Test: symlink into `.claude/plugins/` → `/forge "<req>"` (auto-bootstraps) → `/forge run --dry-run <req>` → `/forge run <req>` → check `.forge/state.json`.
  ```

- [ ] **Step 1e — Update `CLAUDE.md` "Confidence scoring" line (currently ~line 202).** Replace the `LOW (<0.4) → /forge-shape` reference. The new line:

  ```markdown
  Confidence scoring: two-level — (1) finding confidence (HIGH=1.0x, MEDIUM=0.75x, LOW=0.5x weight multipliers); (2) pipeline confidence (4-dimension: clarity 0.30, familiarity 0.25, complexity 0.20, history 0.25). Gate: HIGH (>=0.7) proceeds, MEDIUM (>=0.4) asks, LOW (<0.4) → BRAINSTORMING (handled by `fg-010-shaper`; previously delegated to retired `/forge-shape`). Adaptive trust in `.forge/trust.json`. Config: `confidence.*`.
  ```

- [ ] **Step 2 — Update `CLAUDE.md` section "Skill selection guide" (currently ~lines 92-124).** Replace the entire 33-row table with a three-row table:

  ```markdown
  ## Skill selection guide

  Three skills cover the entire surface. Use `/forge` to write, `/forge-ask` to read, `/forge-admin` to manage state.

  | Skill | Surface | When to use |
  |---|---|---|
  | `/forge` | [writes] | Build a feature, fix a bug, deploy, review, commit, migrate, bootstrap, generate docs, run a security audit. Universal entry. Hybrid grammar — explicit verbs win, plain text falls through to the intent classifier. Auto-bootstraps a missing `forge.local.md` on first run. |
  | `/forge-ask` | [read-only] | Ask anything about the codebase or pipeline state — wiki, graph, run history, analytics, profile, onboarding tour. Never mutates project state. Subcommands: bare `<question>`, `status`, `history`, `insights`, `profile`, `tour`. |
  | `/forge-admin` | [writes] | Manage forge state and configuration — recover, abort, edit config, hand off sessions, manage automations and playbooks, compress agents/output, run knowledge-graph ops, apply playbook refinements. Two-level dispatch: `<area> [<action>]`. |

  See each skill's `SKILL.md` body for the full subcommand grammar and flag matrix.
  ```

- [ ] **Step 3 — Update `CLAUDE.md` section "Getting started flows" (currently ~lines 126-138).** Apply the §12.1 mapping table from the spec verbatim. The replacement block:

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

  Note the deletion: `/forge-help` is gone (interactive decision tree absorbed into this getting-started block). `/forge-init` is gone (auto-bootstrap on first `/forge` invocation).

- [ ] **Step 4 — Update `CLAUDE.md` section "Skills (29 total), hooks, kanban, git" (currently ~line 306).** Rewrite the section header and the Skills paragraph:

  ```markdown
  ## Skills (3 total), hooks, kanban, git

  **Skills:** Three top-level skills cover all functionality:

  - `/forge` — write surface. Universal entry; hybrid verb grammar (`run`, `fix`, `sprint`, `review`, `verify`, `deploy`, `commit`, `migrate`, `bootstrap`, `docs`, `audit`); plain-text fallthrough routes via `shared/intent-classification.md`; auto-bootstraps a missing `forge.local.md` on first invocation.
  - `/forge-ask` — read-only surface. Default action is codebase Q&A via wiki + graph + explore cache + docs index. Subcommands: `status`, `history`, `insights`, `profile`, `tour`.
  - `/forge-admin` — state management surface. Two-level subcommand dispatch: `recover`, `abort`, `config`, `handoff`, `automation`, `playbooks`, `compress`, `graph`, `refine`.

  Each skill's `SKILL.md` body documents the full subcommand grammar, flag matrix, and dispatch table.
  ```

  Leave the **Hooks**, **Kanban**, **Git**, **Init** subsections intact except for one edit in the **Init** subsection — replace the line with:

  ```markdown
  **Init:** No explicit `/forge-init` skill. The first `/forge` invocation in a project missing `.claude/forge.local.md` auto-bootstraps via `shared/bootstrap-detect.py` (added in commit A2). Detection prompts the user with detected stack defaults and offers `[proceed]`/`[open wizard]`/`[cancel]`. Autonomous mode skips the prompt and writes defaults silently. MCP auto-provisioning runs as part of bootstrap.
  ```

- [ ] **Step 5 — Update `CLAUDE.md` "Stage contracts & shipping" section (currently ~line 192).** Insert BRAINSTORMING into the state list. The replacement line:

  ```markdown
  States: PREFLIGHT → BRAINSTORMING → EXPLORING → PLANNING → VALIDATING → IMPLEMENTING → VERIFYING → REVIEWING → DOCUMENTING → SHIPPING → LEARNING. BRAINSTORMING is feature-mode only (skipped in bugfix/migration/bootstrap modes, on `--from=<post-brainstorm>` resume, or with `--spec <well-formed-path>`); see `agents/fg-010-shaper.md` for the seven-step pattern. Migration: MIGRATING/PAUSED/CLEANUP/VERIFY. PR rejection → Stage 4 (impl) or Stage 2 (design) via `fg-710-post-run`.
  ```

- [ ] **Step 6 — Update `CLAUDE.md` "## Agents" section header and Pre-pipeline agent line (currently ~lines 140-143).**

  First, bump the section header from `## Agents (50 total, agents/*.md)` to `## Agents (51 total, agents/*.md)` to reflect the new `fg-021-hypothesis-investigator` added by Phase D6. (Pre-D total of 50 already accounts for fg-302-diff-judge and fg-540-intent-verifier shipped in Phase 7.)

  Then update the Pre-pipeline bullet to note the always-on shaper and the new sub-investigator:

  ```markdown
  - Pre-pipeline: `fg-010-shaper` (always-on for feature mode — adopts seven-step superpowers brainstorming pattern with one-question-at-a-time, 2-3 approach proposals, sectioned approval gates, transcript mining via F29 FTS5, autonomous degradation), `fg-015-scope-decomposer`, `fg-020-bug-investigator` (hypothesis register + Bayesian pruning + parallel sub-investigators via `fg-021-hypothesis-investigator`, fix-gate posterior ≥ 0.75), `fg-021-hypothesis-investigator` (Tier-4 sub-investigator dispatched by `fg-020` for hypothesis branching; new in Phase D6), `fg-050-project-bootstrapper`
  ```

- [ ] **Step 7 — Add new section "Pattern parity" to `CLAUDE.md` after the "Stage contracts & shipping" section.** Sourced from spec §10.1 coverage matrix:

  ```markdown
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
  - **Cross-reviewer consistency voting** (§5) — ≥3 reviewers agreeing on a dedup key promotes confidence to HIGH.
  - **Transcript mining** (§3 / §10) — `fg-010-shaper` queries the F29 run-history-store FTS5 index for similar features and pre-loads question patterns.
  - **Hypothesis branching** (§7) — `fg-020-bug-investigator` dispatches up to 3 sub-investigators in parallel, prunes by Bayesian posterior, refuses to fix below the gate threshold.
  - **Structured PR-finishing dialog** (§8) — `fg-600-pr-builder` uses `AskUserQuestion` for the merge/PR/cleanup decision; autonomous mode honors `pr_builder.default_strategy` (default `open-pr-draft`).

  Two superpowers patterns are out of scope: `writing-skills` (forge does not author skills at runtime) and `using-superpowers` (plugin entry skill, no forge analogue).
  ```

- [ ] **Step 8 — Update `CLAUDE.md` "Routing & decomposition" section (currently ~line 174).** Replace the first bullet:

  ```markdown
  - `/forge "<request>"` auto-classifies intent and routes via `shared/intent-classification.md`. Explicit verbs (`run|fix|sprint|review|verify|deploy|commit|migrate|bootstrap|docs|audit`) win; plain text falls through to the classifier. The classifier's `vague` outcome (signal-count < 2) defaults to `run` mode (which then enters BRAINSTORMING). The `<50 words missing 3+ of (actors, entities, surface, criteria)` shaper threshold is **removed** — BRAINSTORMING is always-on for feature mode (opt out via `brainstorm.enabled: false`). Config: `routing.*`, `scope.*`, `brainstorm.*` in `forge-config.md`.
  ```

- [ ] **Step 9 — Update `CLAUDE.md` "Pipeline modes" section (currently ~lines 376-382).** Replace the `Greenfield`, `Bootstrap`, and `Bugfix` lines:

  ```markdown
  - **Greenfield:** `/forge` on an empty project detects no recognizable stack → offer `/forge bootstrap <stack>` or `/forge-admin config wizard`. No silent half-init.
  - **Bootstrap:** Stage 4 skipped. Reduced validation + review. Target = `pass_threshold`. Triggered by `/forge bootstrap <stack>` or `bootstrap:` prefix.
  - **Bugfix:** `/forge fix "<description>"` or `bugfix:` prefix. Skips BRAINSTORMING. `fg-020-bug-investigator` runs reproduction (max 3) → hypothesis register (up to 3) → optional parallel sub-investigators (`fg-021-hypothesis-investigator`) → Bayesian pruning → fix-gate (posterior ≥ `bug.fix_gate_threshold`, default 0.75). 4-perspective validation. Reduced reviewers. Patterns in `.forge/forge-log.md`.
  ```

- [ ] **Step 10 — Update `CLAUDE.md` "Implementation" gotchas section (currently ~line 393-400).** Replace the worktree exception line and feedback-loop line:

  ```markdown
  - Worktree created at PREFLIGHT (not IMPLEMENT). Exceptions: `--dry-run`, auto-bootstrap on first `/forge` invocation, `/forge bootstrap <stack>`. Branch from kanban ticket ID. Stale-worktree detection flags worktrees older than `worktree.stale_after_days` (default 30).
  - Feedback loop: same PR rejection 2+ times → escalate options. `feedback_loop_count` incremented by orchestrator. **Only "actionable" feedback (per `fg-710-post-run` defense check) increments the counter** — feedback marked "wrong" (defended) or "preference" (acknowledged) does not.
  ```

- [ ] **Step 11 — Update `CLAUDE.md` "Structural" gotchas section (currently ~line 355).** Replace the bullet listing files that survive `/forge-recover reset`:

  ```markdown
  - `explore-cache.json`, `plan-cache/`, `code-graph.db`, `trust.json`, `events.jsonl`, `playbook-analytics.json`, `run-history.db`, `playbook-refinements/`, `consistency-cache.jsonl`, `.forge/plans/candidates/`, `.forge/runs/<id>/handoffs/`, `.forge/brainstorm-transcripts/`, and `.forge/runs/<id>/feedback-decisions.jsonl` survive `/forge-admin recover reset`. Only manual `rm -rf .forge/` removes them.
  ```

  Also: do a final §12.1 sweep across `CLAUDE.md` to catch any retired skill name not already addressed by Steps 1a-1e or Steps 2-12. Apply every entry from the §12.1 mapping table:

  ```
  /forge-init                  →  (auto on /forge or /forge bootstrap or /forge-admin config wizard)
  /forge-run                   →  /forge run
  /forge-fix                   →  /forge fix
  /forge-shape                 →  (absorbed into BRAINSTORMING in /forge run)
  /forge-sprint                →  /forge sprint
  /forge-review                →  /forge review
  /forge-verify                →  /forge verify
  /forge-deploy                →  /forge deploy
  /forge-commit                →  /forge commit
  /forge-migration             →  /forge migrate
  /forge-bootstrap             →  /forge bootstrap
  /forge-docs-generate         →  /forge docs
  /forge-security-audit        →  /forge audit
  /forge-status                →  /forge-ask status
  /forge-history               →  /forge-ask history
  /forge-insights              →  /forge-ask insights
  /forge-profile               →  /forge-ask profile
  /forge-tour                  →  /forge-ask tour
  /forge-help                  →  (deleted; remove any remaining refs)
  /forge-ask                   →  /forge-ask     (unchanged)
  /forge-recover               →  /forge-admin recover
  /forge-abort                 →  /forge-admin abort
  /forge-config                →  /forge-admin config
  /forge-handoff               →  /forge-admin handoff
  /forge-automation            →  /forge-admin automation
  /forge-playbooks             →  /forge-admin playbooks
  /forge-playbook-refine       →  /forge-admin refine
  /forge-compress              →  /forge-admin compress
  /forge-graph                 →  /forge-admin graph
  ```

  Specifically known stragglers in `CLAUDE.md` that this sweep must catch (not exhaustively listed elsewhere): line 25 (`Entry: /forge-run`), line 53 (bash code in Quick start), line 60 (Development workflow), line 174 (Routing & decomposition `/forge-run` and `/forge-sprint`), line 202 (Confidence scoring `/forge-shape`), line 204 (Repo-map `/forge-recover reset`), lines 285/291/316/354/360/376/393 (Cross-repo, SQLite code graph, Init, Structural gotchas, Wiki, Greenfield, Implementation gotchas). Most are already covered by Steps 1a-1e or 12; this sweep is the safety net.

- [ ] **Step 12 — Update `CLAUDE.md` "Cross-repo" line (currently ~line 285).** Replace `/forge-init` reference:

  ```markdown
  - **Cross-repo:** 5-step discovery on auto-bootstrap (or explicit `/forge bootstrap`). Contract validation, linked PRs, multi-repo worktrees. Timeout: 30min (configurable). Alphabetical lock ordering. PR failures don't block main PR. Discovery results stored with `detected_via`.
  ```

- [ ] **Step 13 — Update `CLAUDE.md` "Adaptive MCP detection" reference and "Init" line in MCP server feature row (in feature matrix).** The feature-matrix row for F30 currently reads `Auto-provisioned by `/forge-init` into `.mcp.json``. E1 leaves the matrix alone (E2 owns regeneration); rewrite this single string in F30's row to `Auto-provisioned by auto-bootstrap (or `/forge-admin config wizard`) into `.mcp.json``. Note: this single in-row edit is a quick patch ahead of E2's full regeneration to keep the file passing AC-S005 between commits E1 and E2.

- [ ] **Step 14 — Update `README.md` Quick Start (lines 17-29).** Replace with:

  ```markdown
  ## Quick start

  ```bash
  # 1. Install the plugin
  /plugin marketplace add quantumbitcz/forge
  /plugin install forge@quantumbitcz

  # 2. Run it — auto-bootstraps forge.local.md on first invocation
  /forge "Add user dashboard with activity feed"
  ```

  No explicit init step. The first `/forge` invocation detects your stack (language, framework, testing, build) and offers `[proceed]` / `[open wizard]` / `[cancel]`. Autonomous mode (`autonomous: true` in `.claude/forge.local.md`, or `--autonomous` flag) writes defaults silently and continues.
  ```

  Leave the alternative-Git-submodule details collapsible in place.

- [ ] **Step 15 — Update `README.md` "Available skills" section (lines 100-138).** Replace the 30+ row table with three rows:

  ```markdown
  ## Available skills

  Three skills cover all functionality. Each advertises its impact with a `[read-only]` or `[writes]` prefix in its description. Read-only skills expose `--json`; writing skills expose `--dry-run`. All skills expose `--help`. See `shared/skill-contract.md` for the full contract.

  | Skill | Badge | Description |
  |-------|-------|-------------|
  | `/forge` | [writes] | Build, fix, deploy, review, or modify code. Universal entry; hybrid grammar (`run`, `fix`, `sprint`, `review`, `verify`, `deploy`, `commit`, `migrate`, `bootstrap`, `docs`, `audit`); free-text falls through to the intent classifier. Auto-bootstraps a missing `forge.local.md` on first invocation. |
  | `/forge-ask` | [read-only] | Query forge state, codebase knowledge, run history, or analytics. Subcommands: bare `<question>`, `status`, `history`, `insights`, `profile`, `tour`. |
  | `/forge-admin` | [writes] | Manage forge state and configuration. Two-level dispatch: `recover`, `abort`, `config`, `handoff`, `automation`, `playbooks`, `compress`, `graph`, `refine`. |
  ```

- [ ] **Step 16 — Update `README.md` "Setup details" section (lines 237-252).** Replace the usage examples:

  ```markdown
  ## Setup details

  After [Quick start](#quick-start):

  ```bash
  # Customize your project config
  # Open .claude/forge.local.md and set commands, scaffolder patterns, quality gate

  # Usage examples
  /forge "Add plan comment feature"                    # full pipeline; brainstorms first
  /forge run --dry-run "Add user dashboard"            # dry-run (PREFLIGHT → VALIDATE only)
  /forge run --from=implement "Add versioning"         # resume from stage
  /forge run --playbook=add-rest-endpoint entity=Task  # use playbook template
  /forge fix "Users get 404 on group endpoint"         # bugfix workflow (skips BRAINSTORMING)
  /forge sprint                                        # multi-feature parallel execution
  /forge sprint --parallel "feat A" "feat B"           # explicit sprint with two features
  ```
  ```

- [ ] **Step 17 — Update `README.md` "Troubleshooting" table (lines 254-265).** Replace:

  ```markdown
  | Problem | Fix |
  |---------|-----|
  | "No active pipeline" | Run `/forge "<requirement>"` (auto-bootstraps if needed) |
  | Pipeline stuck | `/forge-admin recover diagnose` (read-only), then `/forge-admin recover repair` |
  | Lock file blocks run | `/forge-admin recover reset` or remove `.forge/.lock` |
  | Check engine errors | Install bash 4+ (`brew install bash`). Check `.forge/.hook-failures.log` |
  | Score oscillating | Check `oscillation_tolerance` in forge-config.md (default 5) |
  | Budget exhausted | Check `total_retries_max` (default 10, range 5-30) |
  | Evidence stale | Increase `shipping.evidence_max_age_minutes` (default 30) |
  | MCP not detected | `/forge-ask status`. Pipeline degrades gracefully |
  ```

- [ ] **Step 18 — Add `README.md` "Multi-VCS support" line near the Integrations section (after line 187).** Insert a new bullet just before the existing Integrations table or as a sub-section beneath it:

  ```markdown
  ### Multi-VCS support

  Forge detects the PR/MR platform once at PREFLIGHT (cached in `state.platform`) and dispatches feedback posts and PR opens through the matching adapter:

  | Platform | Auth | Adapter |
  |---|---|---|
  | GitHub | `gh` CLI auth or `GITHUB_TOKEN` env | GitHub MCP (with `gh api` fallback) |
  | GitLab | `glab` CLI auth or `GITLAB_TOKEN` env | `glab` CLI; Python `urllib.request` fallback when `glab` is absent |
  | Bitbucket | `BITBUCKET_USERNAME` + `BITBUCKET_APP_PASSWORD` env | Pure Python (`urllib.request` against REST API v2.0) |
  | Gitea / Forgejo | `GITEA_TOKEN` env | Pure Python (`urllib.request` against REST API v1) |

  All adapters are pure Python — no `curl` or shell-out — and work uniformly on Windows, macOS, and Linux. Detection is automatic (`platform.detection: auto`) via remote URL pattern matching plus repo-marker files (`.gitlab-ci.yml`, `bitbucket-pipelines.yml`) and an API-probe for self-hosted Gitea/Forgejo. Override with `platform.detection: github|gitlab|bitbucket|gitea` in `forge.local.md`.
  ```

- [ ] **Step 19 — Update `README.md` "Key features" list (lines 50-75).** Strike the `/forge-init` references and add three new bullets for the new behaviors:

  Replace the existing "Environment health check" line with:

  ```markdown
  - **Auto-bootstrap** -- First `/forge` invocation in a project missing `.claude/forge.local.md` detects the stack via `shared/bootstrap-detect.py`, prompts the user with detected defaults, and writes the config atomically. Autonomous mode skips the prompt. No explicit init step.
  ```

  Add three new bullets at the end of the list (preserving the "Caveman benchmark" line):

  ```markdown
  - **Always-on brainstorming** -- Every feature-mode `/forge` run starts with BRAINSTORMING (`fg-010-shaper` adopts the superpowers seven-step pattern: explore context, ask one question at a time, propose 2-3 approaches, sectioned approval gates, write spec, self-review, hand off). Opt out via `brainstorm.enabled: false`. Transcript mining queries past run history (F29 FTS5) for similar features.
  - **Hypothesis-driven debugging** -- `/forge fix` runs reproduction → up to 3 competing hypotheses → optional parallel sub-investigators (`fg-021-hypothesis-investigator`) → Bayesian pruning → fix-gate (posterior ≥ 0.75). Refuses to plan a fix without root-cause evidence.
  - **Multi-VCS first-class** -- GitHub, GitLab, Bitbucket, Gitea/Forgejo. Pure-Python adapters under `shared/platform_adapters/` work uniformly on Windows, macOS, and Linux. Automatic detection at PREFLIGHT.
  - **Structured PR finishing** -- `/forge` ships ready-to-merge work via `AskUserQuestion` dialog: open-pr / open-pr-draft / direct-push / stash / abandon. Cleanup checklist runs after the chosen strategy completes. Autonomous default: `open-pr-draft`.
  - **Cross-reviewer consistency voting** -- When ≥3 reviewers flag the same dedup key, confidence is promoted to HIGH (1.0× weight). Reduces false positives from any single reviewer's fresh-context limitations.
  ```

- [ ] **Step 20 — Update `README.md` skills/agents badges (lines 5-11).** Update the agent and skill counts to reflect ground truth:

  ```markdown
  [![Agents](https://img.shields.io/badge/agents-51-green?style=flat-square)](#agents)
  [![Skills](https://img.shields.io/badge/skills-3-green?style=flat-square)](#available-skills)
  ```

  (Pre-existing drift: README badge currently reads `agents-42`, but `agents/` actually contains 50 files at spec date (Phase 7 added `fg-302-diff-judge` and `fg-540-intent-verifier` to the original 48 in Phases 1-6). Phase D adds `fg-021-hypothesis-investigator`, bringing the post-Phase-D total to **51**. The badge is corrected to ground truth in this commit, not a +1 from the stale value. Skill count drops from 35 to 3 — the consolidation is the dominant change.)

  Also update the lead-paragraph prose at line 15 (`...orchestrating 42 specialized agents...`) to read `51 specialized agents`.

- [ ] **Step 21 — Update `README.md` "Agents" section (lines 158-164).** Bump the count to 51 and resync the enumeration with the actual `agents/` directory (the existing list omits 8 agents added between earlier doc passes — this is pre-existing drift):

  ```markdown
  ## Agents

  51 agents organized by pipeline stage. See `shared/agents.md#registry` for the full list.

  **Pipeline agents** (42): fg-010-shaper, fg-015-scope-decomposer, fg-020-bug-investigator, fg-021-hypothesis-investigator (Tier-4 sub-investigator for hypothesis branching, new in Phase D6), fg-050-project-bootstrapper, fg-090-sprint-orchestrator, fg-100-orchestrator, fg-101-worktree-manager, fg-102-conflict-resolver, fg-103-cross-repo-coordinator, fg-130-docs-discoverer, fg-135-wiki-generator, fg-140-deprecation-refresh, fg-143-observability-bootstrap, fg-150-test-bootstrapper, fg-155-i18n-validator, fg-160-migration-planner, fg-200-planner, fg-205-plan-judge, fg-210-validator, fg-250-contract-validator, fg-300-implementer, fg-301-implementer-judge, fg-302-diff-judge, fg-310-scaffolder, fg-320-frontend-polisher, fg-350-docs-generator, fg-400-quality-gate, fg-500-test-gate, fg-505-build-verifier, fg-506-migration-verifier, fg-510-mutation-analyzer, fg-515-property-test-generator, fg-540-intent-verifier, fg-555-resilience-tester, fg-590-pre-ship-verifier, fg-600-pr-builder, fg-610-infra-deploy-verifier, fg-620-deploy-verifier, fg-650-preview-validator, fg-700-retrospective, fg-710-post-run.

  **Review agents** (9): fg-410-code-reviewer, fg-411-security-reviewer, fg-412-architecture-reviewer, fg-413-frontend-reviewer, fg-414-license-reviewer, fg-416-performance-reviewer, fg-417-dependency-reviewer, fg-418-docs-consistency-reviewer, fg-419-infra-deploy-reviewer.
  ```

  Verify `(42 pipeline + 9 review = 51)` matches the `## Agents (51 total ...)` header in `CLAUDE.md` (Step 6) and the badge value in Step 20. Also update the line `## Architecture` "42 agents organized by pipeline stage" reference at README line 171 (`docs/architecture/agent-dispatch.md -- 42 agents organized by pipeline stage`) to read `51 agents`.

- [ ] **Step 22 — Run AC-S005 sanity grep across both files.**

  ```bash
  grep -nE '/forge-(init|run|fix|shape|sprint|review|verify|deploy|commit|migration|bootstrap|docs-generate|security-audit|status|history|insights|profile|tour|help|recover|abort|config|handoff|automation|playbooks|playbook-refine|compress|graph)([^a-z-]|$)' /Users/denissajnar/IdeaProjects/forge/CLAUDE.md /Users/denissajnar/IdeaProjects/forge/README.md
  ```

  Expected output: empty. The single `/forge-ask` skill is allowed (it's not retired).

  If the grep returns matches, fix each one against the §12.1 mapping table. Re-run until empty.

- [ ] **Step 23 — Run a structural sanity check.**

  ```bash
  ./tests/run-all.sh structural 2>&1 | tail -30
  ```

  Expected: all checks pass. The skill-references-allowlist test owned by B13 covers AC-S005 authoritatively; this is a confirmation that E1 didn't regress B13.

- [ ] **Step 24 — Commit.** Conventional commit, no AI attribution, no `--no-verify`. Suggested message:

  ```
  docs(consolidation): rewrite CLAUDE.md and README.md for three-skill surface

  - Replace skill selection guide with three-row table (/forge, /forge-ask, /forge-admin)
  - Update getting started flows for auto-bootstrap and consolidated skills
  - Insert BRAINSTORMING into pipeline state list
  - Add "Pattern parity" section listing 12 mirrored superpowers patterns
  - Document four beyond-superpowers extensions (consistency voting, transcript mining,
    hypothesis branching, structured PR-finishing dialog)
  - README: correct agent badge to 51 (was stale at 42; Phase 7 added fg-302 and fg-540 bringing pre-Phase-D total to 50, +1 from fg-021-hypothesis-investigator brings actual file count to 51), skills badge to 3
  - README: resync agent enumeration to include 9 added/omitted agents
    (fg-021 new in Phase D6; fg-302 and fg-540 added by Phase 7; fg-143,
    fg-155, fg-301, fg-414, fg-506, fg-555 were previously omitted from
    the README enumeration despite existing in agents/)
  - README: add Multi-VCS support section (GitHub/GitLab/Bitbucket/Gitea)
  - Strike all retired skill names (28); replace per spec §12.1 mapping table
  ```

### Implementer prompt template

```
You are updating top-level project docs to reflect a major surface rewrite. The reader of these docs is either Claude Code (loading CLAUDE.md as context) or a developer reading README.md to onboard. Both must come away with an accurate picture. Match the spec exactly — no embellishment, no omission. Use the §12.1 mapping table verbatim where skill-name substitutions are needed.

Constraints:
- Do not alter sections that are not listed in the steps above. Untouched sections stay byte-for-byte unchanged.
- The §12.1 mapping table is the single source of truth for old → new skill name substitutions.
- Run the AC-S005 grep before committing. If any match returns, fix and re-run.
- Do not introduce new finding categories, new feature flags, or new agent files in this commit — those are owned by phases A through D.
- Commit message follows Conventional Commits. No `Co-Authored-By`, no AI attribution, no `--no-verify`.
- All file paths in commands are absolute; never use relative paths.
```

### Spec reviewer prompt template

```
You are checking that the doc updates accurately reflect the new surface. Verify by reading the actual files (not the implementer's report):

1. Open /Users/denissajnar/IdeaProjects/forge/CLAUDE.md and confirm:
   - The "Skill selection guide" section has exactly three rows: /forge, /forge-ask, /forge-admin.
   - "Getting started flows" uses the new skill names exclusively.
   - "Skills (N total)" header reads "Skills (3 total)".
   - "## Agents (N total ...)" header reads "## Agents (51 total, agents/*.md)" — reflects fg-021 added by Phase D6 on top of the Phase-7 additions (fg-302, fg-540).
   - The "Start Here (5-minute path)", "What this is", "Quick start" bash, "Development workflow", and "Confidence scoring" sections all reference only the new three-skill surface.
   - The pipeline state list contains BRAINSTORMING immediately after PREFLIGHT.
   - A "Pattern parity" section is present with all 12 mapped superpowers skills (per spec §10.1) and a "Beyond-superpowers extensions" sub-list with 4 items (consistency voting, transcript mining, hypothesis branching, structured PR-finishing dialog).
   - No reference to any of the 28 retired skills survives anywhere in the file (single allowed: /forge-ask, which is not retired). Run:
     grep -nE '/forge-(init|run|fix|shape|sprint|review|verify|deploy|commit|migration|bootstrap|docs-generate|security-audit|status|history|insights|profile|tour|help|recover|abort|config|handoff|automation|playbooks|playbook-refine|compress|graph)([^a-z-]|$)' CLAUDE.md
     Expected: empty.

2. Open /Users/denissajnar/IdeaProjects/forge/README.md and confirm:
   - Quick Start uses /forge (not /forge-init then /forge-run).
   - Skill badge reads `skills-3` and agent badge reads `agents-51` (NOT `agents-43` — README badge was already stale at 42 pre-Phase-E; the corrected value is the actual file count post-Phase-D, which includes the Phase-7 fg-302 and fg-540 additions and Phase-D's fg-021).
   - Lead-paragraph at line ~15 reads "51 specialized agents" (not 42 or 43).
   - "Available skills" section is the three-row table.
   - "Multi-VCS support" section is present and lists GitHub, GitLab, Bitbucket, Gitea.
   - "Agents" section count reads 51 and explicitly lists fg-021-hypothesis-investigator alongside the 8 other agents that were missing from the prior README enumeration (fg-143-observability-bootstrap, fg-155-i18n-validator, fg-301-implementer-judge, fg-302-diff-judge, fg-414-license-reviewer, fg-506-migration-verifier, fg-540-intent-verifier, fg-555-resilience-tester).
   - The "## Architecture" sub-line referencing the agent-dispatch diagram reads "51 agents organized by pipeline stage" (not 42).
   - Same retired-skill grep as above returns empty.

3. The new sections quote the spec verbatim where the spec uses verbatim language (descriptions in §1; pattern-parity table in §10.1). The implementer is not permitted to paraphrase those.

If any check fails, return REVISE with the specific failed step. If all pass, return APPROVE.
```

---

## Task E2: Regenerate the FEATURE_MATRIX block in `CLAUDE.md`

**Risk:** low

**Files modified:**
- `CLAUDE.md` (FEATURE_MATRIX_START → FEATURE_MATRIX_END block only)

**ACs covered:** none directly. The FEATURE_MATRIX sentinel contract is owned by Phase 2's spec; this task obeys it.

### Pre-condition

Phase 2's `<!-- FEATURE_MATRIX_START -->` and `<!-- FEATURE_MATRIX_END -->` sentinel contract must already be in place. As of the spec date (2026-04-27), the sentinels are not yet present in `CLAUDE.md` (verified by grep). The two acceptable interpretations are:

1. **Phase 2 ships before Phase E.** The sentinels exist; E2 regenerates the block between them.
2. **Phase 2 has not yet shipped.** E2 introduces the sentinel pair around the existing feature table (currently at lines 208-254) and writes the new content. This satisfies the Phase 2 sentinel contract (`exact literal byte strings on their own line with trailing newline; appear exactly once each`).

Option 2 is the conservative path — E2 does not assume Phase 2's commit ordering. The plan below uses Option 2; if Phase 2 has already landed by the time E2 runs, skip Step 1 (sentinel insertion) and jump straight to Step 2 (block regeneration).

### TDD steps

- [ ] **Step 1 — Read the current state of the feature table.** Open `CLAUDE.md` at the "Features (each has dedicated doc in `shared/`):" line (currently ~line 206). Capture the current table boundaries: the table starts at the `| Feature | Config | Key details |` header and ends just before the "### Deterministic Control Flow" heading.

- [ ] **Step 2 — Insert sentinel comments around the table** (only if not already present from Phase 2). The sentinel placement:

  - Place `<!-- FEATURE_MATRIX_START -->` on its own line immediately before the table header line.
  - Place `<!-- FEATURE_MATRIX_END -->` on its own line immediately after the last table row.
  - Each sentinel ends with a single `\n` (trailing newline).
  - No surrounding whitespace variations.
  - Sentinels appear exactly once each.

  Verify with:

  ```bash
  grep -nE '^<!-- FEATURE_MATRIX_(START|END) -->$' /Users/denissajnar/IdeaProjects/forge/CLAUDE.md
  ```

  Expected: exactly two matches.

- [ ] **Step 3 — Regenerate the table content between the sentinels.** Replace everything strictly between (not including) the two sentinel lines with the full feature matrix. Preserve every existing row (F05, F07, F09, F10, F11, F12, F13, F14, F15, F16, F17, F18, F19, F20, F21, F22, F23, F24, F25, F26, F27, F28, F29, F30, F31, F32, F33, F34, plus the unnumbered rows for Wiki generator, Memory discovery, Background execution, Automations, Visual verification, LSP integration, Observability, Data classification, Security posture, A2A protocol, Pipeline timeline, Codebase Q&A, Caveman I/O, Repo-map PageRank, Speculative plan branches, Docs integrity, and Active knowledge base — see current file lines 210-254 for the authoritative list).

  **Patch existing rows** for the `/forge-init` reference and renamed skills:

  - Row F30 (`MCP server`): change `Auto-provisioned by /forge-init into .mcp.json` to `Auto-provisioned by auto-bootstrap (or /forge-admin config wizard) into .mcp.json`.
  - Row F31 (`Self-improving playbooks`): change `Skill: /forge-playbook-refine` to `Skill: /forge-admin refine`.
  - Row F34 (`Session handoff`): change `Skill: /forge-handoff` to `Skill: /forge-admin handoff`.
  - Row "Active knowledge base (F09)": no change (no skill reference).
  - Row "Pipeline timeline": change `Per-stage timing via /forge-insights` to `Per-stage timing via /forge-ask insights`.

  **Append eight new rows** at the bottom of the table (in F-number order), reflecting the new features added by phases A-D of this spec:

  | Feature | Config | Key details |
  |---|---|---|
  | BRAINSTORMING (F35) | `brainstorm.*` | Always-on for feature mode; `enabled: false` to disable. Seven-step pattern in `fg-010-shaper`. Spec dir `docs/superpowers/specs/` (configurable via `brainstorm.spec_dir`). State enum `BRAINSTORMING` in `state-schema.md`. |
  | Transcript mining (F36) | `brainstorm.transcript_mining.*` | F29 FTS5-backed historical context for `fg-010-shaper`. `top_k` default 3 (range 1-10); `max_chars` default 4000. Writes `.forge/brainstorm-transcripts/<run_id>.jsonl`. |
  | Cross-reviewer consistency voting (F37) | `quality_gate.consistency_promotion.*` | ≥`threshold` reviewer agreement (default 3, range 2-9) on a dedup key promotes confidence to HIGH (1.0× weight). Logged as `consistency_promoted: true` on the finding. |
  | Defense-check feedback handling (F38) | `post_run.defense_*` | `fg-710-post-run` per-comment verdict: `actionable` / `wrong` / `preference`. Defense responses posted to PR thread via platform adapter. State: `state.feedback_decisions[]`; mirror at `.forge/runs/<run_id>/feedback-decisions.jsonl`. Only `actionable` increments `feedback_loop_count`. |
  | Hypothesis branching for bugs (F39) | `bug.hypothesis_branching.*` | Up to 3 parallel sub-investigators via `fg-021-hypothesis-investigator`. Bayesian pruning per spec §7. Fix-gate threshold `bug.fix_gate_threshold` (default 0.75, range 0.50-0.95). State: `state.bug.hypotheses[]`. |
  | Multi-VCS platform abstraction (F40) | `platform.*` | GitHub / GitLab / Bitbucket / Gitea/Forgejo. Detection at PREFLIGHT via `shared/platform-detect.py`; cached in `state.platform`. Adapters under `shared/platform_adapters/`. Pure Python (`urllib.request`); cross-platform Windows/macOS/Linux. |
  | Structured PR finishing (F41) | `pr_builder.*` | `fg-600-pr-builder` `AskUserQuestion` dialog with five options: `open-pr` / `open-pr-draft` / `direct-push` / `stash` / `abandon`. Cleanup checklist runs after the chosen strategy. Autonomous default: `open-pr-draft`. |
  | Stale-worktree detection (F42) | `worktree.stale_after_days` | `fg-101-worktree-manager` flags worktrees older than the threshold (default 30, range 1-365). Finding category `WORKTREE-STALE` (WARNING). |

  **Authoring rules** (per Phase 2 spec §AC-8):
  - ASCII-only between sentinels. No em dashes, en dashes, or smart quotes (U+2018, U+2019, U+201C, U+201D). Use `-` for hyphens, `--` for em-dash equivalents.
  - Pipe-aligned formatting; trailing newline after `<!-- FEATURE_MATRIX_END -->`.
  - Stable formatting — sort rows by F-number ascending where F-number exists; unnumbered rows go last in their original relative order.
  - Each row's `Default` and `Usage` columns: not in this spec (Phase 2 introduces those columns separately at `shared/feature-matrix.md`; the CLAUDE.md table here uses the existing 3-column shape `Feature | Config | Key details`).

- [ ] **Step 4 — Verify sentinel sanctity.** Run:

  ```bash
  grep -cE '^<!-- FEATURE_MATRIX_START -->$' /Users/denissajnar/IdeaProjects/forge/CLAUDE.md
  grep -cE '^<!-- FEATURE_MATRIX_END -->$' /Users/denissajnar/IdeaProjects/forge/CLAUDE.md
  ```

  Expected: each command outputs `1`. The sentinels appear exactly once each.

- [ ] **Step 5 — Run AC-S005 sanity grep again.**

  ```bash
  grep -nE '/forge-(init|run|fix|shape|sprint|review|verify|deploy|commit|migration|bootstrap|docs-generate|security-audit|status|history|insights|profile|tour|help|recover|abort|config|handoff|automation|playbooks|playbook-refine|compress|graph)([^a-z-]|$)' /Users/denissajnar/IdeaProjects/forge/CLAUDE.md
  ```

  Expected: empty. (The intra-row `/forge-init` patches in Step 3 are why this must run after E2, not just E1.)

- [ ] **Step 6 — Run structural tests.**

  ```bash
  ./tests/run-all.sh structural 2>&1 | tail -30
  ```

  Expected: all checks pass. If Phase 2 has shipped before this commit, the freshness check `tests/contract/test_feature_matrix_freshness.py` will run and must pass.

- [ ] **Step 7 — Commit.**

  ```
  docs(consolidation): regenerate FEATURE_MATRIX block with eight new feature rows

  - Patch /forge-init / /forge-handoff / /forge-playbook-refine / /forge-insights references
    in F30, F31, F34, and Pipeline timeline rows
  - Append F35 (BRAINSTORMING), F36 (transcript mining), F37 (cross-reviewer consistency
    voting), F38 (defense-check feedback handling), F39 (hypothesis branching),
    F40 (multi-VCS platform abstraction), F41 (structured PR finishing),
    F42 (stale-worktree detection)
  - Sentinel-bounded for Phase 2 generator compatibility
  ```

### Implementer prompt template

```
You are regenerating a sentinel-bounded machine block. The reader of this block is either Phase 2's freshness check (a Python script that compares the block to a generated version) or a developer reading CLAUDE.md to find the right config key.

Constraints (from Phase 2 spec §AC-8):
- ASCII-only between sentinels. No em dashes, en dashes, or smart quotes.
- Pipe-aligned formatting.
- Stable: sort by F-number ascending where present.
- Sentinels appear exactly once each on their own line with a trailing newline.
- Append the eight new rows in F-number order (F35 through F42).
- Patch existing rows F30, F31, F34, and Pipeline timeline per the §12.1 mapping table.
- Do not change row count of pre-existing rows except for the four patched ones.

Run the AC-S005 grep and the sentinel-count grep before committing. If either fails, fix and re-run.
```

### Spec reviewer prompt template

```
You are checking that the FEATURE_MATRIX block accurately reflects the new feature flags. Verify by reading CLAUDE.md (not the implementer's report):

1. Run:
   grep -cE '^<!-- FEATURE_MATRIX_START -->$' /Users/denissajnar/IdeaProjects/forge/CLAUDE.md
   grep -cE '^<!-- FEATURE_MATRIX_END -->$' /Users/denissajnar/IdeaProjects/forge/CLAUDE.md
   Expected: each outputs 1.

2. Open the file at the FEATURE_MATRIX_START sentinel and confirm:
   - The eight new rows are present with the correct config keys per spec §11.1:
     F35 brainstorm.*; F36 brainstorm.transcript_mining.*;
     F37 quality_gate.consistency_promotion.*;
     F38 post_run.defense_*; F39 bug.hypothesis_branching.*;
     F40 platform.*; F41 pr_builder.*; F42 worktree.stale_after_days.
   - Rows F30, F31, F34, and "Pipeline timeline" reference the new skill names per §12.1.
   - Between sentinels, the content is ASCII-only — no em dashes (U+2014), en dashes (U+2013),
     or smart quotes (U+2018, U+2019, U+201C, U+201D).

3. Run:
   grep -nE '/forge-(init|run|fix|shape|sprint|review|verify|deploy|commit|migration|bootstrap|docs-generate|security-audit|status|history|insights|profile|tour|help|recover|abort|config|handoff|automation|playbooks|playbook-refine|compress|graph)([^a-z-]|$)' CLAUDE.md
   Expected: empty.

If any check fails, return REVISE with the specific failed step. If all pass, return APPROVE.
```

---

## Self-review checklist

- [ ] **E1 covers all sections that mention the old skill surface, BRAINSTORMING, or uplifts?**
  - Start Here / 5-minute path (Step 1a) — yes
  - What this is (Step 1b) — yes
  - Quick start bash code (Step 1c) — yes
  - Development workflow (Step 1d) — yes
  - Confidence scoring `/forge-shape` reference (Step 1e) — yes
  - Skill selection guide (Step 2) — yes
  - Getting started flows (Step 3) — yes
  - Skills (N total) section header + paragraph (Step 4) — yes
  - Stage contracts & shipping line (Step 5) — yes
  - "## Agents (51 total ...)" header bump + Pre-pipeline agent line (Step 6) — yes
  - New "Pattern parity" section (Step 7) — yes
  - Routing & decomposition (Step 8) — yes
  - Pipeline modes (Step 9) — yes
  - Implementation gotchas (Step 10) — yes
  - Structural gotchas + full §12.1 sweep (Step 11) — yes
  - Cross-repo line (Step 12) — yes
  - F30 row patch (Step 13) — yes (anticipates E2)
  - README.md Quick Start (Step 14) — yes
  - README.md Available skills (Step 15) — yes
  - README.md Setup details (Step 16) — yes
  - README.md Troubleshooting (Step 17) — yes
  - README.md Multi-VCS section (Step 18) — yes
  - README.md Key features (Step 19) — yes
  - README.md badges + lead-paragraph agent count (Step 20) — yes
  - README.md Agents section (resync to 51) + Architecture line (Step 21) — yes
  - AC-S005 grep verification (Step 22) — yes

- [ ] **E2 feature matrix has 8 new entries with correct config keys?**
  - F35 BRAINSTORMING / `brainstorm.*` — yes
  - F36 Transcript mining / `brainstorm.transcript_mining.*` — yes
  - F37 Cross-reviewer consistency voting / `quality_gate.consistency_promotion.*` — yes
  - F38 Defense-check feedback handling / `post_run.defense_*` — yes
  - F39 Hypothesis branching for bugs / `bug.hypothesis_branching.*` — yes
  - F40 Multi-VCS platform abstraction / `platform.*` — yes
  - F41 Structured PR finishing / `pr_builder.*` — yes
  - F42 Stale-worktree detection / `worktree.stale_after_days` — yes

- [ ] **Both tasks have AC-S005 grep verification?**
  - E1 Step 22 — yes
  - E2 Step 5 — yes

- [ ] **Both tasks ASCII-only in machine blocks?** E2 explicitly enforces ASCII-only between sentinels (Phase 2 §AC-8). E1 prose is unconstrained but should not introduce smart quotes either; the implementer is expected to copy verbatim from this plan, which uses ASCII throughout.

- [ ] **No code changes, no test additions?** Confirmed — Phase E is documentation-only by spec.

- [ ] **Commit ordering?** E1 must commit before E2 because E2's sentinel insertion (Step 2) depends on the table existing in its current shape, which E1 leaves intact. Both commits ship in the same train; E1 lands first.
