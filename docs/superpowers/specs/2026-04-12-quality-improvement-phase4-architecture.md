# Phase 4: Architecture Refinements

**Parent:** [Umbrella Spec](./2026-04-12-quality-improvement-umbrella-design.md)
**Priority:** Lower — new artifacts and centralization. Higher effort, broader impact.
**Approach:** Test-gated. New artifacts get structural tests; modifications get regression tests.

## Item 4.1: Centralize MCP detection logic

**Rationale:** Skills forge-run, forge-fix, deep-health, and migration each independently detect MCPs by checking tool name prefixes. This creates duplication — if a tool name prefix changes, multiple skills silently break. In a doc-only plugin, "centralization" means a canonical reference document that skills point to.

**Category:** Architecture — reduce fragility.

**New file:** `shared/mcp-detection.md`

**Content structure:**
```markdown
# MCP Detection Reference

Canonical tool name prefixes and degradation behavior for each detected MCP.
Skills MUST reference this document instead of inline detection logic.

## Detection Table

| MCP | Tool Name Prefix | Detection Probe Tool | Available Capability | Degradation When Unavailable |
|---|---|---|---|---|
| Linear | `mcp__claude_ai_Linear__` | `mcp__claude_ai_Linear__list_teams` | Epic/story tracking, status sync | File-based kanban only; skip Linear sync |
| Playwright | `mcp__plugin_playwright_playwright__` | `mcp__plugin_playwright_playwright__browser_navigate` | Browser automation, E2E testing, screenshots | Skip preview validation; manual testing |
| Slack | `mcp__claude_ai_Slack__` | `mcp__claude_ai_Slack__slack_send_message` | Channel messaging, search, canvas | Skip notifications; console output only |
| Context7 | `mcp__plugin_context7_context7__` | `mcp__plugin_context7_context7__resolve-library-id` | Live documentation lookup, version-aware API refs | Fall back to training data + WebSearch |
| Figma | `mcp__claude_ai_Figma__` | `mcp__claude_ai_Figma__get_design_context` | Design-to-code, screenshots, component mapping | Skip design system validation |
| Excalidraw | `mcp__claude_ai_Excalidraw__` | `mcp__claude_ai_Excalidraw__create_view` | Architecture diagrams, visual documentation | Text-based diagrams only |
| Neo4j | neo4j-mcp | `neo4j-mcp` (tool name) | Knowledge graph queries, codebase graph | Skip graph enrichment; file-based analysis |

## Detection Protocol

1. At PREFLIGHT, probe each MCP by checking if its detection probe tool is available
2. First failure → mark MCP as `degraded` for the remainder of the run
3. Log an INFO finding: `MCP-UNAVAILABLE: {mcp_name} — {degradation behavior}`
4. Do NOT invoke the recovery engine for MCP failures (per error-taxonomy.md)

## Referencing This Document

Skills should reference this table rather than hardcoding detection logic:
- "Detect MCPs per `shared/mcp-detection.md` detection table"
- Do NOT duplicate the tool name prefixes in skill files
```

**Skill updates:** In skills that currently inline MCP detection (forge-run, forge-fix, deep-health, migration), replace inline detection blocks with a reference: "Detect available MCPs per `shared/mcp-detection.md`." The exact tool name prefixes are removed from skill files.

**New test:** `tests/contract/mcp-detection-completeness.bats`
- Reads MCP list from CLAUDE.md
- Asserts each MCP has a row in `shared/mcp-detection.md`
- Asserts the file contains the Detection Protocol section

## Item 4.2: Add error logging to forge-compact-check.sh

**Rationale:** Three of four hooks log failures to `.forge/.hook-failures.log`. `forge-compact-check.sh` silently swallows errors when `atomic_increment` fails, leaving no trace for debugging.

**Category:** Observability — consistency with other hooks.

**Change:** In `shared/forge-compact-check.sh`, add error logging in the fallback paths where `atomic_increment` fails or returns empty:

```bash
# After the atomic_increment call, in the error/fallback path:
if [[ -z "$count" || "$count" == "0" ]]; then
  # Check if this is a real 0 or an error
  if [[ ! -f "$TOKEN_FILE" ]] || [[ "$(cat "$TOKEN_FILE" 2>/dev/null)" != "0" ]]; then
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) compact-check: atomic_increment failed or returned empty" \
      >> "${FORGE_DIR}/.hook-failures.log" 2>/dev/null
  fi
fi
```

The hook continues to exit 0 (best-effort pattern) — logging is observational, not blocking.

**New test:** `tests/unit/compact-check-logging.bats`
- Mocks `atomic_increment` to fail (returns empty)
- Runs forge-compact-check.sh
- Asserts `.hook-failures.log` contains "compact-check" entry
- Asserts exit code is 0 (non-blocking)

## Item 4.3: Create shared/agent-registry.md

**Rationale:** Agent IDs are hardcoded across 28 skills and shared documents. If an agent is renamed or removed, references silently break. A central registry provides a single source of truth and enables automated cross-reference validation.

**Category:** Architecture — single source of truth.

**New file:** `shared/agent-registry.md`

**Content structure:**
```markdown
# Agent Registry

Single source of truth for all forge agents. When referencing an agent in skills or
shared documents, use the ID from this registry. When adding, renaming, or removing
an agent, update this registry FIRST.

## Registry

| Agent ID | Tier | Dispatches? | Pipeline Stage | Category |
|---|---|---|---|---|
| fg-010-shaper | 1 | No | Pre-pipeline | Shaping |
| fg-015-scope-decomposer | 1 | No | Pre-pipeline | Decomposition |
| fg-020-bug-investigator | 2 | No | Pre-pipeline | Investigation |
| fg-050-project-bootstrapper | 1 | No | Pre-pipeline | Bootstrap |
| fg-090-sprint-orchestrator | 1 | Yes | Sprint | Orchestration |
| fg-100-orchestrator | 2 | Yes | Core | Orchestration |
| fg-101-worktree-manager | 4 | No | Core | Git |
| fg-102-conflict-resolver | 4 | No | Core | Analysis |
| fg-103-cross-repo-coordinator | 2 | Yes | Core | Coordination |
| fg-130-docs-discoverer | 3 | No | Preflight | Discovery |
| fg-140-deprecation-refresh | 3 | No | Preflight | Maintenance |
| fg-150-test-bootstrapper | 3 | Yes | Preflight | Testing |
| fg-160-migration-planner | 1 | No | Preflight | Migration |
| fg-200-planner | 1 | Yes | Plan | Planning |
| fg-210-validator | 4 | No | Validate | Validation |
| fg-250-contract-validator | 3 | Yes | Validate | Contracts |
| fg-300-implementer | 3 | No | Implement | TDD |
| fg-310-scaffolder | 3 | No | Implement | Scaffolding |
| fg-320-frontend-polisher | 3 | No | Implement | Frontend |
| fg-350-docs-generator | 3 | Yes | Document | Documentation |
| fg-400-quality-gate | 2 | Yes | Review | Coordination |
| fg-410-code-reviewer | 4 | No | Review | Quality |
| fg-411-security-reviewer | 4 | No | Review | Security |
| fg-412-architecture-reviewer | 4 | No | Review | Architecture |
| fg-413-frontend-reviewer | 4 | No | Review | Frontend |
| fg-416-backend-performance-reviewer | 4 | No | Review | Performance |
| fg-417-version-compat-reviewer | 4 | No | Review | Compatibility |
| fg-418-docs-consistency-reviewer | 4 | No | Review | Documentation |
| fg-419-infra-deploy-reviewer | 4 | No | Review | Infrastructure |
| fg-420-dependency-reviewer | 4 | No | Review | Dependencies |
| fg-500-test-gate | 2 | Yes | Verify | Coordination |
| fg-505-build-verifier | 3 | No | Verify | Build |
| fg-590-pre-ship-verifier | 3 | Yes | Ship | Verification |
| fg-600-pr-builder | 2 | Yes | Ship | Shipping |
| fg-610-infra-deploy-verifier | 3 | No | Ship | Infrastructure |
| fg-650-preview-validator | 3 | No | Ship | Preview |
| fg-700-retrospective | 3 | No | Learn | Learning |
| fg-710-post-run | 2 | No | Learn | Feedback |

## Rules

1. Agent IDs follow the pattern `fg-{NNN}-{role}` where NNN determines pipeline ordering
2. When referencing an agent in a skill or shared doc, use the exact ID from this table
3. When adding a new agent, add a row here BEFORE creating the agent file
4. When removing an agent, remove the row here AND grep for references across skills/shared docs
5. The Dispatches? column indicates whether the agent has `Agent` in its tools list
```

**New test:** `tests/contract/agent-registry-sync.bats`
- For each `.md` file in `agents/`, extracts the `name:` from frontmatter
- Asserts a matching row exists in `shared/agent-registry.md`
- For each agent ID in the registry, asserts `agents/{id}.md` exists
- Bidirectional sync: no orphans in either direction

## Item 4.4: Create graph-debug skill

**Rationale:** Current graph skills are `graph-status` (read-only overview), `graph-query` (raw Cypher), and `graph-rebuild` (full rebuild). There's no targeted diagnostic tool for partial issues — orphaned nodes, stale data, missing enrichments. Users must write raw Cypher to diagnose problems.

**Category:** New feature — fills diagnostic gap.

**New file:** `skills/graph-debug/SKILL.md`

**Content structure:**
```markdown
---
name: graph-debug
description: Diagnose Neo4j knowledge graph issues — orphaned nodes, stale data, missing enrichments, relationship integrity. Use when graph-status shows anomalies or graph queries return unexpected results.
---

# Graph Debug

Targeted diagnostic skill for the Neo4j knowledge graph. Provides structured
diagnostic recipes without requiring raw Cypher knowledge.

## Prerequisites

- Neo4j container running (check via `shared/graph/neo4j-health.sh`)
- Graph initialized (`/graph-init` completed)

## Diagnostic Recipes

### 1. Orphaned Nodes
Nodes with no relationships (potential data quality issue):
```cypher
MATCH (n) WHERE NOT (n)--() RETURN labels(n) AS type, count(n) AS count
```

### 2. Stale Nodes
Nodes not updated since a given commit:
```cypher
MATCH (n {project_id: $project_id})
WHERE n.last_updated_sha <> $current_sha
RETURN labels(n)[0] AS type, n.name AS name, n.last_updated_sha AS stale_sha
LIMIT 50
```

### 3. Missing Enrichments
Expected enrichment properties absent on node types:
```cypher
MATCH (n:Function {project_id: $project_id})
WHERE n.complexity IS NULL OR n.test_coverage IS NULL
RETURN n.name AS function, n.file_path AS file
LIMIT 50
```

### 4. Relationship Integrity
Check for dangling references:
```cypher
MATCH (a)-[r]->(b)
WHERE a.project_id = $project_id AND b IS NULL
RETURN type(r) AS rel_type, a.name AS source
```

### 5. Node Count Summary
Quick health overview by label:
```cypher
MATCH (n {project_id: $project_id})
RETURN labels(n)[0] AS label, count(n) AS count
ORDER BY count DESC
```

## Procedure

1. Run Neo4j health check via `shared/graph/neo4j-health.sh`
2. If unhealthy: report status and suggest `/graph-init` or Docker troubleshooting
3. If healthy: derive `project_id` from git remote
4. Run diagnostic recipes 1-5, report findings in table format
5. If user provides a specific concern, run targeted Cypher (read-only, enforce LIMIT)
6. Suggest remediation: `/graph-rebuild` for widespread staleness, manual fixes for isolated issues

## Safety

- All queries are READ-ONLY (no CREATE, MERGE, DELETE, SET)
- All queries enforce LIMIT (max 50 rows default, configurable)
- Never modify graph state — diagnostic only
```

**New test:** `tests/contract/graph-debug-skill.bats`
- Asserts `skills/graph-debug/SKILL.md` exists
- Asserts frontmatter contains `name: graph-debug` and `description:`
- Asserts all Cypher queries in the skill are read-only (no CREATE, MERGE, DELETE, SET)

## Phase 4 Verification Checklist

- [ ] 4 new tests written and failing (red)
- [ ] `shared/mcp-detection.md` created with all 7 MCPs
- [ ] Skills updated to reference mcp-detection.md (forge-run, forge-fix, deep-health, migration)
- [ ] `forge-compact-check.sh` error logging added
- [ ] `shared/agent-registry.md` created with all 38 agents
- [ ] `skills/graph-debug/SKILL.md` created
- [ ] 4 new tests passing (green)
- [ ] All existing tests passing (`./tests/run-all.sh`)
- [ ] `/requesting-code-review` passes
