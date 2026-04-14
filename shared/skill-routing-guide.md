# Skill Routing Guide

This document is the canonical reference for routing user intents to the correct skill.

## Primary Entry Points

| User Intent | Skill | NOT This |
|------------|-------|----------|
| "Implement a feature" | `/forge-run` | |
| "Fix a bug" / "debug" | `/forge-fix` | Not `/forge-run bugfix:` (use `/forge-fix`) |
| "Shape a requirement" | `/forge-shape` | |
| "Bootstrap new project" | `/forge-bootstrap` | |
| "Migrate library/framework" | `/forge-migration` | |
| "Run multiple features" | `/forge-sprint` | Not `/forge-run --sprint` |

## Health & Quality (Most Confused)

| User Intent | Skill | Key Differentiator |
|------------|-------|-------------------|
| "Check code for issues" (read-only report) | `/forge-codebase-health` | Read-only. No fixes. All files. |
| "Fix all code issues" (iterative fixes + commits) | `/forge-deep-health` | Fixes + commits. All files. Loops until clean. |
| "Review changed files" (fix recent changes only) | `/forge-review` | Fixes. Changed files only. No commits. |
| "Run security scan" | `/forge-security-audit` | Security-specific. Read-only. |
| "Quick build/lint/test check" | `/forge-verify` | Commands only. No agent dispatch. |

## Status & History

| User Intent | Skill | Key Differentiator |
|------------|-------|-------------------|
| "What's the pipeline doing now?" | `/forge-status` | Current run state |
| "How have runs trended over time?" | `/forge-history` | Cross-run trends |
| "What's wrong with the pipeline state?" | `/forge-diagnose` | Read-only state diagnostics |

## Graph Operations

| User Intent | Skill |
|------------|-------|
| "Set up knowledge graph" | `/forge-graph-init` |
| "Is the graph healthy?" | `/forge-graph-status` |
| "Query the graph" | `/forge-graph-query` |
| "Rebuild the graph" | `/forge-graph-rebuild` |

## Recovery & Maintenance

| User Intent | Skill |
|------------|-------|
| "Start fresh" | `/forge-reset` |
| "Undo pipeline changes" | `/forge-rollback` |
| "Fix corrupted state" | `/forge-repair-state` |
| "Check config before running" | `/forge-config-validate` |
| "Stop the pipeline" | `/forge-abort` |
| "Resume after failure" | `/forge-resume` |
| "View pipeline run profile" | `/forge-profile` |

## Deployment

| User Intent | Skill |
|------------|-------|
| "Deploy to staging/production" | `/forge-deploy` |

## Documentation

| User Intent | Skill |
|------------|-------|
| "Generate docs" | `/forge-docs-generate` |
| "Set up forge for this project" | `/forge-init` |
