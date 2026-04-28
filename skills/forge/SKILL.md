---
name: forge
description: "[writes] Build, fix, deploy, review, or modify code in this project. Universal entry for the forge pipeline. Auto-bootstraps on first run; brainstorms before planning when given a feature description. Use when you want to take any productive action: implementing features, fixing bugs, reviewing branches, deploying, committing, running migrations."
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

This skill uses **positional verbs with NL fallback**.

**Dispatch rules:**

1. Read `$ARGUMENTS`.
2. If `$ARGUMENTS` is empty: print usage block (see §Usage below) and exit 0. (AC-S009)
3. If `$ARGUMENTS` is `--help` or first token is `--help`: print usage and exit 0. (AC-S008)
3.5. **Consume top-level flags from the start of `$ARGUMENTS`.** Repeatedly: if the first token of `$ARGUMENTS` matches `--dry-run|--autonomous|--background|--from=*|--spec` (the latter consumes the next token as its value), shift it into a `FLAGS` accumulator. Stop when the first token is no longer a flag. The remaining `$ARGUMENTS` is the verb-and-rest. (`--parallel` is a sprint-only flag and is consumed by step 5's verb dispatcher, not here.)
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
