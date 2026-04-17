---
name: forge-tour
description: "[read-only] Guided 5-stop introduction to Forge covering init, verify, run, fix, and review. Use when new to Forge, onboarding team members, or want a walkthrough of the most important skills. Trigger: /forge-tour, how does forge work, getting started, teach me forge"
allowed-tools: ['Read', 'Bash', 'Glob', 'Grep']
disable-model-invocation: false
---

# Forge Tour — 5-Stop Guided Introduction

## Flags

- **--help**: print usage and exit 0
- **--json**: structured JSON output

## Exit codes

See `shared/skill-contract.md` for the standard exit-code table.

## Prerequisites

None. Works before or after /forge-init.

## Instructions

Present each stop sequentially. Pause between stops to let the user ask questions or try the skill.

## Error Handling

None. This skill displays informational content.

Welcome to Forge, a 10-stage autonomous development pipeline. This tour walks you through the 5 skills you'll use most, in the order you'll need them.

## Stop 1: /forge-init (Setup)

**What it does:** Configures Forge for your project by detecting your tech stack (language, framework, testing) and generating local config files.

**When to use:** First time setting up Forge in a project.

**What happens:**
- Detects your language, framework, and testing setup
- Generates `.claude/forge.local.md` (project config)
- Generates `.claude/forge-config.md` (pipeline settings)
- Detects available MCP integrations (Linear, Playwright, etc.)

**Try it:** Run `/forge-init` in any project.

---

## Stop 2: /verify (Quick Health Check)

**What it does:** Runs build + lint + test and reports pass/fail. No pipeline, no agents — just a quick sanity check.

**When to use:** Before any pipeline run, after manual changes, before committing.

**What happens:**
- Runs your build command (if configured)
- Runs your lint command (if configured)
- Runs your test command (if configured)
- Reports PASS / FAIL / SKIPPED per step

**Try it:** Run `/forge-verify` to check your project's baseline health.

---

## Stop 3: /forge-run (Build Features)

**What it does:** The main entry point. Give it a requirement, and it runs the full 10-stage pipeline: explore → plan → implement (TDD) → verify → review → ship.

**When to use:** When you have a clear feature to build.

**Example:**
```
/forge-run Add email validation to user registration with error messages
```

**What happens:**
1. Explores your codebase for context (~1 min)
2. Creates an implementation plan (may ask for approval)
3. Implements via TDD — writes tests first, then code
4. Verifies: runs tests, lint, and code review
5. Fixes any issues found in review (may loop 2-5 times)
6. Generates documentation and creates a PR

---

## Stop 4: /forge-fix (Fix Bugs)

**What it does:** Specialized bugfix workflow — investigates root cause, writes a failing test that reproduces the bug, implements the fix.

**When to use:** When you have a bug to fix.

**Example:**
```
/forge-fix Users get 404 when accessing /api/groups endpoint
```

**What happens:**
1. Investigates the bug (max 3 reproduction attempts)
2. Writes a failing test demonstrating the bug
3. Implements the minimal fix
4. Verifies no regressions

---

## Stop 5: /forge-review (Review Changes)

**What it does:** Reviews your recent code changes using 3-8 specialized review agents (security, architecture, performance, accessibility, etc.).

**When to use:** After making changes, before committing or creating a PR.

**Example:**
```
/forge-review          # Quick mode: 3 agents
/forge-review --full   # Full mode: up to 8 agents
```

**What happens:**
- Detects changed files (staged + unstaged)
- Dispatches review agents in parallel
- Reports findings by severity (CRITICAL / WARNING / INFO)
- Calculates quality score (0-100)
- Offers to fix findings automatically

---

## Summary

| Skill | When | Time |
|-------|------|------|
| `/forge-init` | First time setup | ~1 min |
| `/forge-verify` | Quick health check | ~30s |
| `/forge-run` | Build a feature | 5-30 min |
| `/forge-fix` | Fix a bug | 3-15 min |
| `/forge-review` | Review code quality | 1-5 min |

## What's Next?

- **All skills:** `/forge-help`
- **Reduce token usage:** `/forge-caveman`
- **Pipeline analytics:** `/forge-insights`
- **Multiple features:** `/forge-sprint`

---

## Platform Notes

### Windows (WSL2) — Recommended

WSL2 is the recommended way to run Forge on Windows. All scripts require bash 4.0+ which WSL2 provides natively.

```bash
# Install WSL2 (PowerShell as Administrator)
wsl --install -d Ubuntu

# Inside WSL2
sudo apt update && sudo apt install -y bash python3 git docker.io
```

**Important:** Run all Forge commands from within WSL2, not PowerShell or CMD.

### Windows (Git Bash) — Limited Support

Git Bash provides a minimal bash environment but has known limitations:

- MSYS path translation causes issues with hook path resolution (see commit `0ac4874`)
- Docker commands require Docker Desktop with WSL2 backend enabled
- Some scripts may hit Windows long path limits (260 chars)

```bash
# Requires Git for Windows with Git Bash
# Enable long paths in git
git config --global core.longpaths true
```

### macOS — Full Support

macOS ships with bash 3.x. Forge requires bash 4.0+.

```bash
brew install bash python3
# Verify version
bash --version  # Must show 4.0+
```

### Linux — Full Support

All major distributions are supported. Install bash 4+ and python3:

```bash
# Ubuntu / Debian
sudo apt update && sudo apt install -y bash python3 git

# Fedora / RHEL
sudo dnf install -y bash python3 git

# Arch Linux
sudo pacman -S bash python git
```

## See Also

- `/forge-help` — full skill decision tree
- `/forge-init` — first-time project setup
- `/forge-run` — build a feature
