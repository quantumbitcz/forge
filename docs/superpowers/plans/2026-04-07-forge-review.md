# `/forge-review` Skill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create a standalone `/forge-review` skill that dispatches forge review agents, fixes findings, re-verifies, and loops until score 100 or max iterations.

**Architecture:** Single SKILL.md file following the forge skill pattern (YAML frontmatter + instructions). No shell scripts — agent dispatch and fixes handled by Claude runtime. Documentation updates in CLAUDE.md, README.md, and seed.cypher.

**Tech Stack:** Markdown (SKILL.md), bash (seed regeneration), bats (test verification)

---

### Task 1: Create the SKILL.md file

**Files:**
- Create: `skills/forge-review/SKILL.md`

- [ ] **Step 1: Create the skill directory**

```bash
mkdir -p skills/forge-review
```

- [ ] **Step 2: Write the SKILL.md**

Create `skills/forge-review/SKILL.md` with the full skill content:

```markdown
---
name: forge-review
description: Review + fix changed files using forge's own review agents. Dispatches reviewers, fixes all findings, re-verifies in a loop until score reaches 100 or max iterations. Quick mode (3 agents) for iteration checks, full mode (11 agents) for final reviews.
disable-model-invocation: false
---

# /forge-review — Review + Fix with Forge Agents

You review changed files using forge's own specialized review agents, fix all findings, and re-verify until the score reaches 100 or max iterations. You are a self-contained review-fix-verify loop.

**Philosophy:** Apply principles from `shared/agent-philosophy.md` — challenge every design decision before fixing. Search documentation (Context7, WebSearch) when uncertain about best practices.

## Arguments

Parse `$ARGUMENTS` for flags:

- `--full`: Dispatch all applicable agents (default: core 3 only)
- `--range <base>..<head>`: Custom commit range (default: `HEAD~1..HEAD` + uncommitted)
- `--files <pattern>`: Specific files only (glob pattern)
- `--max-iterations <N>`: Override inner loop cap (default: 3)

Flags are combinable.

## Instructions

### 1. Determine Scope

Compute the file list based on flags:

**Default (no --range, no --files):**
```bash
PROJECT_ROOT=$(git rev-parse --show-toplevel)
# Last commit + uncommitted changes
COMMITTED=$(git diff --name-only HEAD~1..HEAD 2>/dev/null || git diff --name-only HEAD 2>/dev/null || echo "")
UNCOMMITTED=$(git diff --name-only 2>/dev/null)
STAGED=$(git diff --name-only --cached 2>/dev/null)
FILES=$(echo -e "$COMMITTED\n$UNCOMMITTED\n$STAGED" | sort -u | grep -v '^$')
```

**With --range:**
```bash
FILES=$(git diff --name-only {base}..{head})
```

**With --files:**
Glob expansion against project root.

**Filter** to source files (same extensions as `/codebase-health`):
```bash
echo "$FILES" | grep -E '\.(kt|kts|java|ts|tsx|js|jsx|py|go|rs|c|h|cs|cpp|swift|rb|php|dart|ex|scala|vue|svelte|html|css|scss)$'
```

Also include `.md` files if `--full` is set (for docs-consistency-reviewer).

If zero files remain: report "No changed source files to review. PERFECT." and stop.

Report: "Reviewing {count} files in {mode} mode."

### 2. Select Agents

**Quick mode (default):** Always dispatch these 3:
- `forge:architecture-reviewer`
- `forge:security-reviewer`
- `forge:code-quality-reviewer`

**Full mode (`--full`):** Core 3 + conditional agents based on file types present:

| Agent | Dispatch condition |
|---|---|
| `forge:docs-consistency-reviewer` | Any `.md` files in scope |
| `forge:frontend-reviewer` | Any `.tsx`, `.jsx`, `.vue`, `.svelte`, `.html` files |
| `forge:frontend-performance-reviewer` | Any frontend files present |
| `forge:frontend-design-reviewer` | Any `.css`, `.scss`, `.styled.*` files present |
| `forge:frontend-a11y-reviewer` | Any frontend files present |
| `forge:backend-performance-reviewer` | Any `.kt`, `.java`, `.py`, `.go`, `.rs`, `.cs` files |
| `forge:version-compat-reviewer` | Any `package.json`, `build.gradle.kts`, `go.mod`, `Cargo.toml`, `*.csproj` |
| `forge:infra-deploy-reviewer` | Any `Dockerfile`, `docker-compose.*`, `*.yaml`/`*.yml` with k8s markers, Helm charts |

Report: "Dispatching {count} review agents: {agent_names}"

### 3. Review-Fix-Verify Loop

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
  Compile findings from all agents.
  Deduplicate by (file, line, category) — keep highest severity.
  Score: max(0, 100 - 20*CRITICAL - 5*WARNING - 2*INFO)
  Report: "Iteration {ITERATION}: {count} findings, score {score}/100"

  --- Step C: CHECK ---
  If score == 100:
    Mark task completed
    BREAK → report PERFECT
  If ITERATION >= MAX_ITERATIONS:
    Mark task completed
    BREAK → report final verdict with remaining findings

  --- Step D: FIX ---
  For each finding (CRITICAL first, then WARNING, then INFO):
    1. Read the affected file and surrounding context (±20 lines)
    2. Challenge: is there a better solution? Consider project conventions.
    3. Fix using Edit tool. Follow existing patterns.
    4. Track: add to FIXED list with original finding details
    TOTAL_FIXED += 1

  After all fixes applied:
    Read .claude/forge.local.md for commands section.
    If commands.build exists: run it. On failure → revert last fix, mark as unfixable.
    If commands.test exists: run it. On failure → revert last fix, mark as unfixable.
    If commands.lint exists: run it. On failure → revert last fix, mark as unfixable.

  --- Step E: NARROW SCOPE ---
  SCOPE_FILES = files touched by fixes (git diff --name-only)
  Mark task completed
  GOTO LOOP
```

### 4. Report

After loop exits, produce the final report:

```
## Forge Review -- {PERFECT|PASS|CONCERNS|FAIL} (Score: {score}/100)

**Mode:** {quick|full} | **Files reviewed:** {count} | **Agents dispatched:** {count}
**Iterations:** {ITERATION}/{MAX_ITERATIONS} | **Findings fixed:** {TOTAL_FIXED} | **Remaining:** {remaining}

### Fixed ({TOTAL_FIXED})
- `file:line` | CATEGORY | SEVERITY | what was fixed

### Remaining ({remaining})  [omit section if PERFECT]
- `file:line` | CATEGORY | SEVERITY | message | reason unfixable

### Verdict
{PERFECT: Clean — score 100, no findings.}
{PASS: Score {N}/100. {remaining} findings could not be resolved in {MAX_ITERATIONS} iterations.}
{CONCERNS: Score {N}/100. Review findings above — manual intervention recommended.}
{FAIL: Score {N}/100. Critical issues remain — do not proceed.}
```

Verdict thresholds:
- **PERFECT**: score == 100
- **PASS**: score >= 80 AND 0 CRITICALs
- **CONCERNS**: score 60-79 AND 0 CRITICALs
- **FAIL**: score < 60 OR any CRITICAL remaining

### 5. Important Rules

- **Target is always 100.** Fix ALL severities — CRITICAL, WARNING, and INFO. Do not stop at "good enough."
- **Challenge before fixing.** For each finding, ask: is there a fundamentally better approach? Search docs if needed.
- **Follow project conventions.** Read `.claude/forge.local.md` for patterns. Match existing code style.
- **Revert on regression.** If a fix breaks build/test/lint, revert it and mark as unfixable rather than cascading.
- **Do NOT create PRs, tickets, or state files.** This skill is a pure review+fix loop.
- **Do NOT run the check engine.** That is `/codebase-health`. This skill dispatches review agents only.
- **Do NOT commit.** The caller decides when to commit. You only fix files.
```

- [ ] **Step 3: Verify the file was created correctly**

```bash
head -5 skills/forge-review/SKILL.md
```

Expected: YAML frontmatter with `name: forge-review`

- [ ] **Step 4: Commit**

```bash
git add skills/forge-review/SKILL.md
git commit -m "feat: add /forge-review skill — review+fix+verify loop with forge agents"
```

---

### Task 2: Update CLAUDE.md skills list

**Files:**
- Modify: `CLAUDE.md:204-206`

- [ ] **Step 1: Update the skills count and list**

In `CLAUDE.md` line 204, change `Skills (21 in \`skills/\`)` to `Skills (22 in \`skills/\`)`.

In the skills list on line 206, add `forge-review` (review + fix changed files using forge's own review agents — dispatches reviewers, fixes all findings, re-verifies until score 100) in alphabetical position after `forge-reset`.

- [ ] **Step 2: Verify the count matches**

```bash
ls -d skills/*/SKILL.md | wc -l
```

Expected: 22

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: add forge-review to CLAUDE.md skills list (22 skills)"
```

---

### Task 3: Update README.md

**Files:**
- Modify: `README.md` (lines 5, 66, 190, 194, 383-404)

- [ ] **Step 1: Update skill counts**

Change all `21 skills` references to `22 skills`:
- Line 66: `22 skills provide the user-facing interface`
- Line 194: `skills/ (22 user-facing commands)`
- Line 383: `skills/                               # 22 user-facing skills`

- [ ] **Step 2: Add forge-review to directory listing**

In the skills directory listing (around line 389), add `forge-review/` in alphabetical position between `forge-fix/` and `forge-history/`.

- [ ] **Step 3: Verify**

```bash
grep -c "22 skills\|22 user" README.md
```

Expected: 3 (all count references updated)

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "docs: add forge-review to README skills listing (22 skills)"
```

---

### Task 4: Regenerate seed.cypher and run tests

**Files:**
- Modify: `shared/graph/seed.cypher` (auto-generated)

- [ ] **Step 1: Regenerate the seed**

```bash
./shared/graph/generate-seed.sh
```

Expected: "Seed written to .../seed.cypher" with updated CREATE count.

- [ ] **Step 2: Verify seed is fresh**

```bash
committed=$(shasum -a 256 shared/graph/seed.cypher | awk '{print $1}')
generated=$(./shared/graph/generate-seed.sh --dry-run | shasum -a 256 | awk '{print $1}')
[ "$committed" = "$generated" ] && echo "MATCH" || echo "STALE"
```

Expected: After committing, MATCH.

- [ ] **Step 3: Run full test suite**

```bash
./tests/validate-plugin.sh
```

Expected: `51 passed, 0 failed` (structural count may increase if new checks added).

- [ ] **Step 4: Commit seed if changed**

```bash
git add shared/graph/seed.cypher
git commit -m "chore: regenerate seed.cypher after adding forge-review skill"
```

- [ ] **Step 5: Run contract tests to verify skill frontmatter**

```bash
./tests/lib/bats-core/bin/bats tests/contract/skill-frontmatter.bats
```

Expected: All tests pass, including the new skill being picked up.
