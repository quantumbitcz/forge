---
name: forge-help
description: "[read-only] Interactive decision tree to find the right Forge skill. Use when unsure which skill to use, exploring capabilities, or need help choosing between similar skills. Trigger: /forge-help, which skill should I use, help me choose, what can forge do"
allowed-tools: ['Read', 'Bash', 'Glob', 'Grep']
disable-model-invocation: true
---

# Forge Help — Skill Decision Tree

## Flags

- **--help**: print usage and exit 0
- **--json**: structured JSON output

## Exit codes

See `shared/skill-contract.md` for the standard exit-code table.

## Prerequisites

None. This skill is a reference guide.

## Instructions

Display the decision tree below. If the user asks a specific question, navigate to the relevant category.

## Error Handling

None. This skill displays static content.

## What do you want to do?

### Tier 1 — Essential Skills (start here)

The 7 skills that cover 80% of usage:

| Skill | What it does | When to use |
|-------|-------------|-------------|
| `/forge-init` [writes] | First-time project setup | Setting up Forge on a new or existing project |
| `/forge-run` [writes] | Build a feature (full 10-stage pipeline) | You have a clear requirement to implement |
| `/forge-fix` [writes] | Fix a bug with root cause investigation | Bug report, failing test, ticket ID |
| `/forge-review` [writes] | Review your recent code changes | Before committing, after finishing a feature |
| `/forge-verify` [read-only] | Quick build + lint + test check | Sanity check, pre-commit, baseline health |
| `/forge-status` [read-only] | Check pipeline state and progress | See what stage the pipeline is at |
| `/forge-help` [read-only] | This decision tree | Not sure which skill to use |

**New to Forge?** Start with `/forge-tour` [read-only] for a guided 5-stop introduction.

---

### Tier 2 — Power User Skills

For users who run Forge regularly:

| Category | Skill | What it does |
|----------|-------|-------------|
| **Plan** | `/forge-shape` [writes] | Turn a vague idea into a structured spec |
| **Plan** | `/forge-sprint` [writes] | Execute multiple features in parallel |
| **Quality** | `/forge-review` [read-only] | Full codebase audit (read-only, no fixes) |
| **Quality** | `/forge-review` [writes] | Fix all issues iteratively until clean |
| **Quality** | `/forge-security-audit` [read-only] | Security vulnerability scan |
| **Ship** | `/forge-deploy` [writes] | Deploy to staging/production/preview |
| **Ship** | `/forge-commit` [writes] | Generate conventional commit messages |
| **Docs** | `/forge-docs-generate` [writes] | Generate README, ADRs, API specs |
| **Migrate** | `/forge-migration` [writes] | Framework/library version upgrade |
| **Know** | `/forge-ask` [read-only] | Ask questions about the codebase |
| **Config** | `/forge-config` [writes] | Edit pipeline settings interactively |
| **Output** | `/forge-compress output <mode>` [writes] | Toggle terse output (save tokens) |

---

### Tier 3 — Advanced Skills

Pipeline management, analytics, graph, and compression:

#### Pipeline Management
| Skill | What it does |
|-------|-------------|
| `/forge-recover` [writes] | Unified recovery — `diagnose` (read-only), `repair`, `reset`, `resume`, `rollback` subcommands |
| `/forge-abort` [writes] | Stop active run, preserve for resume |
| `/forge-config-validate` [read-only] | Check config before running |

#### Analytics
| Skill | What it does |
|-------|-------------|
| `/forge-history` [read-only] | Score trends across runs |
| `/forge-insights` [read-only] | Cross-run quality + cost analytics |
| `/forge-profile` [read-only] | Per-stage/agent timing analysis |

#### Knowledge Graph (requires Docker)
| Skill | What it does |
|-------|-------------|
| `/forge-graph-init` [writes] | Start Neo4j, build codebase graph |
| `/forge-graph-status` [read-only] | Check graph health |
| `/forge-graph-query` [read-only] | Run Cypher queries |
| `/forge-graph-rebuild` [writes] | Rebuild graph from scratch |
| `/forge-graph-debug` [read-only] | Diagnose graph issues |

#### Token Optimization
| Skill | What it does |
|-------|-------------|
| `/forge-compress` [writes] | Unified compression — `agents` (compress prompts), `output <mode>` (runtime), `status`, `help` |

#### Automation & Recipes
| Skill | What it does |
|-------|-------------|
| `/forge-automation` [writes] | Set up automatic pipeline triggers |
| `/forge-playbooks` [read-only] | Manage reusable pipeline recipes |
| `/forge-playbook-refine` [writes] | Review/apply playbook refinement proposals |
| `/forge-bootstrap` [writes] | Scaffold a new project from scratch |

---

### Similar Skills — When to Use Which

| Confused between... | Use this one | Why |
|---|---|---|
| `/forge-review` vs `/forge-review` | `review` for recent changes, `health` for full codebase | Review targets staged/unstaged changes only |
| `/forge-review` vs `/forge-review` | `codebase-health` to read, `deep-health` to fix | Health is read-only; deep-health fixes iteratively |
| `/forge-recover repair` vs `/forge-recover reset` | `repair` to fix corruption, `reset` to start fresh | Repair preserves more state than reset |
| `/forge-abort` vs `/forge-recover reset` | `abort` to pause for later, `reset` to clear everything | Abort + resume continues; reset starts over |
| `/forge-history` vs `/forge-insights` | `history` for trends, `insights` for deeper analytics | Insights adds cost analysis and memory health |
| `/forge-compress agents` vs `/forge-compress output` | `agents` for input tokens, `output` for session tokens | Agents rewrites files; output changes session style |
| `/forge-run bugfix:` vs `/forge-fix` | `/forge-fix` for bugs | Fix has richer source resolution and root cause investigation |

## Quick Reference

```
Build → /forge-run    Fix → /forge-fix    Review → /forge-review
Health → /forge-review    Pipeline broken → /forge-recover diagnose
New here → /forge-tour    This help → /forge-help
```

## See Also

- `/forge-tour` — guided 5-stop introduction for new users
- `/forge-init` — first-time project setup
- `/forge-compress help` — compression features reference

## --json output

When invoked with `--json`, `/forge-help` emits the decision tree as structured JSON:

```json
{
  "total_skills": 35,
  "tiers": {
    "essential": [
      {"name": "forge-run", "mode": "writes", "summary": "Full 10-stage pipeline"},
      ...
    ],
    "power_user": [...],
    "advanced": [...]
  },
  "similar_skills": [
    {"category": "health-audit", "read": "forge-codebase-health", "fix": "forge-deep-health"},
    ...
  ]
}
```
