---
name: forge-help
description: >
  Interactive decision tree to find the right Forge skill for your situation.
  Trigger: /forge-help, "which skill should I use", "help me choose",
  "what can forge do", "forge commands"
disable-model-invocation: true
---

# Forge Help — Skill Decision Tree

## What do you want to do?

### A) Build something new

| Situation | Skill | What it does |
|-----------|-------|-------------|
| Vague idea, needs refinement | `/forge-shape` | Collaborative spec refinement with epics, stories, AC |
| Clear requirement, single feature | `/forge-run` | Full 10-stage pipeline (explore→plan→implement→verify→review→ship) |
| Multiple features in parallel | `/forge-sprint` | Parallel pipeline orchestration |
| New project from scratch | `/bootstrap-project` | Scaffold project with architecture, CI/CD, tooling |
| Library/framework upgrade | `/migration` | Phased migration plan with rollback |

### B) Fix something broken

| Situation | Skill | What it does |
|-----------|-------|-------------|
| Specific bug with description or ticket | `/forge-fix` | Root cause investigation + targeted fix |
| Failing tests / broken build | `/verify` | Quick build+lint+test check |
| Pipeline stuck or broken | `/forge-diagnose` → `/repair-state` | Read-only diagnostic, then targeted fixes |
| Need to undo pipeline changes | `/forge-rollback` | Revert worktree, state, or commits |

### C) Review or improve code quality

| Situation | Skill | What it does |
|-----------|-------|-------------|
| Just my recent changes | `/forge-review` | 3-8 review agents on changed files |
| Entire codebase health check | `/codebase-health` | Read-only analysis, no fixes |
| Fix all issues iteratively | `/deep-health` | Review → fix → re-review loop until clean |
| Security vulnerabilities | `/security-audit` | Module-appropriate vulnerability scanners |

### D) Manage the pipeline

| Situation | Skill | What it does |
|-----------|-------|-------------|
| Check current status | `/forge-status` | Stage, score, convergence, integrations |
| Resume aborted run | `/forge-resume` | Continue from last checkpoint |
| Start completely fresh | `/forge-reset` | Clear state, preserve learnings |
| Abort current run | `/forge-abort` | Graceful stop, preserve for resume |
| Validate config before running | `/config-validate` | Check forge.local.md + forge-config.md |
| Change config settings | `/forge-config` | Interactive config editor with validation |
| See pipeline performance | `/forge-profile` | Time per stage, per agent, per iteration |
| See quality trends | `/forge-insights` | Cross-run analytics |
| View run history | `/forge-history` | Score oscillations, agent effectiveness |

### E) Documentation

| Situation | Skill | What it does |
|-----------|-------|-------------|
| Generate/update docs | `/docs-generate` | README, ADRs, API specs, changelogs |

### F) Understand the codebase

| Situation | Skill | What it does |
|-----------|-------|-------------|
| Ask a question about code | `/forge-ask` | Wiki, graph, explore cache, docs index |
| Explore knowledge graph | `/graph-query` | Run Cypher queries |
| See available playbooks | `/forge-playbooks` | List, run, analyze pipeline recipes |

### G) Reduce token usage

| Situation | Skill | What it does |
|-----------|-------|-------------|
| Terse pipeline output | `/forge-caveman` | User-facing output compression (lite/full/ultra) |
| Compress agent prompts | `/forge-compress` | Input token reduction for .md files |

## Quick Reference

```
Build → /forge-run    Fix → /forge-fix    Review → /forge-review
Health → /codebase-health    Pipeline broken → /forge-diagnose
New here → /forge-tour    This help → /forge-help
```
