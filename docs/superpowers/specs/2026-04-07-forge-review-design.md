# Design: `/forge-review` Skill

## Problem Statement

Iterative development workflows (Ralph Loop, manual fix cycles, `/deep-health`) need a way to verify code quality using forge's own review agents without running the full 10-stage pipeline. Currently, users must either use the external `/requesting-code-review` (single general-purpose agent, no scoring) or manually dispatch forge agents. Neither is practical for repeated use in loops.

## Solution

A standalone `/forge-review` skill that dispatches forge review agents against changed files and returns a scored verdict. Two modes: **quick** (core 3 agents, for mid-iteration checks) and **full** (all applicable agents, for final reviews).

## Interface

```
/forge-review                          # Quick review of changes since last commit
/forge-review --full                   # Full review with all applicable agents
/forge-review --range abc123..def456   # Custom commit range
/forge-review --files "src/**/*.kt"    # Specific files only
```

Flags are combinable: `/forge-review --full --range abc123..HEAD`

## Behavior

### 1. Determine Scope

Compute the file list:
- **Default (no flags):** `git diff --name-only HEAD~1..HEAD` + `git diff --name-only` (staged + unstaged uncommitted changes). If no commits exist, use all tracked source files.
- **`--range <base>..<head>`:** `git diff --name-only <base>..<head>`
- **`--files <pattern>`:** Glob expansion against project root.

Filter to source files only (same extensions as `/codebase-health`).

If zero files match: report "No changed files to review." and exit with PASS.

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

### 3. Dispatch Agents

Dispatch selected agents **in parallel** (max 3 concurrent to manage context). Each agent receives:
- Changed file list with full paths
- Conventions file path (from `.claude/forge.local.md` if present, otherwise omit)
- Review focus: "Review these changes. Report ALL findings with severity (CRITICAL/WARNING/INFO) and category."

### 4. Collect & Score

Compile all findings from all agents. Deduplicate by `(file, line, category)` — keep highest severity on collision.

Score using the forge formula: `max(0, 100 - 20*CRITICAL - 5*WARNING - 2*INFO)`

### 5. Report Verdict

| Score | Condition | Verdict |
|---|---|---|
| 100 | Perfect | **PERFECT** — no findings, ready to ship |
| >= 80 AND 0 CRITICALs | Acceptable but imperfect | **PASS** — list remaining findings to fix toward 100 |
| 60-79 AND 0 CRITICALs | Minor issues | **CONCERNS** — fix before proceeding |
| < 60 OR any CRITICAL | Blocking issues | **FAIL** — must fix before proceeding |

**Target is always 100.** PASS (>=80) means the code won't break, but findings still exist. The review should always list ALL remaining findings so the caller can fix toward a perfect score. Only PERFECT (100) means "nothing left to improve."

Output format:
```
## Forge Review -- {PERFECT|PASS|CONCERNS|FAIL} (Score: {N}/100)

**Mode:** {quick|full} | **Files reviewed:** {count} | **Agents dispatched:** {count}
**Target:** 100 | **Remaining:** {total_count} findings to fix

### Findings ({total_count})

**Critical ({count}):**
- `file:line` | CATEGORY | message

**Warning ({count}):**
- `file:line` | CATEGORY | message

**Info ({count}):**
- `file:line` | CATEGORY | message

### Verdict
{PERFECT: Clean — no findings. | PASS: Acceptable but {N} findings remain — fix to reach 100. | CONCERNS/FAIL: Fix required before proceeding.}
```

If zero findings: "PERFECT -- Score: 100/100. No findings."

## What It Does NOT Do

- Does NOT fix code (review only -- the caller decides what to do)
- Does NOT run the check engine Layer 1/Layer 2 (that's `/codebase-health`)
- Does NOT create PRs, tickets, branches, or state files
- Does NOT modify any files in the project
- Does NOT write to `.forge/` state

## Integration Points

- **Ralph Loop:** `/forge-review` at each iteration (quick), `/forge-review --full` at final iteration
- **Manual workflow:** Run before committing or creating PRs
- **`/deep-health`:** Could delegate its verification step to `/forge-review --full` (future refactor)
- **Pipeline complement:** Lighter than Stage 6 (REVIEW), usable outside the full pipeline

## Implementation Notes

- Skill file: `skills/forge-review/SKILL.md`
- No shell scripts needed -- agent dispatch is handled by the Claude runtime via the Agent tool
- Add to CLAUDE.md skills list (22 skills after addition)
- Add to `.claude-plugin/plugin.json` keywords if needed
- Add to README skills directory listing
- Regenerate `seed.cypher` after adding the skill directory

## Out of Scope

- Auto-fix mode (that's `/deep-health`)
- Check engine integration (that's `/codebase-health`)
- CI/CD integration (future -- would need a shell wrapper)
- Custom reviewer selection (e.g., "only run security") -- use `--full` or default
