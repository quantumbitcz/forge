# Forge Plugin Redesign — Design Specification

> **Date:** 2026-04-02
> **Status:** Draft
> **Scope:** Rename dev-pipeline → forge, add kanban tracking, bugfix workflow, graph enrichment, init automation, smart tool recommendations, sub-agent visibility, branch/commit conventions, worktree enforcement, backward compat removal

---

## 1. Overview

This specification describes the redesign of the `dev-pipeline` Claude Code plugin into **Forge** — a fully rebranded, feature-complete autonomous development pipeline. The redesign introduces 9 major changes shipped across 4 phased releases (v1.0.0–v1.3.0), with no backward compatibility to prior versions.

### Release Phases

| Phase | Version | Scope |
|-------|---------|-------|
| 1 | v1.0.0 | Rename + backward compat removal + marketplace cleanup + version reset |
| 2 | v1.1.0 | Kanban tracking + branch naming + commit conventions + sub-agent visibility + worktree enforcement |
| 3 | v1.2.0 | Bugfix workflow (`/forge-fix`, `bugfix:` mode, `fg-020-bug-investigator`) |
| 4 | v1.3.0 | Graph enrichment + init automation + smart tool recommendations + MCP auto-provisioning |

### Key Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Plugin name | forge | Evocative of building/crafting, short, professional |
| Agent prefix | `fg-` | Full rebrand for consistency |
| Runtime directory | `.forge/` | Replaces `.pipeline/` |
| Sub-agent visibility | Orchestrator creates sub-tasks | No sub-agent changes needed |
| Kanban structure | Folder-per-status | Physical layout IS the board |
| Branch naming | Configurable template with hook detection | Respect existing project conventions |
| Bugfix entry | Source-aware (ticket/Linear/description) | Integrates with kanban and Linear |
| Graph access | Distributed to key agents | Interactive exploration for brainstorming |
| Tool dedup | Category tags with exclusive_group | DRY, framework-agnostic |
| Init automation | Project-local plugin | Claude Code-native, team-shareable |
| Backward compat | None — clean break | No users yet, remove all legacy |
| MCP provisioning | Auto-install if missing | Zero manual setup |
| Worktree usage | All workflows, no exceptions | User's working tree never modified |

---

## 2. Rename — Forge Branding (v1.0.0)

### 2.1 Naming Map

| What | From | To |
|------|------|----|
| Plugin name | `dev-pipeline` | `forge` |
| Plugin directory | `.claude/plugins/dev-pipeline/` | `.claude/plugins/forge/` |
| Runtime directory | `.pipeline/` | `.forge/` |
| Config file | `.claude/dev-pipeline.local.md` | `.claude/forge.local.md` |
| Mutable params | `.claude/pipeline-config.md` | `.claude/forge-config.md` |
| Learnings log | `.claude/pipeline-log.md` | `.claude/forge-log.md` |
| Neo4j container | `pipeline-neo4j` | `forge-neo4j` |
| Neo4j volume | `pipeline-neo4j-data` | `forge-neo4j-data` |
| Env var default | `NEO4J_CONTAINER=pipeline-neo4j` | `NEO4J_CONTAINER=forge-neo4j` |

### 2.2 Skills (7 renamed + 11 unchanged)

| From | To |
|------|----|
| `/pipeline-run` | `/forge-run` |
| `/pipeline-init` | `/forge-init` |
| `/pipeline-status` | `/forge-status` |
| `/pipeline-reset` | `/forge-reset` |
| `/pipeline-rollback` | `/forge-rollback` |
| `/pipeline-history` | `/forge-history` |
| `/pipeline-shape` | `/forge-shape` |

The 11 non-prefixed skills (`verify`, `security-audit`, `deploy`, `graph-*`, `bootstrap-project`, `codebase-health`, `docs-generate`, `migration`) keep their names.

### 2.3 Agents (21 renamed)

All `pl-NNN-name` → `fg-NNN-name`:

| From | To |
|------|----|
| `pl-010-shaper` | `fg-010-shaper` |
| `pl-050-project-bootstrapper` | `fg-050-project-bootstrapper` |
| `pl-100-orchestrator` | `fg-100-orchestrator` |
| `pl-130-docs-discoverer` | `fg-130-docs-discoverer` |
| `pl-140-deprecation-refresh` | `fg-140-deprecation-refresh` |
| `pl-150-test-bootstrapper` | `fg-150-test-bootstrapper` |
| `pl-160-migration-planner` | `fg-160-migration-planner` |
| `pl-200-planner` | `fg-200-planner` |
| `pl-210-validator` | `fg-210-validator` |
| `pl-250-contract-validator` | `fg-250-contract-validator` |
| `pl-300-implementer` | `fg-300-implementer` |
| `pl-310-scaffolder` | `fg-310-scaffolder` |
| `pl-320-frontend-polisher` | `fg-320-frontend-polisher` |
| `pl-350-docs-generator` | `fg-350-docs-generator` |
| `pl-400-quality-gate` | `fg-400-quality-gate` |
| `pl-500-test-gate` | `fg-500-test-gate` |
| `pl-600-pr-builder` | `fg-600-pr-builder` |
| `pl-650-preview-validator` | `fg-650-preview-validator` |
| `pl-700-retrospective` | `fg-700-retrospective` |
| `pl-710-feedback-capture` | `fg-710-feedback-capture` |
| `pl-720-recap` | `fg-720-recap` |

The 11 review agents (`architecture-reviewer`, `security-reviewer`, `frontend-reviewer`, `frontend-design-reviewer`, `frontend-a11y-reviewer`, `frontend-performance-reviewer`, `backend-performance-reviewer`, `version-compat-reviewer`, `infra-deploy-reviewer`, `infra-deploy-verifier`, `docs-consistency-reviewer`) keep their names.

### 2.4 Hook Scripts

- `pipeline-checkpoint.sh` → `forge-checkpoint.sh`
- `hooks/hooks.json` updated to reference new script name

### 2.5 Marketplace Cleanup

- Remove `dev-pipeline` entry from `marketplace.json`
- Add `forge` as new entry at v1.0.0
- Update `.claude-plugin/plugin.json` — name, description, all references
- Old install path `quantumbitcz/dev-pipeline` becomes dead — no redirect, no alias
- Install instructions: `/plugin marketplace add quantumbitcz/forge`

### 2.6 Files Affected

~780 references across ~150 files. Systematic find-and-replace with manual verification of:
- YAML frontmatter `name:` fields (must match filename)
- Orchestrator dispatch table (hardcoded agent names)
- Test assertions (minimum counts, path expectations)
- CLAUDE.md (full rewrite)
- CONTRIBUTING.md, README.md, SECURITY.md

---

## 3. Backward Compatibility Removal (v1.0.0)

### 3.1 What Gets Deleted

**State schema:**
- Remove all v1.x and v2.0.0 references and migration notes from `state-schema.md`
- State schema starts fresh at **v1.0.0**
- Remove `recovery_applied` deprecated field entirely
- Remove "old state files are incompatible" warnings
- Remove any "if old schema detected" branching

**Config templates:**
- All 21 framework `pipeline-config-template.md` → `forge-config-template.md`
- All 21 framework `local-template.md` files — update all references
- Remove any migration/compatibility logic

**Documentation:**
- CLAUDE.md — full rewrite, no historical version references
- CONTRIBUTING.md, README.md — update all references
- CHANGELOG.md — start fresh from v1.0.0 (forge era)
- Remove all "Breaking changes from vX.Y.Z" sections

**Tests:**
- Update all path expectations from `.pipeline/` to `.forge/`
- Update all agent name assertions from `pl-` to `fg-`
- Update all skill name assertions from `pipeline-*` to `forge-*`
- Remove backward-compat test cases

### 3.2 Version Numbering Reset

| What | Old | New |
|------|-----|-----|
| Plugin version | v1.4.0 | **v1.0.0** |
| State schema | v2.0.0 | **v1.0.0** |
| `plugin.json` version | 1.4.0 | 1.0.0 |
| `marketplace.json` | dev-pipeline 1.4.0 | forge 1.0.0 |

---

## 4. File-Based Kanban Tracking (v1.1.0)

### 4.1 Directory Structure

```
.forge/tracking/
├── counter.json                          # { "next": 4, "prefix": "FG" }
├── board.md                              # Auto-generated summary
├── backlog/
│   └── FG-003-add-search.md
├── in-progress/
│   ├── FG-001-user-notifications.md
│   └── FG-002-fix-booking-overlap.md
├── review/
│   └── (files moved here during REVIEW/SHIP stages)
└── done/
    └── (files moved here on PR merge or manual close)
```

### 4.2 Ticket File Format

```markdown
---
id: FG-001
title: Add user notifications
type: feature                             # feature | bugfix | refactor | chore
status: in-progress                       # backlog | in-progress | review | done
priority: medium                          # low | medium | high | critical
branch: feat/FG-001-user-notifications
created: 2026-04-02T10:30:00Z
updated: 2026-04-02T14:15:00Z
linear_id: null                           # LIN-1234 if synced to Linear
spec: .forge/specs/user-notifications.md  # link to shaped spec (if exists)
pr: null                                  # PR URL when created
---

## Description
Users should receive in-app notifications when their coach updates a plan.

## Acceptance Criteria
- [ ] Notification appears within 5s of plan update
- [ ] Notification links to the updated plan
- [ ] Read/unread state persisted

## Stories
1. Story 1: Backend notification service
2. Story 2: Frontend notification bell component

## Activity Log
- 2026-04-02 10:30 — Created by /forge-shape
- 2026-04-02 14:15 — Moved to in-progress by fg-100-orchestrator
```

### 4.3 Board Generation (`board.md`)

Auto-regenerated markdown table whenever a ticket moves:

```markdown
# Forge Board

> Last updated: 2026-04-02 14:15 UTC

| Status | ID | Title | Type | Priority | Branch |
|--------|----|-------|------|----------|--------|
| **In Progress** | FG-001 | User notifications | feature | medium | `feat/FG-001-user-notifications` |
| **In Progress** | FG-002 | Fix booking overlap | bugfix | high | `fix/FG-002-booking-overlap` |
| **Backlog** | FG-003 | Add search | feature | low | — |
```

### 4.4 Counter and ID Generation

- `counter.json`: `{ "next": 1, "prefix": "FG" }`
- Configurable prefix in `forge.local.md`: `tracking.prefix: "WP"` → produces `WP-001`
- IDs never reused — counter only increments

### 4.5 Linear Sync

- **Linear available at init**: Create Linear issue → store `linear_id` in frontmatter. Status changes sync both ways.
- **Linear becomes available mid-run**: Offer to sync existing tickets to Linear.
- **Linear unavailable**: Pure file-based. Kanban is the primary system, Linear is the optional mirror.

### 4.6 Integration with Forge Stages

| Stage | Kanban action |
|-------|---------------|
| `/forge-shape` | Creates ticket in `backlog/`, populates from spec |
| `/forge-run` (PREFLIGHT) | Moves ticket to `in-progress/` |
| `/forge-fix` (no ticket) | Creates ticket in `in-progress/` directly |
| REVIEW stage | Moves to `review/` |
| SHIP (PR created) | Updates `pr:` field in frontmatter |
| SHIP (PR merged) | Moves to `done/` |
| Abort/failure | Moves back to `backlog/`, adds activity log entry |

---

## 5. Branch Naming & Commit Conventions (v1.1.0)

### 5.1 Branch Naming

**Default template:**
```
{type}/{ticket}-{slug}
```

Examples:
- `feat/FG-001-user-notifications`
- `fix/FG-002-booking-overlap`
- `refactor/FG-003-extract-validation`
- `chore/FG-004-update-dependencies`

**Configuration in `forge.local.md`:**
```yaml
git:
  branch_template: "{type}/{ticket}-{slug}"
  branch_types: [feat, fix, refactor, chore]
  slug_max_length: 40
  ticket_source: auto                     # auto | linear | file | none
```

`ticket_source: auto`: use Linear ID if available → fall back to FG-xxx from kanban → fall back to no ticket prefix.

### 5.2 Project Hook Detection

During `/forge-init`, before writing git conventions:

1. **Scan for existing hooks:**
   - `.husky/` — Husky pre-commit/commit-msg hooks
   - `.git/hooks/` — native git hooks
   - `.pre-commit-config.yaml` — pre-commit framework
   - `lefthook.yml` — Lefthook
   - `commitlint.config.*` — commitlint config
   - `.czrc`, `.cz.json` — Commitizen config

2. **Parse existing conventions:**
   - If commitlint found → extract allowed types, scopes, rules
   - If branch naming hook found → extract pattern
   - If Conventional Commits detected → adopt the project's format

3. **Respect, don't override:**
   - If project already has commit/branch conventions → adopt them into `forge.local.md` `git:` section
   - If no conventions exist → write forge defaults
   - Always ask before creating new hooks

### 5.3 Commit Conventions

**Default format (Conventional Commits):**
```
{type}({scope}): {description}

{optional body}
```

**Rules enforced by forge agents:**
- Type: `feat`, `fix`, `test`, `refactor`, `docs`, `chore`, `perf`, `ci`
- Scope: optional, derived from affected module/component
- Description: imperative mood, lowercase start, no period, max 72 chars
- **Never include**: `Co-Authored-By`, `Generated by`, any AI attribution
- **Never include**: `--no-verify`, force push, skip hooks

**Configuration in `forge.local.md`:**
```yaml
git:
  commit_format: conventional              # conventional | project (use detected)
  commit_types: [feat, fix, test, refactor, docs, chore, perf, ci]
  commit_scopes: auto
  max_subject_length: 72
  require_scope: false
  sign_commits: false
```

### 5.4 Small Commit Strategy

The PR builder (`fg-600-pr-builder`) groups changes into logical units. Each commit must be independently valid (compiles, tests pass for its scope). Example:

```
feat(plan): add PlanComment entity and ports
feat(plan): implement create plan comment use case
feat(plan): add plan comment persistence adapter
feat(plan): add plan comment endpoint with tests
feat(plan): add plan comment UI component
```

---

## 6. Sub-Agent Progress Visibility (v1.1.0)

### 6.1 Problem

The orchestrator creates 10 `TaskCreate` items (one per stage). Sub-agents dispatched within stages are invisible to the user.

### 6.2 Solution

Before dispatching any sub-agent, the orchestrator calls `TaskCreate`. After the sub-agent returns, it marks the sub-task completed.

**Example — Stage 0 (PREFLIGHT):**
```
◼ Stage 0: Preflight
  ✓ Loading project config
  ✓ Detecting dependency versions
  ◼ Dispatching fg-130-docs-discoverer
  ◻ Dispatching fg-140-deprecation-refresh
  ◻ Dispatching fg-150-test-bootstrapper
◻ Stage 1: Explore
```

### 6.3 Sub-Task Creation Rules

| When | Subject format |
|------|---------------|
| Dispatching a named agent | `Dispatching fg-NNN-name` |
| Inline orchestrator work | Descriptive: `Loading project config`, `Acquiring run lock` |
| Review batches | `Review batch 1: architecture, security` |
| Convergence iterations | `Convergence iteration 2/5 (score: 74 → 82)` |

### 6.4 Implementation Scope

Only `fg-100-orchestrator` changes. Sub-agents don't know about the task system. The orchestrator wraps every `Agent` dispatch with:
1. `TaskCreate` (subject = what's being dispatched)
2. `Agent` dispatch
3. `TaskUpdate` (mark completed or note failure)

Stage tasks use `addBlocks`/`addBlockedBy` for dependency hierarchy.

---

## 7. Worktree Enforcement (v1.1.0)

### 7.1 Universal Rule

All forge workflows run in worktrees. No exceptions except `--dry-run` (read-only analysis) and `/forge-init` itself (writes to `.claude/` config, not source files).

### 7.2 Worktree Branch Mapping

| Entry point | Worktree branch | Location |
|-------------|----------------|----------|
| `/forge-run` (feature) | `feat/{ticket}-{slug}` | `.forge/worktree` |
| `/forge-fix` (bugfix) | `fix/{ticket}-{slug}` | `.forge/worktree` |
| `/forge-run --spec` | `feat/{ticket}-{slug}` | `.forge/worktree` |
| `/forge-run migrate:...` | `migrate/{ticket}-{slug}` | `.forge/worktree` |
| `/forge-run bootstrap:...` | `chore/{ticket}-bootstrap` | `.forge/worktree` |
| `/forge-init` setup tasks | `chore/{ticket}-{slug}` | `.forge/worktree` |

### 7.3 Worktree Lifecycle

```
PREFLIGHT → create worktree + branch (moved from Stage 4 to Stage 0)
EXPLORE through DOCS → all work inside worktree
SHIP → PR created from worktree branch
  ├─ PR merged → remove worktree, delete local branch
  ├─ PR rejected → preserve worktree for next iteration
  └─ Abort → preserve worktree, notify user of location
```

### 7.4 Cross-Cutting Constraint

Documented in `shared/stage-contract.md` as a cross-cutting constraint inherited by all agents. User's working tree is **never** modified during any forge workflow.

---

## 8. Bugfix Workflow (v1.2.0)

### 8.1 Entry Points

```bash
/forge-fix FG-005                              # from kanban tracking
/forge-fix --linear LIN-1234                   # from Linear issue
/forge-fix "Users get 404 on group endpoint"   # plain description → creates ticket
```

### 8.2 New Skill: `/forge-fix`

Thin launcher (like `/forge-run`). Detects MCPs, parses input source, dispatches `fg-100-orchestrator` with `mode: bugfix`.

### 8.3 New Agent: `fg-020-bug-investigator`

**Tools:** `Read`, `Grep`, `Glob`, `Bash`, `Agent`, `AskUserQuestion`, `neo4j-mcp`

**Responsibilities:**
- Pull context from ticket source (Linear issue body, kanban file, or raw description)
- Query graph for affected entities, dependencies, recent changes
- Explore code for the likely fault area
- Attempt automated reproduction (write a failing test)
- If reproduction not automatable → ask user for confirmation
- Output: root cause hypothesis + reproduction evidence + affected file list

### 8.4 Stage Mapping (Bugfix Mode)

| Stage | Standard mode | Bugfix mode | Agent |
|-------|---------------|-------------|-------|
| 0 | PREFLIGHT | PREFLIGHT (same) | fg-100 inline |
| 1 | EXPLORE | **INVESTIGATE** — pull ticket context, explore fault area, query graph | fg-020-bug-investigator |
| 2 | PLAN | **REPRODUCE** — write failing test or get user confirmation | fg-020-bug-investigator (continued) |
| 3 | VALIDATE | **ROOT CAUSE** — confirm hypothesis, validate reproduction | fg-210-validator (reused, bugfix perspective) |
| 4 | IMPLEMENT | **FIX** — TDD: make failing test pass, refactor | fg-300-implementer (reused) |
| 5 | VERIFY | VERIFY (same) | fg-500-test-gate (reused) |
| 6 | REVIEW | REVIEW (reduced batch for backend-only bugs) | fg-400-quality-gate (reused) |
| 7 | DOCS | DOCS (minimal — changelog + affected docs) | fg-350-docs-generator (reused) |
| 8 | SHIP | SHIP (same) | fg-600-pr-builder (reused) |
| 9 | LEARN | LEARN (same + bug pattern tracking) | fg-700-retrospective (reused) |

### 8.5 Ticket Creation from Description

When `/forge-fix` receives a plain description (no ticket reference):
1. Generate next ID from `.forge/tracking/counter.json`
2. Create ticket file in `.forge/tracking/in-progress/FG-XXX-{slug}.md` with `type: bugfix`
3. If Linear available → create Linear issue, store `linear_id` in frontmatter
4. Use the generated ID for branch naming: `fix/FG-XXX-{slug}`

### 8.6 Reproduction Strategy

```
1. Extract reproduction steps from ticket (if available)
2. Query graph: what tests exist for the affected area?
3. Attempt to write a failing test:
   a. Unit test if isolated logic bug
   b. Integration test if data/API bug
   c. Playwright script if UI bug (requires Playwright MCP)
4. Run the test:
   - FAILS → reproduction confirmed, proceed to ROOT CAUSE
   - PASSES → hypothesis wrong, re-investigate (max 3 attempts)
5. If cannot automate after 3 attempts:
   - Ask user: "I believe the bug occurs when {scenario}. Can you confirm?"
   - User confirms → proceed with manual reproduction evidence
   - User denies → ask for more context, retry investigation
6. If still unresolvable → escalate with options:
   (A) Provide more context
   (B) Pair debug
   (C) Close as unreproducible
```

### 8.7 Bug Pattern Tracking (LEARN Stage)

The retrospective agent tracks bug patterns in `.forge/forge-log.md`:
- **Root cause category**: off-by-one, null handling, race condition, missing validation, wrong assumption, config error
- **Affected layer**: domain, persistence, API, frontend, infra
- **Detection method**: test, user report, monitoring, code review
- **Time to reproduce**: automated / manual / unresolvable

### 8.8 State Schema Addition

```json
{
  "mode": "bugfix",
  "bugfix": {
    "source": "kanban|linear|description",
    "source_id": "FG-005",
    "reproduction": {
      "method": "automated|manual|unresolvable",
      "test_file": "src/test/.../GroupEndpoint404Test.kt",
      "attempts": 2
    },
    "root_cause": {
      "hypothesis": "Missing null check on group lookup",
      "category": "null_handling",
      "affected_files": ["src/.../GroupService.kt"],
      "confidence": "high"
    }
  }
}
```

---

## 9. Neo4j Graph Enrichment (v1.3.0)

### 9.1 Distributed Access

Agents gaining `neo4j-mcp` tool:

| Agent | Why | Query patterns |
|-------|-----|----------------|
| `fg-010-shaper` | Interactive exploration during brainstorming | 2, 3, 7, 9, 11, 14, 15 |
| `fg-200-planner` | Deeper dependency analysis during task decomposition | 2, 3, 7, 9 |
| `fg-210-validator` | Interactive decision/constraint validation | 11, 12 |
| `fg-400-quality-gate` | Stale docs, contradictions when coordinating reviews | 10, 11, 12 |
| `fg-020-bug-investigator` | Trace dependencies, find related tests | 2, 3, 7, 14, 15 |

The orchestrator (`fg-100-orchestrator`) keeps `neo4j-mcp` for pre-querying on behalf of agents without direct access.

### 9.2 Pattern 3 Activation: Entity Impact Analysis (Currently Unused)

```cypher
MATCH (target:ProjectClass {name: $entityName})
MATCH (consumer:ProjectFile)-[:IMPORTS]->(targetFile:ProjectFile)-[:CLASS_IN_FILE]->(target)
MATCH (consumer)-[:USES_CONVENTION]->(conv)
RETURN consumer.path, conv.name, targetFile.path
```

Used by shaper, bug investigator, and planner for blast radius analysis.

### 9.3 Pattern 6 Activation: Recommendation (Currently Partially Used)

```cypher
MATCH (fw:Framework {name: $framework})-[:PAIRS_WITH]->(layer:LayerModule)
RETURN layer.name, layer.category
ORDER BY layer.adoption_score DESC
```

Used by `/forge-init` for data-driven layer module recommendations.

### 9.4 New Pattern 14: Bug Hotspot Analysis

```cypher
MATCH (f:ProjectFile)
WHERE f.bug_fix_count > 0
RETURN f.path, f.bug_fix_count, f.last_bug_fix_date
ORDER BY f.bug_fix_count DESC
LIMIT 20
```

Populated by retrospective after each bugfix. Used by shaper and quality gate for risk-aware decisions.

### 9.5 New Pattern 15: Test Coverage by Entity

```cypher
MATCH (c:ProjectClass)
OPTIONAL MATCH (t:ProjectFile)-[:TESTS]->(f:ProjectFile)-[:CLASS_IN_FILE]->(c)
WHERE t IS NULL
RETURN c.name, f.path AS source_file
```

Used by bug investigator and test gate for coverage gap detection.

### 9.6 Shaper Enrichment Flow

Phase 4 (Identify Components) becomes graph-powered:
1. Query Pattern 7: Blast radius from feature keywords → affected packages
2. Query Pattern 3: Entity impact for each affected entity → consumer files
3. Query Pattern 11: Active decisions constraining the affected area
4. Query Pattern 14: Bug hotspots in affected area → flag risk
5. Query Pattern 15: Test coverage gaps → note in spec
6. Synthesize into Technical Notes section of spec

### 9.7 Graceful Degradation

All agents with `neo4j-mcp` follow the same rule:
- If graph unavailable → skip graph queries, fall back to grep/glob
- Log INFO: "Graph unavailable, using file-based analysis"
- No recovery engine invocation for graph failures

### 9.8 MCP Auto-Provisioning

```
1. Check Docker available?
   ├─ NO → "Graph features require Docker. Skip? (Y/N)"
   └─ YES ↓
2. Check Neo4j container running?
   ├─ NO → Start via docker-compose
   └─ YES ↓
3. Check Neo4j MCP configured?
   ├─ NO → Search internet for latest neo4j-mcp package
   │       Install via npx
   │       Write config to .mcp.json
   └─ YES ↓
4. Verify connectivity (RETURN 1)
   ├─ FAIL → Retry once, then degrade
   └─ OK → Graph ready
```

**General MCP auto-provisioning config in `forge.local.md`:**
```yaml
mcps:
  neo4j:
    required: false
    auto_install: true
    package: "@neo4j/mcp"             # resolved to latest at install time
    verify: "RETURN 1"
  playwright:
    required: false
    auto_install: true
    package: "@anthropic/mcp-playwright"  # resolved to latest at install time
    verify: null
```

> **Note:** Package names in config are hints for search — actual package is resolved by searching npm/pypi at install time for the latest compatible version. Never hardcode versions.

For every MCP the forge detects as useful: check if configured → if not, search internet for latest version → install → verify → mark available. No manual setup required.

---

## 10. Smart Tool Recommendations (v1.3.0)

### 10.1 Category Tags in Code-Quality Modules

Every `modules/code-quality/*.md` file gets frontmatter tags:

```yaml
---
name: ktlint
categories: [linter, formatter]
languages: [kotlin]
exclusive_group: kotlin-formatter
recommendation_score: 90
detection_files: [".editorconfig", "ktlint.yml", ".ktlint"]
---
```

### 10.2 Exclusive Groups

| Group | Tools | Default winner |
|-------|-------|----------------|
| `kotlin-formatter` | ktlint, spotless, ktfmt | ktlint |
| `kotlin-linter` | detekt | detekt (no conflict) |
| `js-formatter` | prettier, biome | biome (if no existing prettier config) |
| `js-linter` | eslint, biome | biome (superset) |
| `python-formatter` | black, ruff-format, yapf | ruff-format |
| `python-linter` | ruff, flake8, pylint | ruff |
| `go-formatter` | gofmt, goimports | goimports (superset) |
| `ruby-formatter` | rubocop | rubocop (no conflict) |
| `rust-linter` | clippy | clippy (no conflict) |
| `csharp-formatter` | dotnet-format, csharpier | csharpier |
| `security-scanner` | owasp, snyk, trivy, npm-audit, cargo-audit, safety | **no exclusion** — complementary |

### 10.3 Recommendation Algorithm

```
1. Load framework's code_quality_recommended list
2. For each tool: read module file, extract exclusive_group
3. Group by exclusive_group
4. For each group:
   a. If project already has one → keep it, skip others
   b. If none detected → pre-select highest recommendation_score
   c. Mark others as "alternative (not selected)"
5. Present to user:
   ✅ detekt — static analysis (recommended)
   ✅ ktlint — linting + formatting (recommended)
      ↳ Alternatives: spotless, ktfmt (same category: kotlin-formatter)
   ...
   (A) Accept recommendations
   (B) Customize selection
   (C) Skip
```

### 10.4 Customize Selection Flow

Radio buttons for exclusive groups, checkboxes for non-exclusive (complementary) groups:

```
Kotlin formatter (pick one):
  ● ktlint — fast, Kotlin-native (recommended)
  ○ spotless — Gradle plugin, wraps multiple formatters
  ○ ktfmt — Google's opinionated formatter
  ○ None

Security scanning (pick any):
  ☑ owasp-dependency-check — CVE database
  ☐ snyk — SaaS-based
  ☐ trivy — container + filesystem
```

### 10.5 Existing Tool Detection

Each module declares `detection_files` in frontmatter. If any detection file exists in the project → tool marked "already configured" and pre-selected regardless of `recommendation_score`.

---

## 11. Init Automation Creation (v1.3.0)

### 11.1 Project-Local Plugin Structure

```
.claude/plugins/project-tools/
├── plugin.json
├── hooks/
│   ├── hooks.json
│   ├── commit-msg-guard.sh
│   └── branch-name-guard.sh
├── skills/
│   ├── run-tests/SKILL.md
│   ├── build/SKILL.md
│   ├── lint/SKILL.md
│   └── deploy/SKILL.md
├── agents/
│   └── commit-reviewer.md
└── .mcp.json
```

### 11.2 Hook Generation

**Commit message guard** — generated based on detected or configured conventions:
```bash
#!/usr/bin/env bash
MSG_FILE="$1"
MSG=$(head -1 "$MSG_FILE")
PATTERN="^(feat|fix|test|refactor|docs|chore|perf|ci)(\(.+\))?: .{1,72}$"
if ! echo "$MSG" | grep -qE "$PATTERN"; then
  echo "ERROR: Commit message doesn't match conventional commits format"
  echo "Expected: type(scope): description"
  echo "Got: $MSG"
  exit 1
fi
```

**Branch name guard** — validates against configured template:
```bash
#!/usr/bin/env bash
BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null)
PATTERN="^(feat|fix|refactor|chore)/[A-Z]+-[0-9]+-[a-z0-9-]+$"
if ! echo "$BRANCH" | grep -qE "$PATTERN"; then
  echo "WARNING: Branch '$BRANCH' doesn't match naming convention"
  echo "Expected: {type}/{TICKET-ID}-{slug}"
fi
```

If the project already has commitlint/husky → skip, note in `forge.local.md`: `git.commit_enforcement: external`.

### 11.3 Skill Generation

Init detects build/test/lint/deploy tools and generates wrapper skills:

| Detected | Generates | Command |
|----------|-----------|---------|
| `build.gradle.kts` | `/build`, `/run-tests` | `./gradlew build`, `./gradlew test` |
| `package.json` + vitest | `/run-tests` | `npm run test` |
| `package.json` + jest | `/run-tests` | `npm run test` |
| `Makefile` | `/build` | `make build` |
| `pyproject.toml` + pytest | `/run-tests` | `pytest` |
| `Cargo.toml` | `/build`, `/run-tests` | `cargo build`, `cargo test` |
| `Dockerfile` + `docker-compose.yml` | `/deploy` | `docker compose up --build` |
| `detekt.yml` | `/lint` | `./gradlew detekt` |
| `ruff.toml` | `/lint` | `ruff check .` |
| `.eslintrc*` or `biome.json` | `/lint` | `npx eslint .` or `npx biome check .` |

### 11.4 Init Dispatch to Pipeline for Setup Tasks

After generating config and project-local plugin, init checks for implementation tasks:

```
"The following tools need implementation:
1. dokka — needs Gradle plugin + task configuration
2. jacoco — needs Gradle plugin + coverage thresholds
3. GitHub Actions — needs .github/workflows/ci.yml

(A) Run /forge-run to implement all setup tasks now
(B) Add to backlog — creates tickets in .forge/tracking/backlog/
(C) Skip — configure manually later"
```

If (A): creates tickets, dispatches `/forge-run` with bundled requirement (in worktree).
If (B): creates tickets for future runs.

### 11.5 Existing Project Respect

```
For each automation category:
  1. Detect if project already has equivalent
  2. If YES → skip, adopt existing into forge.local.md
  3. If NO → generate, ask user confirmation per category
  4. Never overwrite existing hooks/scripts/configs
```

---

## 12. Development Process (Implementation Phase)

### 12.1 Per-Phase Workflow

```
1. Spec approved (this document)
2. Implementation plan written (/writing-plans skill)
3. Plan approved by user
4. For each plan step:
   a. Work in git worktree (isolated branch per phase)
   b. Ralph Loop:
      ┌─────────────────────────────────────────────┐
      │ 1. Implement the step                       │
      │ 2. Deep investigation:                      │
      │    - Missing features / gaps                │
      │    - Design flaws / logical issues          │
      │    - Discrepancies between docs and code    │
      │    - Platform independence issues            │
      │    - Enhancement opportunities              │
      │    - Challenge: is there a better solution? │
      │    - Search internet for docs/best practices│
      │ 3. Fix everything found                     │
      │ 4. Update documentation                     │
      │ 5. /requesting-code-review                  │
      │ 6. Fix ALL issues (including minor)         │
      │ 7. Commit (small, logical chunks)           │
      │ 8. Loop condition:                          │
      │    - More to fix/improve? → next iteration  │
      │    - Clean review + no impact? → exit loop  │
      └─────────────────────────────────────────────┘
   c. Final /requesting-code-review after loop ends
   d. Commit remaining changes
5. Phase complete → next phase
```

### 12.2 Commit Discipline

- Small logical commits throughout the loop
- Conventional commits format: `type(scope): description`
- No AI attribution — ever
- Each commit independently valid
- Example for rename phase:
  ```
  refactor(plugin): rename plugin.json from dev-pipeline to forge
  refactor(agents): rename pl- prefix to fg- across all 21 agents
  refactor(skills): rename pipeline-* skills to forge-*
  refactor(shared): update .pipeline/ references to .forge/
  refactor(hooks): rename pipeline-checkpoint to forge-checkpoint
  refactor(modules): update all framework templates to forge naming
  refactor(tests): update assertions for forge naming
  docs: rewrite CLAUDE.md for forge branding
  docs: update CONTRIBUTING.md and README.md
  chore: reset version to 1.0.0
  ```

### 12.3 Platform Independence Checks

Every Ralph Loop iteration verifies:
- Shell scripts use `#!/usr/bin/env bash`
- No macOS-specific flags (`sed -i ''` vs `sed -i`)
- Path separators handled correctly
- No hardcoded absolute paths
- Docker commands work on Linux/macOS/WSL
- `engine.sh` and hook scripts use POSIX-compatible constructs where possible

### 12.4 Release Phase Branches

| Phase | Version | Branch |
|-------|---------|--------|
| 1 | v1.0.0 | `feat/FG-001-forge-rename` |
| 2 | v1.1.0 | `feat/FG-002-kanban-and-git` |
| 3 | v1.2.0 | `feat/FG-003-bugfix-workflow` |
| 4 | v1.3.0 | `feat/FG-004-graph-and-init` |
