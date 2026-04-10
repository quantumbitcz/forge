---
name: deep-health
description: Deep iterative codebase health investigation and fix loop. Dispatches forge's own review agents for investigation and verification, fixes all findings including minor, commits per iteration. Loops until all review agents report clean. Use on any codebase.
disable-model-invocation: false
---

# /deep-health — Deep Iterative Codebase Health Fix

You are an autonomous codebase health improvement loop. You dispatch forge's own review agents to find issues, fix aggressively, re-dispatch to verify, and iterate until clean. Every iteration ends with a commit.

**Core principle:** The same forge review agents that find issues also verify fixes. No separate "investigation" vs "review" — one set of agents, used twice per iteration.

## Philosophy

- **Challenge every design decision.** For each issue found, ask: "Is there a better solution?" before fixing. Search the internet for best practices and documentation when needed (Context7, WebSearch).
- **Fix everything, including minor issues.** Minor issues compound. If any reviewer flags it, fix it.
- **Small commits.** Each iteration produces its own focused commit. Never batch unrelated fixes.
- **Verify against documentation.** Every fix must be consistent with the project's documented decisions, conventions, and contracts.
- **Reuse, don't reinvent.** All investigation and verification is done by forge's 8 existing review agents — the same agents used by the pipeline quality gate.

## Instructions

### 1. Determine Scope

Parse `$ARGUMENTS`:

- **No arguments:** All source files in the project.
- **`--changed`:** Only files changed in current branch vs main/master.
- **`--files <pattern>`:** Specific files or directories.
- **`--focus <domain>`:** Limit to: `architecture`, `security`, `performance`, `quality`, `tests`, `docs`, `frontend`, or `all` (default).
- **`--max-iterations <N>`:** Override iteration cap (default: 5).

### 2. Baseline — Run Check Engine + Collect File List

```bash
PROJECT_ROOT=$(git rev-parse --show-toplevel)
# Get files to investigate
FILES=$(git diff --name-only $(git merge-base origin/master HEAD 2>/dev/null || echo HEAD~10)..HEAD 2>/dev/null)
[ -z "$FILES" ] && FILES=$(git ls-files --cached --exclude-standard | grep -E '\.(kt|kts|java|ts|tsx|js|jsx|py|go|rs|c|h|cs|cpp|swift|rb|php|dart|ex|scala|vue|svelte|html|css|scss)$')
```

Run the check engine for a fast baseline scan (Layer 1 + Layer 2):
```bash
echo "$FILES" | while read -r f; do
  "${CLAUDE_PLUGIN_ROOT}/shared/checks/engine.sh" --review --project-root "$PROJECT_ROOT" --files-changed "$PROJECT_ROOT/$f" 2>/dev/null
done
```

Record baseline score. Save `ITERATION_BASE_SHA=$(git rev-parse HEAD)`.

### 3. Investigation — Dispatch Forge Review Agents

Dispatch forge's own review agents to investigate the scoped files. Select agents based on `--focus` and file types:

| Agent | Dispatched when |
|---|---|
| `forge:fg-410-code-reviewer` | Always (unless `--focus` excludes) |
| `forge:fg-411-security-reviewer` | Always |
| `forge:fg-412-architecture-reviewer` | Always (unless `--focus` excludes) |
| `forge:fg-418-docs-consistency-reviewer` | Always (or `--focus docs`) |
| `forge:fg-413-frontend-reviewer` (mode: `full`) | Frontend files (code, styling, layout, a11y, performance) |
| `forge:fg-416-backend-performance-reviewer` | Backend files present |
| `forge:fg-417-version-compat-reviewer` | Dependency files changed (package.json, build.gradle.kts, go.mod, etc.) |
| `forge:fg-419-infra-deploy-reviewer` | Infra files present (Dockerfile, helm, k8s manifests) |
| `forge:fg-420-dependency-reviewer` | Dependency manifests present |

Dispatch applicable agents **in parallel** (max 3 at a time to manage context). Each receives:
- File list to investigate
- Conventions file path (from `.claude/forge.local.md` if present)
- Focus: "Deep health investigation — report ALL findings, not just critical"

Agents return findings in standard format: `file:line | CATEGORY | SEVERITY | message | fix_hint`

### 4. Triage & Score

Compile ALL findings from all agents. Deduplicate by `(file, line, category)` — keep highest severity. Score: `max(0, 100 - 20*CRITICAL - 5*WARNING - 2*INFO)`.

Prioritize:
1. **Critical** — fix first
2. **Warning** — fix second
3. **Info** — fix third (do NOT skip)

### 5. Fix Phase

For each finding (highest severity first):

1. **Challenge the approach.** Before fixing, consider: is there a fundamentally better design? Search docs (Context7) if needed. If the current code is fine, fix minimally. If a better approach exists, implement it.
2. **Fix the issue.** Follow existing project conventions.
3. **Update documentation.** If the fix changes behavior, update all affected docs.
4. **Run build/test/lint** after each logical group of fixes. Stop if tests fail — fix the regression before continuing.

### 6. Verification — Re-Dispatch Review Agents

After all fixes are applied and tests pass, re-dispatch the SAME review agents against the changed files:

```bash
git diff --name-only $ITERATION_BASE_SHA..HEAD
```

Process findings:
- **Any severity:** Fix immediately. The goal is a clean pass, not just "no criticals".
- If new findings emerge from the verification round, fix those too.
- Loop: fix → re-dispatch → fix, until agents find zero new issues or score reaches 100.

Inner verification loop hard cap: 3 passes per iteration (prevents oscillation).

### 7. Commit

After verification is clean:

```bash
git add <changed files — be specific, no git add -A>
git commit -m "<type>: <concise description>"
```

One commit per iteration. Follow project commit conventions per `shared/git-conventions.md` — check for existing hooks (Husky, commitlint, etc.) and adopt the project's format.

### 8. Loop Decision

- **Continue** if: previous iteration fixed issues AND iteration count < max (default 5).
- **Stop** if: zero new findings in investigation, OR max iterations reached, OR the fixes in the last iteration were purely cosmetic with no behavioral impact.

If continuing: return to Step 3 (Investigation), but narrow scope to files affected by the previous iteration's changes. This prevents re-scanning the entire codebase.

### 9. Final Full Review

After the loop ends, dispatch ALL forge review agents one final time against the full diff range:

```bash
FULL_BASE=$(git merge-base origin/master HEAD 2>/dev/null || git merge-base origin/main HEAD 2>/dev/null || echo $INITIAL_BASE_SHA)
FULL_HEAD=$(git rev-parse HEAD)
git diff --name-only $FULL_BASE..$FULL_HEAD
```

This catches cross-iteration inconsistencies. Score the result.

**Report to user:**
```
## Deep Health Complete

Iterations: {N}
Issues fixed: {M} ({critical} critical, {warning} warnings, {info} info)
Final score: {S}/100
Commits: {list of commit SHAs + messages}

### Remaining (if any)
- {issue}: {reason not fixed — out of scope / intentional design / accepted trade-off}
```

Save to `.forge/deep-health-report.md`.

## Configuration

Respects `forge-config.md` parameters when available:
- `max_iterations` — iteration cap (default: 5)
- `pass_threshold` — minimum quality score (default: 80)
- `autonomous` — if true, skip user confirmation between iterations
- `convergence.oscillation_tolerance` — score delta considered "no progress"

## When to Use

- After a major feature is complete and ready for final polish
- Before a release to ensure codebase quality
- When technical debt has accumulated
- After merging multiple PRs to verify integration quality
- On any codebase — not limited to forge consumers

## Important

- This skill **MODIFIES files** — it's not read-only like `/codebase-health`
- Each iteration creates a commit — review with `git log`
- Hard cap of 5 iterations prevents infinite loops (configurable via `--max-iterations`)
- If the project has no tests, fix phase skips test verification but review agents still run
- Internet search (Context7, WebSearch) validates fixes against current documentation
