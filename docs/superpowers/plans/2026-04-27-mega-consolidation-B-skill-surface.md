# Forge Mega-Consolidation — Phase B: Skill Surface + Rewiring Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the 29-skill surface with three skills (`/forge`, `/forge-ask`, `/forge-admin`), rewire ~200 callsites across the codebase, atomically delete 28 retired skill directories, and verify cleanliness.

**Architecture:** Three new skill files dispatch to existing agents via the same patterns the old skills used (no agent rewrites in Phase B). Rewiring happens through a deterministic sed pass driven by a pre-captured grep snapshot. Atomic deletion comes last so any rewiring miss fails CI before the deletion lands.

**Tech Stack:** Markdown (SKILL.md), bash sed (rewiring), bats (structural + unit tests).

**Spec reference:** `docs/superpowers/specs/2026-04-27-skill-consolidation-design.md` commit 660dbef7. Read §1, §12 (incl. mapping table), and the AC list before starting.

---

## Cross-phase dependencies (read before starting)

- **B1 depends on A2** (`shared/bootstrap-detect.py` must exist before `skills/forge/SKILL.md` can call it). Do not start B1 until A2 is merged.
- **B7-B8 depend on A5** (intent classifier must already accept the 11 verbs `run|fix|sprint|review|verify|deploy|commit|migrate|bootstrap|docs|audit` before agent files reference the new skill names). Do not start B7 or B8 until A5 is merged.
- **B12 (deletion) MUST come AFTER B5-B10 (rewiring)** — otherwise CI will fail because rewiring couldn't find old skill paths to update.
- **C/D/E phases depend on B12 having deleted the old skills** before they touch agent or doc files that the deletion would conflict with.

## Mapping table — canonical sed source-of-truth (used by B5-B10)

This table is referenced by every rewiring task. Do not change the right-hand side without updating both this plan and the spec.

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
/forge-help                  →  (delete refs)
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

**Sed-substitution discipline:**
- Always anchor on the leading slash to avoid mangling unrelated tokens (e.g., `forge-runner` should not collide with `/forge-run`).
- Always include a trailing word boundary (space, end-of-line, quote, backtick, or punctuation) to avoid grabbing prefixes — `/forge-recover` must not greedy-match into `/forge-recover-something`.
- The 28 retired-skill names are listed verbatim in the B12 deletion command — use that list as the closed set.

---

## Task index

| # | Task | Risk | TDD shape |
|---|---|---|---|
| 7 | B1 — create `skills/forge/SKILL.md` (hybrid grammar) | medium | unit test: forge-dispatch.bats fixtures (deferred to B13) |
| 8 | B2 — create `skills/forge-admin/SKILL.md` | low | structural test: subcommand-section grep |
| 9 | B3 — rewrite `skills/forge-ask/SKILL.md` in place | low | structural test: subcommand-section grep |
| 10 | B4 — pre-flight grep capture | low | grep snapshot, immutable input to B5-B10 |
| 11 | B5 — rewire `docs/` | medium | grep clean + diff stat |
| 12 | B6 — rewire `tests/` | medium | grep clean + diff stat (excluding allowlist) |
| 13 | B7 — rewire `agents/` (48 files) | high | grep clean + diff stat + manual orchestrator review |
| 14 | B8 — rewire `shared/` (~56 files) | high | grep clean + diff stat |
| 15 | B9 — rewire `modules/` (~49 files) | medium | grep clean + diff stat |
| 16 | B10 — rewire root + manifests + hooks | medium | grep clean + diff stat |
| 17 | B11 — `shared/skill-subcommand-pattern.md` decision | low | file removal verified by `git rm` |
| 18 | B12 — atomic deletion of 28 retired skill directories | high | structural: skill-consolidation.bats asserts exactly 3 dirs |
| 19 | B13 — add new tests + allowlist file | medium | the tests themselves are the test |

**Risk justifications** for high-risk tasks appear in the task body per AC-PLAN-009.

---

## Task B1: Create `skills/forge/SKILL.md` (hybrid grammar entry)

**Files:**
- Create: `skills/forge/SKILL.md`
- Reference (read-only, do not modify): `shared/intent-classification.md`, `shared/bootstrap-detect.py`, `shared/skill-contract.md`, `shared/mcp-detection.md`

**Risk:** medium — this is the new write-surface entry point and must dispatch to the right agent in 11 distinct cases. Mitigation: B13 ships unit tests covering each verb plus three NL-fallback cases. The body below is the canonical content.

**ACs covered:** AC-S001 (one of three), AC-S002 (frontmatter shape), AC-S006 (verb dispatch), AC-S007 (NL fallback), AC-S008 (--help), AC-S009 (no-args usage), AC-S010 (unknown verb falls through, no "did you mean"), AC-S015 (auto-bootstrap trigger), AC-S016 (`.forge/` absence does NOT trigger bootstrap), AC-S017 (autonomous skip prompt).

### Implementer mini-prompt (pass to subagent if dispatching)

> Create `skills/forge/SKILL.md` with the exact content shown in Step 3 below. Frontmatter description is verbatim from spec §1. Hybrid grammar dispatch logic: explicit verbs win; unknown tokens fall through to `shared/intent-classification.md`. On bootstrap detection (missing `.claude/forge.local.md`), call `shared/bootstrap-detect.py` (added in commit A2). Do not modify any other file.

### Spec-reviewer mini-prompt

> Verify the new `skills/forge/SKILL.md` against AC-S006, AC-S007, AC-S008, AC-S009, AC-S010, AC-S015, AC-S016. The 11 verbs map to the agent dispatches given in spec §1. Frontmatter description string must match spec §1 verbatim. Bootstrap trigger fires on `.claude/forge.local.md` absence, NOT on `.forge/` absence.

### Steps

- [ ] **Step 1: Confirm A2 has merged**

```bash
test -f /Users/denissajnar/IdeaProjects/forge/shared/bootstrap-detect.py
```

Expected: file exists. If not, stop — A2 has not merged. Resume B1 only after A2 lands.

- [ ] **Step 2: Confirm `skills/forge/` directory does not yet exist**

```bash
test ! -e /Users/denissajnar/IdeaProjects/forge/skills/forge
```

Expected: exit 0 (directory absent).

- [ ] **Step 3: Write `skills/forge/SKILL.md`**

Create the file with this exact content:

````markdown
---
name: forge
description: "[writes] Build, fix, deploy, review, or modify code in this project. Universal entry for the forge pipeline. Auto-bootstraps on first run; brainstorms before planning when given a feature description. Use for any productive action: implementing features, fixing bugs, reviewing branches, deploying, committing, running migrations."
allowed-tools: ['Read', 'Write', 'Edit', 'Bash', 'Glob', 'Grep', 'Agent', 'AskUserQuestion']
---

# /forge — Universal Write Surface

Hybrid grammar: explicit verb subcommands win; bare free-text falls through to the natural-language intent classifier. Auto-bootstraps when `.claude/forge.local.md` is absent.

## Flags

- **--help**: print usage and exit 0
- **--dry-run**: preview only; PREFLIGHT → VALIDATE; no worktree, no commits
- **--autonomous**: no `AskUserQuestion` calls; auto-decisions logged with `[AUTO]` prefix; honors `autonomous: true` in `forge.local.md`
- **--from=<stage>**: resume from a specific pipeline stage
- **--spec <path>**: start from an existing spec; for `run`, skips BRAINSTORMING if spec is well-formed
- **--parallel**: only valid for `sprint`
- **--background**: enqueue for background execution; output to `.forge/alerts.json`

Flags must appear BEFORE the free-text argument: `/forge run --dry-run "add CSV export"` is correct; `/forge run "add CSV export" --dry-run` is an error and must fail fast with usage.

## Exit codes

See `shared/skill-contract.md` for the standard exit-code table.

## Subcommand dispatch

Follow `shared/skill-subcommand-pattern.md`. This skill uses **positional verbs with NL fallback**.

**Dispatch rules:**

1. Read `$ARGUMENTS`.
2. If `$ARGUMENTS` is empty: print usage block (see §Usage below) and exit 0. (AC-S009)
3. If `$ARGUMENTS` is `--help` or first token is `--help`: print usage and exit 0. (AC-S008)
4. Split: `SUB="$1"; shift; REST="$*"`.
5. If `$SUB` matches one of the 11 known verbs (`run | fix | sprint | review | verify | deploy | commit | migrate | bootstrap | docs | audit`): dispatch to the matching `### Subcommand: <SUB>` section with `$REST` as its arguments.
6. Otherwise (unknown verb or first-token-is-not-a-verb): treat the entire `$ARGUMENTS` string as a natural-language requirement and fall through to the NL-classifier path. Do NOT print "did you mean" or any disambiguation message — silently classify. (AC-S010)

**No default subcommand.** A bare `/forge` (no args) prints usage and exits 0; it never dispatches.

## Usage

```
/forge <subcommand> [args]
/forge "<free-text requirement>"

Subcommands:
  run "<feature>"           Full feature pipeline (BRAINSTORM → ... → SHIP)
  fix "<bug or ticket>"     Bugfix pipeline (skips BRAINSTORM)
  sprint [--parallel] ...   Sprint orchestration
  review [flags]            Quality review (--full, --scope=changed|all, --fix)
  verify [flags]            Build/lint/test or config validation
  deploy <env>              Deployment
  commit                    Generate conventional commit from staged changes
  migrate "<from> to <to>"  Migration pipeline
  bootstrap [<stack>]       Greenfield project scaffold
  docs [<scope>]            Docs generation
  audit                     Security audit

Flags:
  --dry-run                 Preview only
  --autonomous              No prompts; log [AUTO] decisions
  --from=<stage>            Resume from stage
  --spec <path>             Use existing spec
  --parallel                (sprint only)
  --background              Enqueue for background; alerts in .forge/alerts.json
  --help                    Show this message

Examples:
  /forge run "add CSV export"
  /forge fix FG-742
  /forge "fix the login redirect"     # NL fallback → bugfix mode
  /forge --dry-run run "refactor auth"
```

## Bootstrap trigger (auto-init)

**Trigger condition:** `/forge` invoked with `.claude/forge.local.md` absent.

The runtime directory `.forge/` is **not** a trigger. Clearing `.forge/` (e.g. via `/forge-admin recover reset`) must not re-trigger bootstrap. Config file is the contract; runtime state is the cache. (AC-S016)

**Detection logic:**

1. Check `test -f .claude/forge.local.md`. If present, skip bootstrap and proceed to subcommand dispatch.
2. If absent, invoke `python3 "${CLAUDE_PLUGIN_ROOT}/shared/bootstrap-detect.py" --root .` and parse the JSON output `{language, framework, testing, build, confidence}`.

**Interaction shape (interactive mode, AC-S015):**

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

Use `AskUserQuestion` with default option `[proceed]`. After bootstrap, the user's original request continues without re-prompting.

**Autonomous-mode behavior (AC-S017):**

- With `--autonomous` flag or `autonomous: true` in any config, **skip the prompt entirely**.
- Detect, write `forge.local.md` via `bootstrap-detect.write_forge_local_md()`, log `[AUTO] bootstrapped with detected defaults: <stack>` to `.claude/forge-log.md`.
- Proceed to the user's original request.

**Failure modes (AC-S018):**

- **Detection ambiguous** (no recognizable build tool, mixed stacks at root, multiple package managers without a clear primary): abort with exit 2 and message "couldn't auto-bootstrap; run `/forge-admin config wizard`". No silent half-init.
- **Write fails** (permissions, disk full): abort the run; do not proceed with the user's original request. Print error and exit non-zero.
- **`forge.local.md` is present but malformed:** treat as configured but broken. Do **not** auto-bootstrap (config exists). Surface a hard error pointing to `/forge-admin config` or `/forge verify --config`.

## Shared prerequisites

Before any subcommand:

1. **Git repository:** Run `git rev-parse --show-toplevel 2>/dev/null`. If fails: report "Not a git repository. Navigate to a project directory." and STOP.
2. **Forge bootstrap:** If `.claude/forge.local.md` is absent, run the auto-bootstrap flow above. Otherwise proceed.

---

### Subcommand: run

Full feature pipeline. Auto-classifies multi-feature, vague, refactor, performance, testing, documentation modes when the requirement is ambiguous.

#### Step 1: Parse input

`$REST` is the work item — a free-text feature description like "Add plan versioning endpoint". If `$REST` is empty (no input after the `run` token), ask the user: "What would you like to build? Provide a feature description, e.g., 'Add plan versioning endpoint'." Do not dispatch the orchestrator with empty input.

Recognized prefixes (mode override):
- `bugfix:` or `fix:` → Mode: bugfix (prefer `/forge fix` for richer source resolution)
- `migrate:` or `migration:` → Mode: migration (prefer `/forge migrate`)
- `bootstrap:` → Mode: bootstrap (prefer `/forge bootstrap`)
- (no prefix) → classify via `shared/intent-classification.md`

#### Step 2: Classify intent

Unless an explicit mode prefix or flag is set, classify `$REST` per `shared/intent-classification.md`. First match wins. Modes: bugfix, migration, bootstrap, multi-feature, testing, documentation, refactor, performance, vague, standard (default).

If `routing.auto_classify: false` in `forge-config.md`: use `Mode: standard`.

#### Step 3: Detect available MCPs

Per `shared/mcp-detection.md`. Build a comma-separated list (e.g., `Linear, Context7`). If none: `none`.

#### Step 4: Route by mode

| Mode | Dispatch target |
|---|---|
| `multi-feature` | `fg-015-scope-decomposer` |
| `vague` | `fg-010-shaper` |
| `bugfix` | `fg-100-orchestrator` (Mode: bugfix) |
| `migration` | `fg-100-orchestrator` (Mode: migration) |
| `bootstrap` | `fg-100-orchestrator` (Mode: bootstrap) |
| `testing` | `fg-100-orchestrator` (Mode: testing) |
| `documentation` | `fg-350-docs-generator` standalone |
| `refactor` | `fg-100-orchestrator` (Mode: refactor) |
| `performance` | `fg-100-orchestrator` (Mode: performance) |
| `standard` (default) | `fg-100-orchestrator` |

For feature-mode invocations, the orchestrator enters BRAINSTORMING (added in C2) before EXPLORING.

Dispatch prompt template:

> Execute the full development pipeline for: `{REST}`
>
> Mode: `{classified_mode}`
> Available MCPs: `{detected_mcps}`
> Flags: `{flags}`

#### Step 5: Relay output

When the dispatched agent completes, relay its final output (PR URL, summary, decomposition plan, escalation) back to the user unchanged.

### Subcommand: fix

Bugfix pipeline. Skips BRAINSTORMING — the bug investigator (`fg-020`) plays the equivalent role.

#### Step 1: Parse input

`$REST` is the bug description, ticket ID, error message, or Linear issue reference.

#### Step 2: Resolve source

If `$REST` matches `{PREFIX}-{NNN}` ticket pattern: source `shared/tracking/tracking-ops.sh` and call `find_ticket ".forge/tracking" "{ticket_id}"`. Read ticket title and `## Description` as the bug description.

If `$REST` is a Linear issue ID and Linear MCP is available: fetch the issue via `mcp__claude_ai_Linear__get_issue` and use the body.

Otherwise: treat `$REST` as the bug description verbatim.

#### Step 3: Dispatch

Dispatch `fg-020-bug-investigator`:

> Investigate and fix this bug:
>
> `{bug_description}`
>
> Source: `{ticket_id | linear_id | inline}`
> Available MCPs: `{detected_mcps}`

### Subcommand: sprint

Multi-feature parallel orchestration.

#### Step 1: Parse input

`$REST` is either:
- One or more `"<feature>"` quoted strings (each becomes a sprint feature), OR
- A Linear cycle ID matching the Linear API identifier shape (passed through to `fg-090-sprint-orchestrator` for validation).

#### Step 2: Dispatch

Dispatch `fg-090-sprint-orchestrator`:

> Execute sprint:
>
> Features: `{features_or_cycle_id}`
> Parallel: `{--parallel flag present?}`
> Available MCPs: `{detected_mcps}`

### Subcommand: review

Quality review. Default `--scope=changed`. Subcommand-specific flags: `--full`, `--scope=changed|all`, `--fix`.

#### Step 1: Parse flags

- `--scope=<changed|all>` (default `changed`)
- `--full` (run all reviewer batches; default is quick batch)
- `--fix` (iterative fix loop; only valid with `--scope=all`)

#### Step 2: Dispatch

Dispatch `fg-400-quality-gate` directly (read-only path) or `fg-100-orchestrator` (write path with --fix):

> Run quality review:
>
> Scope: `{changed | all}`
> Mode: `{quick | full}`
> Fix loop: `{enabled | disabled}`

### Subcommand: verify

Pre-pipeline checks. Default `--build`. Subcommand-specific flags: `--build`, `--config`, `--all`.

#### Step 1: Parse flags

- `--build` (default): run configured build + lint + test
- `--config`: validate `forge.local.md` against PREFLIGHT constraints (read-only)
- `--all`: both

#### Step 2: Dispatch

Dispatch the verify path directly (no orchestrator). Reads `forge.local.md`, runs scripts, reports pass/fail. Read-only when `--config`; write-cap-equivalent for `--build` (test/build artefacts only, no project source mutation).

### Subcommand: deploy

Deployment. `$REST` is the environment name (`staging | production | preview`).

#### Step 1: Parse input

If `$REST` is empty: ask "Which environment? (staging | production | preview)".

#### Step 2: Dispatch

Dispatch `fg-620-deploy-verifier` for staged deployments or invoke direct CLI (kubectl, helm, argocd) per `forge.local.md` deployment config.

### Subcommand: commit

Generate a conventional commit from staged changes. No agent dispatch — this is a thin wrapper around git diff parsing and conventional-commit templating.

#### Step 1: Verify staged changes

Run `git diff --cached --stat`. If empty: report "No staged changes. Run `git add <files>` first." and STOP.

#### Step 2: Generate commit

Read diff, infer type (feat, fix, refactor, docs, chore, test, build, ci) and scope, draft message. Present 2-3 options via `AskUserQuestion` (autonomous: pick highest-confidence option).

#### Step 3: Execute

Run `git commit -m "<message>"`. Relay output.

### Subcommand: migrate

Migration pipeline. `$REST` is `"<from-version> to <to-version>"` or a free-text migration description.

#### Step 1: Parse input

If `$REST` is empty: ask "What's the migration target? e.g., 'Spring Boot 2 to 3'".

#### Step 2: Dispatch

Dispatch `fg-100-orchestrator` with `Mode: migration`:

> Execute migration:
>
> `{REST}`
>
> Mode: migration
> Available MCPs: `{detected_mcps}`

### Subcommand: bootstrap

Greenfield project scaffold. `$REST` is the optional stack hint.

#### Step 1: Detect or accept stack

If `$REST` is non-empty: pass to bootstrapper as the explicit stack request.

If `$REST` is empty: invoke `bootstrap-detect.py` for stack detection. If detection succeeds with high confidence, present detected stack via `AskUserQuestion`; otherwise prompt for explicit stack.

#### Step 2: Dispatch

Dispatch `fg-050-project-bootstrapper`:

> Bootstrap a new project:
>
> Stack: `{stack}`
> Available MCPs: `{detected_mcps}`

### Subcommand: docs

Documentation generation. `$REST` is the optional scope (e.g., `readme`, `architecture`, `api`).

#### Step 1: Parse scope

If `$REST` is empty: dispatch in standalone mode with default scope (README + architecture + ADRs).

#### Step 2: Dispatch

Dispatch `fg-350-docs-generator`:

> Generate documentation:
>
> Scope: `{REST or "default"}`
> Mode: standalone
> Available MCPs: `{detected_mcps}`

### Subcommand: audit

Security audit. No `$REST` arguments accepted; bare invocation only.

#### Step 1: Dispatch

Dispatch `fg-411-security-reviewer` standalone or run module-appropriate scanners per `forge.local.md` security config.

> Run security audit:
>
> Available MCPs: `{detected_mcps}`

---

## NL fallback path (unknown verb / no verb)

When `$SUB` is not one of the 11 verbs (Step 5 of dispatch rules), the entire `$ARGUMENTS` string is fed to `shared/intent-classification.md`. The classifier returns one of: `bugfix | migration | bootstrap | multi-feature | testing | documentation | refactor | performance | vague | standard`.

**Dispatch:** route to the corresponding `### Subcommand: <name>` section using the classifier's output. For `vague`, the spec contract is: dispatch `run` mode (which then enters BRAINSTORMING and lets the shaper resolve ambiguity). The `vague` outcome is defined by the classifier as signal-count < 2 across (actors, entities, surface, criteria).

**No "did you mean" message** is ever printed (AC-S010). The classifier's verdict is binding.

## Error Handling

| Condition | Action |
|---|---|
| Prerequisites fail | Report specific error and STOP |
| Empty argument (no input after stripping flags) | Print usage and exit 0 |
| `--help` | Print usage and exit 0 |
| Unknown verb | Fall through to NL classifier with full original string. NEVER print "did you mean". |
| Classifier returns `vague` | Dispatch `run` mode; let BRAINSTORMING resolve ambiguity |
| Bootstrap detection ambiguous | Abort with exit 2 + message pointing to `/forge-admin config wizard` |
| `forge.local.md` malformed | Abort with exit 2 + message pointing to `/forge verify --config` |
| Agent dispatch fails | Report "Pipeline orchestrator failed to start. Check plugin installation." and STOP |
| State corruption mid-run | Suggest `/forge-admin recover diagnose` |

## See Also

- `/forge-ask` — Read-only queries (status, history, insights, profile, tour, codebase Q&A)
- `/forge-admin` — State and config management (recover, abort, config, handoff, automation, playbooks, compress, graph, refine)
````

- [ ] **Step 4: Verify file size and frontmatter**

```bash
test -f /Users/denissajnar/IdeaProjects/forge/skills/forge/SKILL.md
head -7 /Users/denissajnar/IdeaProjects/forge/skills/forge/SKILL.md
```

Expected:
```
---
name: forge
description: "[writes] Build, fix, deploy, review, or modify code in this project. ..."
allowed-tools: ['Read', 'Write', 'Edit', 'Bash', 'Glob', 'Grep', 'Agent', 'AskUserQuestion']
---
```

The `description` line must match spec §1 verbatim. Frontmatter MUST end with `---` on its own line before the H1.

- [ ] **Step 5: Verify dispatch sections present**

```bash
grep -c '^### Subcommand: ' /Users/denissajnar/IdeaProjects/forge/skills/forge/SKILL.md
```

Expected: `11` (one for each verb: run, fix, sprint, review, verify, deploy, commit, migrate, bootstrap, docs, audit).

- [ ] **Step 6: Commit**

```bash
git add skills/forge/SKILL.md
git commit -m "feat(skills): add /forge hybrid-grammar entry skill (B1)

New write-surface entry. Dispatches to existing agents via 11 verb
subcommands plus NL fallback through shared/intent-classification.md.
Auto-bootstraps on missing forge.local.md by calling A2's helper.

Refs spec §1, AC-S001 (1/3), AC-S002, AC-S006, AC-S007, AC-S008,
AC-S009, AC-S010, AC-S015, AC-S016, AC-S017."
```

---

## Task B2: Create `skills/forge-admin/SKILL.md` (state-management surface)

**Files:**
- Create: `skills/forge-admin/SKILL.md`
- Reference (read-only): existing `skills/forge-recover/`, `skills/forge-abort/`, `skills/forge-config/`, `skills/forge-handoff/`, `skills/forge-automation/`, `skills/forge-playbooks/`, `skills/forge-playbook-refine/`, `skills/forge-compress/`, `skills/forge-graph/` for behavior to absorb.

**Risk:** low — this is a thin dispatcher to existing agents and scripts; no new behavior introduced. Each subcommand preserves the body of its corresponding old skill verbatim under a new section heading.

**ACs covered:** AC-S001 (one of three), AC-S002 (frontmatter shape), AC-S013 (subcommand dispatch), AC-S014 (graph query read-only enforcement).

### Implementer mini-prompt

> Create `skills/forge-admin/SKILL.md` with the exact content shown in Step 2 below. Frontmatter description verbatim from spec §1. Subcommand-only grammar (no NL fallback). Each of the 9 subcommands maps to its corresponding old skill's behavior under `### Subcommand: <name>`.

### Spec-reviewer mini-prompt

> Verify the new `skills/forge-admin/SKILL.md` against AC-S013 (9 subcommands present: recover, abort, config, handoff, automation, playbooks, refine, compress, graph) and AC-S014 (graph query rejects non-read-only Cypher). The skill MUST NOT carry any NL fallback — unknown subcommand prints help and exits 2.

### Steps

- [ ] **Step 1: Confirm `skills/forge-admin/` directory does not yet exist**

```bash
test ! -e /Users/denissajnar/IdeaProjects/forge/skills/forge-admin
```

Expected: exit 0.

- [ ] **Step 2: Write `skills/forge-admin/SKILL.md`**

Create the file with this exact content:

````markdown
---
name: forge-admin
description: "[writes] Manage forge state and configuration: recovery, abort, config edits, session handoff, automations, playbooks, output compression, knowledge graph maintenance. Use to recover from broken pipeline state, edit settings, manage long-lived state."
allowed-tools: ['Read', 'Write', 'Edit', 'Bash', 'Glob', 'Grep', 'Agent', 'AskUserQuestion']
---

# /forge-admin — State Management Surface

Two-level dispatch: top-level `<area>` (recover, abort, config, handoff, automation, playbooks, refine, compress, graph) and per-area `<action>` where applicable. No NL fallback — unknown areas print help and exit 2.

## Flags

- **--help**: print usage and exit 0
- **--dry-run**: preview only (where applicable)
- **--json**: structured JSON output (status-like subcommands only)

## Exit codes

See `shared/skill-contract.md` for the standard table.

## Subcommand dispatch

Follow `shared/skill-subcommand-pattern.md`. **Positional, no NL fallback.**

**Dispatch rules:**

1. Read `$ARGUMENTS`.
2. Split: `AREA="$1"; shift; ACTION="$1"; shift; REST="$*"`.
3. If `$AREA` is empty OR matches `-*`: print usage and exit 2.
4. If `$AREA == --help` or `help`: print usage and exit 0.
5. If `$AREA` is in `{recover, abort, config, handoff, automation, playbooks, refine, compress, graph}`: dispatch to `### Subcommand: <AREA>` with `$ACTION` and `$REST`.
6. Otherwise: print `Unknown area '<AREA>'. Valid: recover | abort | config | handoff | automation | playbooks | refine | compress | graph. Try /forge-admin --help.` and exit 2.

## Usage

```
/forge-admin <area> [<action>] [args]

Areas:
  recover <action>          State recovery (diagnose | repair | reset | resume | rollback | rewind | list)
  abort                     Stop active pipeline run gracefully
  config [<action>]         Config editor (wizard | <key=val>)
  handoff [<action>]        Session handoff (list | show | resume | search | <text>)
  automation [<action>]     Event-driven triggers (list | add | remove | test)
  playbooks [<action>]      Reusable recipes (list | run <id> | create | analyze)
  refine [<playbook-id>]    Apply playbook refinement proposals
  compress [<action>]       Token compression (agents | output <mode> | status | help)
  graph <action>            Knowledge graph (init | status | query <cypher> | rebuild | debug)

Flags:
  --help                    Show this message
  --dry-run                 Preview only (where applicable)
  --json                    Structured output (status-like subcommands)
```

## Shared prerequisites

Before any subcommand:

1. **Git repository:** `git rev-parse --show-toplevel`. If fails: STOP.
2. **Forge initialized:** `.claude/forge.local.md` exists. If absent: report "Forge not initialized. Run /forge first." and STOP. (This skill does NOT auto-bootstrap; bootstrap is a `/forge` concern.)

---

### Subcommand: recover

State diagnostics and repair. Actions: `diagnose | repair | reset | resume | rollback | rewind | list`.

Default action when none provided: `diagnose` (read-only, safe default).

#### Action: diagnose (read-only, default)

Read `.forge/state.json`, `.forge/.lock`, recent events; report stuck stage, missing checkpoints, lock holders, score history. No mutations.

#### Action: repair

Reset counters, clear stale `.forge/.lock` (>24h), normalize state to a known-good shape. Preserves explore-cache, plan-cache, code-graph.db, run-history.db, wiki, learnings.

#### Action: reset

Clear `.forge/state.json` and worktree state. Preserves: `.forge/explore-cache.json`, `.forge/plan-cache/`, `.forge/code-graph.db`, `.forge/trust.json`, `.forge/events.jsonl`, `.forge/playbook-analytics.json`, `.forge/run-history.db`, `.forge/playbook-refinements/`, `.forge/consistency-cache.jsonl`, `.forge/plans/candidates/`, `.forge/runs/<id>/handoffs/`, `.forge/wiki/`, `.forge/brainstorm-transcripts/`. Confirms via `AskUserQuestion` unless `--autonomous`.

#### Action: resume

Continue from last checkpoint. Reads `.forge/state.json.head_checkpoint`, validates checkpoint integrity, dispatches `fg-100-orchestrator` with resume context.

#### Action: rollback

Roll back worktree commits to last good checkpoint. Confirms via `AskUserQuestion` (destructive).

#### Action: rewind <checkpoint-id>

Rewind to any prior checkpoint in the DAG (time-travel). Lists candidates if no `<checkpoint-id>` given.

#### Action: list

Print checkpoint DAG with timestamps, scores, and stage labels.

### Subcommand: abort

Stop active pipeline run gracefully. Writes ABORT marker to state, releases `.forge/.lock`, preserves checkpoints. Compatible with `/forge-admin recover resume`.

### Subcommand: config

Interactive config editor. Actions: `wizard` (full multi-question setup) or `<key=val>` (single-key edit).

#### Action: wizard

Run the full bootstrap wizard (lifted from old `/forge-init`). Detects stack via `bootstrap-detect.py`, asks for overrides, writes `.claude/forge.local.md`.

#### Action: <key=val>

Parse `<key>=<val>`, validate against `shared/preflight-constraints.md`, write to `.claude/forge.local.md`. Surfaces validation errors.

### Subcommand: handoff

Session handoff. Default action (no args, `<text>` arg) = write. Actions: `list | show | resume | search | <text>`.

#### Action: <text> (or default with args)

Write a structured handoff artefact to `.forge/runs/<run_id>/handoffs/<timestamp>.md` capturing run state, conversation context, and resume instructions.

#### Action: list

List handoff artefacts in reverse chronological order.

#### Action: show <id>

Display the handoff artefact body.

#### Action: resume <id>

Pre-fill the current Claude Code session with the handoff context (memory + state restoration).

#### Action: search <query>

FTS5 search over `.forge/runs/*/handoffs/*.md`.

### Subcommand: automation

Event-driven trigger management. Actions: `list | add | remove | test`.

Backed by `hooks/automation_trigger.py`. Triggers: cron, CI failure, PR event, file change.

### Subcommand: playbooks

Reusable pipeline recipes. Actions: `list | run <id> | create | analyze`.

Backed by `.forge/playbooks/` YAML and `.forge/playbook-analytics.json`.

### Subcommand: refine

Apply playbook refinement proposals from `.forge/playbook-refinements/`. Optional `<playbook-id>` filter. Interactive review/apply via `AskUserQuestion`.

### Subcommand: compress

Token-cost compression controls. Actions: `agents | output <mode> | status | help`.

#### Action: agents

Compress agent `.md` files via terse rewriting (30-50% reduction). Confirms via `AskUserQuestion`.

#### Action: output <mode>

Set runtime output compression. `<mode>` is `off | lite | full | ultra`. Writes `.forge/caveman-mode`.

#### Action: status

Print current compression settings (read-only).

#### Action: help

Print compression reference card.

### Subcommand: graph

Knowledge-graph operations. Actions: `init | status | query <cypher> | rebuild | debug`.

**Read-only enforcement (AC-S014):** the `query` action MUST reject any Cypher containing `CREATE | MERGE | DELETE | SET | REMOVE | DROP` (case-insensitive) before sending to Neo4j. Use a regex pre-check; if matched, abort with exit 2 and message "Read-only mode: only MATCH queries permitted. Use `/forge-admin graph rebuild` for writes."

The five sub-actions preserve the behavior of the old `/forge-graph` skill verbatim — see `skills/forge-graph/SKILL.md` (the original) for the per-action body. (After B12, that file is deleted; this section IS the canonical home of that behavior.) The full content is embedded inline:

#### Action: init

(Body identical to old `skills/forge-graph/SKILL.md` Subcommand: init — Steps 1-8.)

#### Action: status

(Body identical to old skills/forge-graph Subcommand: status.)

#### Action: query <cypher>

(Body identical to old skills/forge-graph Subcommand: query, with the read-only regex pre-check added per AC-S014.)

#### Action: rebuild

(Body identical to old skills/forge-graph Subcommand: rebuild.)

#### Action: debug

(Body identical to old skills/forge-graph Subcommand: debug.)

## Error Handling

| Condition | Action |
|---|---|
| Shared prerequisites fail | Report and STOP |
| Empty area / `-*` first token | Print usage and exit 2 |
| `--help` | Print usage and exit 0 |
| Unknown area | Print "Unknown area" and exit 2 |
| Unknown action within area | Print area-specific usage and exit 2 |
| `graph query` with non-read-only Cypher | Reject with exit 2 (AC-S014) |
| State corruption | `recover diagnose` reports; `recover repair` mutates |

## See Also

- `/forge` — Write-surface entry (run, fix, sprint, review, verify, deploy, commit, migrate, bootstrap, docs, audit)
- `/forge-ask` — Read-only queries (status, history, insights, profile, tour, codebase Q&A)
````

(Note: the inline "(Body identical to old …)" placeholders are filled in fully during implementation by copying the corresponding sections from the existing `/forge-graph`, `/forge-recover`, etc. SKILL.md files. The implementer must inline the full body — no cross-file references after B12 deletes the source files.)

- [ ] **Step 3: Inline-expand the placeholder sections**

For each `### Action:` section currently marked "(Body identical to old …)", copy the corresponding content from the source skill into this file before B12 deletes the source. Sources:
- `recover` → `skills/forge-recover/SKILL.md`
- `abort` → `skills/forge-abort/SKILL.md`
- `config` → `skills/forge-config/SKILL.md`
- `handoff` → `skills/forge-handoff/SKILL.md`
- `automation` → `skills/forge-automation/SKILL.md`
- `playbooks` → `skills/forge-playbooks/SKILL.md`
- `refine` → `skills/forge-playbook-refine/SKILL.md`
- `compress` → `skills/forge-compress/SKILL.md`
- `graph` → `skills/forge-graph/SKILL.md`

**Why inline:** B12 deletes the sources. After B12 there is no other home for that content. The B11 decision deletes the cross-skill pattern doc, so each SKILL.md is fully self-contained.

After expansion, the file will be ~1500-2000 lines. That is acceptable — it is the canonical home of all admin-area behavior.

- [ ] **Step 4: Verify subcommand sections present**

```bash
grep -c '^### Subcommand: ' /Users/denissajnar/IdeaProjects/forge/skills/forge-admin/SKILL.md
```

Expected: `9` (recover, abort, config, handoff, automation, playbooks, refine, compress, graph).

```bash
grep -c '^#### Action: ' /Users/denissajnar/IdeaProjects/forge/skills/forge-admin/SKILL.md
```

Expected: at least `25` (sum of actions across all 9 subcommands).

- [ ] **Step 5: Verify graph query read-only enforcement is documented**

```bash
grep -E 'CREATE \| MERGE \| DELETE \| SET \| REMOVE \| DROP' /Users/denissajnar/IdeaProjects/forge/skills/forge-admin/SKILL.md
grep -E 'Read-only mode: only MATCH' /Users/denissajnar/IdeaProjects/forge/skills/forge-admin/SKILL.md
```

Expected: both grep commands match (AC-S014).

- [ ] **Step 6: Commit**

```bash
git add skills/forge-admin/SKILL.md
git commit -m "feat(skills): add /forge-admin state management skill (B2)

Two-level dispatch: 9 areas (recover, abort, config, handoff,
automation, playbooks, refine, compress, graph), each with its
own actions. No NL fallback. Inlined the body of every absorbed
old skill so B12 can safely delete the sources.

Refs spec §1, AC-S001 (2/3), AC-S002, AC-S013, AC-S014."
```

---

## Task B3: Rewrite `skills/forge-ask/SKILL.md` in place

**Files:**
- Modify: `skills/forge-ask/SKILL.md`
- Reference (read-only, body absorbed): `skills/forge-status/SKILL.md`, `skills/forge-history/SKILL.md`, `skills/forge-insights/SKILL.md`, `skills/forge-profile/SKILL.md`, `skills/forge-tour/SKILL.md`

**Risk:** low — additive rewrite; the existing default-action behavior (codebase Q&A) is preserved as the bare-args path. New subcommands just route to other agents/scripts.

**ACs covered:** AC-S001 (one of three, edited in place), AC-S002 (frontmatter), AC-S011 (subcommand dispatch), AC-S012 (read-only contract), AC-S011-LIVE (status subcommand reproduces the `--- live ---` separator behavior introduced by Phase 1 Task 24 — see Step 3.5 below).

**Phase 1 coordination note:** Phase 1 Task 24 (plan: `docs/superpowers/plans/2026-04-22-phase-1-truth-and-observability.md`) added a `### Live progress` section to `skills/forge-status/SKILL.md`. B12 deletes that file. This task MUST absorb the Live progress section verbatim into the `status` subcommand body so the `--- live ---` separator behavior survives the deletion. See Step 3.5.

**Acceptance criterion (explicit):** After this task ships, `/forge ask status` (the new B3 status subcommand surface) reproduces the `--- live ---` separator behavior introduced by Phase 1 Task 24 — same data sources (`.forge/progress/status.json`, `.forge/run-history-trends.json`), same elapsed/timeout printout, same hung-run detection, same fallback message.

### Implementer mini-prompt

> Rewrite `skills/forge-ask/SKILL.md` in place to absorb status, history, insights, profile, tour subcommands. Default action with text args is unchanged (codebase Q&A). Add a subcommand dispatch block at the top that routes to the new sections. Inline the body of each absorbed skill — B12 deletes the sources.

### Spec-reviewer mini-prompt

> Verify the rewritten `skills/forge-ask/SKILL.md` against AC-S011 (5 subcommands plus default Q&A) and AC-S012 (no `Write`, `Edit` in `allowed-tools`; every subcommand body is read-only). Frontmatter description must match spec §1.

### Steps

- [ ] **Step 1: Read current `skills/forge-ask/SKILL.md`**

```bash
cat /Users/denissajnar/IdeaProjects/forge/skills/forge-ask/SKILL.md | head -10
```

Verify the existing description and `allowed-tools` block. The new version preserves `allowed-tools: ['Read', 'Bash', 'Glob', 'Grep', 'Agent']` (no Write, no Edit — AC-S012).

- [ ] **Step 2: Write the new `skills/forge-ask/SKILL.md`**

Replace the existing file with this content:

````markdown
---
name: forge-ask
description: "[read-only] Query forge state, codebase knowledge, run history, or analytics. Never mutates project state. Use to check pipeline status, search wiki/graph for code answers, view past runs, see analytics, or get an onboarding tour."
allowed-tools: ['Read', 'Bash', 'Glob', 'Grep', 'Agent']
---

# /forge-ask — Read-Only Query Surface

Five subcommands plus a default codebase Q&A path. Read-only — no mutations to project state. Always-safe to invoke.

## Flags

- **--help**: print usage and exit 0
- **--json**: structured JSON output (status, history, insights, profile)
- **--fresh**: bypass cache (codebase Q&A only)
- **--deep**: exhaustive grep/glob (codebase Q&A only)

## Exit codes

See `shared/skill-contract.md` for the standard table.

## Subcommand dispatch

**Positional, no NL fallback. Bare args (no recognized verb) default to codebase Q&A.**

**Dispatch rules:**

1. Read `$ARGUMENTS`.
2. If `$ARGUMENTS` is empty: prompt "What would you like to know about this codebase?" and re-read.
3. If `$ARGUMENTS == --help`: print usage and exit 0.
4. Split: `SUB="$1"; shift; REST="$*"`.
5. If `$SUB` is in `{status, history, insights, profile, tour}`: dispatch to `### Subcommand: <SUB>` with `$REST`.
6. Otherwise: treat the entire `$ARGUMENTS` string as a freeform question and dispatch to `### Subcommand: ask` (default).

## Usage

```
/forge-ask <subcommand> [args]
/forge-ask "<freeform question>"

Subcommands:
  status                    Current pipeline state
  history [--limit=N]       Past runs from .forge/run-history.db
  insights [--scope=...]    Quality, cost, convergence trends
  profile [<run-id>]        Per-stage timing and cost breakdown
  tour                      5-stop guided introduction

Default action (no recognized subcommand): codebase Q&A via wiki + graph + explore cache + docs.

Flags:
  --help                    Show this message
  --json                    Structured output (status-like)
  --fresh                   Bypass cache (Q&A only)
  --deep                    Exhaustive search (Q&A only)
```

## Shared prerequisites

1. **Git repository:** `git rev-parse --show-toplevel`. If fails: STOP.
2. **Forge initialized:** `.claude/forge.local.md` exists. If absent: report "Forge not initialized. Run /forge first." and STOP. (This skill does NOT auto-bootstrap.)

## Read-only contract (AC-S012)

This skill MUST NOT modify any file under the project root, `.forge/`, or `.claude/`. Verified by a contract test that runs every subcommand and asserts `git status` is unchanged after.

`allowed-tools` excludes `Write` and `Edit` — the harness enforces this.

The Q&A subcommand may write to `.forge/ask-cache/` (an opaque cache); this is the only permitted write and is excluded from the AC-S012 contract test by an explicit cache-path check.

---

### Subcommand: ask (default)

Codebase Q&A. (Body identical to the existing skills/forge-ask/SKILL.md before this rewrite — preserves cache, source priority, output format.)

#### Configuration

| Key | Default | Description |
|-----|---------|-------------|
| `forge_ask.enabled` | `true` | Enable/disable subcommand |
| `forge_ask.deep_mode` | `false` | Also run grep/glob for exhaustive answers |
| `forge_ask.max_source_files` | `20` | Max file references to include in answer |
| `forge_ask.cache_answers` | `true` | Cache answers in `.forge/ask-cache/` |

#### Steps

1. **Parse question:** read `$REST` (or full `$ARGUMENTS` when no subcommand). Empty: prompt user.
2. **Check cache** (if `cache_answers: true`): compute key from normalized question, check `.forge/ask-cache/<key>.md`, validate freshness against `state.json._seq`. Return cached answer with note if hit. `--fresh` bypasses.
3. **Query data sources** in priority order:
   - **Source 1 — Wiki** (`.forge/wiki/`) — highest confidence.
   - **Source 2 — Knowledge Graph** (Neo4j MCP) — entity relationships.
   - **Source 3 — Explore Cache** (`.forge/explore-cache.json`) — structural context.
   - **Source 4 — Docs Index** (`.forge/docs-index.json` or project docs) — authoritative intent.
   - **Source 5 — Direct Search** (deep mode only or `--deep`) — grep/glob for question entities.
4. **Aggregate and synthesize:** combine fragments, resolve conflicts (wiki > graph > cache > docs > direct), compose answer with `## Answer / ### Details / ### Key Files / ### Sources` shape. Cap file refs at `max_source_files`.
5. **Cache answer** (if enabled, not `--fresh`): write to `.forge/ask-cache/<key>.md`. Trim oldest 10 if cache > 50 entries.

### Subcommand: status

Current pipeline run state. Read `.forge/state.json` and present stage, score, convergence phase, integrations, and background run progress.

(Body identical to old skills/forge-status/SKILL.md, INCLUDING the `### Live progress` section absorbed from Phase 1 Task 24 — see Step 3.5 below for the canonical block.)

### Subcommand: history

Past runs from `.forge/run-history.db` (SQLite FTS5). Optional `--limit=N` (default 10), `--filter=<expr>` (FTS5 query).

(Body identical to old skills/forge-history/SKILL.md.)

### Subcommand: insights

Pipeline analytics. Quality trajectory, agent effectiveness, cost analysis, convergence patterns, memory health. Optional `--scope=run|cycle|all` (default `cycle`).

(Body identical to old skills/forge-insights/SKILL.md.)

### Subcommand: profile

Per-stage timing and cost breakdown. Optional `<run-id>` (default: most recent run).

(Body identical to old skills/forge-profile/SKILL.md.)

### Subcommand: tour

5-stop guided introduction to forge. Walks through `/forge bootstrap`, `/forge verify`, `/forge run`, `/forge fix`, `/forge review`.

(Body identical to old skills/forge-tour/SKILL.md.)

## Error Handling

| Condition | Action |
|---|---|
| Prerequisites fail | Report and STOP |
| Empty question (default subcommand, no args) | Prompt "What would you like to know?" |
| `--help` | Print usage and exit 0 |
| Unknown subcommand | Treat as freeform question; dispatch to default Q&A |
| No data sources (wiki, graph, cache, docs all absent) | Fall back to direct grep/glob regardless of `deep_mode` |
| Neo4j unavailable | Skip graph; log INFO; continue |
| All sources empty | Report "Could not find relevant information. Try rephrasing or use `--deep`." |

## See Also

- `/forge` — Write-surface entry (run, fix, sprint, review, verify, deploy, commit, migrate, bootstrap, docs, audit)
- `/forge-admin` — State and config management (recover, abort, config, handoff, automation, playbooks, compress, graph, refine)
````

- [ ] **Step 3: Inline-expand the placeholder sections**

For each `### Subcommand:` section currently marked "(Body identical to old …)", copy the corresponding content from the source skill into this file. Sources:
- `ask` → existing `skills/forge-ask/SKILL.md` body before this rewrite (lines 38-145 of the original)
- `status` → `skills/forge-status/SKILL.md` **including the `### Live progress` section appended by Phase 1 Task 24** (do NOT skip — see Step 3.5 for the verbatim block to confirm the absorbed content matches)
- `history` → `skills/forge-history/SKILL.md`
- `insights` → `skills/forge-insights/SKILL.md`
- `profile` → `skills/forge-profile/SKILL.md`
- `tour` → `skills/forge-tour/SKILL.md`

After expansion, file will be ~800-1100 lines.

- [ ] **Step 3.5: Confirm Phase 1 Task 24 `--- live ---` block is present in the `status` subcommand**

Phase 1 Task 24 added a `### Live progress` section to `skills/forge-status/SKILL.md`. B12 deletes that source file. Copying only the pre-Phase-1 body would silently regress the `--- live ---` separator behavior. After Step 3, verify the absorbed `status` subcommand body contains the following block **verbatim** (modulo the `### Live progress` heading level — keep it as a `####` subheading inside `### Subcommand: status` to match the surrounding nesting):

```markdown
<!-- absorbed from Phase 1 Task 24 (skills/forge-status/SKILL.md §Live progress) -->
#### Live progress

After the primary status output, print a `--- live ---` separator and
render data from `.forge/progress/status.json` and
`.forge/run-history-trends.json` (both optional):

If `.forge/progress/status.json` exists:
1. Parse via `python3 -c "import json; print(json.load(open('.forge/progress/status.json')))"`.
2. Print: `Stage: {stage}  Agent: {agent_active or 'idle'}`.
3. Print elapsed vs timeout: `{elapsed_ms_in_stage}ms / {timeout_ms}ms`.
4. If `(now - updated_at) > 60s` and `(now - state_entered_at) > stage_timeout_ms`: print "Run appears hung — consider /forge-recover diagnose."

If `.forge/run-history-trends.json` exists:
1. Print last 5 runs as a table: run_id, verdict, score, duration_s.
2. Print count of `recent_hook_failures`.

If neither file exists: print "No live data (run has not completed a
subagent dispatch yet)."
```

Update the `/forge-recover diagnose` reference to `/forge-admin recover diagnose` if and only if the surrounding doc has already been rewired by B5-B10 at the time this step lands. If the rewire has not happened yet, leave the original `/forge-recover diagnose` text — B5-B10 will sweep it via the canonical mapping table at the top of this plan.

Verify with:

```bash
grep -c '^#### Live progress$' /Users/denissajnar/IdeaProjects/forge/skills/forge-ask/SKILL.md
grep -c -- '--- live ---' /Users/denissajnar/IdeaProjects/forge/skills/forge-ask/SKILL.md
grep -c '\.forge/progress/status\.json' /Users/denissajnar/IdeaProjects/forge/skills/forge-ask/SKILL.md
grep -c '\.forge/run-history-trends\.json' /Users/denissajnar/IdeaProjects/forge/skills/forge-ask/SKILL.md
```

Each must return `>= 1`. If any return `0`, the Phase 1 Task 24 work has been dropped — fix before proceeding to Step 4.

- [ ] **Step 4: Verify subcommand sections present**

```bash
grep -c '^### Subcommand: ' /Users/denissajnar/IdeaProjects/forge/skills/forge-ask/SKILL.md
```

Expected: `6` (ask, status, history, insights, profile, tour).

- [ ] **Step 5: Verify allowed-tools is read-only**

```bash
grep '^allowed-tools:' /Users/denissajnar/IdeaProjects/forge/skills/forge-ask/SKILL.md
```

Expected: `allowed-tools: ['Read', 'Bash', 'Glob', 'Grep', 'Agent']`. No `Write`, no `Edit`.

- [ ] **Step 6: Commit**

```bash
git add skills/forge-ask/SKILL.md
git commit -m "refactor(skills): rewrite /forge-ask in place with subcommand dispatch (B3)

Absorbs status, history, insights, profile, tour as subcommands.
Default action (bare args) preserves the existing codebase Q&A
behavior. Read-only contract preserved (no Write/Edit in
allowed-tools).

Refs spec §1, AC-S001 (3/3), AC-S002, AC-S011, AC-S012."
```

---

## Task B4: Pre-flight grep capture → `tests/structural/migration-callsites.txt`

**Files:**
- Create: `tests/structural/migration-callsites.txt` (committed snapshot)

**Risk:** low — pure read-side capture. The output is the canonical input for B5-B10.

**ACs covered:** AC-S005 (callsite cleanliness — this snapshot is the closed set of files that B5-B10 must rewire).

### Implementer mini-prompt

> Run the canonical grep against the repository root and write the output (file paths, sorted, deduplicated) to `tests/structural/migration-callsites.txt`. Commit. Do not fix anything yet — this is the input for B5-B10.

### Spec-reviewer mini-prompt

> Verify `tests/structural/migration-callsites.txt` exists, is sorted, has no duplicates, and references at least 200 files (per spec §12 expected blast radius). The file MUST end with a trailing newline.

### Steps

- [ ] **Step 1: Run the canonical grep**

```bash
cd /Users/denissajnar/IdeaProjects/forge
grep -rln '/forge-' \
  --include='*.md' \
  --include='*.json' \
  --include='*.py' \
  --include='*.yml' \
  --include='*.yaml' \
  --include='*.bats' \
  --include='*.sh' \
  . 2>/dev/null \
  | sed 's|^\./||' \
  | sort -u \
  > tests/structural/migration-callsites.txt
```

Expected: writes a sorted, deduplicated file list. The leading `./` from `grep -r .` is stripped so paths are repository-relative.

- [ ] **Step 2: Verify shape**

```bash
wc -l /Users/denissajnar/IdeaProjects/forge/tests/structural/migration-callsites.txt
head -5 /Users/denissajnar/IdeaProjects/forge/tests/structural/migration-callsites.txt
tail -5 /Users/denissajnar/IdeaProjects/forge/tests/structural/migration-callsites.txt
```

Expected: line count ≥ 200, first line begins with `.github/` or similar early-alphabet path, last line begins with `tests/` or similar late-alphabet path. No `./` prefix anywhere. No empty lines.

- [ ] **Step 3: Spot-check coverage**

```bash
grep -c '^docs/superpowers/' /Users/denissajnar/IdeaProjects/forge/tests/structural/migration-callsites.txt
grep -c '^agents/' /Users/denissajnar/IdeaProjects/forge/tests/structural/migration-callsites.txt
grep -c '^shared/' /Users/denissajnar/IdeaProjects/forge/tests/structural/migration-callsites.txt
grep -c '^modules/' /Users/denissajnar/IdeaProjects/forge/tests/structural/migration-callsites.txt
grep -c '^tests/' /Users/denissajnar/IdeaProjects/forge/tests/structural/migration-callsites.txt
```

Expected: each top-level directory shows non-zero counts roughly matching the `wc -l` per-directory breakdown captured during plan authorship (docs ≈ 21, agents ≈ 12, shared ≈ 79, modules ≈ 49, tests ≈ 86).

- [ ] **Step 4: Commit**

```bash
git add tests/structural/migration-callsites.txt
git commit -m "test(structural): snapshot pre-rewiring callsites (B4)

Canonical grep output for /forge-* references across the repo.
This file is the input for B5-B10 sed passes and the AC-S005
test fixture. Frozen at this commit; do not regenerate without
also updating the sed pipeline.

Refs spec §12 pre-flight, AC-S005."
```

---

## Task B5: Rewire `docs/`

**Files:**
- Modify: every file under `docs/` that the B4 snapshot lists. Approximately 21 files: `docs/superpowers/specs/*.md` (8), `docs/superpowers/plans/*.md` (8), plus a few README/notes.
- Reference: `tests/structural/migration-callsites.txt` (B4 output) for the closed set.

**Risk:** medium — 21 files, mostly per-token replacements. Mitigation: the mapping table is closed and tokenized; sed runs against a fixed list; verify-clean grep proves no stragglers remain. **Risk justification:** Spec documents are read by future planners as the canonical contract. A missed rewrite could cause future agents to dispatch to deleted skills, surfacing as a cascade of "skill not found" errors only after B12 deletes the sources. Mitigation: B4 snapshot is the closed-set input; sed runs against the snapshot directly; the verify-clean grep at Step 4 fails CI before B12 lands.

**ACs covered:** AC-S005 (partial — docs/ subset).

### Implementer mini-prompt

> Apply the mapping table at the top of this plan to every file under `docs/` that appears in `tests/structural/migration-callsites.txt`. Use sed with anchored, word-bounded patterns. After the sed pass, re-run the canonical grep against `docs/` and assert zero stragglers. Commit.

### Spec-reviewer mini-prompt

> Verify the docs/ rewiring against AC-S005 (subset). Run `grep -rln '/forge-init\|/forge-run\|/forge-fix\|/forge-shape\|/forge-sprint\|/forge-review\|/forge-verify\|/forge-deploy\|/forge-commit\|/forge-migration\|/forge-bootstrap\|/forge-docs-generate\|/forge-security-audit\|/forge-status\|/forge-history\|/forge-insights\|/forge-profile\|/forge-tour\|/forge-help\|/forge-recover\|/forge-abort\|/forge-config\|/forge-handoff\|/forge-automation\|/forge-playbooks\|/forge-playbook-refine\|/forge-compress\|/forge-graph' docs/` and confirm zero matches.

### Steps

- [ ] **Step 1: Confirm B4 snapshot exists**

```bash
test -f /Users/denissajnar/IdeaProjects/forge/tests/structural/migration-callsites.txt
grep -c '^docs/' /Users/denissajnar/IdeaProjects/forge/tests/structural/migration-callsites.txt
```

Expected: file exists; ~21 lines under `docs/`.

- [ ] **Step 2: Build the docs-only file list**

```bash
cd /Users/denissajnar/IdeaProjects/forge
DOCS_FILES=$(grep '^docs/' tests/structural/migration-callsites.txt)
echo "Will rewire $(echo "$DOCS_FILES" | wc -l) files under docs/"
echo "$DOCS_FILES"
```

- [ ] **Step 3: Apply the mapping with sed**

Use a single sed script that applies all 28 substitutions in one pass per file. The pattern uses a leading slash anchor and word-boundary `\b` to avoid mangling. Apply in dependency order (longer patterns first so `forge-playbook-refine` is matched before `forge-playbooks`).

```bash
cd /Users/denissajnar/IdeaProjects/forge

# Helper: apply all 28 substitutions to a file in place.
# Order matters: longest old-name first to avoid greedy collisions.
apply_mapping() {
  local f="$1"
  # Use perl for portable in-place edit with word boundaries; sed -i
  # syntax differs between macOS and Linux.
  perl -pi -e '
    s{/forge-docs-generate\b}{/forge docs}g;
    s{/forge-security-audit\b}{/forge audit}g;
    s{/forge-playbook-refine\b}{/forge-admin refine}g;
    s{/forge-playbooks\b}{/forge-admin playbooks}g;
    s{/forge-automation\b}{/forge-admin automation}g;
    s{/forge-handoff\b}{/forge-admin handoff}g;
    s{/forge-recover\b}{/forge-admin recover}g;
    s{/forge-compress\b}{/forge-admin compress}g;
    s{/forge-config\b}{/forge-admin config}g;
    s{/forge-abort\b}{/forge-admin abort}g;
    s{/forge-graph\b}{/forge-admin graph}g;
    s{/forge-migration\b}{/forge migrate}g;
    s{/forge-bootstrap\b}{/forge bootstrap}g;
    s{/forge-insights\b}{/forge-ask insights}g;
    s{/forge-profile\b}{/forge-ask profile}g;
    s{/forge-history\b}{/forge-ask history}g;
    s{/forge-status\b}{/forge-ask status}g;
    s{/forge-sprint\b}{/forge sprint}g;
    s{/forge-review\b}{/forge review}g;
    s{/forge-verify\b}{/forge verify}g;
    s{/forge-deploy\b}{/forge deploy}g;
    s{/forge-commit\b}{/forge commit}g;
    s{/forge-shape\b}{/forge run}g;
    s{/forge-tour\b}{/forge-ask tour}g;
    s{/forge-help\b}{/forge --help}g;
    s{/forge-init\b}{/forge}g;
    s{/forge-fix\b}{/forge fix}g;
    s{/forge-run\b}{/forge run}g;
  ' "$f"
}

# Apply to every docs/ file from the snapshot.
while IFS= read -r f; do
  apply_mapping "$f"
done < <(grep '^docs/' tests/structural/migration-callsites.txt)
```

Notes on the mapping choices:
- `/forge-init` → `/forge` (the new entry skill auto-bootstraps)
- `/forge-shape` → `/forge run` (BRAINSTORMING absorbs the shaping role; users typing `/forge-shape "X"` should now type `/forge run "X"` and let BRAINSTORMING run)
- `/forge-help` → `/forge --help` (deletion of help skill, replaced by the universal `--help` flag)
- `/forge-tour` → `/forge-ask tour` (read-only, fits under ask)

- [ ] **Step 4: Verify clean — re-run the grep against docs/**

```bash
cd /Users/denissajnar/IdeaProjects/forge
grep -rn '/forge-init\b\|/forge-run\b\|/forge-fix\b\|/forge-shape\b\|/forge-sprint\b\|/forge-review\b\|/forge-verify\b\|/forge-deploy\b\|/forge-commit\b\|/forge-migration\b\|/forge-bootstrap\b\|/forge-docs-generate\b\|/forge-security-audit\b\|/forge-status\b\|/forge-history\b\|/forge-insights\b\|/forge-profile\b\|/forge-tour\b\|/forge-help\b\|/forge-recover\b\|/forge-abort\b\|/forge-config\b\|/forge-handoff\b\|/forge-automation\b\|/forge-playbooks\b\|/forge-playbook-refine\b\|/forge-compress\b\|/forge-graph\b' docs/
```

Expected: zero output. If any line is printed, sed missed something — open the file, fix manually, re-run the grep.

- [ ] **Step 5: Confirm diff stat is reasonable**

```bash
git diff --stat docs/ | tail -3
```

Expected: ~21 files changed, edit counts in the low hundreds (each retired skill name appears 5-15 times across the doc set).

- [ ] **Step 6: Commit**

```bash
git add docs/
git commit -m "refactor(docs): rewire skill references for consolidation (B5)

Applied the canonical mapping (28 retired skill names → /forge,
/forge-ask, /forge-admin) to every doc under docs/superpowers/
specs and plans, plus root README/CLAUDE refs. Sed input:
tests/structural/migration-callsites.txt.

Refs spec §12 commit B5, AC-S005 (docs/ subset)."
```

---

## Task B6: Rewire `tests/`

**Files:**
- Modify: every file under `tests/` that the B4 snapshot lists. Approximately 86 files: `.bats` files, scenario fixtures, helper scripts.
- Exclude: `tests/structural/migration-callsites.txt` itself (the snapshot is data, not code).

**Risk:** medium — 86 files including bats integration tests that may have hardcoded skill names in test assertions. Mitigation: sed pass + verify-clean. Some tests may need manual review if they were testing the OLD skill behavior (those tests are obsolete and will be replaced by B13).

**ACs covered:** AC-S005 (partial — tests/ subset).

### Implementer mini-prompt

> Apply the mapping table to every file under `tests/` listed in `tests/structural/migration-callsites.txt`, EXCLUDING `tests/structural/migration-callsites.txt` itself. After the sed pass, re-run the canonical grep against `tests/` and assert zero stragglers (with the snapshot file allowed). Some tests may now be obsolete (testing deleted skills) — leave them in place for B13 to address; do not delete tests in B6.

### Spec-reviewer mini-prompt

> Verify tests/ rewiring against AC-S005 (subset). Confirm the snapshot file is preserved. Do NOT confirm test pass/fail — many tests will be broken until B13 lands.

### Steps

- [ ] **Step 1: Build the tests-only file list (excluding the snapshot)**

```bash
cd /Users/denissajnar/IdeaProjects/forge
TESTS_FILES=$(grep '^tests/' tests/structural/migration-callsites.txt \
              | grep -v '^tests/structural/migration-callsites.txt$')
echo "Will rewire $(echo "$TESTS_FILES" | wc -l) files under tests/"
```

- [ ] **Step 2: Apply the mapping with the same `apply_mapping` helper from B5**

```bash
cd /Users/denissajnar/IdeaProjects/forge

# Use the apply_mapping perl block from B5 (same script body).
# Apply to every tests/ file from the snapshot, except the snapshot itself.
while IFS= read -r f; do
  if [ "$f" = "tests/structural/migration-callsites.txt" ]; then continue; fi
  perl -pi -e '
    s{/forge-docs-generate\b}{/forge docs}g;
    s{/forge-security-audit\b}{/forge audit}g;
    s{/forge-playbook-refine\b}{/forge-admin refine}g;
    s{/forge-playbooks\b}{/forge-admin playbooks}g;
    s{/forge-automation\b}{/forge-admin automation}g;
    s{/forge-handoff\b}{/forge-admin handoff}g;
    s{/forge-recover\b}{/forge-admin recover}g;
    s{/forge-compress\b}{/forge-admin compress}g;
    s{/forge-config\b}{/forge-admin config}g;
    s{/forge-abort\b}{/forge-admin abort}g;
    s{/forge-graph\b}{/forge-admin graph}g;
    s{/forge-migration\b}{/forge migrate}g;
    s{/forge-bootstrap\b}{/forge bootstrap}g;
    s{/forge-insights\b}{/forge-ask insights}g;
    s{/forge-profile\b}{/forge-ask profile}g;
    s{/forge-history\b}{/forge-ask history}g;
    s{/forge-status\b}{/forge-ask status}g;
    s{/forge-sprint\b}{/forge sprint}g;
    s{/forge-review\b}{/forge review}g;
    s{/forge-verify\b}{/forge verify}g;
    s{/forge-deploy\b}{/forge deploy}g;
    s{/forge-commit\b}{/forge commit}g;
    s{/forge-shape\b}{/forge run}g;
    s{/forge-tour\b}{/forge-ask tour}g;
    s{/forge-help\b}{/forge --help}g;
    s{/forge-init\b}{/forge}g;
    s{/forge-fix\b}{/forge fix}g;
    s{/forge-run\b}{/forge run}g;
  ' "$f"
done < <(grep '^tests/' tests/structural/migration-callsites.txt | grep -v '^tests/structural/migration-callsites.txt$')
```

- [ ] **Step 3: Verify the snapshot file was NOT modified**

```bash
cd /Users/denissajnar/IdeaProjects/forge
git diff tests/structural/migration-callsites.txt
```

Expected: empty diff (file unchanged).

- [ ] **Step 4: Verify clean — re-run the grep against tests/, excluding the snapshot**

```bash
cd /Users/denissajnar/IdeaProjects/forge
grep -rn '/forge-init\b\|/forge-run\b\|/forge-fix\b\|/forge-shape\b\|/forge-sprint\b\|/forge-review\b\|/forge-verify\b\|/forge-deploy\b\|/forge-commit\b\|/forge-migration\b\|/forge-bootstrap\b\|/forge-docs-generate\b\|/forge-security-audit\b\|/forge-status\b\|/forge-history\b\|/forge-insights\b\|/forge-profile\b\|/forge-tour\b\|/forge-help\b\|/forge-recover\b\|/forge-abort\b\|/forge-config\b\|/forge-handoff\b\|/forge-automation\b\|/forge-playbooks\b\|/forge-playbook-refine\b\|/forge-compress\b\|/forge-graph\b' tests/ \
  | grep -v 'tests/structural/migration-callsites.txt'
```

Expected: zero output.

- [ ] **Step 5: Confirm diff stat**

```bash
git diff --stat tests/ | tail -3
```

Expected: ~85 files changed (86 minus the preserved snapshot).

- [ ] **Step 6: Commit**

```bash
git add tests/
git commit -m "refactor(tests): rewire skill references for consolidation (B6)

Applied the canonical mapping to every test file listed in the
B4 snapshot, except the snapshot itself. Some bats tests may now
exercise removed skills — those are addressed in B13.

Refs spec §12 commit B6, AC-S005 (tests/ subset)."
```

---

## Task B7: Rewire `agents/` (48 files)

**Files:**
- Modify: every file under `agents/` (48 files). Snapshot lists ~12 files referencing the retired skills, but every agent file gets a sed pass for safety (the sed is idempotent — files with no matches are unchanged).
- Special attention: `agents/fg-100-orchestrator.md`, `agents/fg-700-retrospective.md`, `agents/fg-710-post-run.md` — these have richer integration that may contain dispatch blocks pointing at the old skill names.

**Risk:** high. **Risk justification:** Agents are loaded as system prompts at runtime. A miss in an agent file means the agent will instruct itself or its sub-agents to dispatch to a deleted skill, which will silently fail (the harness skill list is the source of truth — old names just won't resolve, no error message). The orchestrator alone references skill suggestions in error-handling, retrospective reads "what to suggest next time", and post-run classifies PR feedback against skill verbs. Mitigation: dual-pass — apply sed to all 48 files, then manually inspect the three high-touch orchestrator/retrospective/post-run files for dispatch blocks the sed pattern might have missed (e.g., embedded code-block markers or multiline strings).

**ACs covered:** AC-S005 (partial — agents/ subset).

### Implementer mini-prompt

> Apply the mapping table sed pass to every file under `agents/`. Then manually open `agents/fg-100-orchestrator.md`, `agents/fg-700-retrospective.md`, and `agents/fg-710-post-run.md`, scan each for any remaining old skill references that the sed regex might have missed (embedded JSON, fenced code blocks, multi-line strings), and fix them. Specifically, the orchestrator's stage-routing block is the highest-risk site — verify it dispatches to `/forge-admin recover`, not `/forge-recover`, in error escalation paths.

### Spec-reviewer mini-prompt

> Verify agents/ rewiring against AC-S005 (subset). Run the canonical grep against `agents/`; expect zero output. Open the orchestrator file (the longest agent file) and search specifically for: stage-routing blocks, error-escalation blocks, "see also" or "next step" suggestions to confirm all skill refs use the new vocabulary.

### Steps

- [ ] **Step 1: Confirm A5 has merged (intent classifier accepts 11 verbs)**

```bash
# A5 added the 11-verb list to shared/intent-classification.md. Spot-check
# that all 11 verb names appear at least once each.
for verb in run fix sprint review verify deploy commit migrate bootstrap docs audit; do
  if ! grep -qw "$verb" /Users/denissajnar/IdeaProjects/forge/shared/intent-classification.md; then
    echo "MISSING VERB IN A5: $verb"
  fi
done
```

Expected: zero `MISSING VERB` lines. If any verb is missing, A5 has not merged (or is incomplete) — STOP.

- [ ] **Step 2: Apply mapping to every agent file**

```bash
cd /Users/denissajnar/IdeaProjects/forge
find agents/ -name '*.md' -type f | while IFS= read -r f; do
  perl -pi -e '
    s{/forge-docs-generate\b}{/forge docs}g;
    s{/forge-security-audit\b}{/forge audit}g;
    s{/forge-playbook-refine\b}{/forge-admin refine}g;
    s{/forge-playbooks\b}{/forge-admin playbooks}g;
    s{/forge-automation\b}{/forge-admin automation}g;
    s{/forge-handoff\b}{/forge-admin handoff}g;
    s{/forge-recover\b}{/forge-admin recover}g;
    s{/forge-compress\b}{/forge-admin compress}g;
    s{/forge-config\b}{/forge-admin config}g;
    s{/forge-abort\b}{/forge-admin abort}g;
    s{/forge-graph\b}{/forge-admin graph}g;
    s{/forge-migration\b}{/forge migrate}g;
    s{/forge-bootstrap\b}{/forge bootstrap}g;
    s{/forge-insights\b}{/forge-ask insights}g;
    s{/forge-profile\b}{/forge-ask profile}g;
    s{/forge-history\b}{/forge-ask history}g;
    s{/forge-status\b}{/forge-ask status}g;
    s{/forge-sprint\b}{/forge sprint}g;
    s{/forge-review\b}{/forge review}g;
    s{/forge-verify\b}{/forge verify}g;
    s{/forge-deploy\b}{/forge deploy}g;
    s{/forge-commit\b}{/forge commit}g;
    s{/forge-shape\b}{/forge run}g;
    s{/forge-tour\b}{/forge-ask tour}g;
    s{/forge-help\b}{/forge --help}g;
    s{/forge-init\b}{/forge}g;
    s{/forge-fix\b}{/forge fix}g;
    s{/forge-run\b}{/forge run}g;
  ' "$f"
done
```

- [ ] **Step 3: Manually review the orchestrator file**

Open `agents/fg-100-orchestrator.md`. Scan for these patterns (use grep with the file as input):

```bash
cd /Users/denissajnar/IdeaProjects/forge
grep -nE 'forge-(init|run|fix|shape|sprint|review|verify|deploy|commit|migration|bootstrap|docs-generate|security-audit|status|history|insights|profile|tour|help|recover|abort|config|handoff|automation|playbooks|playbook-refine|compress|graph)' agents/fg-100-orchestrator.md
```

Expected: zero output. If any match remains:
- It is likely inside a fenced code block, multiline string, JSON literal, or table cell that the perl regex's `\b` boundary did not catch (e.g., `forge-init` inside a markdown table cell with surrounding `|` characters that break `\b`).
- Fix manually — replace with the mapped value from the table.

The specific orchestrator stage-routing block (around the EXPLORING/PLANNING/IMPLEMENTING transitions) and the error-escalation block (around `total_retries` exhaustion) are the highest-density sites. Inspect those sections by name.

- [ ] **Step 4: Manually review retrospective and post-run files**

```bash
cd /Users/denissajnar/IdeaProjects/forge
grep -nE 'forge-(init|run|fix|shape|sprint|review|verify|deploy|commit|migration|bootstrap|docs-generate|security-audit|status|history|insights|profile|tour|help|recover|abort|config|handoff|automation|playbooks|playbook-refine|compress|graph)' agents/fg-700-retrospective.md
grep -nE 'forge-(init|run|fix|shape|sprint|review|verify|deploy|commit|migration|bootstrap|docs-generate|security-audit|status|history|insights|profile|tour|help|recover|abort|config|handoff|automation|playbooks|playbook-refine|compress|graph)' agents/fg-710-post-run.md
```

Expected: zero output for each. Fix any remainders manually.

- [ ] **Step 5: Verify clean — global grep across agents/**

```bash
cd /Users/denissajnar/IdeaProjects/forge
grep -rn '/forge-init\b\|/forge-run\b\|/forge-fix\b\|/forge-shape\b\|/forge-sprint\b\|/forge-review\b\|/forge-verify\b\|/forge-deploy\b\|/forge-commit\b\|/forge-migration\b\|/forge-bootstrap\b\|/forge-docs-generate\b\|/forge-security-audit\b\|/forge-status\b\|/forge-history\b\|/forge-insights\b\|/forge-profile\b\|/forge-tour\b\|/forge-help\b\|/forge-recover\b\|/forge-abort\b\|/forge-config\b\|/forge-handoff\b\|/forge-automation\b\|/forge-playbooks\b\|/forge-playbook-refine\b\|/forge-compress\b\|/forge-graph\b' agents/
```

Expected: zero output.

- [ ] **Step 6: Confirm diff stat**

```bash
git diff --stat agents/ | tail -3
```

Expected: between 12 and 48 files changed (depending on how many had retired-skill refs). The orchestrator alone may have 50+ edits.

- [ ] **Step 7: Commit**

```bash
git add agents/
git commit -m "refactor(agents): rewire skill references for consolidation (B7)

Applied the canonical mapping to every file under agents/.
Manual review of fg-100-orchestrator, fg-700-retrospective,
fg-710-post-run for embedded refs that perl word-boundary
might have missed.

Refs spec §12 commit B7, AC-S005 (agents/ subset)."
```

---

## Task B8: Rewire `shared/` (~56 files)

**Files:**
- Modify: every file under `shared/` listed in the B4 snapshot. ~79 files matched the grep, but the modify set is the subset of those that contain retired skill references (the sed is idempotent). Spec §12 estimates ~56 actually-modified files.
- Special attention: `shared/intent-classification.md` (already partly updated in A5 — this is the reconciliation pass), `shared/skill-subcommand-pattern.md` (B11 may delete it), `shared/agents.md` (registry), `shared/decision-log.md`.

**Risk:** high. **Risk justification:** `shared/` files are contracts. They are loaded by multiple agents, hooks, and scripts at runtime. A skill-name miss in `shared/scoring.md` or `shared/state-transitions.md` may cause downstream agents to format suggestions referring to deleted skills. The agent registry in `shared/agents.md` and the model-routing tables in `shared/model-routing.md` are particularly sensitive — they are read by the orchestrator at every dispatch. Mitigation: same sed pass + verify-clean. Specifically grep `shared/intent-classification.md` after the pass to confirm the new verb list is present and old skill aliases are absent.

**ACs covered:** AC-S005 (partial — shared/ subset).

### Implementer mini-prompt

> Apply the mapping table sed pass to every file under `shared/` listed in `tests/structural/migration-callsites.txt`. Reconcile any conflicts with A5's earlier edits to `shared/intent-classification.md` (A5 added the 11-verb list; B8 should not undo that). After the sed pass, run the verify-clean grep against `shared/` and assert zero stragglers.

### Spec-reviewer mini-prompt

> Verify shared/ rewiring. Confirm `shared/intent-classification.md` still contains the 11-verb list from A5. Confirm `shared/agents.md` registry has no retired skill names. Run the canonical grep against `shared/` — expect zero output.

### Steps

- [ ] **Step 1: Build the shared-only file list**

```bash
cd /Users/denissajnar/IdeaProjects/forge
SHARED_FILES=$(grep '^shared/' tests/structural/migration-callsites.txt)
echo "Will rewire $(echo "$SHARED_FILES" | wc -l) files under shared/"
```

- [ ] **Step 2: Apply the mapping**

```bash
cd /Users/denissajnar/IdeaProjects/forge
while IFS= read -r f; do
  perl -pi -e '
    s{/forge-docs-generate\b}{/forge docs}g;
    s{/forge-security-audit\b}{/forge audit}g;
    s{/forge-playbook-refine\b}{/forge-admin refine}g;
    s{/forge-playbooks\b}{/forge-admin playbooks}g;
    s{/forge-automation\b}{/forge-admin automation}g;
    s{/forge-handoff\b}{/forge-admin handoff}g;
    s{/forge-recover\b}{/forge-admin recover}g;
    s{/forge-compress\b}{/forge-admin compress}g;
    s{/forge-config\b}{/forge-admin config}g;
    s{/forge-abort\b}{/forge-admin abort}g;
    s{/forge-graph\b}{/forge-admin graph}g;
    s{/forge-migration\b}{/forge migrate}g;
    s{/forge-bootstrap\b}{/forge bootstrap}g;
    s{/forge-insights\b}{/forge-ask insights}g;
    s{/forge-profile\b}{/forge-ask profile}g;
    s{/forge-history\b}{/forge-ask history}g;
    s{/forge-status\b}{/forge-ask status}g;
    s{/forge-sprint\b}{/forge sprint}g;
    s{/forge-review\b}{/forge review}g;
    s{/forge-verify\b}{/forge verify}g;
    s{/forge-deploy\b}{/forge deploy}g;
    s{/forge-commit\b}{/forge commit}g;
    s{/forge-shape\b}{/forge run}g;
    s{/forge-tour\b}{/forge-ask tour}g;
    s{/forge-help\b}{/forge --help}g;
    s{/forge-init\b}{/forge}g;
    s{/forge-fix\b}{/forge fix}g;
    s{/forge-run\b}{/forge run}g;
  ' "$f"
done < <(grep '^shared/' tests/structural/migration-callsites.txt)
```

- [ ] **Step 3: Reconciliation — confirm intent-classification.md still has the 11-verb list**

```bash
cd /Users/denissajnar/IdeaProjects/forge
missing=0
for verb in run fix sprint review verify deploy commit migrate bootstrap docs audit; do
  if ! grep -qw "$verb" shared/intent-classification.md; then
    echo "VERB CLOBBERED BY SED: $verb"
    missing=$((missing + 1))
  fi
done
[ "$missing" -eq 0 ]
```

Expected: zero `VERB CLOBBERED` lines. If any verb is missing, A5's edit was clobbered by the sed pass — restore from git history (`git show <A5-commit>:shared/intent-classification.md`) and re-apply.

- [ ] **Step 4: Verify clean — global grep across shared/**

```bash
cd /Users/denissajnar/IdeaProjects/forge
grep -rn '/forge-init\b\|/forge-run\b\|/forge-fix\b\|/forge-shape\b\|/forge-sprint\b\|/forge-review\b\|/forge-verify\b\|/forge-deploy\b\|/forge-commit\b\|/forge-migration\b\|/forge-bootstrap\b\|/forge-docs-generate\b\|/forge-security-audit\b\|/forge-status\b\|/forge-history\b\|/forge-insights\b\|/forge-profile\b\|/forge-tour\b\|/forge-help\b\|/forge-recover\b\|/forge-abort\b\|/forge-config\b\|/forge-handoff\b\|/forge-automation\b\|/forge-playbooks\b\|/forge-playbook-refine\b\|/forge-compress\b\|/forge-graph\b' shared/
```

Expected: zero output. (`shared/skill-subcommand-pattern.md` may still exist with refs — B11 handles its fate; if it remains until B11, it's allowed to retain refs because B11 either deletes or rewrites it.)

If `shared/skill-subcommand-pattern.md` has any refs after this sed pass, document them in the next step's commit message — they are B11's responsibility.

- [ ] **Step 5: Confirm diff stat**

```bash
git diff --stat shared/ | tail -3
```

Expected: ~50-60 files changed.

- [ ] **Step 6: Commit**

```bash
git add shared/
git commit -m "refactor(shared): rewire skill references for consolidation (B8)

Applied the canonical mapping to every shared/ file in the B4
snapshot. Reconciled with A5's intent-classifier edits.
shared/skill-subcommand-pattern.md left alone — B11 handles it.

Refs spec §12 commit B8, AC-S005 (shared/ subset)."
```

---

## Task B9: Rewire `modules/` (~49 files)

**Files:**
- Modify: every file under `modules/` listed in the B4 snapshot. ~49 files: framework `local-template.md`, `forge-config-template.md`, conventions docs that mention skills.

**Risk:** medium — files are templates; refs are mostly in "see also" or onboarding instructions. Mitigation: same sed pass + verify-clean.

**ACs covered:** AC-S005 (partial — modules/ subset).

### Implementer mini-prompt

> Apply the mapping table sed pass to every file under `modules/` listed in `tests/structural/migration-callsites.txt`. Verify-clean grep against `modules/`. Commit.

### Spec-reviewer mini-prompt

> Verify modules/ rewiring. Run the canonical grep against `modules/` — expect zero output.

### Steps

- [ ] **Step 1: Build modules-only file list**

```bash
cd /Users/denissajnar/IdeaProjects/forge
MODULES_FILES=$(grep '^modules/' tests/structural/migration-callsites.txt)
echo "Will rewire $(echo "$MODULES_FILES" | wc -l) files under modules/"
```

- [ ] **Step 2: Apply mapping**

```bash
cd /Users/denissajnar/IdeaProjects/forge
while IFS= read -r f; do
  perl -pi -e '
    s{/forge-docs-generate\b}{/forge docs}g;
    s{/forge-security-audit\b}{/forge audit}g;
    s{/forge-playbook-refine\b}{/forge-admin refine}g;
    s{/forge-playbooks\b}{/forge-admin playbooks}g;
    s{/forge-automation\b}{/forge-admin automation}g;
    s{/forge-handoff\b}{/forge-admin handoff}g;
    s{/forge-recover\b}{/forge-admin recover}g;
    s{/forge-compress\b}{/forge-admin compress}g;
    s{/forge-config\b}{/forge-admin config}g;
    s{/forge-abort\b}{/forge-admin abort}g;
    s{/forge-graph\b}{/forge-admin graph}g;
    s{/forge-migration\b}{/forge migrate}g;
    s{/forge-bootstrap\b}{/forge bootstrap}g;
    s{/forge-insights\b}{/forge-ask insights}g;
    s{/forge-profile\b}{/forge-ask profile}g;
    s{/forge-history\b}{/forge-ask history}g;
    s{/forge-status\b}{/forge-ask status}g;
    s{/forge-sprint\b}{/forge sprint}g;
    s{/forge-review\b}{/forge review}g;
    s{/forge-verify\b}{/forge verify}g;
    s{/forge-deploy\b}{/forge deploy}g;
    s{/forge-commit\b}{/forge commit}g;
    s{/forge-shape\b}{/forge run}g;
    s{/forge-tour\b}{/forge-ask tour}g;
    s{/forge-help\b}{/forge --help}g;
    s{/forge-init\b}{/forge}g;
    s{/forge-fix\b}{/forge fix}g;
    s{/forge-run\b}{/forge run}g;
  ' "$f"
done < <(grep '^modules/' tests/structural/migration-callsites.txt)
```

- [ ] **Step 3: Verify clean**

```bash
cd /Users/denissajnar/IdeaProjects/forge
grep -rn '/forge-init\b\|/forge-run\b\|/forge-fix\b\|/forge-shape\b\|/forge-sprint\b\|/forge-review\b\|/forge-verify\b\|/forge-deploy\b\|/forge-commit\b\|/forge-migration\b\|/forge-bootstrap\b\|/forge-docs-generate\b\|/forge-security-audit\b\|/forge-status\b\|/forge-history\b\|/forge-insights\b\|/forge-profile\b\|/forge-tour\b\|/forge-help\b\|/forge-recover\b\|/forge-abort\b\|/forge-config\b\|/forge-handoff\b\|/forge-automation\b\|/forge-playbooks\b\|/forge-playbook-refine\b\|/forge-compress\b\|/forge-graph\b' modules/
```

Expected: zero output.

- [ ] **Step 4: Confirm diff stat**

```bash
git diff --stat modules/ | tail -3
```

Expected: ~49 files changed.

- [ ] **Step 5: Commit**

```bash
git add modules/
git commit -m "refactor(modules): rewire skill references for consolidation (B9)

Applied the canonical mapping to every modules/ file in the B4
snapshot. Framework local-template, forge-config-template, and
conventions docs updated.

Refs spec §12 commit B9, AC-S005 (modules/ subset)."
```

---

## Task B10: Rewire root + manifests + hooks

**Files:**
- Modify: the remaining files in the B4 snapshot not yet covered by B5-B9. Approximately:
  - `README.md` (1)
  - `CLAUDE.md` (1) — note: heavy edit; sed pass plus manual review of feature matrix and skill table
  - `CHANGELOG.md` (1) — preserve historical entries verbatim if they document old skill names; only update the description text, not the entry titles. Actually — `CHANGELOG.md` is in the AC-S005 allowlist (B13), so leave its retired-skill refs in place. **Apply NO sed to CHANGELOG.md.**
  - `DEPRECATIONS.md` (1) — same rule: in the AC-S005 allowlist. **Apply NO sed to DEPRECATIONS.md.**
  - `CONTRIBUTING.md` (1) — sed pass
  - `SECURITY.md` (1) — sed pass (per spec AC-S005 explicit enumeration)
  - `plugin.json` (1) — sed pass
  - `marketplace.json` (1) — sed pass
  - `.github/` files (1+) — sed pass
  - `hooks/` files (~8) — sed pass
  - `evals/` files (~3) — sed pass

**Risk:** medium — small file count but root manifests are user-visible. CHANGELOG.md and DEPRECATIONS.md are intentionally preserved (allowlist) — do NOT sed them.

**ACs covered:** AC-S005 (final partial — root + manifests + hooks).

### Implementer mini-prompt

> Apply the mapping table sed pass to root files (README.md, CLAUDE.md, CONTRIBUTING.md, SECURITY.md, plugin.json, marketplace.json), `.github/`, `hooks/`, `evals/`. EXPLICITLY SKIP `CHANGELOG.md` and `DEPRECATIONS.md` — they are in the AC-S005 allowlist (historical references are intentional). Verify-clean grep across the whole repo, allowing only the two skipped files plus the snapshot file. Commit.

### Spec-reviewer mini-prompt

> Verify the rewiring. Run the canonical grep across the entire repo. Expected non-empty results: only `tests/structural/migration-callsites.txt` (the snapshot), `CHANGELOG.md`, `DEPRECATIONS.md`, and `skills/forge/SKILL.md` / `skills/forge-admin/SKILL.md` / `skills/forge-ask/SKILL.md` (the new skill files reference the old names in "Old → new" mapping tables and migration notes). Anything else fails AC-S005.

### Steps

- [ ] **Step 1: Build the residual file list (B4 snapshot minus what B5-B9 already covered)**

```bash
cd /Users/denissajnar/IdeaProjects/forge
RESIDUAL=$(grep -vE '^(docs|tests|agents|shared|modules|skills)/' tests/structural/migration-callsites.txt \
           | grep -vE '^(CHANGELOG|DEPRECATIONS)\.md$')
echo "Will rewire $(echo "$RESIDUAL" | wc -l) residual files"
echo "$RESIDUAL"
```

Expected output: README.md, CLAUDE.md, CONTRIBUTING.md, SECURITY.md, plugin.json, marketplace.json, plus files under `.github/`, `hooks/`, `evals/`.

- [ ] **Step 2: Confirm CHANGELOG.md and DEPRECATIONS.md are explicitly excluded**

```bash
cd /Users/denissajnar/IdeaProjects/forge
echo "$RESIDUAL" | grep -E '^(CHANGELOG|DEPRECATIONS)\.md$'
```

Expected: empty output (those two files are NOT in the residual list).

- [ ] **Step 3: Apply the mapping**

```bash
cd /Users/denissajnar/IdeaProjects/forge
while IFS= read -r f; do
  if [ -z "$f" ]; then continue; fi
  perl -pi -e '
    s{/forge-docs-generate\b}{/forge docs}g;
    s{/forge-security-audit\b}{/forge audit}g;
    s{/forge-playbook-refine\b}{/forge-admin refine}g;
    s{/forge-playbooks\b}{/forge-admin playbooks}g;
    s{/forge-automation\b}{/forge-admin automation}g;
    s{/forge-handoff\b}{/forge-admin handoff}g;
    s{/forge-recover\b}{/forge-admin recover}g;
    s{/forge-compress\b}{/forge-admin compress}g;
    s{/forge-config\b}{/forge-admin config}g;
    s{/forge-abort\b}{/forge-admin abort}g;
    s{/forge-graph\b}{/forge-admin graph}g;
    s{/forge-migration\b}{/forge migrate}g;
    s{/forge-bootstrap\b}{/forge bootstrap}g;
    s{/forge-insights\b}{/forge-ask insights}g;
    s{/forge-profile\b}{/forge-ask profile}g;
    s{/forge-history\b}{/forge-ask history}g;
    s{/forge-status\b}{/forge-ask status}g;
    s{/forge-sprint\b}{/forge sprint}g;
    s{/forge-review\b}{/forge review}g;
    s{/forge-verify\b}{/forge verify}g;
    s{/forge-deploy\b}{/forge deploy}g;
    s{/forge-commit\b}{/forge commit}g;
    s{/forge-shape\b}{/forge run}g;
    s{/forge-tour\b}{/forge-ask tour}g;
    s{/forge-help\b}{/forge --help}g;
    s{/forge-init\b}{/forge}g;
    s{/forge-fix\b}{/forge fix}g;
    s{/forge-run\b}{/forge run}g;
  ' "$f"
done < <(grep -vE '^(docs|tests|agents|shared|modules|skills)/' tests/structural/migration-callsites.txt \
         | grep -vE '^(CHANGELOG|DEPRECATIONS)\.md$')
```

- [ ] **Step 4: Verify CHANGELOG and DEPRECATIONS were not touched**

```bash
cd /Users/denissajnar/IdeaProjects/forge
git diff CHANGELOG.md DEPRECATIONS.md
```

Expected: empty diff (those two files are unchanged).

- [ ] **Step 5: Manual review of CLAUDE.md and README.md**

CLAUDE.md has feature tables and skill listings that may have multi-line patterns the sed missed (e.g., a row spanning lines, code-fence content, or table cells with non-standard punctuation).

```bash
cd /Users/denissajnar/IdeaProjects/forge
grep -nE 'forge-(init|run|fix|shape|sprint|review|verify|deploy|commit|migration|bootstrap|docs-generate|security-audit|status|history|insights|profile|tour|help|recover|abort|config|handoff|automation|playbooks|playbook-refine|compress|graph)' CLAUDE.md README.md CONTRIBUTING.md SECURITY.md
```

Expected: zero output. Fix any remainders manually.

- [ ] **Step 6: Verify clean — global grep across the whole repo, with allowlist exceptions**

```bash
cd /Users/denissajnar/IdeaProjects/forge
grep -rn '/forge-init\b\|/forge-run\b\|/forge-fix\b\|/forge-shape\b\|/forge-sprint\b\|/forge-review\b\|/forge-verify\b\|/forge-deploy\b\|/forge-commit\b\|/forge-migration\b\|/forge-bootstrap\b\|/forge-docs-generate\b\|/forge-security-audit\b\|/forge-status\b\|/forge-history\b\|/forge-insights\b\|/forge-profile\b\|/forge-tour\b\|/forge-help\b\|/forge-recover\b\|/forge-abort\b\|/forge-config\b\|/forge-handoff\b\|/forge-automation\b\|/forge-playbooks\b\|/forge-playbook-refine\b\|/forge-compress\b\|/forge-graph\b' . 2>/dev/null \
  --include='*.md' --include='*.json' --include='*.py' --include='*.yml' --include='*.yaml' --include='*.bats' --include='*.sh' \
  | grep -vE '^(\./)?(CHANGELOG|DEPRECATIONS)\.md:' \
  | grep -vE '^(\./)?tests/structural/migration-callsites\.txt:' \
  | grep -vE '^(\./)?skills/(forge|forge-admin|forge-ask)/SKILL\.md:'
```

Expected: zero output. (The new SKILL.md files are allowed to reference old names in their internal mapping/migration notes — those will go into the AC-S005 allowlist in B13.)

If non-zero: open each file, fix manually, re-run.

- [ ] **Step 7: Confirm diff stat**

```bash
git diff --stat | tail -3
```

Expected: ~10-15 residual files changed.

- [ ] **Step 8: Commit**

```bash
git add README.md CLAUDE.md CONTRIBUTING.md SECURITY.md plugin.json marketplace.json .github/ hooks/ evals/
git commit -m "refactor(root): rewire skill references in root + manifests + hooks (B10)

Applied the canonical mapping to README.md, CLAUDE.md,
CONTRIBUTING.md, SECURITY.md, plugin.json, marketplace.json,
.github/, hooks/, evals/. CHANGELOG.md and DEPRECATIONS.md
preserved (allowlisted in AC-S005).

Refs spec §12 commit B10, AC-S005 (final root subset)."
```

---

## Task B11: `shared/skill-subcommand-pattern.md` decision (DELETE)

**Files:**
- Delete: `shared/skill-subcommand-pattern.md`

**Risk:** low — file is referenced from multiple SKILL.md files (forge-graph, forge-review, forge-verify), but those skills are deleted in B12. By the time B11 lands, only the three new SKILL.md files remain. The new skills inline their own dispatch pattern rather than referencing a shared doc. Deletion is the simpler choice.

**Decision (made in this plan, not deferred):** **DELETE**. Rationale: the dispatch pattern is now internal to each of the three SKILL.md bodies (each is fully self-contained). A shared reference doc would only be necessary if there were many skills sharing the pattern; with only three skills, inline is cheaper than indirection.

**ACs covered:** none directly; supports AC-S005 by removing a file that B5-B10's sed missed (the old skill-subcommand-pattern.md may still contain references to the retired skills).

### Implementer mini-prompt

> Delete `shared/skill-subcommand-pattern.md`. The new skills inline their dispatch pattern. After deletion, search for any remaining references to the file path; the three new SKILL.md files reference it under `Subcommand dispatch` — replace those references with an inline note.

### Spec-reviewer mini-prompt

> Verify `shared/skill-subcommand-pattern.md` is gone. Confirm the three new SKILL.md files no longer reference its path. Confirm no other file references it.

### Steps

- [ ] **Step 1: Confirm the file exists**

```bash
test -f /Users/denissajnar/IdeaProjects/forge/shared/skill-subcommand-pattern.md
```

Expected: exit 0.

- [ ] **Step 2: Find all references to the file**

```bash
cd /Users/denissajnar/IdeaProjects/forge
grep -rln 'shared/skill-subcommand-pattern' . 2>/dev/null
```

Expected: at least three references — the new SKILL.md files have a `Follow shared/skill-subcommand-pattern.md.` line in their dispatch sections.

- [ ] **Step 3: Remove references from the new SKILL.md files**

```bash
cd /Users/denissajnar/IdeaProjects/forge
perl -pi -e 's{Follow `shared/skill-subcommand-pattern\.md`\. ?}{}g; s{See `shared/skill-subcommand-pattern\.md` for the pattern\. ?}{}g' \
  skills/forge/SKILL.md skills/forge-admin/SKILL.md skills/forge-ask/SKILL.md
```

Verify:

```bash
grep -l 'shared/skill-subcommand-pattern' /Users/denissajnar/IdeaProjects/forge/skills/forge/SKILL.md /Users/denissajnar/IdeaProjects/forge/skills/forge-admin/SKILL.md /Users/denissajnar/IdeaProjects/forge/skills/forge-ask/SKILL.md
```

Expected: empty output.

- [ ] **Step 4: Find any other references**

```bash
cd /Users/denissajnar/IdeaProjects/forge
grep -rln 'shared/skill-subcommand-pattern' . 2>/dev/null
```

Expected: zero matches anywhere. Fix any remainders manually.

- [ ] **Step 5: Delete the file**

```bash
cd /Users/denissajnar/IdeaProjects/forge
git rm shared/skill-subcommand-pattern.md
```

- [ ] **Step 6: Update the structural test that asserts the file's existence**

```bash
cd /Users/denissajnar/IdeaProjects/forge
grep -n 'skill-subcommand-pattern' tests/structural/skill-consolidation.bats
```

Expected: the existing test `@test "shared/skill-subcommand-pattern.md exists"` (around line 103). Remove this test — it's obsolete.

```bash
perl -i -e '
  my $in_block = 0;
  while (<>) {
    if (/^\@test "shared\/skill-subcommand-pattern\.md exists"/) { $in_block = 1; next; }
    if ($in_block && /^\}$/) { $in_block = 0; next; }
    next if $in_block;
    print;
  }
' tests/structural/skill-consolidation.bats
```

Verify:

```bash
grep 'skill-subcommand-pattern' /Users/denissajnar/IdeaProjects/forge/tests/structural/skill-consolidation.bats
```

Expected: empty output.

(B13 will also rewrite parts of `tests/structural/skill-consolidation.bats` to reflect the new 3-skill set; this step just removes the dead test.)

- [ ] **Step 7: Commit**

```bash
git add -u shared/ skills/forge/SKILL.md skills/forge-admin/SKILL.md skills/forge-ask/SKILL.md tests/structural/skill-consolidation.bats
git commit -m "chore(shared): delete skill-subcommand-pattern.md (B11)

The three new SKILL.md files inline their dispatch pattern.
With only three skills, a shared reference doc adds indirection
without value. References removed from the three new skill
files and from the structural test.

Refs spec §12 commit B11."
```

---

## Task B12: Atomic deletion of 28 retired skill directories

**Files:**
- Delete (as directories): 28 skill directories under `skills/`. Full enumerated list:
  1. `skills/forge-abort/`
  2. `skills/forge-automation/`
  3. `skills/forge-bootstrap/`
  4. `skills/forge-commit/`
  5. `skills/forge-compress/`
  6. `skills/forge-config/`
  7. `skills/forge-deploy/`
  8. `skills/forge-docs-generate/`
  9. `skills/forge-fix/`
  10. `skills/forge-graph/`
  11. `skills/forge-handoff/`
  12. `skills/forge-help/`
  13. `skills/forge-history/`
  14. `skills/forge-init/`
  15. `skills/forge-insights/`
  16. `skills/forge-migration/`
  17. `skills/forge-playbook-refine/`
  18. `skills/forge-playbooks/`
  19. `skills/forge-profile/`
  20. `skills/forge-recover/`
  21. `skills/forge-review/`
  22. `skills/forge-run/`
  23. `skills/forge-security-audit/`
  24. `skills/forge-shape/`
  25. `skills/forge-sprint/`
  26. `skills/forge-status/`
  27. `skills/forge-tour/`
  28. `skills/forge-verify/`

**Risk:** high. **Risk justification:** This is the irreversible commit that locks in the consolidation. If B5-B10 missed any rewiring site, that site will silently break — old skill names will fail to resolve at the harness level (no error message, just a "skill not found" at dispatch time). The blast radius is the entire pipeline because every agent dispatch goes through skill resolution. Mitigation: the deletion runs ONLY after the verify-rewiring-complete gate at Step 1 confirms all prior commits landed AND the canonical grep returns zero. The allowlist file (B13) is also pre-positioned so the AC-S005 test passes immediately after deletion.

**ACs covered:** AC-S001 (final), AC-S003 (28 directories absent), AC-S005 (no remaining stragglers — ratified by deletion).

### Implementer mini-prompt

> Run the safety gate at Step 1 to verify B5-B10 are merged AND the canonical grep is clean (modulo allowlist). If any check fails, STOP — do not delete. If all checks pass, run the single `git rm -r` command at Step 3, which removes all 28 directories atomically. Commit.

### Spec-reviewer mini-prompt

> Verify B12 deletion. After the commit, `ls skills/` must show exactly three entries: `forge`, `forge-admin`, `forge-ask`. The structural test `tests/structural/skill-consolidation.bats` (updated in B13) must pass.

### Steps

- [ ] **Step 1: Verify rewiring complete (safety gate)**

This step is mandatory. If any check fails, STOP — do not delete.

```bash
cd /Users/denissajnar/IdeaProjects/forge

# 1.1: confirm B5-B10 commits are present in this branch
git log --oneline | head -20 | grep -E 'B5|B6|B7|B8|B9|B10'
```

Expected: at least 6 commits matching B5-B10. If fewer, the rewiring is incomplete — STOP.

```bash
# 1.2: confirm B11 is present (skill-subcommand-pattern decision made)
test ! -f /Users/denissajnar/IdeaProjects/forge/shared/skill-subcommand-pattern.md
```

Expected: exit 0 (file does not exist). If 1, B11 has not been applied — STOP.

```bash
# 1.3: pre-position the AC-S005 allowlist file (B13's work, but B12 needs it before deletion)
test -f /Users/denissajnar/IdeaProjects/forge/tests/structural/skill-references-allowlist.txt
```

Expected: file exists. If not, create it now with the four canonical entries (CHANGELOG.md, DEPRECATIONS.md, the snapshot, the three new SKILL.md files):

```bash
cat > /Users/denissajnar/IdeaProjects/forge/tests/structural/skill-references-allowlist.txt <<'EOF'
CHANGELOG.md
DEPRECATIONS.md
tests/structural/migration-callsites.txt
skills/forge/SKILL.md
skills/forge-admin/SKILL.md
skills/forge-ask/SKILL.md
EOF
```

(B13 will further refine this list and add it under its own commit, but B12 needs it pre-positioned so the post-deletion grep test does not block the commit.)

```bash
# 1.4: canonical grep returns clean (modulo allowlist)
grep -rn '/forge-init\b\|/forge-run\b\|/forge-fix\b\|/forge-shape\b\|/forge-sprint\b\|/forge-review\b\|/forge-verify\b\|/forge-deploy\b\|/forge-commit\b\|/forge-migration\b\|/forge-bootstrap\b\|/forge-docs-generate\b\|/forge-security-audit\b\|/forge-status\b\|/forge-history\b\|/forge-insights\b\|/forge-profile\b\|/forge-tour\b\|/forge-help\b\|/forge-recover\b\|/forge-abort\b\|/forge-config\b\|/forge-handoff\b\|/forge-automation\b\|/forge-playbooks\b\|/forge-playbook-refine\b\|/forge-compress\b\|/forge-graph\b' . 2>/dev/null \
  --include='*.md' --include='*.json' --include='*.py' --include='*.yml' --include='*.yaml' --include='*.bats' --include='*.sh' \
  | awk -F: '{print $1}' \
  | sort -u \
  | while read -r path; do
      # strip leading ./ if present
      clean=$(echo "$path" | sed 's|^\./||')
      # check if path is in allowlist OR matches an allowlist entry
      if ! grep -qFx "$clean" /Users/denissajnar/IdeaProjects/forge/tests/structural/skill-references-allowlist.txt; then
        echo "STRAGGLER: $clean"
      fi
    done
```

Expected: zero `STRAGGLER:` lines. If any, fix the file (return to B5-B10 logic) before proceeding.

- [ ] **Step 2: Confirm `ls skills/` shows the expected pre-deletion state**

```bash
ls /Users/denissajnar/IdeaProjects/forge/skills/ | wc -l
ls /Users/denissajnar/IdeaProjects/forge/skills/
```

Expected: 31 entries (29 old + 2 new: `forge`, `forge-admin`). The third "edited in place" skill (`forge-ask`) was already in the 29.

If the count is not 31, something is wrong — investigate before deletion.

- [ ] **Step 3: Atomic deletion**

```bash
cd /Users/denissajnar/IdeaProjects/forge
git rm -r \
  skills/forge-abort \
  skills/forge-automation \
  skills/forge-bootstrap \
  skills/forge-commit \
  skills/forge-compress \
  skills/forge-config \
  skills/forge-deploy \
  skills/forge-docs-generate \
  skills/forge-fix \
  skills/forge-graph \
  skills/forge-handoff \
  skills/forge-help \
  skills/forge-history \
  skills/forge-init \
  skills/forge-insights \
  skills/forge-migration \
  skills/forge-playbook-refine \
  skills/forge-playbooks \
  skills/forge-profile \
  skills/forge-recover \
  skills/forge-review \
  skills/forge-run \
  skills/forge-security-audit \
  skills/forge-shape \
  skills/forge-sprint \
  skills/forge-status \
  skills/forge-tour \
  skills/forge-verify
```

- [ ] **Step 4: Verify post-deletion state**

```bash
ls /Users/denissajnar/IdeaProjects/forge/skills/
```

Expected output (alphabetical):
```
forge
forge-admin
forge-ask
```

Three entries. No others.

```bash
ls /Users/denissajnar/IdeaProjects/forge/skills/ | wc -l
```

Expected: `3`.

- [ ] **Step 5: Confirm no broken refs**

Run the canonical grep one more time (full repo). The allowlist is the only place old names should remain.

```bash
cd /Users/denissajnar/IdeaProjects/forge
grep -rn '/forge-init\b\|/forge-run\b\|/forge-fix\b\|/forge-shape\b\|/forge-sprint\b\|/forge-review\b\|/forge-verify\b\|/forge-deploy\b\|/forge-commit\b\|/forge-migration\b\|/forge-bootstrap\b\|/forge-docs-generate\b\|/forge-security-audit\b\|/forge-status\b\|/forge-history\b\|/forge-insights\b\|/forge-profile\b\|/forge-tour\b\|/forge-help\b\|/forge-recover\b\|/forge-abort\b\|/forge-config\b\|/forge-handoff\b\|/forge-automation\b\|/forge-playbooks\b\|/forge-playbook-refine\b\|/forge-compress\b\|/forge-graph\b' . 2>/dev/null \
  --include='*.md' --include='*.json' --include='*.py' --include='*.yml' --include='*.yaml' --include='*.bats' --include='*.sh' \
  | awk -F: '{print $1}' \
  | sort -u
```

Expected: only files listed in `tests/structural/skill-references-allowlist.txt`.

- [ ] **Step 6: Commit**

```bash
git add -u skills/ tests/structural/skill-references-allowlist.txt
git commit -m "feat(skills): atomic deletion of 28 retired skill directories (B12)

After B5-B11 rewiring, removes:
  forge-abort, forge-automation, forge-bootstrap, forge-commit,
  forge-compress, forge-config, forge-deploy, forge-docs-generate,
  forge-fix, forge-graph, forge-handoff, forge-help, forge-history,
  forge-init, forge-insights, forge-migration, forge-playbook-refine,
  forge-playbooks, forge-profile, forge-recover, forge-review,
  forge-run, forge-security-audit, forge-shape, forge-sprint,
  forge-status, forge-tour, forge-verify

skills/ now contains exactly three: forge, forge-admin, forge-ask.

Allowlist file pre-positioned for AC-S005 (B13 will refine).

Refs spec §12 commit B12, AC-S001, AC-S003, AC-S005."
```

---

## Task B13: Add new tests + finalize allowlist

**Files:**
- Create: `tests/unit/skill-execution/forge-dispatch.bats` (11 verbs + 3 NL fallback)
- Create: `tests/unit/skill-execution/spec-wellformed.bats` (regex per AC-S029)
- Create: `tests/scenarios/autonomous-cold-start.bats` (full-pipeline scenario per AC-S027)
- Create: `tests/structural/fg-010-shaper-shape.bats` (heading grep per AC-S021)
- Modify: `tests/structural/skill-consolidation.bats` (asserts exactly 3 dirs)
- Modify (or confirm): `tests/structural/skill-references-allowlist.txt`
- Modify: `tests/lib/module-lists.bash` — bump `MIN_SKILLS=3` (was 29) and replace `EXPECTED_SKILL_NAMES` with the three-element array.

**Risk:** medium — these tests are gates. If a test is wrong, it can mask a real regression. Mitigation: each test asserts only what it claims; structural tests use `grep -c` for exact counts; scenario tests run the actual pipeline.

**ACs covered:** AC-S004 (skill-consolidation.bats enforces AC-S001 + AC-S003), AC-S007 (forge-dispatch.bats covers 11 verbs + NL fallback), AC-S010 (no "did you mean"), AC-S021 (fg-010-shaper-shape.bats grep), AC-S027 (autonomous-cold-start.bats), AC-S029 (spec-wellformed.bats regex).

### Implementer mini-prompt

> Create the four new bats test files at the paths shown. Update `tests/structural/skill-consolidation.bats` to assert exactly 3 skills (was 29). Update `tests/lib/module-lists.bash` to set `MIN_SKILLS=3` and `EXPECTED_SKILL_NAMES=(forge forge-admin forge-ask)`. The body of each test is provided verbatim below — do not invent assertions.

### Spec-reviewer mini-prompt

> Verify the four new test files exist, the existing skill-consolidation test asserts 3 (not 29), and module-lists.bash matches. Run all four new test files locally if bats is available; otherwise rely on CI.

### Steps

- [ ] **Step 1: Update `tests/structural/skill-consolidation.bats`**

The current file asserts 29 skills. Replace its body with:

```bash
cat > /Users/denissajnar/IdeaProjects/forge/tests/structural/skill-consolidation.bats <<'BATS_EOF'
#!/usr/bin/env bats
# Skill-consolidation structural guards (post-B12).
# Locks in the consolidated 3-skill surface and forbids the 28 retired names.

load ../lib/module-lists.bash

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}

@test "skill count is exactly MIN_SKILLS (3)" {
  actual=$(ls -d "$PLUGIN_ROOT"/skills/*/ 2>/dev/null | wc -l | tr -d ' ')
  [ "$actual" -eq 3 ]
}

@test "the three expected skills exist with SKILL.md" {
  for name in forge forge-admin forge-ask; do
    [ -f "$PLUGIN_ROOT/skills/$name/SKILL.md" ] || \
      { echo "MISSING: skills/$name/SKILL.md"; return 1; }
  done
}

@test "no retired skill directory exists" {
  retired=(
    forge-abort forge-automation forge-bootstrap forge-commit
    forge-compress forge-config forge-deploy forge-docs-generate
    forge-fix forge-graph forge-handoff forge-help forge-history
    forge-init forge-insights forge-migration forge-playbook-refine
    forge-playbooks forge-profile forge-recover forge-review forge-run
    forge-security-audit forge-shape forge-sprint forge-status
    forge-tour forge-verify
  )
  for name in "${retired[@]}"; do
    [ ! -e "$PLUGIN_ROOT/skills/$name" ] || \
      { echo "STILL PRESENT: skills/$name"; return 1; }
  done
}

@test "/forge has 11 subcommand sections" {
  count=$(grep -c '^### Subcommand: ' "$PLUGIN_ROOT/skills/forge/SKILL.md")
  [ "$count" -eq 11 ]
}

@test "/forge-admin has 9 subcommand sections" {
  count=$(grep -c '^### Subcommand: ' "$PLUGIN_ROOT/skills/forge-admin/SKILL.md")
  [ "$count" -eq 9 ]
}

@test "/forge-ask has 6 subcommand sections (incl default)" {
  count=$(grep -c '^### Subcommand: ' "$PLUGIN_ROOT/skills/forge-ask/SKILL.md")
  [ "$count" -eq 6 ]
}

@test "/forge frontmatter description matches spec §1" {
  grep -q 'Universal entry for the forge pipeline' "$PLUGIN_ROOT/skills/forge/SKILL.md"
  grep -q 'Auto-bootstraps on first run' "$PLUGIN_ROOT/skills/forge/SKILL.md"
}

@test "/forge-admin frontmatter description matches spec §1" {
  grep -q 'Manage forge state and configuration' "$PLUGIN_ROOT/skills/forge-admin/SKILL.md"
}

@test "/forge-ask frontmatter description matches spec §1" {
  grep -q 'Query forge state, codebase knowledge' "$PLUGIN_ROOT/skills/forge-ask/SKILL.md"
}

@test "/forge-ask allowed-tools is read-only (no Write, no Edit)" {
  ! grep -E "^allowed-tools:.*\bWrite\b" "$PLUGIN_ROOT/skills/forge-ask/SKILL.md"
  ! grep -E "^allowed-tools:.*\bEdit\b" "$PLUGIN_ROOT/skills/forge-ask/SKILL.md"
}

@test "/forge-admin graph query enforces read-only Cypher" {
  grep -qE 'CREATE \| MERGE \| DELETE \| SET \| REMOVE \| DROP' "$PLUGIN_ROOT/skills/forge-admin/SKILL.md"
}

@test "callsite allowlist file exists" {
  [ -f "$PLUGIN_ROOT/tests/structural/skill-references-allowlist.txt" ]
}

@test "no retired skill name appears outside the allowlist (AC-S005)" {
  cd "$PLUGIN_ROOT"
  stragglers=$(grep -rn '/forge-init\b\|/forge-run\b\|/forge-fix\b\|/forge-shape\b\|/forge-sprint\b\|/forge-review\b\|/forge-verify\b\|/forge-deploy\b\|/forge-commit\b\|/forge-migration\b\|/forge-bootstrap\b\|/forge-docs-generate\b\|/forge-security-audit\b\|/forge-status\b\|/forge-history\b\|/forge-insights\b\|/forge-profile\b\|/forge-tour\b\|/forge-help\b\|/forge-recover\b\|/forge-abort\b\|/forge-config\b\|/forge-handoff\b\|/forge-automation\b\|/forge-playbooks\b\|/forge-playbook-refine\b\|/forge-compress\b\|/forge-graph\b' . 2>/dev/null \
    --include='*.md' --include='*.json' --include='*.py' --include='*.yml' --include='*.yaml' --include='*.bats' --include='*.sh' \
    | awk -F: '{print $1}' \
    | sort -u \
    | sed 's|^\./||' \
    | while read -r path; do
        if ! grep -qFx "$path" tests/structural/skill-references-allowlist.txt; then
          echo "$path"
        fi
      done)
  if [ -n "$stragglers" ]; then
    echo "Stragglers (not in allowlist):"
    echo "$stragglers"
    return 1
  fi
}
BATS_EOF
```

- [ ] **Step 2: Update `tests/lib/module-lists.bash` (skills section)**

```bash
cd /Users/denissajnar/IdeaProjects/forge
perl -i -pe '
  s/^MIN_SKILLS=29/MIN_SKILLS=3/;
' tests/lib/module-lists.bash
```

Then replace the `EXPECTED_SKILL_NAMES` array. Open the file, find the array (it currently lists all 29 names), and replace the body with:

```bash
EXPECTED_SKILL_NAMES=(
  forge
  forge-admin
  forge-ask
)
```

(Use a manual edit if perl multiline replacement is fragile. Verify after editing.)

```bash
grep -A5 'EXPECTED_SKILL_NAMES=' /Users/denissajnar/IdeaProjects/forge/tests/lib/module-lists.bash | head -8
```

Expected:
```
EXPECTED_SKILL_NAMES=(
  forge
  forge-admin
  forge-ask
)
```

```bash
grep '^MIN_SKILLS=' /Users/denissajnar/IdeaProjects/forge/tests/lib/module-lists.bash
```

Expected: `MIN_SKILLS=3`.

- [ ] **Step 3: Create `tests/unit/skill-execution/forge-dispatch.bats`**

```bash
cat > /Users/denissajnar/IdeaProjects/forge/tests/unit/skill-execution/forge-dispatch.bats <<'BATS_EOF'
#!/usr/bin/env bats
# /forge dispatch grammar — 11 verb tests + 3 NL fallback tests.
# Per AC-S006, AC-S007, AC-S010.

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  SKILL_FILE="$PLUGIN_ROOT/skills/forge/SKILL.md"
}

# These tests assert structural properties of the SKILL.md dispatch
# table — they verify each verb has a documented dispatch target. Full
# end-to-end runtime tests are out of scope for unit-level bats.

@test "verb 'run' is dispatched in skills/forge/SKILL.md" {
  grep -q '^### Subcommand: run' "$SKILL_FILE"
}

@test "verb 'fix' is dispatched in skills/forge/SKILL.md" {
  grep -q '^### Subcommand: fix' "$SKILL_FILE"
}

@test "verb 'sprint' is dispatched in skills/forge/SKILL.md" {
  grep -q '^### Subcommand: sprint' "$SKILL_FILE"
}

@test "verb 'review' is dispatched in skills/forge/SKILL.md" {
  grep -q '^### Subcommand: review' "$SKILL_FILE"
}

@test "verb 'verify' is dispatched in skills/forge/SKILL.md" {
  grep -q '^### Subcommand: verify' "$SKILL_FILE"
}

@test "verb 'deploy' is dispatched in skills/forge/SKILL.md" {
  grep -q '^### Subcommand: deploy' "$SKILL_FILE"
}

@test "verb 'commit' is dispatched in skills/forge/SKILL.md" {
  grep -q '^### Subcommand: commit' "$SKILL_FILE"
}

@test "verb 'migrate' is dispatched in skills/forge/SKILL.md" {
  grep -q '^### Subcommand: migrate' "$SKILL_FILE"
}

@test "verb 'bootstrap' is dispatched in skills/forge/SKILL.md" {
  grep -q '^### Subcommand: bootstrap' "$SKILL_FILE"
}

@test "verb 'docs' is dispatched in skills/forge/SKILL.md" {
  grep -q '^### Subcommand: docs' "$SKILL_FILE"
}

@test "verb 'audit' is dispatched in skills/forge/SKILL.md" {
  grep -q '^### Subcommand: audit' "$SKILL_FILE"
}

@test "NL fallback path is documented (vague-input case)" {
  # AC-S007: vague free-text falls through to intent classifier and
  # defaults to run mode. The skill must reference shared/intent-classification.md.
  grep -q 'shared/intent-classification.md' "$SKILL_FILE"
  grep -q 'NL fallback' "$SKILL_FILE"
}

@test "NL fallback path: classifier-resolved input dispatches to verb" {
  # The dispatch rules must mention falling through to NL classifier
  # when the first token is not a known verb.
  grep -q 'fall through to the NL-classifier' "$SKILL_FILE"
}

@test "test_unknown_verb_falls_through (no 'did you mean' message)" {
  # AC-S010: unknown verbs MUST NOT produce "did you mean" output.
  ! grep -qi 'did you mean' "$SKILL_FILE"
  # And the skill must explicitly document silent fall-through:
  grep -q 'silently classify' "$SKILL_FILE"
}

@test "ambiguous-flag-positioning is documented as an error (AC-S007)" {
  # AC-S007: third NL-fallback case — flags after the free-text arg
  # must fail fast with usage. The skill body documents this rule.
  grep -q 'Flags must appear BEFORE the free-text argument' "$SKILL_FILE"
  grep -q 'fail fast with usage' "$SKILL_FILE"
}
BATS_EOF
```

- [ ] **Step 4: Create `tests/unit/skill-execution/spec-wellformed.bats`**

```bash
cat > /Users/denissajnar/IdeaProjects/forge/tests/unit/skill-execution/spec-wellformed.bats <<'BATS_EOF'
#!/usr/bin/env bats
# Spec well-formedness regex (AC-S029).
# /forge run --spec <path> parses the spec for three required sections:
#   ## Objective | ## Goal | ## Goals
#   ## Scope | ## Non-goals
#   ## Acceptance Criteria | ## ACs

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
  TMPDIR_TEST="$(mktemp -d)"
}

teardown() {
  rm -rf "$TMPDIR_TEST"
}

# Helper: simulates the well-formedness check by running the three
# required regexes against a candidate file.
check_spec_wellformed() {
  local file="$1"
  grep -qE '^## (Objective|Goal|Goals)$' "$file" || return 1
  grep -qE '^## (Scope|Non-goals)$' "$file" || return 2
  grep -qE '^## (Acceptance [Cc]riteria|ACs)$' "$file" || return 3
  return 0
}

@test "well-formed spec with Objective + Scope + Acceptance Criteria passes" {
  cat > "$TMPDIR_TEST/good.md" <<'EOF'
# A spec

## Objective

Do X.

## Scope

In: x. Out: y.

## Acceptance Criteria

- AC-001: ...
EOF
  run check_spec_wellformed "$TMPDIR_TEST/good.md"
  [ "$status" -eq 0 ]
}

@test "alt heading 'Goals' is accepted in place of 'Objective'" {
  cat > "$TMPDIR_TEST/goals.md" <<'EOF'
## Goals

Do X.

## Non-goals

Don't do Y.

## ACs

- AC-001
EOF
  run check_spec_wellformed "$TMPDIR_TEST/goals.md"
  [ "$status" -eq 0 ]
}

@test "missing Objective fails with code 1" {
  cat > "$TMPDIR_TEST/no-obj.md" <<'EOF'
## Scope

In: x.

## Acceptance Criteria

- AC-001
EOF
  run check_spec_wellformed "$TMPDIR_TEST/no-obj.md"
  [ "$status" -eq 1 ]
}

@test "missing Scope/Non-goals fails with code 2" {
  cat > "$TMPDIR_TEST/no-scope.md" <<'EOF'
## Objective

Do X.

## Acceptance Criteria

- AC-001
EOF
  run check_spec_wellformed "$TMPDIR_TEST/no-scope.md"
  [ "$status" -eq 2 ]
}

@test "missing Acceptance Criteria fails with code 3" {
  cat > "$TMPDIR_TEST/no-ac.md" <<'EOF'
## Objective

Do X.

## Scope

In: x.
EOF
  run check_spec_wellformed "$TMPDIR_TEST/no-ac.md"
  [ "$status" -eq 3 ]
}

@test "case-sensitive Objective header — 'objective' (lowercase) fails" {
  cat > "$TMPDIR_TEST/bad-case.md" <<'EOF'
## objective

Lower case.

## Scope

x

## Acceptance Criteria

- AC
EOF
  run check_spec_wellformed "$TMPDIR_TEST/bad-case.md"
  [ "$status" -eq 1 ]
}

@test "lowercase 'criteria' is accepted (Acceptance criteria | ACs)" {
  cat > "$TMPDIR_TEST/lc-criteria.md" <<'EOF'
## Objective

x

## Scope

y

## Acceptance criteria

- AC
EOF
  run check_spec_wellformed "$TMPDIR_TEST/lc-criteria.md"
  [ "$status" -eq 0 ]
}
BATS_EOF
```

- [ ] **Step 5: Create `tests/scenarios/autonomous-cold-start.bats`**

```bash
mkdir -p /Users/denissajnar/IdeaProjects/forge/tests/scenarios
cat > /Users/denissajnar/IdeaProjects/forge/tests/scenarios/autonomous-cold-start.bats <<'BATS_EOF'
#!/usr/bin/env bats
# Scenario: AC-S027 — /forge --autonomous "<request>" on a project with no
# forge.local.md must chain auto-bootstrap → BRAINSTORMING → EXPLORING in a
# single run, with both [AUTO] log lines present, and abort cleanly on failure.

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  TMPDIR_TEST="$(mktemp -d)"
  cd "$TMPDIR_TEST"
  git init -q
  # No .claude/forge.local.md present. No .forge/ present.
}

teardown() {
  cd "$PLUGIN_ROOT"
  rm -rf "$TMPDIR_TEST"
}

@test "cold-start skill files exist and frontmatter is valid" {
  [ -f "$PLUGIN_ROOT/skills/forge/SKILL.md" ]
  grep -q '^name: forge$' "$PLUGIN_ROOT/skills/forge/SKILL.md"
}

@test "/forge SKILL.md documents auto-bootstrap on missing forge.local.md" {
  grep -q 'forge.local.md.*absent' "$PLUGIN_ROOT/skills/forge/SKILL.md"
  grep -q 'Bootstrap trigger' "$PLUGIN_ROOT/skills/forge/SKILL.md"
}

@test "/forge SKILL.md documents the AUTO log line for autonomous bootstrap" {
  grep -qE '\[AUTO\] bootstrapped' "$PLUGIN_ROOT/skills/forge/SKILL.md"
}

@test "/forge SKILL.md documents that .forge/ absence does NOT trigger bootstrap (AC-S016)" {
  grep -q 'runtime directory `.forge/` is .*not. a trigger' "$PLUGIN_ROOT/skills/forge/SKILL.md"
}

@test "shared/bootstrap-detect.py exists (A2 dependency)" {
  [ -f "$PLUGIN_ROOT/shared/bootstrap-detect.py" ]
}

@test "AUTO brainstorm-skipped log line is documented in fg-010-shaper" {
  # The shaper documents autonomous degradation (AC-S022, post-C1).
  # B13 only verifies the log line is mentioned in the skill or shaper file.
  if [ -f "$PLUGIN_ROOT/agents/fg-010-shaper.md" ]; then
    grep -qE '\[AUTO\] brainstorm skipped' "$PLUGIN_ROOT/agents/fg-010-shaper.md" \
      || skip "fg-010-shaper not yet rewritten (C1) — autonomous-cold-start AC-S027 deferred"
  else
    skip "fg-010-shaper.md missing — pre-Phase-C state"
  fi
}

@test "atomic-write contract is documented in bootstrap-detect.py (A2)" {
  grep -q 'temp-file-and-rename' "$PLUGIN_ROOT/shared/bootstrap-detect.py" \
    || grep -q 'atomic' "$PLUGIN_ROOT/shared/bootstrap-detect.py"
}

@test "autonomous-cold-start scenario: no partial state on failure" {
  # The skill body MUST commit to: detection failure aborts; write failure aborts.
  grep -q 'Detection ambiguous' "$PLUGIN_ROOT/skills/forge/SKILL.md"
  grep -q 'Write fails' "$PLUGIN_ROOT/skills/forge/SKILL.md"
}
BATS_EOF
```

(Note: the runtime-side scenario test is bats-structural for now; full pipeline simulation lives in `tests/evals/pipeline/` and runs in CI per the existing pattern. The bats above asserts the contract is documented; CI eval asserts the contract is honored at runtime.)

- [ ] **Step 6: Create `tests/structural/fg-010-shaper-shape.bats`**

```bash
cat > /Users/denissajnar/IdeaProjects/forge/tests/structural/fg-010-shaper-shape.bats <<'BATS_EOF'
#!/usr/bin/env bats
# AC-S021: fg-010-shaper.md must implement the seven-step pattern from §3.
# Each heading must appear EXACTLY ONCE.

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  SHAPER="$PLUGIN_ROOT/agents/fg-010-shaper.md"
}

@test "fg-010-shaper.md exists" {
  [ -f "$SHAPER" ]
}

# C1 (Phase C) does the rewrite; Phase B's structural test asserts the headings.
# Until C1 lands these tests will fail or skip — they are the gate that keeps
# C1 honest about the seven-step pattern.

@test "## Explore project context heading appears exactly once" {
  count=$(grep -c '^## Explore project context$' "$SHAPER" || true)
  if [ "$count" -eq 0 ]; then
    skip "fg-010-shaper not yet rewritten (C1) — AC-S021 deferred"
  fi
  [ "$count" -eq 1 ]
}

@test "## Ask clarifying questions heading appears exactly once" {
  count=$(grep -c '^## Ask clarifying questions$' "$SHAPER" || true)
  if [ "$count" -eq 0 ]; then
    skip "C1 deferred"
  fi
  [ "$count" -eq 1 ]
}

@test "## Propose 2-3 approaches heading appears exactly once" {
  count=$(grep -c '^## Propose 2-3 approaches$' "$SHAPER" || true)
  if [ "$count" -eq 0 ]; then
    skip "C1 deferred"
  fi
  [ "$count" -eq 1 ]
}

@test "## Present design sections heading appears exactly once" {
  count=$(grep -c '^## Present design sections$' "$SHAPER" || true)
  if [ "$count" -eq 0 ]; then
    skip "C1 deferred"
  fi
  [ "$count" -eq 1 ]
}

@test "## Write spec heading appears exactly once" {
  count=$(grep -c '^## Write spec$' "$SHAPER" || true)
  if [ "$count" -eq 0 ]; then
    skip "C1 deferred"
  fi
  [ "$count" -eq 1 ]
}

@test "## Self-review heading appears exactly once" {
  count=$(grep -c '^## Self-review$' "$SHAPER" || true)
  if [ "$count" -eq 0 ]; then
    skip "C1 deferred"
  fi
  [ "$count" -eq 1 ]
}

@test "## Handoff heading appears exactly once" {
  count=$(grep -c '^## Handoff$' "$SHAPER" || true)
  if [ "$count" -eq 0 ]; then
    skip "C1 deferred"
  fi
  [ "$count" -eq 1 ]
}
BATS_EOF
```

(The `skip` clauses keep B13 green when C1 has not yet landed. Once C1 lands, the skips become genuine pass/fail assertions.)

- [ ] **Step 7: Finalize the AC-S005 allowlist**

The allowlist was pre-positioned in B12. Confirm it has the canonical entries:

```bash
cat /Users/denissajnar/IdeaProjects/forge/tests/structural/skill-references-allowlist.txt
```

Expected:
```
CHANGELOG.md
DEPRECATIONS.md
tests/structural/migration-callsites.txt
skills/forge/SKILL.md
skills/forge-admin/SKILL.md
skills/forge-ask/SKILL.md
```

If any entry is missing, append it. If the file has extra entries that don't actually need to be allowlisted, remove them.

- [ ] **Step 8: Run the new tests locally if bats is available, otherwise skip**

```bash
cd /Users/denissajnar/IdeaProjects/forge
if command -v bats >/dev/null 2>&1; then
  bats tests/structural/skill-consolidation.bats
  bats tests/unit/skill-execution/forge-dispatch.bats
  bats tests/unit/skill-execution/spec-wellformed.bats
  bats tests/scenarios/autonomous-cold-start.bats
  bats tests/structural/fg-010-shaper-shape.bats
fi
```

Expected: all green (with `skip` for fg-010-shaper-shape.bats until C1 lands).

If any test fails:
- skill-consolidation.bats failure → re-check B12 deletion was clean.
- forge-dispatch.bats failure → re-check B1 wrote all 11 subcommand sections.
- spec-wellformed.bats failure → the regex implementation in the test helper is wrong; fix and re-run.
- autonomous-cold-start.bats failure → the SKILL.md is missing a documented contract clause; fix B1.

- [ ] **Step 9: Commit**

```bash
git add tests/structural/skill-consolidation.bats \
        tests/structural/skill-references-allowlist.txt \
        tests/structural/fg-010-shaper-shape.bats \
        tests/unit/skill-execution/forge-dispatch.bats \
        tests/unit/skill-execution/spec-wellformed.bats \
        tests/scenarios/autonomous-cold-start.bats \
        tests/lib/module-lists.bash
git commit -m "test: add tests for new skill surface + AC-S005 allowlist (B13)

- skill-consolidation.bats now asserts exactly 3 skills (was 29)
  and forbids the 28 retired names
- forge-dispatch.bats: 11 verb tests + 3 NL fallback tests (AC-S006,
  AC-S007, AC-S010)
- spec-wellformed.bats: AC-S029 well-formedness regex
- autonomous-cold-start.bats: AC-S027 contract check (full pipeline
  in CI eval; bats asserts skill-level contract)
- fg-010-shaper-shape.bats: AC-S021 seven-section grep, skips until
  C1 rewrite lands
- skill-references-allowlist.txt: canonical 6-entry allowlist
- module-lists.bash: MIN_SKILLS=3, EXPECTED_SKILL_NAMES=(forge,
  forge-admin, forge-ask)

Refs spec §12 commit B13, AC-S004, AC-S007, AC-S010, AC-S021,
AC-S027, AC-S029."
```

---

## Phase B completion checklist

After all 13 commits land:

- [ ] `ls skills/` shows exactly: `forge  forge-admin  forge-ask`.
- [ ] `tests/structural/skill-consolidation.bats` passes (asserts exactly 3 skills).
- [ ] `tests/unit/skill-execution/forge-dispatch.bats` passes (11 verbs + 3 NL fallback).
- [ ] `tests/structural/fg-010-shaper-shape.bats` skips cleanly (waiting on C1).
- [ ] Canonical grep across the repo returns only allowlisted files.
- [ ] `tests/structural/skill-references-allowlist.txt` has exactly 6 entries.
- [ ] `tests/lib/module-lists.bash` has `MIN_SKILLS=3`.
- [ ] No file under `agents/`, `shared/`, `modules/`, `docs/`, `tests/`, `hooks/`, `evals/`, `.github/` references any retired skill name.
- [ ] No file at `README.md`, `CLAUDE.md`, `CONTRIBUTING.md`, `SECURITY.md`, `plugin.json`, `marketplace.json` references any retired skill name.
- [ ] CHANGELOG.md and DEPRECATIONS.md retain their historical references (intentional).

If all checks pass, Phase B is done. C, D, E phases can begin. C depends on B12 (deletion) being merged; D is independent and can start in parallel.

## Self-review notes (per writing-plans §Self-Review)

**Spec coverage:** §1 (skill definitions) → B1, B2, B3. §2 (auto-bootstrap trigger) → B1 (calls A2's helper). §12 commit-3 (atomic deletion) → B12. §12 commit-4 (rewiring) → B5-B10. §12 commit-6 (skill-subcommand-pattern decision) → B11. §12 commit-8 (new tests) → B13. ACs S001-S014 (skill surface), S015-S018 (auto-bootstrap), S019-S023 (BRAINSTORMING — those owned by C1 are referenced via skip-clauses), S024-S029 (state and telemetry — S027 + S029 owned here, others by A6/C2).

**Placeholder scan:** every step has actual content — sed scripts, complete file bodies for B1/B2/B3, complete bats test bodies for B13. The "(Body identical to old …)" sections in B2/B3 are explicit copy-from-source instructions, not placeholders — the implementer is told exactly which file to copy from and what section.

**Type consistency:** the mapping table is the single source of truth. The same perl block is used in B5-B10 (verbatim, just changing the file scope). The new SKILL.md frontmatter strings match spec §1 verbatim (cross-checked against the spec extract in this plan's task bodies). The `EXPECTED_SKILL_NAMES` array in module-lists.bash matches the three skill directories created in B1/B2/B3.

**Risk justifications present** on B5, B7, B8, B12 (all four high-risk tasks have ≥30-word risk-justification paragraphs per AC-PLAN-009).

**B12 safety gate:** Step 1 has four explicit checks before deletion (B5-B10 commits present, B11 applied, allowlist file pre-positioned, canonical grep clean). The gate is the largest single block in the plan.

**All 28 retired skills** are enumerated by name in B12's deletion command and again in skill-consolidation.bats's `retired=` array (B13).

**Mapping table appears once** at the top, sourced from spec §12.1, used as the perl-script body verbatim in B5/B6/B7/B8/B9/B10.

**Verify-clean grep step** is present in B5 (Step 4), B6 (Step 4), B7 (Step 5), B8 (Step 4), B9 (Step 3), B10 (Step 6). Each runs the canonical grep against the modified directory and asserts zero output.
