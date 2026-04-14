---
name: forge-commit
description: "Generate terse conventional commit messages from staged changes. Use when you have staged files and want a well-structured commit message that follows Conventional Commits format. Analyzes diffs, infers type and scope, presents options."
allowed-tools: ['Read', 'Write', 'Edit', 'Bash', 'Glob', 'Grep', 'Agent']
---

# /forge-commit -- Terse Conventional Commit Generator

Analyzes staged changes and generates a Conventional Commits message. Subject line <=50 chars, body explains why (not what). Never includes AI attribution.

## Prerequisites

1. **Git repository:** Run `git rev-parse --show-toplevel 2>/dev/null`. If fails: "Not a git repository." STOP.
2. **Staged changes exist:** Run `git diff --cached --stat`. If empty: "No staged changes. Stage files with `git add` first." STOP.

## Instructions

### 1. Analyze Staged Changes

```bash
git diff --cached --stat
git diff --cached
```

Identify:
- **Files changed** -- count and paths
- **Nature of change** -- new feature, bug fix, refactor, test, docs, build, CI, style, perf, chore
- **Scope** -- module/component most affected (e.g., `auth`, `api`, `build`, `ci`)
- **Key behavioral change** -- the "why" in one sentence

### 2. Determine Commit Type

Map changes to Conventional Commits types:

| Type | When |
|------|------|
| `feat` | New functionality visible to users or consumers |
| `fix` | Bug fix |
| `refactor` | Code restructuring without behavior change |
| `test` | Adding or updating tests only |
| `docs` | Documentation only |
| `build` | Build system or dependency changes |
| `ci` | CI/CD configuration |
| `style` | Formatting, whitespace, linting (no logic change) |
| `perf` | Performance improvement |
| `chore` | Maintenance tasks, version bumps |

If multiple types apply, use the most significant one (feat > fix > refactor > others).

### 3. Generate Commit Message

**Subject line rules:**
- Format: `type(scope): imperative description`
- Maximum 50 characters total
- Lowercase, no period at end
- Imperative mood: "add" not "added" or "adds"
- Scope is optional -- omit if change spans many modules

**Body rules (if needed):**
- Blank line after subject
- Explain WHY the change was made, not what changed (diff shows that)
- Wrap at 72 characters
- Reference ticket IDs if present in branch name or staged content

**NEVER include:**
- Co-Authored-By lines
- AI attribution of any kind
- Signed-off-by lines (unless project convention requires it)

### 4. Present Options

Use `AskUserQuestion` to present the generated commit:

```
Proposed commit:

  type(scope): subject line here

  Body explaining why (if applicable).

Options:
1. Commit as-is
2. Edit message (provide revised text)
3. Cancel
```

### 5. Execute

Based on user choice:
- **Commit:** Run `git commit -m "<message>"` (or `-m "<subject>" -m "<body>"` if body present)
- **Edit:** Accept user's revised message, then commit
- **Cancel:** "Commit cancelled." STOP.

After successful commit, report: `Committed: <short-hash> <subject>`

## Terse Mode Integration

If `.forge/caveman-mode` exists and is not `off`, apply compression to all user-facing output:
- `lite`: Drop filler, keep grammar
- `full`: `[type(scope)] subject. hash.`
- `ultra`: `type(scope): subject -> hash`

The commit message itself is NEVER compressed -- only surrounding output.

## Error Handling

| Condition | Action |
|-----------|--------|
| Not a git repo | Report error, STOP |
| No staged changes | Report error, suggest `git add`, STOP |
| Commit fails (pre-commit hook) | Report hook output, suggest fixes, STOP |
| Ambiguous change type | Default to `chore`, note uncertainty in options |
| Subject exceeds 50 chars | Shorten automatically, show original and shortened |

## See Also

- `/forge-review` -- review changed files before committing
- `/verify` -- build + lint + test check
- `/forge-caveman` -- toggle terse output mode
