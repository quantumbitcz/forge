# Neo4j Multi-Project Namespacing — Graph Isolation for Concurrent Projects

> **Scope:** Add `project_id` and `component` properties to all `Project*`/`Doc*` graph nodes, scope all queries and rebuild operations per-project, add incremental auto-update at pipeline stage boundaries. Part of v1.5.0.
>
> **Status:** Design approved
>
> **Dependencies:** None (ships independently, prerequisite for Spec 3: Parallel Multi-Feature Development)

---

## 1. Problem Statement

The Neo4j knowledge graph has no project-level isolation:

- `ProjectFile`, `ProjectClass`, and all other `Project*` nodes lack a project discriminator property
- `/graph-rebuild` deletes ALL `Project*` nodes and rebuilds from the current project — destroying data from any other project that shared the same Neo4j instance
- Two projects on the same machine overwrite each other's graph data
- Monorepo components share the same node space with no way to query per-component
- The graph goes stale during pipeline runs — no auto-update mechanism exists

## 2. Design Decisions

### Considered Alternatives

1. **Separate container per project** — Each project gets its own Neo4j container. Rejected: wasteful on resources, complicates cross-project queries which are a core feature for cross-repo analysis.
2. **Separate databases (Neo4j Enterprise)** — Each project gets its own database within one container. Rejected: requires Neo4j Enterprise Edition (paid license), Community Edition only supports one database.
3. **Shared container, namespaced nodes (chosen)** — Keep one Neo4j instance, add `project_id` and `component` properties to all project-scoped nodes. Queries scope by project. Cross-project queries use explicit multi-project Cypher.

### Justification

The namespaced-nodes approach was chosen because:
- Neo4j Community Edition (what forge uses) only supports one database
- One container keeps resource usage low and cross-project queries natural
- Adding properties + updating queries is a minimal, well-understood change
- Cross-project analysis (a key feature for monorepo/cross-repo setups) stays as simple Cypher without connecting to multiple databases

### Project ID Strategy

- **Primary:** Git remote origin — `git remote get-url origin | sed 's|.*github.com[:/]||; s|\.git$||'` → e.g., `quantumbitcz/wellplanned-be`
- **Fallback:** Absolute path of project root (for non-git projects)
- Automatically derived — no manual configuration needed
- Stable across machines (git remote), natural identifier for cross-repo relationships

### Component Scoping

For monorepo multi-service projects with `components:` in `forge.local.md`:
- Each `Project*` node gets an additional `component` property (e.g., `"api"`, `"web"`)
- Value comes from the `components:` key in `forge.local.md`
- Single-component projects: `component` is `null` (omitted from queries)
- Enables precise per-component queries without fragile path-prefix matching

## 3. Schema Changes

### 3.1 New Properties on Project-Scoped Nodes

Every `Project*` and `Doc*` node gains two properties:

| Property | Type | Source | Required |
|----------|------|--------|----------|
| `project_id` | string | Git remote origin, fallback to absolute path | Always |
| `component` | string \| null | `components:` key from `forge.local.md` | Optional |

Affected node types (12):
- `ProjectLanguage`, `ProjectFile`, `ProjectPackage`, `ProjectDependency`, `ProjectClass`, `ProjectFunction`, `ProjectConfig`
- `DocFile`, `DocSection`, `DocDecision`, `DocConstraint`, `DocDiagram`

Plugin seed nodes (`Language`, `Framework`, `Agent`, `SharedContract`, etc.) are **not** affected — they are global.

### 3.2 ProjectConfig Changes

`ProjectConfig` already has a `project` property. Rename to `project_id` for consistency and add `component`:

```
ProjectConfig { project_id: "quantumbitcz/wellplanned-be", component: "api", language: "kotlin" }
ProjectConfig { project_id: "quantumbitcz/wellplanned-be", component: "web", language: "typescript" }
```

### 3.3 New Composite Indexes

```cypher
CREATE INDEX project_file_idx FOR (n:ProjectFile) ON (n.project_id, n.component, n.path);
CREATE INDEX project_class_idx FOR (n:ProjectClass) ON (n.project_id, n.component, n.name);
CREATE INDEX doc_file_idx FOR (n:DocFile) ON (n.project_id, n.path);
```

## 4. Script Changes

### 4.1 `build-project-graph.sh`

Currently deletes ALL `Project*` nodes, then rebuilds. Changes:

**Scoped deletion:**
```cypher
-- Before (destructive across projects):
MATCH (n) WHERE n:ProjectFile OR n:ProjectClass OR ... DETACH DELETE n

-- After (scoped to current project):
MATCH (n) WHERE (n:ProjectFile OR n:ProjectClass OR ...) AND n.project_id = $project_id DETACH DELETE n
```

**New behavior:**
1. Derive `project_id` at script start from git remote origin with absolute path fallback
2. Accept optional `--component <name>` flag for monorepo per-component rebuilds
3. Pass `project_id` and `component` as Cypher parameters to every `CREATE` statement
4. For monorepo multi-component: iterate `components:` from `forge.local.md`, run build per component scoped to its `path:`

### 4.2 `enrich-symbols.sh`

Same pattern — all `MERGE`/`CREATE` statements gain `project_id` and `component` parameters. Symbol resolution (class references, imports) searches within same `project_id` first, then across related projects if configured.

### 4.3 `generate-seed.sh`

**No changes.** Plugin seed nodes are global — they don't belong to any project.

### 4.4 New Script: `update-project-graph.sh`

Incremental graph update for changed files. Used by the orchestrator at stage boundaries.

Input: `--project-id <id> --component <name> --files <file1,file2,...>`

Behavior:
1. For each changed file: `MERGE` the `ProjectFile` node (upsert), update `last_modified`, `size`
2. Re-run `enrich-symbols.sh` scoped to changed files only — update `ProjectClass`, `ProjectFunction`, `IMPORTS` edges
3. For deleted files: `DETACH DELETE` the node and all outgoing relationships
4. For new doc files: create `DocFile` + `DocSection` nodes

File list comes from `state.json.files_changed` — no filesystem scanning needed.

### 4.5 Skill Command Changes

| Skill | Change |
|-------|--------|
| `/graph-init` | Passes `project_id` to `build-project-graph.sh`. For monorepo, iterates components. |
| `/graph-rebuild` | Accepts optional `--component <name>`. Without it, rebuilds all components for current project. Never touches other projects' nodes. |
| `/graph-query` | Injects `project_id` as default Cypher parameter. User can override or omit for cross-project queries. |
| `/graph-status` | Shows node counts per `project_id` (and per component if applicable). |

## 5. Query Pattern Updates

### 5.1 Existing Patterns (1-15)

All 15 existing query patterns in `query-patterns.md` gain a `project_id` filter on the entry node match.

**Example — Pattern 1 (Convention Stack Resolution):**
```cypher
-- Before:
MATCH (pc:ProjectConfig)-[:USES_CONVENTION]->(conv)
RETURN conv.name, labels(conv)

-- After:
MATCH (pc:ProjectConfig {project_id: $project_id})-[:USES_CONVENTION]->(conv)
RETURN conv.name, labels(conv)
```

**Example — Pattern 14 (Bug Hotspots):**
```cypher
-- Before:
MATCH (f:ProjectFile) WHERE f.bug_fix_count > 0
RETURN f.path, f.bug_fix_count ORDER BY f.bug_fix_count DESC LIMIT 10

-- After:
MATCH (f:ProjectFile {project_id: $project_id}) WHERE f.bug_fix_count > 0
RETURN f.path, f.bug_fix_count ORDER BY f.bug_fix_count DESC LIMIT 10
```

### 5.2 New Cross-Project Patterns

**Pattern 16 — Cross-Project Impact Analysis:**
```cypher
MATCH (f:ProjectFile {project_id: $project_id})-[:IMPORTS]->(dep:ProjectFile)
WHERE dep.project_id <> $project_id
RETURN f.path, dep.project_id, dep.path
```

**Pattern 17 — Cross-Project Dependency Map:**
```cypher
MATCH (d:ProjectDependency {project_id: $project_id})-[:MAPS_TO]->(m)
WITH m
MATCH (d2:ProjectDependency)-[:MAPS_TO]->(m)
WHERE d2.project_id <> $project_id
RETURN d2.project_id, m.name, collect(d2.name) AS shared_deps
```

### 5.3 Component-Scoped Queries

For monorepo per-component analysis, queries accept an optional `$component` parameter:

```cypher
MATCH (f:ProjectFile {project_id: $project_id, component: $component})
```

When `$component` is null, the `component` filter clause is omitted from the query entirely (matches all components in the project). This is a query-generation concern — scripts and skills conditionally include the `AND n.component = $component` clause only when `$component` is non-null. Single-component projects store `component: null` on their nodes, which naturally matches the unfiltered query.

## 6. Auto-Update Strategy

### 6.1 Stage-Boundary Triggers

The orchestrator triggers incremental graph updates at three points:

| Trigger | When | Scope |
|---------|------|-------|
| Post-IMPLEMENT | After Stage 4 completes | All files in `state.json.files_changed` |
| Post-VERIFY | After Stage 5 if fix iterations changed additional files | Delta from last update |
| Pre-REVIEW | Before Stage 6 dispatch | Final consistency check — no-op if nothing changed since last update |

### 6.2 Orchestrator Integration

In `fg-100-orchestrator.md`, after each trigger point:

```
If graph.enabled AND files_changed is non-empty:
  Run update-project-graph.sh --project-id $project_id --component $component --files $changed_files
  Log: "Graph updated: {N} files re-indexed"
```

If the update fails (Neo4j down, timeout): log WARNING, continue pipeline. Graph staleness is non-blocking — same graceful degradation pattern as existing Neo4j failures.

### 6.3 State Tracking

New `graph` section in `state.json`:

```json
"graph": {
  "last_update_stage": 4,
  "last_update_files": ["src/Main.kt", "src/Service.kt"],
  "stale": false
}
```

- `stale` set to `true` when files change after last graph update
- Reset to `false` after each successful update
- Reviewers that query the graph check this flag — if `stale: true`, log INFO note but proceed (not blocking)

## 7. Impact Analysis

### 7.1 Files Created

| File | Purpose |
|------|---------|
| `shared/graph/update-project-graph.sh` | Incremental graph update for changed files |

### 7.2 Files Modified

| File | Change |
|------|--------|
| `shared/graph/schema.md` | Add `project_id`/`component` to all `Project*`/`Doc*` nodes, new indexes, auto-update docs |
| `shared/graph/query-patterns.md` | Add `project_id` filter to patterns 1-15, add patterns 16-17, add component-scoped variants |
| `shared/graph/build-project-graph.sh` | Scope `DELETE`+`CREATE` to `project_id`/`component`, derive `project_id` from git remote |
| `shared/graph/enrich-symbols.sh` | Add `project_id`/`component` to all `MERGE`/`CREATE` |
| `shared/state-schema.md` | Add `graph` section (`last_update_stage`, `last_update_files`, `stale`), bump version to 1.2.0 |
| `agents/fg-100-orchestrator.md` | Add graph update triggers at post-IMPLEMENT, post-VERIFY, pre-REVIEW |
| `skills/graph-init/SKILL.md` | Pass `project_id`, iterate components for monorepo |
| `skills/graph-rebuild/SKILL.md` | Accept `--component` flag, scope deletion to current project |
| `skills/graph-query/SKILL.md` | Inject `project_id` as default parameter |
| `skills/graph-status/SKILL.md` | Show per-project/per-component node counts |
| `CLAUDE.md` | Update graph section with namespacing, auto-update, new state fields, state schema version |

### 7.3 Files NOT Modified

- Agent files (except orchestrator) — they query via Cypher, `project_id` is injected by the skill/script layer
- `shared/graph/generate-seed.sh` — seed nodes are global
- `shared/graph/docker-compose.neo4j.yml` — shared container unchanged
- `shared/scoring.md` — no impact
- Module files — no impact
- Check engine / hooks — no impact

### 7.4 State Schema Version

Bump `state.json.version` from `1.1.0` to `1.2.0` (new `graph` section).

### 7.5 Migration

No backwards compatibility needed. On first `/graph-init` after upgrade:
1. Existing `Project*` nodes lack `project_id` — `/graph-rebuild` deletes and recreates them with the new property
2. No data loss — project graph is always rebuildable from the codebase
3. Old `ProjectConfig.project` property renamed to `project_id` during rebuild
