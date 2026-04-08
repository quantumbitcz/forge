# Agent Consolidation Roadmap

## Current State: 40 Agents

The forge pipeline has 40 agents. Each dispatch costs ~50K+ tokens of context construction.

## Consolidation Opportunities

### Tier 1: Safe Merges (overlapping domains, same stage)

| Current Agents | Merged Agent | Savings | Risk |
|---|---|---|---|
| `fg-413-frontend-reviewer` + `frontend-design-reviewer` | `fg-413-frontend-reviewer` (with design checklist) | 1 dispatch | Low |
| `fg-414-frontend-a11y-reviewer` + `fg-415-frontend-performance-reviewer` | `frontend-quality-reviewer` | 1 dispatch | Low |
| `fg-410-architecture-reviewer` + `fg-412-code-quality-reviewer` | `code-reviewer` (with arch + quality checklists) | 1 dispatch | Medium |

### Tier 2: Moderate Merges

| Current Agents | Merged Agent | Savings | Risk |
|---|---|---|---|
| `fg-710-feedback-capture` + `fg-720-recap` | `fg-710-post-run` | 1 dispatch | Low |
| `fg-101-worktree-manager` + `fg-102-conflict-resolver` | `fg-101-workspace-manager` | 1 dispatch | Medium |

### Tier 3: Do Not Merge

| Agent | Reason |
|---|---|
| `fg-100-orchestrator` | Coordinator — must stay isolated |
| `fg-300-implementer` | Hot path — large prompt |
| `fg-200-planner` | Distinct domain |
| `fg-411-security-reviewer` | Must be independently auditable |
| `fg-590-pre-ship-verifier` | Evidence gate — must be independent |

## Recommended First Merge

`fg-413-frontend-reviewer` + `frontend-design-reviewer` → combined `fg-413-frontend-reviewer`

## Implementation Steps

1. Merge the agent .md files
2. Update plugin.json agent list
3. Update fg-400-quality-gate.md batch dispatch
4. Update CLAUDE.md agent count
5. Update structural tests
6. Run full test suite
7. Validate with dry-run

## Target State: ~30 Agents (from 40)

Tier 1: 40 → 37, Tier 2: 37 → 35, Future: 35 → ~30
