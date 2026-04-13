---
name: forge-tour
description: "Guided 5-stop introduction to Forge covering init, verify, run, fix, and review. Use when new to Forge, onboarding team members, or want a walkthrough of the most important skills. Trigger: /forge-tour, how does forge work, getting started, teach me forge"
---

# /forge-tour -- Guided Introduction

A 5-stop walkthrough of the most important Forge skills. Covers the essentials to get productive quickly.

## Prerequisites

None. Works before or after /forge-init.

## Instructions

Present each stop sequentially. Pause between stops to let the user ask questions or try the skill.

### Stop 1: Initialize -- `/forge-init`

Sets up your project for Forge. Auto-detects framework, language, testing, and generates config files.

```bash
/forge-init
```

**What it creates:** `.claude/forge.local.md`, `.claude/forge-config.md`, `.forge/` directory.

### Stop 2: Verify -- `/verify`

Quick sanity check: build + lint + test. No pipeline, just confirms your project is healthy.

```bash
/verify
```

**When to use:** Before starting work, after manual changes, as a pre-commit check.

### Stop 3: Build -- `/forge-run`

The main skill. Give it a requirement and it runs the full 10-stage pipeline: explore, plan, validate, implement (TDD), verify, review, document, and ship.

```bash
/forge-run Add user dashboard with activity feed
```

**Key flags:** `--dry-run` (plan only), `--from=implement` (resume from stage).

### Stop 4: Fix -- `/forge-fix`

Targeted bugfix workflow. Investigates root cause, writes reproduction test, fixes, and verifies.

```bash
/forge-fix Users get 404 on group endpoint
```

**Accepts:** Description, kanban ticket ID, or Linear issue URL.

### Stop 5: Review -- `/forge-review`

Reviews your changed files with multiple specialized agents (code, security, architecture, frontend, performance).

```bash
/forge-review          # Quick: 3 agents
/forge-review --full   # Full: up to 9 agents
```

**Loops** until score reaches 100 or max iterations.

### What's next?

All skills are listed in `/forge-help`. Key next steps:

- `/forge-shape` -- refine vague ideas into structured specs
- `/codebase-health` -- full codebase quality audit
- `/forge-sprint` -- parallel multi-feature execution

## Error Handling

None. This skill displays informational content.

## See Also

- `/forge-help` -- full skill decision tree
- `/forge-init` -- first-time project setup
- `/forge-run` -- build a feature
