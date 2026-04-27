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
- Flags appear after the subcommand and before the free-text argument: `/forge run --dry-run "add CSV export"`. Flags after the argument also work but trigger a deprecation note.
- For `sprint` with a Linear cycle ID, the format is `/forge sprint <linear-cycle-id-or-uuid>` — the dispatcher recognizes both Linear identifiers (e.g. `ENG-cycle-42`) and UUIDs.

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
- Auto-extracts ACs using existing intent classifier + heuristics (presence of "given/when/then", numbered lists of requirements).
- Writes a minimal spec to the same path: header + objective + (extracted) ACs + "**autonomous:** spec auto-generated from raw input".
- Commits the spec.
- Logs `[AUTO] brainstorm skipped — input treated as spec`.
- Proceeds to EXPLORING.

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

### §5 — Migration mechanics (the breaking change)

The bulk of the implementation work. The change is mechanically large because the consolidation rewrites every reference to `/forge-*` skills across the codebase.

**Commit ordering (atomic, no half-states):**

1. **Commit 1 — new skills land:** Create `skills/forge/SKILL.md`, `skills/forge-ask/SKILL.md`, `skills/forge-admin/SKILL.md`. Each delegates to existing agents via the same dispatch patterns the old skills used. New skills must independently work before old skills are deleted (so this commit can be tested in isolation).
2. **Commit 2 — atomic deletion:** `git rm -r` all 26 retired skill directories: `forge-init`, `forge-fix`, `forge-shape`, `forge-sprint`, `forge-review`, `forge-verify`, `forge-deploy`, `forge-commit`, `forge-migration`, `forge-bootstrap`, `forge-docs-generate`, `forge-security-audit`, `forge-status`, `forge-history`, `forge-insights`, `forge-profile`, `forge-tour`, `forge-help` (already deleted in Phase 2; idempotent), `forge-recover`, `forge-abort`, `forge-config`, `forge-handoff`, `forge-automation`, `forge-playbooks`, `forge-playbook-refine`, `forge-compress`, `forge-graph`. (Total: 27 entries; one is already gone, so net 26.)
3. **Commit 3 — reference rewiring:** Search-and-replace all `/forge-X` references to `/forge X` or `/forge-ask X` or `/forge-admin X` based on the mapping table (§5.1). Affects `README.md`, `CLAUDE.md`, all 8 spec files in `docs/superpowers/specs/`, all 8 plan files in `docs/superpowers/plans/`, every `tests/structural/`, `tests/unit/skill-execution/`, `tests/scenarios/` reference, agent `.md` files that emit user-facing suggestions (`fg-100`, `fg-700`, `fg-710`), `plugin.json`, `marketplace.json`, hooks that emit "did you mean" hints.
4. **Commit 4 — `fg-010-shaper` rewrite:** Replace agent prompt with the new pattern. Update `state-schema.md`, `state-transitions.md`, `stage-contract.md` to introduce BRAINSTORMING.
5. **Commit 5 — bootstrap helper extraction:** Move detection logic from `forge-init/SKILL.md` (already deleted) into `shared/bootstrap-detect.py`. Wire `/forge` to call it on missing config.
6. **Commit 6 — test updates:** Extend `tests/structural/skill-consolidation.bats` to enforce exactly 3 skill directories. Add scenario test for auto-bootstrap path. Add unit tests for hybrid grammar dispatch and intent classifier coverage of all 11 verbs.

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

1. **State schema bump ordering.** Phase 5 coordinates a v2.0.0 bump. This spec's BRAINSTORMING addition needs a schema bump too. Two options:
   - (a) Roll into Phase 5's v2.0.0. Cheapest. Couples ship order: this spec must merge before or with Phase 5.
   - (b) Take v1.11.0 between Phase 5 and Phase 6. Decoupled, two bumps.
   - **Default (chosen by this spec):** (a). Phase 5 explicitly accommodates this in its v2.0.0 schema design.

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
- **AC-S007:** `/forge "<free-text>"` (no explicit verb) routes through `shared/intent-classification.md` and dispatches to whichever mode the classifier returns (run, fix, sprint, review, deploy, etc.). When the classifier returns LOW confidence with no winning candidate, the dispatch defaults to `run` (which then enters BRAINSTORMING and lets the shaper resolve ambiguity). Verified by unit tests covering at least one example per verb.
- **AC-S008:** `/forge --help` prints the full subcommand list and flag matrix; exits 0.
- **AC-S009:** `/forge` (no args) prints usage; exits 0.
- **AC-S010:** `/forge <unknown-verb> <args>` does NOT print "did you mean"; falls through to NL classifier with the full string. Verified by unit test.

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
- **AC-S021:** `fg-010-shaper`'s rewritten prompt implements all seven steps from §3 (explore, ask, propose, present, write, self-review, hand off). Verified by structural agent-prompt test that asserts presence of each phase.
- **AC-S022:** `--autonomous` mode runs degraded one-shot: no `AskUserQuestion`, treats input as spec, writes spec, logs `[AUTO] brainstorm skipped`. Verified by scenario test.
- **AC-S023:** Resume during BRAINSTORMING with existing spec prompts user to resume-from-spec or restart. Verified by scenario test.

### State and telemetry (3)

- **AC-S024:** State schema includes `state.stage = "BRAINSTORMING"` enum and `state.brainstorm` object with all fields from §4.
- **AC-S025:** OTel events fire at brainstorm start, question, approaches proposal, spec write, completion/abort. Namespace `forge.brainstorm.*`.
- **AC-S026:** `state-transitions.md` documents the four BRAINSTORMING transitions from §4.

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

## File touchpoints (preview, full list in plan)

- **Created:** `skills/forge/SKILL.md`, `skills/forge-ask/SKILL.md`, `skills/forge-admin/SKILL.md`, `shared/bootstrap-detect.py`.
- **Deleted:** 26 skill directories under `skills/`.
- **Heavily edited:** `agents/fg-010-shaper.md` (full rewrite), `agents/fg-100-orchestrator.md` (BRAINSTORMING stage handling), `shared/state-schema.md`, `shared/state-transitions.md`, `shared/stage-contract.md`, `shared/intent-classification.md`, `CLAUDE.md`, `README.md`.
- **Lightly edited (rewiring only):** all 8 phase specs in `docs/superpowers/specs/`, all 8 phase plans in `docs/superpowers/plans/`, agents that emit user-facing skill suggestions (`fg-700`, `fg-710`), `plugin.json`, `marketplace.json`.
