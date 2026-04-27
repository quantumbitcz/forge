# Skill Consolidation: 29 → 3 — Design

**Status:** Draft (brainstorming output)
**Date:** 2026-04-27
**Author:** Denis Šajnar (with Claude)
**Successor of:** Phase 2 (which already removed `/forge-help` — superseded here by full surface rewrite)
**Predecessor of:** Phase 9 (Superpowers Pattern Parity — separate spec)

## Summary

Replace the current 29-skill surface with three skills (`/forge`, `/forge-ask`, `/forge-admin`). Eliminate `/forge-init` by absorbing bootstrap into `/forge` itself, triggered by the absence of `.claude/forge.local.md`. Make every feature-mode invocation of `/forge` start with a brainstorming phase backed by a rewritten `fg-010-shaper` that adopts the superpowers brainstorming pattern. Hybrid grammar inside `/forge` (explicit verbs win, plain text falls through to the existing intent classifier). No backwards compatibility — atomic deletion of 26 skill directories, atomic creation of three.

## Goals

1. Reduce skill-surface complexity from 29 directories to 3 (~90 % reduction).
2. Eliminate the explicit init step: `/forge "<request>"` on a fresh project must work.
3. Always brainstorm features before planning — no threshold, no opt-in.
4. Preserve all existing capability. No agent is deleted; only the skill-level wrappers around them.
5. Preserve all current parallelization (sprint, task, reviewer levels).
6. Match the brainstorming behavior to the superpowers pattern (one question at a time, propose 2-3 approaches, sectioned design with approval gates) without taking a runtime dependency on the superpowers plugin.

## Non-goals

- **Other superpowers patterns** (writing-plans, requesting-code-review, receiving-code-review, etc.) are out of scope. They land in Phase 9 (separate spec).
- **Adding new agent capabilities.** This spec only changes routing/dispatch, plus the brainstorm-stage rewrite of `fg-010-shaper`.
- **Optional aliases for old skill names.** Per personal-tool stance, deletion is atomic.

## Architecture

### §1 — Three skills

#### `/forge` — write surface

```yaml
name: forge
description: "[writes] Build, fix, deploy, review, or modify code in this project. Universal entry for the forge pipeline. Auto-bootstraps on first run; brainstorms before planning when given a feature description. Use for any productive action: implementing features, fixing bugs, reviewing branches, deploying, committing, running migrations."
allowed-tools: ['Read', 'Write', 'Edit', 'Bash', 'Glob', 'Grep', 'Agent', 'AskUserQuestion']
ui: { tasks: true, ask: true, plan_mode: true }
```

**Hybrid grammar:**

| Form | Behavior |
|---|---|
| `/forge run "<feature description>"` | Explicit feature pipeline (BRAINSTORM → ... → SHIP). |
| `/forge fix "<bug description or ticket ID>"` | Bugfix pipeline. Skips BRAINSTORM. |
| `/forge sprint [--parallel] "<feat>"...` or `/forge sprint <linear-cycle-id>` | Sprint orchestration. |
| `/forge review [--full] [--scope=changed\|all] [--fix]` | Review pipeline. |
| `/forge verify [--build\|--config\|--all]` | Build/lint/test or config validation. |
| `/forge deploy <env>` | Deployment. |
| `/forge commit` | Generate conventional commit from staged changes. |
| `/forge migrate "<from> to <to>"` | Migration pipeline. |
| `/forge bootstrap [<stack>]` | Greenfield project scaffold. |
| `/forge docs [<scope>]` | Docs generation. |
| `/forge audit` | Security audit. |
| `/forge "<free-text>"` | Falls through to `shared/intent-classification.md`. Default → `run` mode. |

**Flags (apply to relevant subcommands):**
- `--dry-run` — preview only; PREFLIGHT → VALIDATE; no worktree, no commits.
- `--autonomous` — no `AskUserQuestion` calls; auto-decisions logged with `[AUTO]` prefix; honors `autonomous: true` in `forge.local.md`.
- `--from=<stage>` — resume from a specific pipeline stage.
- `--spec <path>` — start from an existing spec; for `run`, skips BRAINSTORM if spec is well-formed.
- `--parallel` — only valid for `sprint` (deprecated alias for explicit `sprint`).
- `--background` — enqueue for background execution; output to `.forge/alerts.json`.

**Subcommand fallback rules:**
- Bare `/forge` (no args) prints usage and exits 0.
- `/forge --help` prints subcommand list and flag matrix.
- `/forge <unknown-verb> <args>` falls through to NL classifier with the full string. (Avoids the "did you mean" UX wart.)
- `/forge "fix the login bug"` (no explicit verb) classifies as bugfix via existing intent classifier.

**Argument and flag positioning:**
- Multi-word arguments may be quoted or unquoted. Quoting is recommended: `/forge run "add CSV export"` is unambiguous; `/forge run add CSV export` works but blurs into the NL fallback path.
- Flags must appear before the free-text argument: `/forge run --dry-run "add CSV export"`. Flags after the argument are an error — fail fast with usage.
- For `sprint` with a Linear cycle ID, the format is `/forge sprint <id>` where `<id>` matches the Linear API identifier shape. Exact regex deferred to plan-stage (depends on Linear MCP configuration); for this spec, the dispatcher accepts any non-empty string and lets the downstream Linear MCP call validate.

#### `/forge-ask` — read-only surface

```yaml
name: forge-ask
description: "[read-only] Query forge state, codebase knowledge, run history, or analytics. Never mutates project state. Use to check pipeline status, search wiki/graph for code answers, view past runs, see analytics, or get an onboarding tour."
allowed-tools: ['Read', 'Bash', 'Glob', 'Grep', 'Agent']
ui: { tasks: false, ask: false, plan_mode: false }
```

**Subcommand grammar (no NL fallback):**

| Form | Behavior |
|---|---|
| `/forge-ask "<question>"` | Default action. Codebase Q&A via wiki + graph + explore cache + docs index. |
| `/forge-ask status` | Current pipeline state. |
| `/forge-ask history [--limit=N] [--filter=<expr>]` | Past runs from `.forge/run-history.db`. |
| `/forge-ask insights [--scope=<run\|cycle\|all>]` | Quality, cost, convergence trends. |
| `/forge-ask profile [<run-id>]` | Per-stage timing and cost breakdown. |
| `/forge-ask tour` | 5-stop guided introduction. |

**Removed from this skill (deleted, not absorbed):** `/forge-help` was already deleted in Phase 2. `/forge-tour` becomes `/forge-ask tour` (single-line subcommand, not a top-level skill).

#### `/forge-admin` — state management surface

```yaml
name: forge-admin
description: "[writes] Manage forge state and configuration: recovery, abort, config edits, session handoff, automations, playbooks, output compression, knowledge graph maintenance. Use to recover from broken pipeline state, edit settings, manage long-lived state."
allowed-tools: ['Read', 'Write', 'Edit', 'Bash', 'Glob', 'Grep', 'Agent', 'AskUserQuestion']
ui: { tasks: true, ask: true, plan_mode: false }
```

**Subcommand grammar (two-level dispatch where existing skills had sub-subcommands):**

| Form | Behavior |
|---|---|
| `/forge-admin recover diagnose\|repair\|reset\|resume\|rollback` | State diagnostics and repair. |
| `/forge-admin abort` | Graceful stop of active run. |
| `/forge-admin config [wizard\|<key=val>]` | Interactive config editor. `wizard` runs the multi-question flow lifted from `/forge-init`. |
| `/forge-admin handoff [list\|show\|resume\|search\|<text>]` | Session handoff (default action with text arg = write). |
| `/forge-admin automation [list\|add\|remove\|test]` | Event-driven trigger management. |
| `/forge-admin playbooks [list\|run <id>\|create\|analyze]` | Playbook management. |
| `/forge-admin compress [agents\|output\|status\|help]` | Token-cost compression controls. |
| `/forge-admin graph init\|status\|query <cypher>\|rebuild\|debug` | Knowledge-graph operations. |
| `/forge-admin refine [<playbook-id>]` | Apply playbook refinement proposals. |

### §2 — Auto-bootstrap

**Trigger condition:** `/forge` invoked with `.claude/forge.local.md` absent.

The runtime directory `.forge/` is **not** a trigger. Clearing `.forge/` (e.g. via `/forge-admin recover reset`) must not re-trigger bootstrap. Config file is the contract; runtime state is the cache.

**Detection logic:** Reuse the existing detection in `fg-050-project-bootstrapper` and `shared/check-environment.sh`. Lift the detection branch of `skills/forge-init/SKILL.md` into a callable helper `shared/bootstrap-detect.py` so both auto-bootstrap and `/forge bootstrap` invoke the same code path. No new detection code is written; the existing logic is moved.

**Interaction shape — one consolidated AskUserQuestion:**

```
I detected: <stack-summary>.
  language: Kotlin 2.0.21
  framework: Spring Boot 3.4
  testing: JUnit 5
  build: Gradle 8.10

Bootstrap with these defaults?

  [proceed]      — write forge.local.md and continue with your request
  [open wizard]  — full multi-question setup
  [cancel]       — stop, do nothing
```

Default option: `[proceed]`. After bootstrap, the user's original request continues without re-prompting.

**Autonomous mode behavior:**
- With `autonomous: true` in any config or `--autonomous` flag, **skip the prompt entirely**.
- Detect, write `forge.local.md`, log `[AUTO] bootstrapped with detected defaults: <stack>` to `forge-log.md`.
- Proceed to the user's request.

**Failure modes:**
- **Detection ambiguous** (no recognizable build tool, mixed stacks at root, multiple package managers without a clear primary): abort with "couldn't auto-bootstrap; run `/forge-admin config wizard`". No silent half-init.
- **Write fails** (permissions, disk full): abort the run; do not proceed with the user's original request. Print error and exit non-zero.
- **`forge.local.md` is present but malformed:** treat as configured but broken. Do **not** auto-bootstrap (config exists). Surface a hard error pointing to `/forge-admin config` or `/forge verify --config`. (`forge verify --config` is the existing pre-flight validation skill; bootstrap is for "no config", not "broken config".)

**Effect on `/forge bootstrap`:** Stays as an explicit subcommand for greenfield project creation (currently `/forge-bootstrap`). Auto-bootstrap is the *implicit* path for already-coded projects; `/forge bootstrap <stack>` is the *explicit* path for empty directories. They share `shared/bootstrap-detect.py` but call different downstream agents (`fg-050-project-bootstrapper` for explicit greenfield; only the detect-and-write portion for auto-bootstrap).

### §3 — Brainstorm-first feature flow

#### New pseudo-stage: BRAINSTORM

The pipeline state machine gains one stage that precedes EXPLORE:

```
old:  PREFLIGHT → EXPLORING → PLANNING → VALIDATING → IMPLEMENTING → ...
new:  PREFLIGHT → BRAINSTORMING → EXPLORING → PLANNING → VALIDATING → IMPLEMENTING → ...
```

**Modes that skip BRAINSTORMING:**

| Trigger | Reason |
|---|---|
| `/forge fix ...` or `bugfix:` prefix | `fg-020-bug-investigator` is the bug-mode equivalent of brainstorming. |
| `/forge migrate ...` or `migrate:` prefix | `fg-160-migration-planner` plays this role for migrations. |
| `/forge bootstrap ...` or `bootstrap:` prefix | `fg-050-project-bootstrapper` plays the role for greenfield. |
| `--from=<stage>` resuming past BRAINSTORMING | Idempotent resume. |
| `--spec <path>` with a well-formed spec | Spec is treated as already-brainstormed. Spec well-formedness check: presence of all of (objective, scope, acceptance criteria); absence triggers an explicit "spec is incomplete; run BRAINSTORM" prompt unless `--autonomous`. |

#### `fg-010-shaper` rewrite

The agent's prompt is rewritten to adopt the superpowers brainstorming pattern, owned in-tree (no superpowers runtime dependency). Concretely, the agent:

1. **Explores project context** — reads `CLAUDE.md`, the most recent N commits (default N=20), graph for related modules. Caches results in `.forge/brainstorm-cache.json` to avoid re-exploration on resume.
2. **Asks clarifying questions one at a time** — multiple-choice when possible (uses `AskUserQuestion`). Stops asking when it can articulate purpose, constraints, success criteria.
3. **Proposes 2-3 approaches with tradeoffs** — explicit recommendation among them, reasoning included.
4. **Presents design in sections with approval gates** — architecture, components, data flow, error handling, testing. Each section gets its own `AskUserQuestion` ("looks right?").
5. **Writes spec** to `docs/superpowers/specs/YYYY-MM-DD-<slug>-design.md` (path configurable via `forge-config.md`'s `brainstorm.spec_dir`). Commits the spec.
6. **Self-review pass** — placeholder scan, internal consistency, scope check, ambiguity check. Fixes inline.
7. **Hands off to user** — `AskUserQuestion`: "Spec written. Approve to proceed to planning?"
8. **Transitions to `fg-200-planner`** with the spec path in `state.brainstorm.spec_path`.

The threshold logic (`<50 words missing 3+ of actors/entities/surface/criteria`) is **removed**. Always-on for feature mode is the new default.

#### Autonomous-mode degradation

When `autonomous: true` or `--autonomous`, `fg-010-shaper` runs a degraded one-shot:
- No `AskUserQuestion`. No `EnterPlanMode`.
- Reads input verbatim as the spec content.
- Auto-extracts ACs using a new helper `shared/ac-extractor.py` with explicit input/output contract:
  - **Input:** raw text string.
  - **Output:** `{objective: str, acceptance_criteria: list[str], confidence: "high"|"medium"|"low"}`.
  - **Implementation:** regex pass that matches (a) lines starting with `Given/When/Then`, (b) numbered list items (`^\s*\d+[.)]`), (c) bullets prefixed with imperative verbs from a known list (must, should, will, ensure, validate, return, expose, accept, reject). Returns `confidence: low` when fewer than two distinct AC matches are found, `medium` for 2-4, `high` for 5+.
  - This is **not** the intent classifier. It's a separate, single-purpose extractor; the intent classifier remains responsible for run/fix/sprint/etc. routing only.
- Writes a minimal spec to the same path: header + objective + extracted ACs + a frontmatter line `autonomous: true` + a body note `**Note:** spec auto-generated from raw input under `--autonomous` mode; extractor confidence: <level>`.
- Commits the spec.
- Logs `[AUTO] brainstorm skipped — input treated as spec (extractor confidence: <level>)`.
- Proceeds to EXPLORING. (Downstream stages, especially `fg-210-validator`, see the confidence level and may flag low-confidence specs as REVISE — but that's their existing responsibility, not this spec's.)

This preserves the BRAINSTORMING stage in the state machine for telemetry consistency while honoring the autonomous never-blocks invariant.

#### Resume semantics

If the pipeline is interrupted during BRAINSTORMING:
- **Interactive resume** with a spec already written (`state.brainstorm.spec_path` exists and the file exists) → `fg-010-shaper` reads the spec and asks "Resume from spec? Or restart brainstorming?".
- **Interactive resume** with no spec yet → restart BRAINSTORMING from scratch (questions cache in `.forge/brainstorm-cache.json` is honored; previously-asked questions are not re-asked).
- **Autonomous resume** (any case) → if a spec exists, proceed to EXPLORING with that spec; if no spec, regenerate the autonomous one-shot spec from the original input (re-read from `state.brainstorm.original_input`) and proceed. No prompts.

### §4 — State schema impact

**State schema version:** Bump in lockstep with Phase 5's coordinated v2.0.0 bump. If this spec ships before Phase 5, take an interim v1.11.0; otherwise roll into v2.0.0.

**New fields:**

```jsonc
{
  "stage": "BRAINSTORMING",  // new enum value
  "brainstorm": {
    "spec_path": "docs/superpowers/specs/2026-04-27-add-export-csv-design.md",
    "original_input": "add CSV export to the user list",
    "started_at": "2026-04-27T14:23:11Z",
    "completed_at": "2026-04-27T14:31:42Z",
    "autonomous": false,
    "questions_asked": 4,
    "approaches_proposed": 3,
    "section_approvals": ["architecture", "components", "data_flow", "error_handling", "testing"]
  }
}
```

**Recovery treatment:** BRAINSTORMING is in the `resumable_stages` set. State-transition rules added to `shared/state-transitions.md`:
- `PREFLIGHT → BRAINSTORMING` when `mode == feature` and brainstorm is enabled.
- `BRAINSTORMING → EXPLORING` on completion.
- `BRAINSTORMING → ABORTED` on user abort.
- `BRAINSTORMING → BRAINSTORMING` (self-loop) on resume from cache.

#### §4.1 — Config schema additions

The following keys are added to `forge-config.md` (plugin defaults) and validated by `shared/preflight-constraints.md`:

```yaml
brainstorm:
  enabled: true                  # default true; set false to short-circuit BRAINSTORMING (feature mode → EXPLORING)
  spec_dir: docs/superpowers/specs/   # default; where fg-010-shaper writes specs
  autonomous_extractor_min_confidence: low   # one of: low, medium, high; below this, autonomous mode aborts instead of proceeding to EXPLORING
```

Validation rules:
- `brainstorm.enabled` must be boolean.
- `brainstorm.spec_dir` must be a string. The parent directory must exist or be creatable (write probe at PREFLIGHT).
- `brainstorm.autonomous_extractor_min_confidence` must be one of the three enum values.

These keys are NOT subject to retrospective auto-tuning (they're behavior toggles, not numeric thresholds). Add them to the `<!-- locked -->` section in the generated `forge-config.md`.

### §5 — Migration mechanics (the breaking change)

The bulk of the implementation work. The change is mechanically large because the consolidation rewrites every reference to `/forge-*` skills across the codebase.

**Pre-flight (zero commits):** Run `grep -rln '/forge-' --include='*.md' --include='*.json' --include='*.py' --include='*.yml' --include='*.yaml' --include='*.bats' --include='*.sh' .` and snapshot the file list to `.forge/migration-callsites.txt`. This list is the literal input for commit 4's sed pass — eliminates "we forgot to grep $X" failure modes.

**Ground truth from `ls skills/` (verified 2026-04-27):** 29 skill directories exist. After this spec lands: 1 stays (`forge-ask`, edited in place), 28 are deleted, 2 are newly created (`forge`, `forge-admin`). Net delta: 28 deleted, 2 created, 1 edited. `forge-help` is **still present** today — Phase 2's deletion claim of `/forge-help` was never executed; this spec executes it as part of the 28.

**Commit ordering (atomic, no half-states):**

1. **Commit 1 — extract bootstrap-detect helper:** Lift the stack-detection logic out of `skills/forge-init/SKILL.md` into `shared/bootstrap-detect.py` while `forge-init/` is still on disk. Module exposes `detect_stack() -> dict` and `write_forge_local_md(stack: dict, path: Path) -> None`. Add unit tests at `tests/unit/bootstrap_detect_test.py` exercising at least: Kotlin/Spring, TypeScript/Next, Python/FastAPI, ambiguous-stack rejection, write-failure handling. This commit is a pure addition; nothing yet calls the helper.
2. **Commit 2 — new skills land:** Create `skills/forge/SKILL.md`, `skills/forge-admin/SKILL.md`, and rewrite `skills/forge-ask/SKILL.md` in place. Each delegates to existing agents via the same dispatch patterns the old skills used. `skills/forge/SKILL.md` calls `shared/bootstrap-detect.py` when `.claude/forge.local.md` is absent. New skills must independently work before old skills are deleted (so this commit can be tested in isolation by manually invoking them with the old skills also present — both work, no collision).
3. **Commit 3 — atomic deletion:** `git rm -r` all 28 retired skill directories: `forge-init`, `forge-run`, `forge-fix`, `forge-shape`, `forge-sprint`, `forge-review`, `forge-verify`, `forge-deploy`, `forge-commit`, `forge-migration`, `forge-bootstrap`, `forge-docs-generate`, `forge-security-audit`, `forge-status`, `forge-history`, `forge-insights`, `forge-profile`, `forge-tour`, `forge-help`, `forge-recover`, `forge-abort`, `forge-config`, `forge-handoff`, `forge-automation`, `forge-playbooks`, `forge-playbook-refine`, `forge-compress`, `forge-graph`.
4. **Commit 4 — reference rewiring:** Run a sed pass over the file list captured in pre-flight, applying the mapping table in §5.1. Then re-run `grep` to verify zero stragglers (excluding the allowlist file). Affects, at minimum:
   - **Docs:** `README.md`, `CLAUDE.md`, every file under `docs/superpowers/specs/` and `docs/superpowers/plans/`.
   - **Tests:** `tests/structural/skill-consolidation.bats`, `tests/unit/skill-execution/decision-tree-refs.bats`, every file under `tests/scenarios/` referencing skills.
   - **Agents:** all 48 agent `.md` files (especially `fg-100-orchestrator`, `fg-700-retrospective`, `fg-710-post-run`, and any agent that emits user-facing skill suggestions or learnings markers).
   - **Plugin manifests:** `plugin.json`, `marketplace.json`.
   - **Hooks:** any hook under `hooks/` that emits "did you mean" hints or skill-name diagnostics.
   - **`shared/` (~56 files):** `shared/intent-classification.md`, `shared/skill-subcommand-pattern.md` (likely needs full rewrite — see commit 6), `shared/skill-contract.md`, `shared/git-conventions.md`, `shared/preflight-constraints.md`, `shared/agent-communication.md`, `shared/agent-defaults.md`, `shared/stage-contract.md`, `shared/state-schema.md`, `shared/state-schema-fields.md`, `shared/state-transitions.md`, `shared/recovery/recovery-engine.md`, `shared/recovery/strategies/graceful-stop.md`, `shared/recovery/time-travel.md`, `shared/learnings/memory-discovery.md`, `shared/learnings/README.md`, `shared/learnings/rule-promotion.md`, `shared/cross-project-learnings.md`, `shared/next-task-prediction.md`, `shared/playbooks.md`, `shared/explore-cache.md`, `shared/plan-cache.md`, `shared/event-log.md`, `shared/automations.md`, `shared/decision-log.md`, `shared/speculation.md`, `shared/confidence-scoring.md`, `shared/input-compression.md`, `shared/output-compression.md`, `shared/ask-user-question-patterns.md`, `shared/error-taxonomy.md`, `shared/convergence-examples.md`, `shared/security-audit-trail.md`, `shared/security-posture.md`, `shared/data-classification.md`, `shared/dx-metrics.md`, `shared/visual-verification.md`, `shared/feature-flag-management.md`, `shared/deployment-strategies.md`, `shared/performance-regression.md`, `shared/flaky-test-management.md`, `shared/background-execution.md`, `shared/mcp-provisioning.md`, `shared/version-resolution.md`, `shared/config-validation.md`, `shared/a2a-protocol.md`, `shared/run-history/run-history.md`, `shared/graph/schema-versioning.md`, `shared/graph/query-patterns.md`, `shared/graph/schema.md`, `shared/consistency/voting.md`, `shared/tracking/ticket-format.md`, `shared/knowledge-base.md`, `shared/hook-design.md`, `shared/agents.md`, `shared/README.md`.
   - **`modules/` (~49 files):** every framework's `local-template.md` and `forge-config-template.md` under `modules/frameworks/<name>/` (24 frameworks × ~2 files = ~48), plus any `modules/**/conventions.md` that mentions skill names. Verified 2026-04-27 via `grep -rln '/forge-' modules/`.
5. **Commit 5 — `fg-010-shaper` rewrite + state machine:** Replace agent prompt with the new pattern (§3 seven steps). Update `shared/state-schema.md`, `shared/state-transitions.md`, `shared/stage-contract.md` to introduce the BRAINSTORMING stage. Add new config validations to `shared/preflight-constraints.md` for `brainstorm.spec_dir` and `brainstorm.enabled` (see §4.1).
6. **Commit 6 — `shared/skill-subcommand-pattern.md` rewrite or removal:** That file documents the old subcommand pattern as a normative shape (e.g. `forge-graph init|status|...`); under hybrid grammar inside `/forge`, the pattern flattens. Either delete the file (preferred — pattern is internal to `/forge`/`/forge-ask`/`/forge-admin` SKILL.md bodies and no longer needs cross-cutting documentation) or rewrite to describe the three-skill dispatch model. Decision deferred to plan-stage; spec just flags the choice.
7. **Commit 7 — intent classifier expansion:** Update `shared/intent-classification.md` to recognize all 11 verbs from §1's `/forge` table and define a `vague` output (or matching qualitative state) so AC-S007 has a concrete output to assert against.
8. **Commit 8 — test updates:** Extend `tests/structural/skill-consolidation.bats` to enforce exactly 3 skill directories. Add scenario tests for auto-bootstrap path, chained autonomous bootstrap+brainstorm, BRAINSTORMING resume. Add `tests/unit/skill-execution/forge-dispatch.bats` covering the 11 verbs (one assertion per verb minimum) and the NL fallback.

#### §5.1 — Old → new mapping table (search/replace source of truth)

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
/forge-help                  →  (deleted in Phase 2; remove any remaining refs)
/forge-ask                   →  /forge-ask
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

This table is the authoritative source for the rewiring commit. The implementation plan will codify it as a sed/awk script that the implementer runs against the repo, then verifies with grep.

### §6 — Parallelization (preserved)

All current parallel-execution patterns continue to work in the new surface:

| Level | Mechanism | New invocation |
|---|---|---|
| Feature | `fg-090-sprint-orchestrator` + `fg-015-scope-decomposer` | `/forge sprint --parallel "<feat A>" "<feat B>"` |
| Task | `fg-102-conflict-resolver` (scaffolders serial → conflict detect → implementers parallel) | Internal — happens during `/forge run` IMPLEMENTING stage |
| Reviewer | `fg-400-quality-gate` parallel batch dispatch | Internal — happens during `/forge run` REVIEWING stage |

`--parallel` flag continues to be valid for `/forge sprint`. (Out of scope for this spec: parallelizing EXPLORE by aspect; that lands in Phase 10.)

### §7 — Open coordination questions

1. **State schema bump ordering.** Phase 5 coordinates a v2.0.0 bump for `plan_judge_loops`, `impl_judge_loops`, `judge_verdicts[]`, plus removals of `critic_revisions` and `implementer_reflection_cycles`. Phase 5's spec (read 2026-04-27) does **not** mention `state.brainstorm`; rolling into v2.0.0 would require an explicit edit to Phase 5's spec, which is undesirable cross-coupling between in-flight specs.
   - **Default (chosen by this spec):** Take a fresh `v1.11.0` (if Phase 5 has not landed yet) or `v2.1.0` (if Phase 5 has landed). Decoupled — this spec ships independently of Phase 5's release cadence.
   - Implementation note: the plan-stage will inspect `shared/state-schema.md` at the time of execution and pick whichever next-minor version is correct given the live schema version. No coordination with Phase 5 is required.

2. **OTel namespace.** Phase 1 standardizes `forge.*`. New events under `forge.brainstorm.*` (started, questions_asked, approaches_proposed, spec_written, completed, aborted) fit cleanly. No conflict.

3. **Phase 7 (Intent Assurance) interaction.** `fg-540-intent-verifier` checks ACs at VERIFY. With BRAINSTORMING writing the spec to a known path (`state.brainstorm.spec_path`), `fg-540` reads ACs from there. Tight integration, no conflict — but Phase 7's spec must be updated to consume `state.brainstorm.spec_path` as the AC source when present, falling back to the old behavior when absent (e.g., bugfix mode where there's no brainstorm spec).

4. **Phase 9 (Superpowers Pattern Parity) — out of scope here, but tightly related.** This spec lifts the brainstorming pattern. Phase 9 lifts the writing-plans, requesting-code-review, receiving-code-review, systematic-debugging, and finishing-a-development-branch patterns into the corresponding forge agents. Phase 9 is a separate spec in this directory (date: TBD by orchestrator), sized at ~15-25 ACs covering the seven agent uplifts. It depends on this spec for the BRAINSTORMING pseudo-stage but is otherwise independent.

## Acceptance criteria

### Skill surface (5)

- **AC-S001:** `skills/` contains exactly three subdirectories: `forge/`, `forge-ask/`, `forge-admin/`. No others.
- **AC-S002:** Each of the three skills has valid frontmatter (`name`, `description` matching the patterns in §1, `allowed-tools`, `ui:`).
- **AC-S003:** All 26 retired skill directories are absent from `skills/` (full list in §5 commit 2).
- **AC-S004:** `tests/structural/skill-consolidation.bats` enforces AC-S001 and AC-S003.
- **AC-S005:** No file under `docs/`, `tests/`, `agents/`, `skills/`, `hooks/`, `shared/`, `plugin.json`, `marketplace.json`, `README.md`, or `CLAUDE.md` references any retired skill name. `grep -rn "/forge-init\|/forge-run\|/forge-fix\|...\|/forge-graph"` returns zero results except for paths listed in `tests/structural/skill-references-allowlist.txt` (which holds intentional historical references in CHANGELOG, release notes, or migration docs). The allowlist file is checked into git.

### Hybrid grammar (5)

- **AC-S006:** `/forge run "X"`, `/forge fix "X"`, `/forge sprint ...`, `/forge review`, `/forge verify`, `/forge deploy <env>`, `/forge commit`, `/forge migrate "X to Y"`, `/forge bootstrap <stack>`, `/forge docs`, `/forge audit` each dispatch to the correct downstream agent flow.
- **AC-S007:** `/forge "<free-text>"` (no explicit verb) routes through `shared/intent-classification.md` and dispatches to whichever mode the classifier returns. When the classifier returns its `vague` outcome (signal-count < 2 per the contract added in commit 7), the dispatch defaults to `run` (which then enters BRAINSTORMING and lets the shaper resolve ambiguity). Verified by unit tests at `tests/unit/skill-execution/forge-dispatch.bats` containing at least 11 tests — one per verb (`run`, `fix`, `sprint`, `review`, `verify`, `deploy`, `commit`, `migrate`, `bootstrap`, `docs`, `audit`) — plus 3 tests for the NL fallback (vague-input, classifier-resolved-input, ambiguous-flag-positioning).
- **AC-S008:** `/forge --help` prints the full subcommand list and flag matrix; exits 0.
- **AC-S009:** `/forge` (no args) prints usage; exits 0.
- **AC-S010:** `/forge <unknown-verb> <args>` does NOT print "did you mean"; falls through to NL classifier with the full string. Verified by `tests/unit/skill-execution/forge-dispatch.bats::test_unknown_verb_falls_through` asserting (a) no string `"did you mean"` in stdout/stderr, (b) classifier was invoked with the full original argument string.

### Read and admin surfaces (4)

- **AC-S011:** `/forge-ask <question>` (with text) defaults to codebase Q&A. `/forge-ask status|history|insights|profile|tour` dispatch to their named handlers.
- **AC-S012:** `/forge-ask` writes nothing — verified by a contract test that runs every subcommand and asserts `git status` is unchanged after.
- **AC-S013:** `/forge-admin <area> [<action>]` dispatches correctly for all areas listed in §1: recover, abort, config, handoff, automation, playbooks, compress, graph, refine.
- **AC-S014:** `/forge-admin graph query <cypher>` rejects any non-read-only Cypher (existing constraint, ported).

### Auto-bootstrap (4)

- **AC-S015:** `/forge "<request>"` invoked with `.claude/forge.local.md` absent triggers auto-bootstrap. Detection runs, single confirmation prompt fires, default option `[proceed]` writes `forge.local.md`, then user's original request continues.
- **AC-S016:** Auto-bootstrap is **not** triggered by `.forge/` absence alone. Test: clear `.forge/` while keeping `forge.local.md`, run `/forge`, assert no bootstrap prompt fires.
- **AC-S017:** `--autonomous` or `autonomous: true` skips the confirmation prompt; writes `forge.local.md` with detected defaults; logs `[AUTO] bootstrapped...`.
- **AC-S018:** Detection failure aborts with explicit error pointing to `/forge-admin config wizard`. Malformed `forge.local.md` aborts with explicit error pointing to `/forge verify --config` (does **not** auto-bootstrap on top of broken config).

### BRAINSTORMING stage (5)

- **AC-S019:** Feature-mode invocations of `/forge` (explicit `run` or NL classifier → `run`) traverse PREFLIGHT → BRAINSTORMING → EXPLORING. Verified by scenario test.
- **AC-S020:** Bugfix, migration, bootstrap modes skip BRAINSTORMING. Verified by scenario test for each mode.
- **AC-S021:** `fg-010-shaper`'s rewritten prompt implements all seven steps from §3. Verified by a structural agent-prompt test at `tests/structural/fg-010-shaper-shape.bats` that greps `agents/fg-010-shaper.md` for the exact section headings `## Explore project context`, `## Ask clarifying questions`, `## Propose 2-3 approaches`, `## Present design sections`, `## Write spec`, `## Self-review`, `## Handoff` and asserts each appears exactly once. The headings are normative for the agent's prompt structure.
- **AC-S022:** `--autonomous` mode runs degraded one-shot: no `AskUserQuestion`, treats input as spec, writes spec, logs `[AUTO] brainstorm skipped`. Verified by scenario test.
- **AC-S023:** Resume during BRAINSTORMING with existing spec prompts user to resume-from-spec or restart. Verified by scenario test.

### State and telemetry (3)

- **AC-S024:** State schema includes `state.stage = "BRAINSTORMING"` enum and `state.brainstorm` object with all fields from §4.
- **AC-S025:** OTel events fire at brainstorm start, question, approaches proposal, spec write, completion/abort. Namespace `forge.brainstorm.*`.
- **AC-S026:** `state-transitions.md` documents the four BRAINSTORMING transitions from §4.
- **AC-S027:** `/forge --autonomous "<request>"` invoked on a project with no `forge.local.md` chains auto-bootstrap → BRAINSTORMING → EXPLORING in a single uninterrupted run. Both `[AUTO] bootstrapped...` and `[AUTO] brainstorm skipped...` log lines appear in `.forge/forge-log.md`. The pipeline reaches EXPLORING. If either step fails, the pipeline aborts cleanly with no partial state (`forge.local.md` is either fully written or not written; spec doc is either fully written or not written). Verified by scenario test at `tests/scenarios/autonomous-cold-start.bats`.
- **AC-S028:** Config keys `brainstorm.spec_dir` (default `docs/superpowers/specs/`) and `brainstorm.enabled` (default `true`) are validated by `shared/preflight-constraints.md`. Setting `brainstorm.enabled: false` short-circuits BRAINSTORMING — feature mode goes straight to EXPLORING. Setting an invalid `brainstorm.spec_dir` (non-existent and non-creatable parent) fails PREFLIGHT with a clear error.
- **AC-S029:** `/forge run --spec <path>` parses the spec file at `<path>` for the regex `^## (Objective|Goal|Goals)$`, `^## (Scope|Non-goals)$`, and `^## (Acceptance [Cc]riteria|ACs)$`. All three sections must be present (case-sensitive on the regex). If any is missing, interactive mode prompts "spec at `<path>` is incomplete (missing: <list>); run BRAINSTORMING instead?" and autonomous mode aborts the run with the same diagnostic. Verified by unit test at `tests/unit/skill-execution/spec-wellformed.bats`.

## Risks

1. **Scope blast radius.** ~100+ callsite rewires. Risk: missed reference. Mitigation: AC-S005 grep test catches stragglers; CI fails until clean.
2. **Brainstorm fatigue.** Always-on brainstorm could feel slow for users who already have crisp specs. Mitigation: `--spec <path>` skip-with-existing-spec, plus the autonomous degradation.
3. **Intent classifier weakness.** Hybrid grammar relies on the NL classifier handling 11 verbs cleanly when no explicit verb is given. Risk: misroute. Mitigation: classifier already handles ~4 verbs today; adding 7 more requires expanded test coverage. AC-S007 + new unit tests cover the matrix.
4. **Schema bump coupling with Phase 5.** If Phase 5 is delayed, this spec needs an interim v1.11.0. Mitigation: spec calls out both options; orchestrator picks based on actual ship order.
5. **`fg-010-shaper` autonomous fallback quality.** Auto-extracting ACs from raw input is imperfect. Risk: bad spec → bad plan. Mitigation: the autonomous spec is committed, so downstream stages see it; if validator (`fg-210`) flags it as too vague, recovery escalates. (This is a Phase 7 problem, not this spec's.)

## Out of scope (forward references)

- **Other superpowers patterns** (writing-plans, requesting-code-review, receiving-code-review, systematic-debugging, finishing-a-development-branch) — Phase 9.
- **EXPLORE parallelization by aspect** — Phase 10 (not yet drafted).
- **Backwards-compatibility shims** — explicitly rejected per personal-tool stance.

## File touchpoints (preview, full enumeration in plan)

- **Created:**
  - `skills/forge/SKILL.md`, `skills/forge-admin/SKILL.md` (new skill directories).
  - `shared/bootstrap-detect.py` (lifted detection helper, commit 1).
  - `shared/ac-extractor.py` (autonomous AC extractor for degraded BRAINSTORMING, commit 5).
  - `tests/structural/skill-references-allowlist.txt` (allowlist for AC-S005 grep, commit 8).
  - `tests/unit/skill-execution/forge-dispatch.bats`, `tests/unit/skill-execution/spec-wellformed.bats`, `tests/unit/bootstrap_detect_test.py`, `tests/structural/fg-010-shaper-shape.bats`, `tests/scenarios/autonomous-cold-start.bats` (new tests).
- **Deleted:** 28 skill directories under `skills/` (full list in §5 commit 3).
- **Heavily edited:**
  - `skills/forge-ask/SKILL.md` (rewrite in place to absorb status/history/insights/profile/tour).
  - `agents/fg-010-shaper.md` (full rewrite for the seven-step pattern).
  - `agents/fg-100-orchestrator.md` (BRAINSTORMING stage handling, dispatch updates).
  - `shared/state-schema.md`, `shared/state-transitions.md`, `shared/stage-contract.md` (BRAINSTORMING stage and `state.brainstorm` schema).
  - `shared/intent-classification.md` (commit 7: extend to 11 verbs, define `vague` outcome).
  - `shared/preflight-constraints.md` (validate `brainstorm.*` config keys per §4.1).
  - `shared/skill-subcommand-pattern.md` (rewrite or delete per commit 6 decision).
  - `CLAUDE.md`, `README.md` (skill surface section overhaul).
- **Lightly edited (rewiring only, scope per §5 commit 4):**
  - All 8 phase specs in `docs/superpowers/specs/` and all 8 phase plans in `docs/superpowers/plans/`.
  - All 48 agent `.md` files (especially `fg-700-retrospective`, `fg-710-post-run`, and any agent that prints skill suggestions in reports).
  - All 56 markdown files under `shared/` that reference `/forge-` (full list in §5 commit 4).
  - All ~49 framework template files under `modules/frameworks/*/` that reference `/forge-` (full list in §5 commit 4).
  - `plugin.json`, `marketplace.json`.
  - Hooks under `hooks/` that emit skill suggestions or diagnostics.
