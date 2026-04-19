# Phase 05 — Skill Consolidation 35 → 28 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Collapse the forge plugin's user-facing skill surface from 35 to 28 skills by merging three overlapping clusters (review, graph, verify) into git-style subcommand skills, while keeping every capability reachable.

**Architecture:** Each consolidated skill holds one `## Subcommand dispatch` section, followed by one `### Subcommand: <name>` section per mode — the existing bodies of the merged skills are moved verbatim under those sections, preserving all logic. Old skill directories are hard-deleted in the same PR; no aliases or stubs. A new `shared/skill-subcommand-pattern.md` documents the dispatch contract once and is referenced from each merged SKILL.md.

**Tech Stack:** Pure markdown skill files (Claude Code skill runtime); bash helper inlined per-skill for `$ARGUMENTS` parsing; bats structural tests under `tests/structural/` and `tests/lib/module-lists.bash`; no runtime dependencies.

**Source spec:** `docs/superpowers/specs/2026-04-19-05-skill-consolidation-design.md`
**Review:** `docs/superpowers/reviews/2026-04-19-05-skill-consolidation-spec-review.md` (APPROVE WITH MINOR).

---

## Review-Feedback Resolution (top section)

Three review issues are lifted out of the spec's Open Questions and made concrete in this plan.

| Review # | Concern | Resolution in this plan |
|---|---|---|
| I2 | `--scope=all --fix` safety-confirm gate left as Open Question | Concrete requirement in **Task 3** — `AskUserQuestion` gate fires before the first commit when `--scope=all --fix` runs, unless `--yes` is passed OR `autonomous: true` in config. Structural test in **Task 10** asserts the gate is documented. Success criterion added. |
| I1 | Verify `validate-config.sh` is truly read-only before keeping `[read-only]` label | **Verified during plan authoring** — `shared/validate-config.sh` (257 lines) writes only to stderr (`>&2`) via echo statements and reads stdin via a single `FORGE_YAML_CONTENT` env var; no `touch`, `mkdir`, `tee`, or stdout redirection to filesystem paths. The unified `/forge-verify` in **Task 5** keeps the `[read-only]` description unchanged. **Task 11** adds a regression test that greps the script for forbidden write patterns. |
| S1 | `/forge-help --json` schema-version bump implied, not stated | **Task 7** adds an explicit `"schema_version": "2"` field to the `--json` envelope (new shape: cluster entries with `subcommands` arrays; `total_skills: 28`). **Task 11** adds a structural test that the JSON example in `/forge-help` SKILL.md contains `"schema_version": "2"`. |

---

## File Structure

Before/after layout of every file this plan touches. Tasks are ordered so each commit leaves the tree internally consistent (tests may stay red across the delete→add→test sequence; they go green at **Task 11** when `module-lists.bash` is bumped and structural tests land).

**Created (2 files):**

| Path | Responsibility |
|---|---|
| `shared/skill-subcommand-pattern.md` | Documents the single dispatch contract: algorithm, `parse_args` helper, default-subcommand convention, `--help`/`help` aliasing, exit-2-on-unknown. Referenced by every consolidated SKILL.md. Pure documentation; not sourced at runtime. |
| `tests/structural/skill-consolidation.bats` | Asserts skill count = 28; asserts no forbidden old-skill names exist; asserts each consolidated skill has exactly one `## Subcommand dispatch` block and the expected `### Subcommand: <name>` sections; asserts cross-reference cleanup; asserts `schema_version` and `validate-config.sh` read-only regression. |

**Modified (5 files):**

| Path | Change |
|---|---|
| `skills/forge-review/SKILL.md` | Full rewrite: unified body covering changed/all modes + safety gate. Frontmatter `description` updated. |
| `skills/forge-verify/SKILL.md` | Full rewrite: unified body covering `build`/`config`/`all` subcommands. Frontmatter `description` updated; `[read-only]` label preserved. |
| `skills/forge-help/SKILL.md` | Replace tier tables with ASCII decision tree; add `## Migration (Phase 05)` table; update `--json` example to include `schema_version: "2"` and `subcommands` arrays for clusters; `total_skills: 28`. |
| `CLAUDE.md` | §Skills header `(35 total)` → `(28 total)`; skills paragraph rewritten; Skill Selection Guide table rows for review/graph/verify rewritten; Getting-started flows on lines 106–109 updated. |
| `tests/lib/module-lists.bash` | Add `MIN_SKILLS=28` and `EXPECTED_SKILL_NAMES` array (check-in the canonical 28 names). |
| `shared/skill-contract.md` | Update §4 "Skill categorization" — renumber baseline to 28, move read-only/writes lists to the post-consolidation skill names. |
| `tests/contract/skill-contract.bats` | Update any hard-coded skill counts (currently references 35 via the contract §4). |

**Renamed (1 directory — must be `git mv` to preserve history):**

| From | To |
|---|---|
| `skills/forge-graph-init/` | `skills/forge-graph/` |

The contents of `skills/forge-graph/SKILL.md` are rewritten (not just the old `forge-graph-init` body) but the directory rename must use `git mv` so the review diff renders as a rename + modification rather than delete + add.

**Deleted (6 directories):**

- `skills/forge-codebase-health/`
- `skills/forge-deep-health/`
- `skills/forge-graph-status/`
- `skills/forge-graph-query/`
- `skills/forge-graph-rebuild/`
- `skills/forge-graph-debug/`
- `skills/forge-config-validate/`

(7 deletions total; the 7th is implicit in the `git mv` of `forge-graph-init` → `forge-graph`.)

---

## Task Breakdown

12 tasks. Each ends with a conventional-commit commit. Task 11 is the "tests green" task — tests may be red from Tasks 2–10 and the engineer should not panic about that; Task 11 flips them.

### Task 1: Add the shared subcommand-dispatch contract doc

**Files:**
- Create: `shared/skill-subcommand-pattern.md`

This file is pure documentation. No runtime sourcing. It captures the dispatch contract so Tasks 3, 4, 5 can reference it instead of duplicating the algorithm.

- [ ] **Step 1: Create `shared/skill-subcommand-pattern.md` with the full contract**

```markdown
# Skill Subcommand Dispatch Pattern

Standard pattern for skills that expose multiple modes via subcommands (git-style).
Adopted in Phase 05 for `/forge-review`, `/forge-graph`, `/forge-verify`.

## 1. Dispatch algorithm

Every skill that uses this pattern places **one** `## Subcommand dispatch` section
at the top of its SKILL.md body. That section MUST describe the following steps:

1. Read `$ARGUMENTS` (the raw arg string).
2. Split into tokens: `SUB="$1"; shift; REST="$*"`.
3. If `$SUB` is empty OR `$SUB` matches `-*` (a flag, not a subcommand):
   → treat as the default subcommand (skill-specific; see `## Default subcommand`).
4. If `$SUB == --help` OR `$SUB == help`:
   → print the usage block and exit 0.
5. If `$SUB` is in the subcommand allow-list: dispatch to the matching
   `### Subcommand: <name>` section with `$REST` as its arguments.
6. Otherwise: print
   `Unknown subcommand '<SUB>'. Valid: <list>. Try /<skill> --help.`
   and exit 2 (invalid arguments; see `shared/skill-contract.md` §3).

## 2. Default subcommand

Each skill MAY declare a default subcommand used when `$ARGUMENTS` is empty
or starts with a flag. Skills that touch destructive state (e.g. `/forge-graph`
whose `rebuild` subcommand deletes nodes) MUST NOT declare a default; a bare
invocation prints help and exits 2.

Current defaults (Phase 05):

| Skill | Default | Rationale |
|---|---|---|
| `/forge-review` | `changed` (i.e. `--scope=changed` with `--fix` on) | Preserves old `/forge-review` muscle memory. |
| `/forge-graph` | none — explicit subcommand required | Safer than silently invoking `rebuild`. |
| `/forge-verify` | `build` | Matches old `/forge-verify` default. |

## 3. Arg-parsing helper (inlined per skill)

The Claude Code skill runtime reads one `.md` per skill and expects all logic
inline. Rather than sourcing a shared script, each skill inlines this bash
helper verbatim:

```bash
parse_args() {
  SUB=""
  FLAGS=()
  POSITIONAL=()
  for tok in "$@"; do
    case "$tok" in
      --help|-h) echo "__HELP__"; return 0 ;;
      --*)       FLAGS+=("$tok") ;;
      *)         if [ -z "$SUB" ]; then SUB="$tok"; else POSITIONAL+=("$tok"); fi ;;
    esac
  done
}
```

## 4. Section layout contract

A SKILL.md that adopts this pattern MUST contain:

1. Exactly ONE `## Subcommand dispatch` section (duplicated sections fail the
   structural test in `tests/structural/skill-consolidation.bats`).
2. One `### Subcommand: <name>` section per allowed subcommand, in the order
   listed in the dispatch allow-list.
3. Each subcommand section owns its own Prerequisites, Instructions, Error
   Handling, and Exit-code rows. Shared material (e.g. "forge.local.md must
   exist") MAY be factored once at the top of the SKILL body and referenced.

## 5. Unknown subcommand → exit 2

Following the standard exit-code table in `shared/skill-contract.md` §3:
- `0` — success
- `1` — user error (bad args, missing config)
- `2` — pipeline failure OR **unknown subcommand** (Phase 05 extends this code
  to cover dispatch-table misses)
- `3` — recovery needed
- `4` — user aborted

The "Unknown subcommand" path falls under exit `2` because the user supplied
a value the skill could not act on — semantically closer to pipeline failure
than to a missing required flag.

## 6. When to adopt this pattern

- NEW skill needs ≥ 3 modes whose setup/prerequisites overlap.
- Existing skills that are obvious modes of each other (audit found: review,
  graph, verify — Phase 05).
- DO NOT adopt for single-mode skills (`/forge-status`, `/forge-abort`).
```

- [ ] **Step 2: Verify file exists**

Run: `test -f shared/skill-subcommand-pattern.md && echo OK`
Expected: `OK`

- [ ] **Step 3: Commit**

```bash
git add shared/skill-subcommand-pattern.md
git commit -m "docs(phase5): add skill-subcommand-pattern contract"
```

---

### Task 2: Cross-reference sweep plan — identify every reference to removed skill names

This is a **scout task** — produce a manifest, don't edit yet. Tasks 3–9 will delete the references as the respective files are rewritten; Task 10 catches stragglers.

**Files:**
- Create: `/tmp/forge-phase5-refs.txt` (scratch, not committed)

- [ ] **Step 1: Generate the manifest**

Run:
```bash
cd /Users/denissajnar/IdeaProjects/forge
grep -rln -E '/forge-(codebase-health|deep-health|config-validate|graph-(status|query|rebuild|debug))' \
  --include='*.md' --include='*.json' --include='*.sh' --include='*.bats' --include='*.bash' \
  -- . > /tmp/forge-phase5-refs.txt
cat /tmp/forge-phase5-refs.txt
```
Expected output: ~15–25 files. Include at minimum: `CLAUDE.md`, `README.md`, `CHANGELOG.md`, `skills/forge-help/SKILL.md`, `skills/forge-init/SKILL.md`, `skills/forge-migration/SKILL.md`, `skills/forge-automation/SKILL.md`, `skills/forge-docs-generate/SKILL.md`, `skills/forge-config/SKILL.md`, `skills/forge-ask/SKILL.md`, `skills/forge-review/SKILL.md`, `skills/forge-security-audit/SKILL.md`, `skills/forge-codebase-health/SKILL.md` (itself), `skills/forge-deep-health/SKILL.md` (itself), the six `skills/forge-graph-*/SKILL.md` files (themselves), `shared/skill-contract.md`, `shared/graph/schema.md`, `shared/graph/schema-versioning.md`, `shared/graph/enrich-symbols.sh`, `hooks/automation-trigger.sh`, `tests/contract/skill-contract.bats`, `tests/contract/graph-debug-skill.bats`, `tests/unit/skill-execution/skill-error-handling.bats`, `docs/superpowers/**` (spec + review + this plan, which are allowed to keep old names).

- [ ] **Step 2: Tag the allowed-to-keep list**

The ONLY files allowed to mention removed skill names after Phase 05 lands are:
- `docs/superpowers/specs/**`, `docs/superpowers/reviews/**`, `docs/superpowers/plans/**` — historical record
- `skills/forge-help/SKILL.md` — inside the `## Migration (Phase 05)` section ONLY
- `CHANGELOG.md` — the Phase 05 release notes entry

Every other reference must be removed or rewritten in Tasks 3–9.

- [ ] **Step 3: No commit for this task** — scratch file is not added to git. Proceed to Task 3.

---

### Task 3: Consolidate review cluster → `/forge-review` with `--scope` flag and `--scope=all --fix` safety gate

**Files:**
- Modify: `skills/forge-review/SKILL.md` (full rewrite)
- Delete: `skills/forge-codebase-health/SKILL.md` and directory
- Delete: `skills/forge-deep-health/SKILL.md` and directory

The new SKILL.md is ~360 lines (combining the three old bodies). Step 1 below shows the full replacement.

- [ ] **Step 1: Rewrite `skills/forge-review/SKILL.md`**

Replace the entire file contents with:

````markdown
---
name: forge-review
description: "[writes] Quality review for changed files or the whole codebase. Subcommands via flags: --scope=changed|all, --fix, --dry-run. Use when reviewing staged work before commit (--scope=changed), auditing the codebase (--scope=all), or iteratively fixing all quality issues (--scope=all --fix)."
allowed-tools: ['Read', 'Write', 'Edit', 'Bash', 'Glob', 'Grep', 'Agent']
disable-model-invocation: false
---

# /forge-review — Quality Review (changed | all | all --fix)

This skill unifies what Phase 1 shipped as three separate skills. One dispatch, three behavioral modes.

## Subcommand dispatch

Follow `shared/skill-subcommand-pattern.md`. This skill uses flags (not positional subcommands) because the distinction between "review changed files" and "audit whole codebase" is semantically a scope selection.

**Dispatch rules:**

1. Read `$ARGUMENTS`.
2. Parse flags: `--scope=<changed|all>`, `--fix`, `--dry-run`, `--full`, `--files <pattern>`, `--range <base>..<head>`, `--max-iterations <N>`, `--yes`, `--help`.
3. If `--help` is present: print the usage block below and exit 0.
4. Default values (applied before dispatch):
   - `--scope`: `changed`
   - `--fix`: ON when `--scope=changed`; OFF when `--scope=all` (see exception in Mode C).
5. Dispatch by `(scope, fix)` pair:
   - `(changed, true)` → `### Subcommand: changed --fix` (the default)
   - `(changed, false)` → `### Subcommand: changed` (same as above, fix phase skipped)
   - `(all, false)` → `### Subcommand: all`
   - `(all, true)` → `### Subcommand: all --fix` (**destructive**, gated — see Mode C)
6. Unknown flag or malformed `--scope=<bad>` value: print `Unknown --scope. Valid: changed | all.` and exit 2.

## Flags

- **--help**: print usage and exit 0
- **--dry-run**: preview actions without writing files or committing
- **--scope=changed|all**: required explicit value when not default. `changed` = last commit + uncommitted + staged. `all` = every tracked source file.
- **--fix**: run the fix loop after collecting findings. Default ON for `changed`, OFF for `all`.
- **--yes**: bypass the safety-confirm gate for `--scope=all --fix` (autonomous CI/cron usage)
- **--full**: in `--scope=changed`, dispatch the full reviewer roster (up to 8 agents) instead of the quick 2
- **--range <base>..<head>**: in `--scope=changed`, override the git range (default `HEAD~1..HEAD` + uncommitted)
- **--files <pattern>**: in `--scope=changed`, glob-filter the file set
- **--max-iterations <N>**: override the review-fix-verify inner loop cap (default 3 for `changed`, 5 for `all --fix`)

## Exit codes

See `shared/skill-contract.md` §3 for the standard exit-code table.

## Shared prerequisites

Before any subcommand, verify:

1. **Git repository:** `git rev-parse --show-toplevel 2>/dev/null`. If fails: report "Not a git repository. Navigate to a project directory." and STOP.
2. **Forge initialized:** `.claude/forge.local.md` exists. If not: report "Forge not initialized. Run /forge-init first." and STOP.

## Configuration respected

Reads from `.claude/forge-config.md` (if present):
- `max_iterations` — iteration cap (default: 3 for `changed`, 5 for `all --fix`)
- `pass_threshold` — minimum quality score (default: 80)
- `autonomous` — if true, skip user confirmation between iterations AND skip the Mode C safety gate
- `convergence.oscillation_tolerance` — score delta considered "no progress"
- `quality_gate.*` — reviewer selection overrides

No new config keys are introduced by this phase.

---

### Subcommand: changed

Default when `$ARGUMENTS` is empty or starts with a flag. Review **recently-changed source files** and (when `--fix` is ON, the default) fix findings in a loop.

**Additional prerequisite:** `git diff --name-only HEAD` returns at least one file. If empty: report "No changed files to review." and STOP.

#### 1. Determine scope

Compute the file list:

**Default (no `--range`, no `--files`):**
```bash
PROJECT_ROOT=$(git rev-parse --show-toplevel)
COMMITTED=$(git diff --name-only HEAD~1..HEAD 2>/dev/null || git diff --name-only HEAD 2>/dev/null || echo "")
UNCOMMITTED=$(git diff --name-only 2>/dev/null)
STAGED=$(git diff --name-only --cached 2>/dev/null)
FILES=$(echo -e "$COMMITTED\n$UNCOMMITTED\n$STAGED" | sort -u | grep -v '^$')
```

**With `--range`:** `FILES=$(git diff --name-only {base}..{head})`

**With `--files`:** glob against project root.

Filter to source extensions:
```bash
echo "$FILES" | grep -E '\.(kt|kts|java|ts|tsx|js|jsx|py|go|rs|c|h|cs|cpp|swift|rb|php|dart|ex|scala|vue|svelte|html|css|scss)$'
```

Also include `.md` files if `--full` is set (for `fg-418-docs-consistency-reviewer`).

If zero files remain: report "No changed source files to review. PERFECT." and STOP.

Report: "Reviewing {count} files in {mode} mode."

#### 2. Select agents

**Quick mode (default):** Always dispatch these 2:
- `forge:fg-410-code-reviewer`
- `forge:fg-411-security-reviewer`

**Full mode (`--full`):** Quick 2 + `forge:fg-412-architecture-reviewer` + conditional agents based on file types present:

| Agent | Dispatch condition |
|---|---|
| `forge:fg-418-docs-consistency-reviewer` | Any `.md` files in scope |
| `forge:fg-413-frontend-reviewer` (mode: `full`) | Any `.tsx`, `.jsx`, `.vue`, `.svelte`, `.html`, `.css`, `.scss`, `.styled.*` files |
| `forge:fg-416-performance-reviewer` | Any `.kt`, `.java`, `.py`, `.go`, `.rs`, `.cs` files |
| `forge:fg-417-dependency-reviewer` | Any `package.json`, `build.gradle.kts`, `go.mod`, `Cargo.toml`, `*.csproj`, `pyproject.toml`, lock files |
| `forge:fg-419-infra-deploy-reviewer` | Any `Dockerfile`, `docker-compose.*`, `*.yaml`/`*.yml` with k8s markers, Helm charts |

Report: "Dispatching {count} review agents: {agent_names}"

#### 3. Review-Fix-Verify Loop

```
ITERATION = 0
MAX_ITERATIONS = --max-iterations value or 3
TOTAL_FIXED = 0
SCOPE_FILES = initial file list

LOOP:
  ITERATION += 1
  Create task: "Review iteration {ITERATION}/{MAX_ITERATIONS}"

  --- Step A: DISPATCH ---
  Dispatch selected agents in parallel (max 3 concurrent via Agent tool).
  Each agent receives:
    - File list: SCOPE_FILES (full paths)
    - Conventions: path to .claude/forge.local.md (if exists, else omit)
    - Instruction: "Review these files. Report ALL findings — CRITICAL, WARNING, and INFO.
      Format each finding as: file:line | CATEGORY | SEVERITY | message | fix_hint
      Do not fix anything — report only."

  --- Step B: COLLECT & SCORE ---
  Deduplicate by (file, line, category) — keep highest severity.
  Score: max(0, 100 - 20*CRITICAL - 5*WARNING - 2*INFO)
  Report: "Iteration {ITERATION}: {count} findings, score {score}/100"

  --- Step C: CHECK ---
  If score == 100: BREAK → report PERFECT
  If ITERATION >= MAX_ITERATIONS: BREAK → report final verdict with remaining findings
  If --fix is OFF (user passed --scope=changed without --fix): BREAK after first iteration

  --- Step D: FIX (only if --fix is ON) ---
  For each finding (CRITICAL first, then WARNING, then INFO):
    1. Read affected file + context (±20 lines).
    2. Challenge: is there a better solution? Consider project conventions.
    3. Fix using Edit tool. Follow existing patterns.
    4. Track: add to FIXED list. TOTAL_FIXED += 1

  After fixes: run commands.build, commands.test, commands.lint from forge.local.md.
  If any fail: revert last fix (`git checkout -- <file>`), mark as unfixable.

  --- Step E: NARROW SCOPE ---
  SCOPE_FILES = files touched by fixes.
  GOTO LOOP
```

#### 4. Report

(Section unchanged from the old `/forge-review` — verdict table, terse caveman-mode format, severity markers.)

```
## Forge Review -- {PERFECT|PASS|CONCERNS|FAIL} (Score: {score}/100)
Mode: changed{--fix}  |  Files: {count}  |  Agents: {count}
Iterations: {ITERATION}/{MAX_ITERATIONS}  |  Fixed: {TOTAL_FIXED}  |  Remaining: {remaining}

### Fixed ({TOTAL_FIXED})
- `file:line` | CATEGORY | SEVERITY | what was fixed

### Remaining ({remaining})  [omit if PERFECT]
- `file:line` | CATEGORY | SEVERITY | message | reason unfixable

### Verdict
{PERFECT: Clean — score 100.}
{PASS: Score {N}/100. {remaining} findings could not be resolved in {MAX_ITERATIONS} iterations.}
{CONCERNS: Score {N}/100. Manual intervention recommended.}
{FAIL: Score {N}/100. Critical issues remain.}
```

Verdict thresholds: PERFECT = 100; PASS ≥ 80 and 0 CRITICALs; CONCERNS 60-79 and 0 CRITICALs; FAIL < 60 OR any CRITICAL remaining.

**Do NOT** create PRs, tickets, commits, or state files. This subcommand does not commit.

---

### Subcommand: all

Read-only full-codebase audit via the check engine. Does not fix. Replaces the old `/forge-codebase-health`.

#### 1. Discover source files

```bash
PROJECT_ROOT=$(git rev-parse --show-toplevel)
SOURCE_FILES=$(git -C "$PROJECT_ROOT" ls-files --cached --others --exclude-standard | grep -E '\.(kt|kts|java|ts|tsx|js|jsx|py|go|rs|c|h|cs|csx|cpp|cc|cxx|hpp|swift|rb|php|dart|ex|exs|scala|sc)$')
```

Count and report: "Found {count} source files to scan."

#### 2. Run the check engine (L1 + L2)

```bash
echo "$SOURCE_FILES" | while read -r f; do
  "${CLAUDE_PLUGIN_ROOT}/shared/checks/engine.sh" --review --project-root "$PROJECT_ROOT" --files-changed "$PROJECT_ROOT/$f"
done
```

If the engine is not executable or not found: "Check engine not available. Verify the forge plugin is installed." and STOP.

#### 3. Parse, score, present

Parse pipe-delimited findings: `file:line | CATEGORY | SEVERITY | message | fix_hint`. Count by severity and category prefix. Score with `max(0, 100 - 20*CRITICAL - 5*WARNING - 2*INFO)`. Verdict: PASS (≥80, no CRITICAL), CONCERNS (60-79, no CRITICAL), FAIL (<60 or any CRITICAL).

Produce the `## Codebase Health Report` block from the old `/forge-codebase-health` body (categories table, top 10 issues, etc.).

#### 4. Save the report

Write the full report to `.forge/health-report.md` (preserved path for tooling that greps it). This is the ONLY file this subcommand writes.

**Do NOT fix issues.** If the user wants fixes, they must re-run with `--scope=all --fix`.

---

### Subcommand: all --fix

Iterative fix loop across the whole codebase with per-iteration commits. Replaces the old `/forge-deep-health`. **Destructive** — commits are real; a bad fix is on `HEAD`.

#### 1. Safety-confirm gate (NEW in Phase 05)

**Before any file modification or commit**, this subcommand MUST present an `AskUserQuestion` gate unless ONE of the following is true:

- `--yes` flag is present on the command line, OR
- `.claude/forge-config.md` sets `autonomous: true`, OR
- `--dry-run` flag is present (preview only, never commits)

Gate prompt:
- Header: "Codebase fix loop — confirm"
- Question: "This will run the review-fix-verify loop over the whole codebase and commit after every iteration (up to {max_iterations}). Up to ~{estimated_commits} commits may land on the current branch. Continue?"
- Options: "Proceed — run the fix loop" / "Abort — exit without changes"

If the user picks "Abort": report "Aborted — no changes made." and exit 4 (user-aborted; see skill-contract §3).

Under `autonomous: true` or `--yes`, log a one-line `[AUTO-CONFIRM] Safety gate bypassed by <reason>` and proceed.

#### 2. Baseline — run the check engine

```bash
PROJECT_ROOT=$(git rev-parse --show-toplevel)
FILES=$(git diff --name-only $(git merge-base origin/master HEAD 2>/dev/null || echo HEAD~10)..HEAD 2>/dev/null)
[ -z "$FILES" ] && FILES=$(git ls-files --cached --exclude-standard | grep -E '\.(kt|kts|java|ts|tsx|js|jsx|py|go|rs|c|h|cs|cpp|swift|rb|php|dart|ex|scala|vue|svelte|html|css|scss)$')

echo "$FILES" | while read -r f; do
  "${CLAUDE_PLUGIN_ROOT}/shared/checks/engine.sh" --review --project-root "$PROJECT_ROOT" --files-changed "$PROJECT_ROOT/$f" 2>/dev/null
done
```

Record baseline score. `ITERATION_BASE_SHA=$(git rev-parse HEAD)`.

#### 3. Investigation, triage, fix, verify, commit (per iteration)

Same loop as the old `/forge-deep-health`. Dispatch reviewer roster (selected by file types), collect findings, triage by severity, fix with project conventions, run `build`/`test`/`lint`, revert regressions, re-dispatch to verify, and commit with a conventional-commit message once the iteration is clean.

Inner verification loop hard cap: 3 passes per iteration.

Iteration cap: `--max-iterations` override or config `max_iterations` (default 5).

#### 4. Final full review

After the loop ends, dispatch all reviewers one final time against the full diff `FULL_BASE..HEAD` to catch cross-iteration inconsistencies.

#### 5. Report

Save to `.forge/forge-deep-health-report.md` (preserved path). Format:

```
## Deep Health Complete
Iterations: {N}
Issues fixed: {M} ({critical} critical, {warning} warnings, {info} info)
Final score: {S}/100
Commits: {list of SHAs + messages}

### Remaining (if any)
- {issue}: {reason — out of scope / intentional / accepted trade-off}
```

#### Important rules

- **Target is 100.** Fix all severities.
- **Challenge before fixing.** Search docs (Context7, WebSearch) when uncertain.
- **One commit per iteration.** Never batch unrelated fixes.
- **Revert on regression.** If a fix breaks build/test/lint, revert and mark unfixable.
- **Do NOT create PRs or tickets.** Only commits.

## Error Handling

| Condition | Action |
|---|---|
| Shared prerequisites fail | Report specific error message and STOP |
| No changed files (scope=changed) | Report "No changed files to review." and STOP |
| No source files (scope=all) | Report "No source files found in the repository." and STOP |
| Check engine not available (scope=all) | Report "Check engine not available. Verify the forge plugin is installed." and STOP |
| Agent dispatch failure | Skip failed agent, continue. If ALL fail, report ERROR and STOP |
| Fix introduces regression | Revert the fix (`git checkout -- <file>`), mark as "unfixable: fix caused regression", continue |
| Safety gate declined (scope=all --fix) | Report "Aborted — no changes made." and exit 4 |
| Score stagnation | Report remaining findings, exit loop |
| State corruption | This skill does not depend on state.json — it runs independently |

## See Also

- `/forge-verify --build` — Quick build + lint + test check (no review agents)
- `/forge-security-audit` — Focused security vulnerability scanning
- `/forge-run` — Full pipeline including review as part of the workflow
````

- [ ] **Step 2: Delete the old review-cluster skills**

```bash
git rm -r skills/forge-codebase-health
git rm -r skills/forge-deep-health
```

- [ ] **Step 3: Sanity-check the new skill file renders**

Run: `head -6 skills/forge-review/SKILL.md | grep '^description:' | grep -q 'scope=changed|all' && echo OK`
Expected: `OK`

- [ ] **Step 4: Commit**

```bash
git add skills/forge-review/SKILL.md skills/forge-codebase-health skills/forge-deep-health
git commit -m "feat(phase5)!: consolidate review cluster into /forge-review --scope

Merges /forge-codebase-health and /forge-deep-health into /forge-review with
--scope=changed|all and --fix flags. Adds AskUserQuestion safety gate before
the first commit when --scope=all --fix runs outside autonomous mode.

BREAKING CHANGE: /forge-codebase-health and /forge-deep-health are removed.
Use /forge-review --scope=all (read-only) or --scope=all --fix (fixes)."
```

---

### Task 4: Consolidate graph cluster → `/forge-graph <init|status|query|rebuild|debug>`

**Files:**
- Rename (git mv): `skills/forge-graph-init/` → `skills/forge-graph/`
- Modify: `skills/forge-graph/SKILL.md` (full rewrite after rename)
- Delete: `skills/forge-graph-status/`, `skills/forge-graph-query/`, `skills/forge-graph-rebuild/`, `skills/forge-graph-debug/`

The `git mv` ordering is load-bearing: renames preserve history, raw delete+add does not.

- [ ] **Step 1: Rename the graph-init directory**

```bash
git mv skills/forge-graph-init skills/forge-graph
```

Verify: `test -f skills/forge-graph/SKILL.md && echo OK` → `OK`.

- [ ] **Step 2: Rewrite `skills/forge-graph/SKILL.md`**

Replace the entire file contents with:

````markdown
---
name: forge-graph
description: "[writes for init/rebuild, read-only for status/query/debug] Manage the Neo4j knowledge graph. Subcommands: init, status, query <cypher>, rebuild, debug. Requires Docker. No default — an explicit subcommand is required."
allowed-tools: ['Read', 'Write', 'Edit', 'Bash', 'Glob', 'Grep', 'Agent']
disable-model-invocation: false
---

# /forge-graph — Knowledge Graph Management

One skill, five subcommands. Each subcommand preserves the behavior of the corresponding Phase 1 skill verbatim.

## Subcommand dispatch

Follow `shared/skill-subcommand-pattern.md`. This skill uses **positional subcommands**, NOT flags.

**Dispatch rules:**

1. Read `$ARGUMENTS`.
2. Split: `SUB="$1"; shift; REST="$*"`.
3. If `$SUB` is empty OR matches `-*` (bare invocation or flags-only): print the usage block and exit 2 (`No subcommand provided. Valid: init | status | query | rebuild | debug.`).
4. If `$SUB == --help` OR `$SUB == help`: print usage and exit 0.
5. If `$SUB` is in `{init, status, query, rebuild, debug}`: dispatch to the matching `### Subcommand: <SUB>` section with `$REST` as its arguments.
6. Otherwise: print `Unknown subcommand '<SUB>'. Valid: init | status | query | rebuild | debug. Try /forge-graph --help.` and exit 2.

**No default subcommand.** This is intentional — `rebuild` is destructive, so a bare `/forge-graph` must not silently rebuild.

## Flags

- **--help**: print usage and exit 0
- **--dry-run**: preview actions without writing (applicable to `init`, `rebuild`)
- **--json**: structured JSON output (applicable to `status`, `debug`)

Subcommand-specific flags are documented under each subcommand section.

## Exit codes

See `shared/skill-contract.md` §3.

## Shared prerequisites

Before any subcommand:

1. **Forge initialized:** `.claude/forge.local.md` exists. If not: "Pipeline not initialized. Run `/forge-init` first." STOP.
2. **Graph enabled:** `graph.enabled: true` in `forge.local.md`. If false/absent: "Graph integration is disabled. Set `graph.enabled: true` to use this feature." STOP.
3. **Docker available:** `docker info`. If fails: "Docker is not available. Cannot run graph operations." STOP.

## Container name resolution

Read `graph.neo4j_container_name` from `.claude/forge.local.md`. If not set, default: `forge-neo4j`. Use the resolved name in ALL `docker` commands below.

---

### Subcommand: init

(Body preserved verbatim from the old `/forge-graph-init` — Steps 1–8: VERIFY PREREQUISITES, PREPARE COMPOSE FILE, START CONTAINER, WAIT FOR HEALTH, IMPORT PLUGIN SEED, BUILD PROJECT GRAPH, UPDATE STATE, REPORT. See spec §5.2 for the full content.)

Key behavior preserved:
- Idempotent: skips steps that are already done (container running, seed imported, build-SHA matches HEAD).
- Writes `.forge/graph/.last-build-sha` on success.
- Updates `.forge/state.json.integrations.neo4j.available = true`.
- Pulls `neo4j:5-community` if image not present locally.

### Subcommand: status

(Body preserved verbatim from the old `/forge-graph-status` — Steps 1–6: CONTAINER HEALTH, NODE COUNTS, LAST BUILD SHA, ENRICHMENT COVERAGE, RELATIONSHIP COUNTS, REPORT.)

Read-only. Honors `--json` flag per skill-contract §2.

### Subcommand: query

(Body preserved verbatim from the old `/forge-graph-query` — Steps 1–5: CHECK AVAILABILITY, GET QUERY, EXECUTE QUERY, FORMAT AND DISPLAY RESULTS, FOLLOW-UP.)

Takes the Cypher query as a positional argument (everything after `query` on the command line). If no argument: prompts the user. Read-only.

### Subcommand: rebuild

(Body preserved verbatim from the old `/forge-graph-rebuild` — Steps 0–5: VERIFY GIT REPOSITORY, CHECK AVAILABILITY, CONFIRM WITH USER, RESOLVE PROJECT IDENTITY, SAVE ENRICHMENT DATA, DELETE PROJECT NODES, REBUILD PROJECT GRAPH, RESTORE ENRICHMENT, REPORT NEW NODE COUNTS.)

Honors `--component <name>`, `--clear-enrichment`, and `--dry-run` flags. Uses `AskUserQuestion` for the confirmation step. Destructive — deletes project-scoped nodes (preserves plugin seed).

### Subcommand: debug

(Body preserved verbatim from the old `/forge-graph-debug` — the 5 diagnostic recipes: Orphaned Nodes, Stale Nodes, Missing Enrichments, Relationship Integrity, Node Count Summary.)

Read-only. Enforces `LIMIT 50` on every query. All queries scoped to `project_id`.

## Error Handling

Inherits the error-handling tables from each of the five Phase-1 source skills. Consolidated matrix:

| Condition | Action |
|---|---|
| Shared prerequisites fail | Report specific error and STOP |
| Docker image pull fails (init) | "Failed to pull Neo4j image. Check internet + Docker Hub access." STOP |
| Neo4j health timeout (60s) | "Neo4j did not become healthy within 60 seconds. Check `docker logs forge-neo4j`." STOP |
| Container not running (status/query/rebuild/debug) | "Neo4j not running. Run `/forge-graph init` first." STOP (or show local file data for status) |
| Seed import fails (init) | "Container is running but seed is missing. Retry `/forge-graph init`." |
| Query returns no results (query) | "Query returned no results. Check labels with `MATCH (n) RETURN DISTINCT labels(n)`." |
| User cancels rebuild | "Rebuild cancelled. Graph unchanged." STOP |
| Deletion fails mid-rebuild | "Graph may be in partial state. Run `/forge-graph init` to fully reinitialize." STOP |
| Enrichment restore fails | WARNING "Bugfix telemetry will restart from zero." Continue |

## See Also

- `/forge-ask` — Natural-language queries over the graph
- `/forge-init` — Full project setup (may invoke `/forge-graph init` as a step)
````

- [ ] **Step 3: Delete the four other graph skills**

```bash
git rm -r skills/forge-graph-status
git rm -r skills/forge-graph-query
git rm -r skills/forge-graph-rebuild
git rm -r skills/forge-graph-debug
```

- [ ] **Step 4: Sanity-check**

Run: `grep -c '### Subcommand:' skills/forge-graph/SKILL.md`
Expected: `5`

- [ ] **Step 5: Commit**

```bash
git add skills/forge-graph skills/forge-graph-status skills/forge-graph-query skills/forge-graph-rebuild skills/forge-graph-debug
git commit -m "feat(phase5)!: consolidate graph cluster into /forge-graph <sub>

Merges 5 graph skills into /forge-graph with positional subcommands:
init, status, query, rebuild, debug. No default subcommand — bare
invocation prints help and exits 2 (safer than accidental rebuild).

BREAKING CHANGE: /forge-graph-status, /forge-graph-query,
/forge-graph-rebuild, /forge-graph-debug are removed.
/forge-graph-init is renamed to /forge-graph init."
```

---

### Task 5: Consolidate verify cluster → `/forge-verify --build|--config|--all`

**Files:**
- Modify: `skills/forge-verify/SKILL.md` (full rewrite)
- Delete: `skills/forge-config-validate/SKILL.md` and directory

`validate-config.sh` is read-only (confirmed: writes only to stderr via `>&2`, no `touch`/`mkdir`/`tee`/stdout redirection). The unified `/forge-verify` keeps its `[read-only]` label.

- [ ] **Step 1: Rewrite `skills/forge-verify/SKILL.md`**

Replace the entire file with:

````markdown
---
name: forge-verify
description: "[read-only] Pre-pipeline checks. --build runs configured build+lint+test. --config validates forge.local.md and forge-config.md against PREFLIGHT constraints. --all runs both. Defaults to --build. Never modifies files."
allowed-tools: ['Read', 'Bash', 'Glob', 'Grep']
disable-model-invocation: false
---

# /forge-verify — Pre-Pipeline Checks

One skill, two checks. `--build` runs the configured build/lint/test commands; `--config` validates configuration files. Both are read-only.

## Subcommand dispatch

Follow `shared/skill-subcommand-pattern.md`. This skill uses flags (the two checks are peer checks with a natural combinator).

**Dispatch rules:**

1. Read `$ARGUMENTS`.
2. Parse flags: `--build`, `--config`, `--all`, `--json`, `--help`.
3. `--build`, `--config`, `--all` are mutually exclusive. If more than one is present: `Only one of --build, --config, --all may be specified.` exit 2.
4. If no mode flag: default is `--build`.
5. If `--help`: print usage and exit 0.
6. Dispatch:
   - `--build` → `### Subcommand: build`
   - `--config` → `### Subcommand: config`
   - `--all` → `### Subcommand: all` (config first, then build)

## Flags

- **--help**: print usage and exit 0
- **--json**: structured JSON output
- **--build**: run build + lint + test (default)
- **--config**: validate forge.local.md and forge-config.md
- **--all**: run --config first, then --build (fail-fast if config invalid)

## Exit codes

See `shared/skill-contract.md` §3.

## Shared prerequisites

Before any subcommand:

1. **Git repository:** `git rev-parse --show-toplevel 2>/dev/null`. If fails: "Not a git repository. Navigate to a project directory." STOP.
2. **Forge initialized:** `.claude/forge.local.md` exists. If not: "No pipeline config found. Run `/forge-init` first." STOP.

---

### Subcommand: build

(Body preserved verbatim from the old `/forge-verify` — Instructions 1–3: check which commands are configured, run sequentially, stop on first failure, summary with PASS/FAIL/UNKNOWN verdict.)

Additional prerequisite: **Commands configured** — read `commands` section from forge.local.md. If ALL three (`build`, `lint`, `test`) are empty/missing: report UNKNOWN verdict with message "No build, lint, or test commands configured. Run `/forge-init` or add them to `.claude/forge.local.md`." STOP.

Read-only — does NOT modify any file.

### Subcommand: config

(Body preserved verbatim from the old `/forge-config-validate` — Steps 1–7: LOCATE CONFIG FILES, REQUIRED FIELDS, VALUE RANGE CHECKS, FILE REFERENCE CHECKS, COMMAND EXECUTABILITY, CROSS-REFERENCE CHECKS, REPORT.)

Delegates schema validation to `${CLAUDE_PLUGIN_ROOT}/shared/validate-config.sh`, which is read-only (no writes, no touch/mkdir/tee — only stderr reporting). The script exits 0 (PASS), 1 (ERROR), or 2 (WARNING-only).

Read-only — validates files, never modifies them. Does NOT execute build/test/lint commands (only checks their first-word executables exist).

### Subcommand: all

Run `config` first. If config validation reports ERROR (non-zero exit from `validate-config.sh` or any required-field ERROR): report "Config validation failed — skipping build check. Fix config errors first." and exit 1. **Do not run build** — running build commands against a broken config produces misleading results.

If config validation passes (or reports only WARNINGs): proceed to run `build`. Combine both reports into a single output.

## Error Handling

| Condition | Action |
|---|---|
| Shared prerequisites fail | Report specific error and STOP |
| Both --build and --config specified | "Only one of --build, --config, --all may be specified." exit 2 |
| Build command fails | Report FAIL with error output. Do not proceed to lint/test |
| Lint command fails | Report FAIL with error output. Do not proceed to test |
| Test command fails | Report FAIL with error output and test failure details |
| Command not found on PATH | "Command not found: {cmd}. Install it or update `.claude/forge.local.md`." |
| Command times out | "Command timed out after {N} seconds. The build/test may be hanging." |
| forge.local.md YAML parse failure (config) | "Could not parse YAML frontmatter in forge.local.md. Check syntax." STOP |
| validate-config.sh exits 1 (config) | Report ERRORs, exit 1 |
| validate-config.sh exits 2 (config WARN only) | Report WARNINGs, exit 0 |
| Plugin root not found (config) | "Could not locate forge plugin root. File reference checks skipped." |

## Important

- NEVER enter fix loops — this is a quick check, not a pipeline run.
- NEVER modify files — not even `.forge/` state.
- SKIPPED is not a failure — it means the command was not configured.
- UNKNOWN means nothing could be verified (distinct from PASS).

## See Also

- `/forge-review --scope=changed` — Review and fix changed files
- `/forge-review --scope=all` — Full codebase audit (read-only)
- `/forge-run` — Full pipeline including verification
- `/forge-recover diagnose` — Diagnose runtime pipeline issues (complementary to config validation)
````

- [ ] **Step 2: Delete `forge-config-validate`**

```bash
git rm -r skills/forge-config-validate
```

- [ ] **Step 3: Sanity-check**

Run: `grep -c '### Subcommand:' skills/forge-verify/SKILL.md`
Expected: `3`

- [ ] **Step 4: Commit**

```bash
git add skills/forge-verify/SKILL.md skills/forge-config-validate
git commit -m "feat(phase5)!: consolidate verify cluster into /forge-verify --build|--config|--all

Merges /forge-config-validate into /forge-verify with --config subcommand.
--build (default) runs build+lint+test. --config validates config files.
--all runs config first (fail-fast), then build. Read-only throughout —
verified that validate-config.sh performs no filesystem writes.

BREAKING CHANGE: /forge-config-validate is removed. Use /forge-verify --config."
```

---

### Task 6: Update the `CLAUDE.md` Skills section and Skill Selection Guide

**Files:**
- Modify: `CLAUDE.md` (multiple edits)

- [ ] **Step 1: Update the §Skills header on line 274**

Change `## Skills (35 total), hooks, kanban, git` → `## Skills (28 total), hooks, kanban, git`.

- [ ] **Step 2: Update the Skills paragraph**

Rewrite the `**Skills:**` paragraph under the new header to list 28 skills with subcommand forms for the three consolidated clusters. Old per-skill entries for `forge-codebase-health`, `forge-deep-health`, `forge-graph-status`, `forge-graph-query`, `forge-graph-rebuild`, `forge-graph-debug`, `forge-config-validate` must be REMOVED. The new entries read:

- `forge-review` (supports `--scope=changed` default, `--scope=all` read-only audit, `--scope=all --fix` iterative cleanup with per-iteration commits and AskUserQuestion safety gate)
- `forge-graph` (subcommands: `init`, `status`, `query <cypher>`, `rebuild`, `debug`)
- `forge-verify` (subcommands: `--build` default, `--config`, `--all`)

- [ ] **Step 3: Update the Skill Selection Guide table (lines ~66–100)**

Rewrite these rows verbatim:

| Intent | Skill | Notes |
|---|---|---|
| Review changed files | `/forge-review` | Default `--scope=changed`. Quick (2 agents) or full (8 agents) with `--full` |
| Review entire codebase | `/forge-review --scope=all` | Read-only analysis, no fixes |
| Fix all codebase issues | `/forge-review --scope=all --fix` | Iterative fix loop; AskUserQuestion gate unless `autonomous: true` or `--yes` |
| Quick build+lint+test | `/forge-verify` | Default `--build`. No pipeline |
| Validate config | `/forge-verify --config` | Pre-pipeline config check (read-only) |
| Graph init/status/query/rebuild/debug | `/forge-graph <sub>` | `init` starts Neo4j; `status` reports health; `query <cypher>` runs read-only Cypher; `rebuild` regenerates project graph; `debug` runs diagnostic recipes |

Remove the old separate rows for `/forge-codebase-health`, `/forge-deep-health`, `/forge-config-validate`, and the five `/forge-graph-*` entries.

- [ ] **Step 4: Update the "Getting started flows" block (lines 105–115)**

Old:
```
New project:       /forge-init → /forge-config-validate → /forge-verify → /forge-run <requirement>
Existing project:  /forge-init → /forge-codebase-health → /forge-deep-health → /forge-run <requirement>
Code quality:      /forge-review --full  (changed files) or /forge-codebase-health (all files)
```

New:
```
New project:       /forge-init → /forge-verify --config → /forge-verify → /forge-run <requirement>
Existing project:  /forge-init → /forge-review --scope=all → /forge-review --scope=all --fix → /forge-run <requirement>
Code quality:      /forge-review --full  (changed files) or /forge-review --scope=all (all files)
```

- [ ] **Step 5: Grep-check — no remaining old skill names in CLAUDE.md**

Run: `grep -E '/forge-(codebase-health|deep-health|config-validate|graph-(status|query|rebuild|debug))' CLAUDE.md`
Expected: no output (exit 1 from grep).

- [ ] **Step 6: Commit**

```bash
git add CLAUDE.md
git commit -m "docs(phase5): update CLAUDE.md Skills section and flows for 28 skills"
```

---

### Task 7: Update `/forge-help` decision tree and `--json` envelope (with `schema_version: \"2\"`)

**Files:**
- Modify: `skills/forge-help/SKILL.md`

- [ ] **Step 1: Replace the "What do you want to do?" section with the ASCII decision tree**

Replace lines 31–125 (the three tier tables + "Similar Skills" table + quick reference) with the spec §4.3 ASCII tree:

```markdown
## What do you want to do?

```
What do you want to do?

├── Build something
│   ├── New feature ................. /forge-run
│   ├── Fix a bug ................... /forge-fix
│   ├── Refine a vague idea ......... /forge-shape
│   └── Scaffold a new project ...... /forge-bootstrap
│
├── Check quality
│   ├── Just my recent changes ...... /forge-review             (default: --scope=changed --fix)
│   ├── The whole codebase (read) ... /forge-review --scope=all
│   ├── The whole codebase (fix) .... /forge-review --scope=all --fix
│   ├── Build + lint + test ......... /forge-verify             (default: --build)
│   ├── Config is correct ........... /forge-verify --config
│   └── Security scan ............... /forge-security-audit
│
├── Work with the knowledge graph
│   └── /forge-graph <init|status|query|rebuild|debug>
│
├── Ship / deploy / commit
│   ├── Deploy ...................... /forge-deploy
│   └── Conventional commit ......... /forge-commit
│
├── Pipeline control
│   ├── Status ...................... /forge-status
│   ├── Abort ....................... /forge-abort
│   ├── Recover ..................... /forge-recover <diagnose|repair|reset|resume|rollback>
│   └── Profile a run ............... /forge-profile
│
├── Know the codebase / history
│   ├── Ask a question .............. /forge-ask
│   ├── Run history ................. /forge-history
│   └── Insights .................... /forge-insights
│
└── Configure / automate / compress
    ├── Edit config ................. /forge-config
    ├── Automations ................. /forge-automation
    ├── Playbooks (list) ............ /forge-playbooks
    ├── Playbooks (refine) .......... /forge-playbook-refine
    ├── Compress .................... /forge-compress <agents|output|status|help>
    ├── Docs generate ............... /forge-docs-generate
    └── Migration ................... /forge-migration

New to forge? → /forge-tour
First setup?  → /forge-init
```

**Tree depth:** maximum 3 levels (root → category → item). Subcommands live inside the skill, not as a 4th tree branch.
```

- [ ] **Step 2: Append the `## Migration (Phase 05)` section**

Add at the bottom of the SKILL body (above `## See Also`):

```markdown
## Migration (Phase 05)

The following skill names were removed in Phase 05. Use the replacement on the right:

| Removed                 | Use instead                              |
|-------------------------|------------------------------------------|
| /forge-codebase-health  | /forge-review --scope=all                |
| /forge-deep-health      | /forge-review --scope=all --fix          |
| /forge-graph-status     | /forge-graph status                      |
| /forge-graph-query      | /forge-graph query <cypher>              |
| /forge-graph-rebuild    | /forge-graph rebuild                     |
| /forge-graph-debug      | /forge-graph debug                       |
| /forge-config-validate  | /forge-verify --config                   |

This section is slated for removal in the release after the next minor bump.
```

- [ ] **Step 3: Update the `## --json output` section**

Replace the existing JSON example with:

````markdown
## --json output

When invoked with `--json`, `/forge-help` emits the decision tree as structured JSON. The envelope carries an explicit `schema_version` so downstream consumers (MCP server F30, `/forge-insights`) can detect the shape:

```json
{
  "schema_version": "2",
  "total_skills": 28,
  "categories": {
    "build": [
      {"name": "forge-run", "mode": "writes", "summary": "Full 10-stage pipeline"},
      {"name": "forge-fix", "mode": "writes", "summary": "Root cause bug fix"},
      {"name": "forge-shape", "mode": "writes", "summary": "Refine a vague idea"},
      {"name": "forge-bootstrap", "mode": "writes", "summary": "Scaffold a new project"}
    ],
    "quality": [
      {
        "name": "forge-review",
        "mode": "writes",
        "summary": "Quality review for changed files or whole codebase",
        "subcommands": [
          {"name": "changed", "mode": "writes", "default": true},
          {"name": "all", "mode": "read-only"},
          {"name": "all --fix", "mode": "writes"}
        ]
      },
      {
        "name": "forge-verify",
        "mode": "read-only",
        "summary": "Pre-pipeline checks",
        "subcommands": [
          {"name": "build", "mode": "read-only", "default": true},
          {"name": "config", "mode": "read-only"},
          {"name": "all", "mode": "read-only"}
        ]
      },
      {"name": "forge-security-audit", "mode": "read-only", "summary": "Security scan"}
    ],
    "knowledge_graph": [
      {
        "name": "forge-graph",
        "mode": "writes",
        "summary": "Neo4j knowledge graph (Docker)",
        "subcommands": [
          {"name": "init", "mode": "writes"},
          {"name": "status", "mode": "read-only"},
          {"name": "query", "mode": "read-only"},
          {"name": "rebuild", "mode": "writes"},
          {"name": "debug", "mode": "read-only"}
        ]
      }
    ]
    // ... remaining categories (ship, pipeline_control, know, configure)
  },
  "removed_in_phase_05": [
    {"name": "forge-codebase-health", "replacement": "/forge-review --scope=all"},
    {"name": "forge-deep-health", "replacement": "/forge-review --scope=all --fix"},
    {"name": "forge-config-validate", "replacement": "/forge-verify --config"},
    {"name": "forge-graph-status", "replacement": "/forge-graph status"},
    {"name": "forge-graph-query", "replacement": "/forge-graph query <cypher>"},
    {"name": "forge-graph-rebuild", "replacement": "/forge-graph rebuild"},
    {"name": "forge-graph-debug", "replacement": "/forge-graph debug"}
  ]
}
```

**Schema version history:**

- **1** (Phase 1 baseline): `{ total_skills: 35, tiers: { essential, power_user, advanced }, similar_skills: [...] }` — flat tier tables.
- **2** (Phase 5, this release): `{ schema_version, total_skills: 28, categories: {...}, removed_in_phase_05: [...] }` — categorized with cluster entries carrying `subcommands` arrays.

Consumers SHOULD switch on `schema_version` rather than sniffing for the presence of `subcommands`.
````

- [ ] **Step 4: Sanity-checks**

Run:
```bash
grep -c 'schema_version' skills/forge-help/SKILL.md
grep -c '## Migration (Phase 05)' skills/forge-help/SKILL.md
```
Expected: both ≥ 1.

- [ ] **Step 5: Commit**

```bash
git add skills/forge-help/SKILL.md
git commit -m "docs(phase5): rewrite /forge-help decision tree + bump --json schema_version to 2"
```

---

### Task 8: Sweep cross-references in shared docs and hooks

**Files to modify (from Task 2 manifest):**
- `README.md`
- `CHANGELOG.md` (add Phase 05 entry; leave historical mentions in older entries)
- `shared/skill-contract.md` §4 ("Skill categorization") — update baseline from 35 to 28 and move names
- `shared/graph/schema.md`
- `shared/graph/schema-versioning.md`
- `shared/graph/enrich-symbols.sh`
- `hooks/automation-trigger.sh`
- `skills/forge-init/SKILL.md`
- `skills/forge-migration/SKILL.md`
- `skills/forge-automation/SKILL.md`
- `skills/forge-docs-generate/SKILL.md`
- `skills/forge-config/SKILL.md`
- `skills/forge-ask/SKILL.md`
- `skills/forge-security-audit/SKILL.md`

- [ ] **Step 1: For each file in the list, apply the same find-and-replace mapping**

| Find | Replace with |
|---|---|
| `/forge-codebase-health` | `/forge-review --scope=all` |
| `/forge-deep-health` | `/forge-review --scope=all --fix` |
| `/forge-config-validate` | `/forge-verify --config` |
| `/forge-graph-init` | `/forge-graph init` |
| `/forge-graph-status` | `/forge-graph status` |
| `/forge-graph-query` | `/forge-graph query` |
| `/forge-graph-rebuild` | `/forge-graph rebuild` |
| `/forge-graph-debug` | `/forge-graph debug` |

Use targeted `Edit` calls — do NOT use `sed -i` or `git ls-files | xargs sed` because some contexts need surrounding prose rewritten (e.g. "run /forge-codebase-health before /forge-deep-health" becomes "run /forge-review --scope=all before /forge-review --scope=all --fix", not just a mechanical slash rewrite).

- [ ] **Step 2: Update `shared/skill-contract.md` §4 specifically**

Current content (line 44–48) lists baseline 35 skills. Rewrite as:

```markdown
## 4. Skill categorization (Phase 5 baseline — 28 skills)

**Read-only (11):** forge-ask, forge-help, forge-history, forge-insights, forge-playbooks, forge-profile, forge-security-audit, forge-status, forge-tour, forge-verify, (plus any subcommand of /forge-graph marked read-only, but the parent skill is classified by maximum impact — see §1).

**Writes (17):** forge-abort, forge-automation, forge-bootstrap, forge-commit, forge-compress, forge-config, forge-deploy, forge-docs-generate, forge-fix, forge-graph, forge-init, forge-migration, forge-playbook-refine, forge-recover, forge-review, forge-run, forge-shape, forge-sprint.

**Total: 28.** `/forge-graph` is `[writes]` (its `init` and `rebuild` subcommands write) even though `status`, `query`, and `debug` are read-only — the badge reflects maximum impact per §1.
```

- [ ] **Step 3: Add CHANGELOG Phase 05 entry**

Prepend to `CHANGELOG.md` (under a new `## [Unreleased]` or the next version's section):

```markdown
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
```

- [ ] **Step 4: Verify cleanup**

Run:
```bash
grep -rln -E '/forge-(codebase-health|deep-health|config-validate|graph-(status|query|rebuild|debug))' \
  --include='*.md' --include='*.json' --include='*.sh' --include='*.bats' --include='*.bash' \
  -- . \
  | grep -v '^./docs/superpowers/' \
  | grep -v '^./skills/forge-help/SKILL.md$' \
  | grep -v '^./CHANGELOG.md$'
```
Expected: no output (every remaining reference is in an allowed location).

- [ ] **Step 5: Commit**

```bash
git add README.md CHANGELOG.md shared/skill-contract.md shared/graph/schema.md \
        shared/graph/schema-versioning.md shared/graph/enrich-symbols.sh \
        hooks/automation-trigger.sh skills/forge-init/SKILL.md \
        skills/forge-migration/SKILL.md skills/forge-automation/SKILL.md \
        skills/forge-docs-generate/SKILL.md skills/forge-config/SKILL.md \
        skills/forge-ask/SKILL.md skills/forge-security-audit/SKILL.md
git commit -m "refactor(phase5): sweep cross-references from old to new skill names"
```

---

### Task 9: Update existing skill-contract test

**Files:**
- Modify: `tests/contract/skill-contract.bats`

The contract test reads the 35-skill baseline from `shared/skill-contract.md` §4. Task 8 updated §4 to 28. This task updates the test's hard-coded expectations.

- [ ] **Step 1: Open the file and locate skill-count assertions**

Run: `grep -n '35\|forge-codebase-health\|forge-deep-health\|forge-config-validate' tests/contract/skill-contract.bats`

- [ ] **Step 2: For each match, update to the new baseline**

Replace `35` with `28` where it refers to total skill count. Remove the seven deleted skills from any enumerated lists. Add `forge-graph` (singular) where `forge-graph-init` etc. appeared.

- [ ] **Step 3: Also update `tests/contract/graph-debug-skill.bats`**

This test references `/forge-graph-debug` by name. Replace with `/forge-graph debug` (positional subcommand). If the test asserts the presence of `skills/forge-graph-debug/SKILL.md` specifically, update it to assert `skills/forge-graph/SKILL.md` contains a `### Subcommand: debug` section.

- [ ] **Step 4: Also update `tests/unit/skill-execution/skill-error-handling.bats`**

Run: `grep -n 'forge-codebase-health\|forge-deep-health\|forge-config-validate\|forge-graph-' tests/unit/skill-execution/skill-error-handling.bats`
Apply the same rewrites. Keep `forge-graph-init` references intact only if they appear inside strings that became `/forge-graph init` after rewrite.

- [ ] **Step 5: Commit**

```bash
git add tests/contract/skill-contract.bats tests/contract/graph-debug-skill.bats \
        tests/unit/skill-execution/skill-error-handling.bats
git commit -m "test(phase5): update existing contract+unit tests for 28-skill baseline"
```

---

### Task 10: Bump `tests/lib/module-lists.bash` with `MIN_SKILLS=28` and expected-names fixture

**Files:**
- Modify: `tests/lib/module-lists.bash`

- [ ] **Step 1: Open `tests/lib/module-lists.bash`**

- [ ] **Step 2: Before the "Minimum count guards" section (around line 73), add skill discovery**

```bash
# Skills: directories under skills/ containing SKILL.md
DISCOVERED_SKILLS=()
for d in "$PLUGIN_ROOT"/skills/*/; do
  [[ -d "$d" && -f "$d/SKILL.md" ]] && DISCOVERED_SKILLS+=("$(basename "$d")")
done
```

- [ ] **Step 3: Add the count guard and canonical-names fixture**

In the "Minimum count guards" section, add:

```bash
MIN_SKILLS=28

# Canonical post-Phase-05 skill names. Tasks are written to ensure the skills
# directory contains exactly this set. `DISCOVERED_SKILLS` is compared to
# `EXPECTED_SKILL_NAMES` by `tests/structural/skill-consolidation.bats`.
EXPECTED_SKILL_NAMES=(
  forge-abort
  forge-ask
  forge-automation
  forge-bootstrap
  forge-commit
  forge-compress
  forge-config
  forge-deploy
  forge-docs-generate
  forge-fix
  forge-graph
  forge-help
  forge-history
  forge-init
  forge-insights
  forge-migration
  forge-playbook-refine
  forge-playbooks
  forge-profile
  forge-recover
  forge-review
  forge-run
  forge-security-audit
  forge-shape
  forge-sprint
  forge-status
  forge-tour
  forge-verify
)
```

(Array has exactly 28 entries — verify with `wc -l` after paste.)

- [ ] **Step 4: Verify discovery matches expectation**

Run:
```bash
cd /Users/denissajnar/IdeaProjects/forge
ls skills/ | wc -l
```
Expected: `28` (after Tasks 3/4/5/7 deletions).

- [ ] **Step 5: Commit**

```bash
git add tests/lib/module-lists.bash
git commit -m "test(phase5): add MIN_SKILLS=28 and EXPECTED_SKILL_NAMES fixture"
```

---

### Task 11: Add structural test for skill consolidation (TDD tests green here)

**Files:**
- Create: `tests/structural/skill-consolidation.bats`

This is the first task whose commit should flip CI green. Tests cover: (a) exact skill count, (b) no forbidden old-skill names, (c) each consolidated skill has the expected dispatch block + subcommand sections, (d) `/forge-help` has `schema_version: "2"` and the Migration table, (e) `validate-config.sh` has no write operations (I1 regression guard), (f) cross-reference cleanup.

- [ ] **Step 1: Write the failing test**

```bash
#!/usr/bin/env bats

load ../lib/module-lists.bash

setup() {
  PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}

@test "skill count is exactly MIN_SKILLS (28)" {
  actual=$(ls -d "$PLUGIN_ROOT"/skills/*/ 2>/dev/null | wc -l | tr -d ' ')
  [ "$actual" -eq 28 ]
}

@test "every expected skill directory exists with SKILL.md" {
  for name in "${EXPECTED_SKILL_NAMES[@]}"; do
    [ -f "$PLUGIN_ROOT/skills/$name/SKILL.md" ] || \
      { echo "MISSING: skills/$name/SKILL.md"; return 1; }
  done
}

@test "no removed Phase-05 skill directories exist" {
  removed=(
    forge-codebase-health
    forge-deep-health
    forge-config-validate
    forge-graph-init
    forge-graph-status
    forge-graph-query
    forge-graph-rebuild
    forge-graph-debug
  )
  for name in "${removed[@]}"; do
    [ ! -e "$PLUGIN_ROOT/skills/$name" ] || \
      { echo "STILL PRESENT: skills/$name"; return 1; }
  done
}

@test "forge-review has exactly one '## Subcommand dispatch' section" {
  count=$(grep -c '^## Subcommand dispatch' "$PLUGIN_ROOT/skills/forge-review/SKILL.md")
  [ "$count" -eq 1 ]
}

@test "forge-graph has exactly one '## Subcommand dispatch' section" {
  count=$(grep -c '^## Subcommand dispatch' "$PLUGIN_ROOT/skills/forge-graph/SKILL.md")
  [ "$count" -eq 1 ]
}

@test "forge-verify has exactly one '## Subcommand dispatch' section" {
  count=$(grep -c '^## Subcommand dispatch' "$PLUGIN_ROOT/skills/forge-verify/SKILL.md")
  [ "$count" -eq 1 ]
}

@test "forge-review has 'changed' and 'all' and 'all --fix' subcommand sections" {
  file="$PLUGIN_ROOT/skills/forge-review/SKILL.md"
  grep -q '^### Subcommand: changed' "$file"
  grep -q '^### Subcommand: all' "$file"
  grep -q '^### Subcommand: all --fix' "$file"
}

@test "forge-graph has all 5 positional subcommand sections" {
  file="$PLUGIN_ROOT/skills/forge-graph/SKILL.md"
  for sub in init status query rebuild debug; do
    grep -q "^### Subcommand: $sub" "$file" || \
      { echo "MISSING: ### Subcommand: $sub"; return 1; }
  done
}

@test "forge-verify has build, config, and all subcommand sections" {
  file="$PLUGIN_ROOT/skills/forge-verify/SKILL.md"
  grep -q '^### Subcommand: build' "$file"
  grep -q '^### Subcommand: config' "$file"
  grep -q '^### Subcommand: all' "$file"
}

@test "forge-review --scope=all --fix documents AskUserQuestion safety gate" {
  file="$PLUGIN_ROOT/skills/forge-review/SKILL.md"
  # The gate MUST be documented under the all --fix subcommand.
  grep -q 'AskUserQuestion' "$file"
  grep -qi 'safety.*gate\|safety-confirm\|confirm.*gate' "$file"
  grep -q '\-\-yes' "$file"
}

@test "forge-help declares schema_version '2' in --json example" {
  grep -q '"schema_version":[[:space:]]*"2"' "$PLUGIN_ROOT/skills/forge-help/SKILL.md"
}

@test "forge-help total_skills in --json is 28" {
  grep -q '"total_skills":[[:space:]]*28' "$PLUGIN_ROOT/skills/forge-help/SKILL.md"
}

@test "forge-help has Migration (Phase 05) section" {
  grep -q '^## Migration (Phase 05)' "$PLUGIN_ROOT/skills/forge-help/SKILL.md"
}

@test "CLAUDE.md Skills header reads '(28 total)'" {
  grep -q '^## Skills (28 total)' "$PLUGIN_ROOT/CLAUDE.md"
}

@test "shared/skill-subcommand-pattern.md exists" {
  [ -f "$PLUGIN_ROOT/shared/skill-subcommand-pattern.md" ]
}

@test "validate-config.sh is read-only (I1 regression guard)" {
  # No touch, mkdir, tee, or stdout redirection to filesystem paths.
  # Allowed: echo >&2 (stderr), case-statement redirections.
  forbidden=$(grep -nE '(\b(touch|mkdir|tee)\b|>\s*[./a-zA-Z]|>>\s*[./a-zA-Z])' \
                   "$PLUGIN_ROOT/shared/validate-config.sh" \
                | grep -vE '>\s*&\s*[12]|2>\s*>?[&/]|^[^:]*:[[:space:]]*#' \
                || true)
  [ -z "$forbidden" ] || { echo "FORBIDDEN WRITES in validate-config.sh:"; echo "$forbidden"; return 1; }
}

@test "no dangling references to removed skill names (outside allowed allowlist)" {
  cd "$PLUGIN_ROOT"
  dangling=$(grep -rln -E '/forge-(codebase-health|deep-health|config-validate|graph-(status|query|rebuild|debug))' \
               --include='*.md' --include='*.json' --include='*.sh' --include='*.bats' --include='*.bash' \
               -- . 2>/dev/null \
             | grep -v '^./docs/superpowers/' \
             | grep -v '^./skills/forge-help/SKILL.md$' \
             | grep -v '^./CHANGELOG.md$' \
             | grep -v '^./tests/structural/skill-consolidation.bats$' \
             || true)
  [ -z "$dangling" ] || { echo "DANGLING:"; echo "$dangling"; return 1; }
}

@test "forge-help decision tree nesting is at most 3 levels deep" {
  # Count leading │/├/└ indentation levels in the tree block.
  # Level 1 = category (├──), Level 2 = item (│   ├──), Level 3 is forbidden.
  file="$PLUGIN_ROOT/skills/forge-help/SKILL.md"
  # Any line that starts with 3+ nested │ bars indicates level 4+.
  deep=$(grep -cE '^│[[:space:]]+│[[:space:]]+│' "$file" || true)
  [ "$deep" -eq 0 ] || { echo "Tree exceeds 3 levels deep: $deep lines with 3+ bars"; return 1; }
}
```

- [ ] **Step 2: Run the new test file**

Run: `./tests/lib/bats-core/bin/bats tests/structural/skill-consolidation.bats`
Expected: all 17 tests PASS. If any fail, the preceding task has a gap — fix it before committing.

- [ ] **Step 3: Run the full structural + contract suite**

Run: `./tests/run-all.sh structural` and `./tests/run-all.sh contract`
Expected: all green. If `tests/contract/skill-contract.bats` or `tests/contract/graph-debug-skill.bats` is red, Task 9 has a gap.

- [ ] **Step 4: Commit**

```bash
git add tests/structural/skill-consolidation.bats
git commit -m "test(phase5): add skill-consolidation structural tests (17 assertions)"
```

---

### Task 12: Self-review and final verification

This is a human-driven review pass, not a code change. Still ends with a commit if any fix is needed.

- [ ] **Step 1: Rerun the full test suite**

Run: `./tests/run-all.sh`
Expected: all green. Note any flakes.

- [ ] **Step 2: Manually walk through `/forge-help`**

Open `skills/forge-help/SKILL.md`. Sanity checks:
- Tree is rendered with box-drawing characters (no corruption).
- Migration table lists all 7 removed skills with correct replacements.
- `--json` example parses as valid JSON (paste into a JSON validator).
- `schema_version: "2"` is present.
- `total_skills: 28` is present.

- [ ] **Step 3: Manually walk through `/forge-review` safety gate**

Open `skills/forge-review/SKILL.md`. Sanity checks:
- `### Subcommand: all --fix` section exists.
- Section explicitly mentions `AskUserQuestion`.
- Section documents the `--yes` flag AND the `autonomous: true` config bypass AND `--dry-run` bypass.
- Section specifies "Abort" returns exit code 4.

- [ ] **Step 4: Manually verify `validate-config.sh` is untouched**

Run: `git log --oneline shared/validate-config.sh | head -5`
Expected: the most recent commit predates Phase 05. Phase 05 should NOT have modified this file.

- [ ] **Step 5: Grep-check cross-reference sweep is complete**

Run:
```bash
grep -rln -E '/forge-(codebase-health|deep-health|config-validate|graph-(status|query|rebuild|debug))' \
  --include='*.md' --include='*.json' --include='*.sh' --include='*.bats' --include='*.bash' -- . \
  | grep -v '^./docs/superpowers/' \
  | grep -v '^./skills/forge-help/SKILL.md$' \
  | grep -v '^./CHANGELOG.md$' \
  | grep -v '^./tests/structural/skill-consolidation.bats$'
```
Expected: no output.

- [ ] **Step 6: If any fix is needed, commit it**

If Steps 1–5 surface a gap:
- Fix it inline (edit the offending file).
- Re-run `./tests/run-all.sh`.
- Commit:

```bash
git add <files>
git commit -m "fix(phase5): <specific fix from self-review>"
```

If no fix is needed: no additional commit. Phase 05 implementation is complete.

- [ ] **Step 7: Bump plugin.json**

Open `plugin.json`. Bump version from `3.0.0` to `3.1.0` (minor — new user-facing surface, breaking changes to skill names).

Run: `grep '"version"' plugin.json`
Expected: `"version": "3.1.0"`.

- [ ] **Step 8: Final commit**

```bash
git add plugin.json
git commit -m "chore(phase5): bump plugin version to 3.1.0 for skill consolidation

35 → 28 skills via subcommand dispatch. See CHANGELOG.md for migration table."
```

---

## Self-Review (by plan author)

**Spec coverage check:**

| Spec section | Plan task(s) |
|---|---|
| §3 Scope — Review cluster | Task 3 |
| §3 Scope — Graph cluster | Task 4 |
| §3 Scope — Verify cluster | Task 5 |
| §3 Scope — Delete old directories | Tasks 3, 4, 5 |
| §3 Scope — Unified subcommand-dispatch section | Task 1 (contract), Tasks 3/4/5 (per-skill) |
| §3 Scope — `/forge-help` tree + CLAUDE.md §Skills | Tasks 6, 7 |
| §3 Scope — `shared/skill-subcommand-pattern.md` | Task 1 |
| §3 Scope — `--json` envelope rewrite | Task 7 |
| §3 Scope — `tests/lib/module-lists.bash` | Task 10 |
| §4.1 dispatch algorithm | Task 1 contract + referenced in Tasks 3/4/5 |
| §4.2 arg-parsing helper | Task 1 |
| §4.3 decision tree | Task 7 |
| §5.4 shared doc | Task 1 |
| §5.5 `/forge-help` update | Task 7 |
| §5.6 CLAUDE.md update | Task 6 |
| §7 no-aliases hard-break | Enforced in Tasks 3/4/5 (delete directories) + Task 11 (structural test) |
| §7 migration table in `/forge-help` | Task 7 |
| §8 Testing (items 1–7) | Task 11 (17 assertions covering all 7 items) |
| §9 Rollout — single PR | All tasks produce commits on a single branch |
| §11 Success Criteria | Covered by Task 11 structural test + Task 12 manual review |
| Review I1 (validate-config.sh read-only) | Verified in plan; regression guard in Task 11 |
| Review I2 (safety-confirm gate) | Concrete requirement in Task 3 + assertion in Task 11 |
| Review S1 (schema_version) | Explicit in Task 7 + assertion in Task 11 |

All spec sections accounted for. No placeholder language remains in the plan.

**Type consistency check:** skill names, subcommand names, and flag names used consistently across tasks. `--scope=all --fix` and `--scope=all --fix` are the same string everywhere. `### Subcommand: all --fix` is the section heading in both Task 3 and Task 11.

**Known risks the implementer should watch:**
1. CI will be red between Task 2 and Task 11 — that is by design. The structural test in Task 11 is the first task whose commit restores green.
2. `git mv skills/forge-graph-init skills/forge-graph` in Task 4 must happen BEFORE the content rewrite, otherwise git sees delete+add and history is lost.
3. The `schema_version` check in Task 11 is a string match on the `--json` example in `/forge-help/SKILL.md`. Task 7 must keep the quotes exactly as `"schema_version": "2"`.
4. The decision-tree depth check in Task 11 assumes the tree block uses `│   ` (four characters) as the indent unit. If Task 7's tree uses a different indent, update the grep pattern accordingly.
