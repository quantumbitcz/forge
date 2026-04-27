---
name: forge-help
description: "[read-only] Interactive decision tree to find the right Forge skill. Use when unsure which skill to use, exploring capabilities, or need help choosing between similar skills. Trigger: /forge-help, which skill should I use, help me choose, what can forge do"
allowed-tools: ['Read', 'Bash', 'Glob', 'Grep']
disable-model-invocation: true
---

# Forge Help — Skill Decision Tree

## Flags

- **--help**: print usage and exit 0
- **--json**: structured JSON output (see `## --json output` below; envelope carries `schema_version`)

## Exit codes

See `shared/skill-contract.md` for the standard exit-code table.

## Prerequisites

None. This skill is a reference guide.

## Instructions

Display the decision tree below. If the user asks a specific question, navigate to the relevant category. With `--json`, emit the structured envelope documented under `## --json output`.

## Error Handling

None. This skill displays static content.

## What do you want to do?

```
What do you want to do?

├── Build something
│   ├── New feature ................. /forge-run
│   ├── Fix a bug ................... /forge-fix
│   ├── Refine a vague idea ......... /forge-shape
│   └── Scaffold a new project ...... /forge-bootstrap
│
├── Check quality
│   ├── Just my recent changes ...... /forge-review             (default: --scope=changed --fix)
│   ├── The whole codebase (read) ... /forge-review --scope=all
│   ├── The whole codebase (fix) .... /forge-review --scope=all --fix
│   ├── Build + lint + test ......... /forge-verify             (default: --build)
│   ├── Config is correct ........... /forge-verify --config
│   └── Security scan ............... /forge-security-audit
│
├── Work with the knowledge graph
│   └── /forge-graph <init|status|query|rebuild|debug>
│
├── Ship / deploy / commit
│   ├── Deploy ...................... /forge-deploy
│   └── Conventional commit ......... /forge-commit
│
├── Pipeline control
│   ├── Status ...................... /forge-status
│   ├── Abort ....................... /forge-abort
│   ├── Recover ..................... /forge-recover <diagnose|repair|reset|resume|rollback>
│   └── Profile a run ............... /forge-profile
│
├── Know the codebase / history
│   ├── Ask a question .............. /forge-ask
│   ├── Run history ................. /forge-history
│   └── Insights .................... /forge-insights
│
└── Configure / automate / compress
    ├── Edit config ................. /forge-config
    ├── Automations ................. /forge-automation
    ├── Playbooks (list) ............ /forge-playbooks
    ├── Playbooks (refine) .......... /forge-playbook-refine
    ├── Compress .................... /forge-compress <agents|output|status|help>
    ├── Docs generate ............... /forge-docs-generate
    └── Migration ................... /forge-migration

New to forge? → /forge-tour
First setup?  → /forge-init
```

**Tree depth:** maximum 3 levels (root → category → item). Subcommands live inside the skill, not as a 4th tree branch.

## Skill Tiers

Skills are grouped into three tiers by usage frequency. Tier 1 covers the everyday entry points; Tier 2 covers workflow and quality gates; Tier 3 covers specialized and introspection tools.

### Tier 1 — Everyday entry points

Most-common starting points for any new work.

- `/forge-run` — full 10-stage pipeline for a single feature
- `/forge-fix` — root-cause bug investigation and targeted repair
- `/forge-shape` — refine a vague idea into a structured spec
- `/forge-help` — interactive decision tree (this skill)
- `/forge-tour` — guided 5-stop introduction for new users
- `/forge-init` — first-time setup for an existing project

### Tier 2 — Workflow and quality

Skills used regularly as part of the build/ship/recover loop.

- `/forge-review` — quality audit, changed files (default) or whole codebase
- `/forge-verify` — fast build + lint + test or config validation
- `/forge-deploy` — staging, production, preview, or rollback
- `/forge-sprint` — multi-feature parallel orchestration
- `/forge-recover` — diagnose, repair, reset, resume, or rollback pipeline state
- `/forge-migration` — library or framework version upgrade
- `/forge-bootstrap` — scaffold a brand-new greenfield project

### Tier 3 — Specialized and introspection

Lower-frequency skills for analytics, automation, configuration, and codebase queries.

- `/forge-graph` — Neo4j knowledge graph (init, status, query, rebuild, debug)
- `/forge-security-audit` — module-appropriate vulnerability scanners
- `/forge-docs-generate` — README, ADRs, API specs, runbooks, changelogs
- `/forge-ask` — codebase Q&A across wiki, graph, and explore cache
- `/forge-insights` — quality, cost, convergence, memory analytics
- `/forge-history` — score trends across pipeline runs
- `/forge-status` — current run stage and progress
- `/forge-profile` — per-stage and per-agent timing analysis
- `/forge-automation` — event-driven trigger management
- `/forge-playbooks` — list and run reusable pipeline recipes
- `/forge-playbook-refine` — review and apply playbook refinement proposals
- `/forge-handoff` — write or resume a session handoff artefact
- `/forge-config` — interactive config editor with validation
- `/forge-commit` — terse conventional commit message from staged changes
- `/forge-compress` — agent prompt and runtime output compression
- `/forge-abort` — stop an active pipeline run gracefully

## Similar Skills

Pairs of skills that get confused. Pick the one whose intent matches yours.

- `/forge-fix` vs `/forge-recover` — `forge-fix` investigates and patches a bug in your code; `forge-recover` repairs forge's own pipeline state when a run is stuck.
- `/forge-review --scope=changed` vs `/forge-review --scope=all` — `changed` audits only files modified in the current diff; `all` audits the whole codebase read-only (add `--fix` for an iterative cleanup loop).
- `/forge-verify` vs `/forge-review` — `forge-verify` is a single-shot build+lint+test sanity check; `forge-review` is a multi-agent quality audit with scoring.
- `/forge-shape` vs `/forge-run` — `forge-shape` turns a vague idea into a spec; `forge-run` executes the pipeline against an already-clear requirement.
- `/forge-bootstrap` vs `/forge-init` — `forge-bootstrap` scaffolds a brand-new greenfield project from nothing; `forge-init` onboards an existing project to forge.
- `/forge-sprint` vs `/forge-run` — `forge-sprint` runs multiple independent features in parallel; `forge-run` runs a single feature end-to-end.
- `/forge-abort` vs `/forge-recover reset` — `forge-abort` stops the current run while preserving state for resume; `forge-recover reset` clears state entirely (caches and learnings survive).
- `/forge-history` vs `/forge-insights` — `forge-history` lists per-run score trends; `forge-insights` aggregates analytics across runs (quality, cost, memory health).

## Migration

The following skill names were removed in the skill-consolidation pass. Use the replacement on the right:

| Removed                 | Use instead                              |
|-------------------------|------------------------------------------|
| /forge-codebase-health  | /forge-review --scope=all                |
| /forge-deep-health      | /forge-review --scope=all --fix          |
| /forge-graph-status     | /forge-graph status                      |
| /forge-graph-query      | /forge-graph query <cypher>              |
| /forge-graph-rebuild    | /forge-graph rebuild                     |
| /forge-graph-debug      | /forge-graph debug                       |
| /forge-config-validate  | /forge-verify --config                   |

This section is slated for removal in the release after the next minor bump.

## See Also

- `/forge-tour` — guided 5-stop introduction for new users
- `/forge-init` — first-time project setup
- `/forge-compress help` — compression features reference

## --json output

When invoked with `--json`, `/forge-help` emits the decision tree as structured JSON. The envelope carries an explicit `schema_version` so downstream consumers (MCP server F30, `/forge-insights`) can detect the shape:

```json
{
  "schema_version": "2",
  "total_skills": 29,
  "categories": {
    "build": [
      {"name": "forge-run", "mode": "writes", "summary": "Full 10-stage pipeline"},
      {"name": "forge-fix", "mode": "writes", "summary": "Root cause bug fix"},
      {"name": "forge-shape", "mode": "writes", "summary": "Refine a vague idea"},
      {"name": "forge-bootstrap", "mode": "writes", "summary": "Scaffold a new project"}
    ],
    "quality": [
      {
        "name": "forge-review",
        "mode": "writes",
        "summary": "Quality review for changed files or whole codebase",
        "subcommands": [
          {"name": "changed", "mode": "writes", "default": true},
          {"name": "all", "mode": "read-only"},
          {"name": "all --fix", "mode": "writes"}
        ]
      },
      {
        "name": "forge-verify",
        "mode": "read-only",
        "summary": "Pre-pipeline checks",
        "subcommands": [
          {"name": "build", "mode": "read-only", "default": true},
          {"name": "config", "mode": "read-only"},
          {"name": "all", "mode": "read-only"}
        ]
      },
      {"name": "forge-security-audit", "mode": "read-only", "summary": "Security scan"}
    ],
    "knowledge_graph": [
      {
        "name": "forge-graph",
        "mode": "writes",
        "summary": "Neo4j knowledge graph (Docker)",
        "subcommands": [
          {"name": "init", "mode": "writes"},
          {"name": "status", "mode": "read-only"},
          {"name": "query", "mode": "read-only"},
          {"name": "rebuild", "mode": "writes"},
          {"name": "debug", "mode": "read-only"}
        ]
      }
    ],
    "ship": [
      {"name": "forge-deploy", "mode": "writes", "summary": "Deploy to staging/production/preview"},
      {"name": "forge-commit", "mode": "writes", "summary": "Generate conventional commit messages"}
    ],
    "pipeline_control": [
      {"name": "forge-status", "mode": "read-only", "summary": "Check pipeline state and progress"},
      {"name": "forge-abort", "mode": "writes", "summary": "Stop active run, preserve for resume"},
      {
        "name": "forge-recover",
        "mode": "writes",
        "summary": "Unified recovery dispatcher",
        "subcommands": [
          {"name": "diagnose", "mode": "read-only"},
          {"name": "repair", "mode": "writes"},
          {"name": "reset", "mode": "writes"},
          {"name": "resume", "mode": "writes"},
          {"name": "rollback", "mode": "writes"}
        ]
      },
      {"name": "forge-profile", "mode": "read-only", "summary": "Per-stage / agent timing"}
    ],
    "know": [
      {"name": "forge-ask", "mode": "read-only", "summary": "Ask questions about the codebase"},
      {"name": "forge-history", "mode": "read-only", "summary": "Score trends across runs"},
      {"name": "forge-insights", "mode": "read-only", "summary": "Cross-run quality + cost analytics"}
    ],
    "configure": [
      {"name": "forge-config", "mode": "writes", "summary": "Edit pipeline settings interactively"},
      {"name": "forge-automation", "mode": "writes", "summary": "Set up automatic pipeline triggers"},
      {"name": "forge-playbooks", "mode": "read-only", "summary": "List/manage reusable pipeline recipes"},
      {"name": "forge-playbook-refine", "mode": "writes", "summary": "Review/apply playbook refinement proposals"},
      {
        "name": "forge-compress",
        "mode": "writes",
        "summary": "Token compression dispatcher",
        "subcommands": [
          {"name": "agents", "mode": "writes"},
          {"name": "output", "mode": "writes"},
          {"name": "status", "mode": "read-only"},
          {"name": "help", "mode": "read-only"}
        ]
      },
      {"name": "forge-docs-generate", "mode": "writes", "summary": "Generate README, ADRs, API specs"},
      {"name": "forge-migration", "mode": "writes", "summary": "Framework / library version upgrade"}
    ]
  },
  "removed_in_phase_05": [
    {"name": "forge-codebase-health", "replacement": "/forge-review --scope=all"},
    {"name": "forge-deep-health", "replacement": "/forge-review --scope=all --fix"},
    {"name": "forge-config-validate", "replacement": "/forge-verify --config"},
    {"name": "forge-graph-status", "replacement": "/forge-graph status"},
    {"name": "forge-graph-query", "replacement": "/forge-graph query <cypher>"},
    {"name": "forge-graph-rebuild", "replacement": "/forge-graph rebuild"},
    {"name": "forge-graph-debug", "replacement": "/forge-graph debug"}
  ]
}
```

**Schema version history:**

- **1** (Phase 1 baseline): `{ total_skills: 35, tiers: { essential, power_user, advanced }, similar_skills: [...] }` — flat tier tables.
- **2** (Phase 5, this release): `{ schema_version, total_skills: 28, categories: {...}, removed_in_phase_05: [...] }` — categorized with cluster entries carrying `subcommands` arrays.

Consumers SHOULD switch on `schema_version` rather than sniffing for the presence of `subcommands`.
