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

Final report (verdict table, terse caveman-mode format, severity markers):

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

When `.forge/caveman-mode` exists and is not `off`, compress the final report using text markers (`[CRIT]`, `[WARN]`, `[INFO]`, `[PASS]`). The finding data is unchanged — only the presentation format is compressed.

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

Produce a `## Codebase Health Report` block (categories table, top 10 issues, etc.) replacing the old `/forge-review --scope=all` body.

#### 4. Save the report

Write the full report to `.forge/health-report.md` (preserved path for tooling that greps it). This is the ONLY file this subcommand writes.

**Do NOT fix issues.** If the user wants fixes, they must re-run with `--scope=all --fix`.

---

### Subcommand: all --fix

Iterative fix loop across the whole codebase with per-iteration commits. Replaces the old `/forge-review --scope=all --fix`. **Destructive** — commits are real; a bad fix is on `HEAD`.

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

Same loop as the old `/forge-review --scope=all --fix`. Dispatch reviewer roster (selected by file types), collect findings, triage by severity, fix with project conventions, run `build`/`test`/`lint`, revert regressions, re-dispatch to verify, and commit with a conventional-commit message once the iteration is clean.

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
