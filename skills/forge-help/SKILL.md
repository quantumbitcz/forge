---
name: forge-help
description: "Interactive decision tree to find the right Forge skill. Use when unsure which skill to use, exploring capabilities, or need help choosing between similar skills. Trigger: /forge-help, which skill should I use, help me choose, what can forge do"
allowed-tools: ['Read', 'Bash', 'Glob', 'Grep']
disable-model-invocation: true
---

# Forge Help — Skill Decision Tree

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
| `/forge-init` | First-time project setup | Setting up Forge on a new or existing project |
| `/forge-run` | Build a feature (full 10-stage pipeline) | You have a clear requirement to implement |
| `/forge-fix` | Fix a bug with root cause investigation | Bug report, failing test, ticket ID |
| `/forge-review` | Review your recent code changes | Before committing, after finishing a feature |
| `/forge-verify` | Quick build + lint + test check | Sanity check, pre-commit, baseline health |
| `/forge-status` | Check pipeline state and progress | See what stage the pipeline is at |
| `/forge-help` | This decision tree | Not sure which skill to use |

**New to Forge?** Start with `/forge-tour` for a guided 5-stop introduction.

---

### Tier 2 — Power User Skills

For users who run Forge regularly:

| Category | Skill | What it does |
|----------|-------|-------------|
| **Plan** | `/forge-shape` | Turn a vague idea into a structured spec |
| **Plan** | `/forge-sprint` | Execute multiple features in parallel |
| **Quality** | `/forge-codebase-health` | Full codebase audit (read-only, no fixes) |
| **Quality** | `/forge-deep-health` | Fix all issues iteratively until clean |
| **Quality** | `/forge-security-audit` | Security vulnerability scan |
| **Ship** | `/forge-deploy` | Deploy to staging/production/preview |
| **Ship** | `/forge-commit` | Generate conventional commit messages |
| **Docs** | `/forge-docs-generate` | Generate README, ADRs, API specs |
| **Migrate** | `/forge-migration` | Framework/library version upgrade |
| **Know** | `/forge-ask` | Ask questions about the codebase |
| **Config** | `/forge-config` | Edit pipeline settings interactively |
| **Output** | `/forge-caveman` | Toggle terse output (save tokens) |

---

### Tier 3 — Advanced Skills

Pipeline management, analytics, graph, and compression:

#### Pipeline Management
| Skill | What it does |
|-------|-------------|
| `/forge-diagnose` | Read-only diagnostic when pipeline seems stuck |
| `/forge-repair-state` | Fix corrupted state.json |
| `/forge-abort` | Stop active run, preserve for resume |
| `/forge-resume` | Resume from last checkpoint |
| `/forge-reset` | Clear state, start fresh |
| `/forge-rollback` | Undo pipeline changes |
| `/forge-config-validate` | Check config before running |

#### Analytics
| Skill | What it does |
|-------|-------------|
| `/forge-history` | Score trends across runs |
| `/forge-insights` | Cross-run quality + cost analytics |
| `/forge-profile` | Per-stage/agent timing analysis |

#### Knowledge Graph (requires Docker)
| Skill | What it does |
|-------|-------------|
| `/forge-graph-init` | Start Neo4j, build codebase graph |
| `/forge-graph-status` | Check graph health |
| `/forge-graph-query` | Run Cypher queries |
| `/forge-graph-rebuild` | Rebuild graph from scratch |
| `/forge-graph-debug` | Diagnose graph issues |

#### Token Optimization
| Skill | What it does |
|-------|-------------|
| `/forge-compress` | Reduce agent prompt tokens (30-50%) |
| `/forge-compression-help` | Quick reference for all compression features |

#### Automation & Recipes
| Skill | What it does |
|-------|-------------|
| `/forge-automation` | Set up automatic pipeline triggers |
| `/forge-playbooks` | Manage reusable pipeline recipes |
| `/forge-bootstrap` | Scaffold a new project from scratch |

---

### Similar Skills — When to Use Which

| Confused between... | Use this one | Why |
|---|---|---|
| `/forge-review` vs `/forge-codebase-health` | `review` for recent changes, `health` for full codebase | Review targets staged/unstaged changes only |
| `/forge-codebase-health` vs `/forge-deep-health` | `codebase-health` to read, `deep-health` to fix | Health is read-only; deep-health fixes iteratively |
| `/forge-reset` vs `/forge-repair-state` | `repair-state` to fix corruption, `reset` to start fresh | Repair preserves more state than reset |
| `/forge-abort` vs `/forge-reset` | `abort` to pause for later, `reset` to clear everything | Abort + resume continues; reset starts over |
| `/forge-history` vs `/forge-insights` | `history` for trends, `insights` for deeper analytics | Insights adds cost analysis and memory health |
| `/forge-compress` vs `/forge-caveman` | `compress` for input tokens, `caveman` for output tokens | Compress rewrites files; caveman changes output style |
| `/forge-run bugfix:` vs `/forge-fix` | `/forge-fix` for bugs | Fix has richer source resolution and root cause investigation |

## Quick Reference

```
Build → /forge-run    Fix → /forge-fix    Review → /forge-review
Health → /forge-codebase-health    Pipeline broken → /forge-diagnose
New here → /forge-tour    This help → /forge-help
```

## See Also

- `/forge-tour` — guided 5-stop introduction for new users
- `/forge-init` — first-time project setup
- `/forge-compression-help` — compression features reference
