# Design: `/forge-review` Skill

## Problem Statement

Iterative development workflows (Ralph Loop, manual fix cycles, `/deep-health`) need a way to verify and fix code quality issues using forge's own review agents without running the full 10-stage pipeline. Currently, users must either use the external `/requesting-code-review` (single general-purpose agent, no scoring, no fixes) or manually dispatch forge agents. Neither is practical for repeated use in loops.

## Solution

A standalone `/forge-review` skill that dispatches forge review agents against changed files, fixes all findings, re-verifies, and loops until clean (score 100) or max iterations reached. Two modes: **quick** (core 3 agents, for mid-iteration checks) and **full** (all applicable agents, for final reviews).

## Interface

```
/forge-review                          # Quick review+fix of changes since last commit
/forge-review --full                   # Full review+fix with all applicable agents
/forge-review --range abc123..def456   # Custom commit range
/forge-review --files "src/**/*.kt"    # Specific files only
/forge-review --max-iterations 5       # Override inner loop cap (default: 3)
```

Flags are combinable: `/forge-review --full --range abc123..HEAD`

## Behavior

### 1. Determine Scope

Compute the file list:
- **Default (no flags):** `git diff --name-only HEAD~1..HEAD` + `git diff --name-only` (staged + unstaged uncommitted changes). If no commits exist, use all tracked source files.
- **`--range <base>..<head>`:** `git diff --name-only <base>..<head>`
- **`--files <pattern>`:** Glob expansion against project root.

Filter to source files only (same extensions as `/codebase-health`).

If zero files match: report "No changed files to review." and exit with PERFECT.

### 2. Select Agents

**Quick mode (default):** Core 3 agents always dispatched:
- `forge:architecture-reviewer`
- `forge:security-reviewer`
- `forge:code-quality-reviewer`

**Full mode (`--full`):** Core 3 + conditional agents based on file types:

| Agent | Condition |
|---|---|
| `forge:docs-consistency-reviewer` | Any `.md` files or code with doc comments |
| `forge:frontend-reviewer` | `*.tsx`, `*.jsx`, `*.vue`, `*.svelte`, `*.html` |
| `forge:frontend-performance-reviewer` | Frontend files present |
| `forge:frontend-design-reviewer` | Frontend files with styling/layout (`*.css`, `*.scss`, `*.styled.*`) |
| `forge:frontend-a11y-reviewer` | Frontend files present |
| `forge:backend-performance-reviewer` | Backend source files (`*.kt`, `*.java`, `*.py`, `*.go`, `*.rs`, `*.cs`) |
| `forge:version-compat-reviewer` | Dependency files (`package.json`, `build.gradle.kts`, `go.mod`, `Cargo.toml`, `*.csproj`) |
| `forge:infra-deploy-reviewer` | `Dockerfile`, `*.yaml`/`*.yml` with k8s markers, Helm charts |

### 3. Review-Fix-Verify Loop

```
ITERATION = 0
MAX_ITERATIONS = 3 (or --max-iterations value)

LOOP:
  ITERATION += 1

  Step A — DISPATCH review agents (parallel, max 3 concurrent)
    Each agent receives: file list, conventions path, "Report ALL findings"

  Step B — COLLECT & SCORE
    Deduplicate findings by (file, line, category) — keep highest severity
    Score: max(0, 100 - 20*CRITICAL - 5*WARNING - 2*INFO)

  Step C — CHECK VERDICT
    If score == 100: BREAK → report PERFECT
    If ITERATION >= MAX_ITERATIONS: BREAK → report final verdict

  Step D — FIX all findings (highest severity first)
    For each finding:
      1. Read the affected file and surrounding context
      2. Challenge: is there a better solution than the obvious fix?
      3. Fix following existing project conventions
      4. If fix changes behavior, update affected documentation
    After all fixes: run build/test/lint if available. If tests fail, fix regressions before continuing.

  Step E — UPDATE scope
    Narrow file list to files touched by fixes: git diff --name-only
    GOTO LOOP
```

**Key rules:**
- Fix ALL severities (CRITICAL, WARNING, INFO). The target is 100, not just "no criticals."
- Each loop iteration narrows scope to only files changed by fixes (prevents re-scanning everything).
- Build/test/lint runs after fixes to catch regressions before re-verification.
- The inner loop hard cap (default 3) prevents oscillation. If findings persist after 3 rounds, report them as unfixable.

### 4. Report Verdict

| Score | Condition | Verdict |
|---|---|---|
| 100 | Perfect | **PERFECT** — no findings, ready to ship |
| >= 80, 0 CRITICALs | Acceptable but imperfect | **PASS** — remaining findings listed |
| 60-79, 0 CRITICALs | Minor issues | **CONCERNS** — could not reach 100 |
| < 60 or any CRITICAL | Blocking issues | **FAIL** — critical issues remain |

**Target is always 100.** Only PERFECT means "nothing left to improve."

Output format:
```
## Forge Review -- {PERFECT|PASS|CONCERNS|FAIL} (Score: {N}/100)

**Mode:** {quick|full} | **Files reviewed:** {count} | **Agents dispatched:** {count}
**Iterations:** {N}/{max} | **Findings fixed:** {fixed_count} | **Remaining:** {remaining_count}

### Fixed ({fixed_count})
- `file:line` | CATEGORY | SEVERITY | what was fixed

### Remaining ({remaining_count})  [omitted if PERFECT]
- `file:line` | CATEGORY | SEVERITY | message | reason unfixable

### Verdict
{Contextual summary}
```

If PERFECT on first pass: "PERFECT -- Score: 100/100. No findings on first review."

## Relationship to Other Skills

| Skill | Purpose | Fixes? | Agents? | Use when |
|---|---|---|---|---|
| `/forge-review` | Review + fix changed files | Yes | 3 or 11 | After any code changes, in iterative loops |
| `/deep-health` | Deep investigation + fix entire codebase | Yes | 11 | Full audit, finding issues you don't know about |
| `/codebase-health` | Check engine scan (Layer 1+2) | No | 0 | Quick convention/pattern violation scan |
| `/verify` | Build + lint + test | No | 0 | Verify code compiles and tests pass |

**Key distinction:** `/forge-review` reviews changes you just made. `/deep-health` investigates the whole codebase for issues you don't know about. `/forge-review` is the verification step; `/deep-health` is the investigation step.

## Integration Points

- **Ralph Loop:** `/forge-review` at each iteration (quick), `/forge-review --full` at final iteration
- **Manual workflow:** Run after any code changes, before committing
- **`/deep-health`:** Could delegate its verification step (Step 6) to `/forge-review --full` (future refactor)
- **Pipeline complement:** Lighter than Stage 6 (REVIEW), usable outside the full pipeline

## Error Handling

- **Agent dispatch failure:** Skip failed agent, continue with remaining. Log WARNING. If all agents fail, report ERROR and exit.
- **Fix introduces regression (tests fail):** Revert the fix, mark finding as "unfixable: fix caused regression", continue with next finding.
- **No conventions file:** Agents run without conventions context. Log INFO.
- **Build/test command unknown:** Skip the build/test step. Log WARNING: "No build/test command detected — fixes not verified against test suite."

## Implementation Notes

- Skill file: `skills/forge-review/SKILL.md`
- No shell scripts needed — agent dispatch and fixes handled by Claude runtime via Agent and Edit/Write tools
- Add to CLAUDE.md skills list (22 skills after addition)
- Add to README skills directory listing
- Regenerate `seed.cypher` after adding the skill directory

## Out of Scope

- Deep codebase investigation (that's `/deep-health`)
- Check engine Layer 1/Layer 2 scanning (that's `/codebase-health`)
- CI/CD integration (future — would need a shell wrapper)
- Custom reviewer selection (e.g., "only run security") — use `--full` or default
- Writing to `.forge/` state or creating tickets/PRs
