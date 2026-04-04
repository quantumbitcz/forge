# Neo4j Multi-Project Namespacing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `project_id` and `component` properties to all `Project*`/`Doc*` graph nodes so multiple projects can coexist in a single Neo4j instance without overwriting each other. Add incremental auto-update at pipeline stage boundaries.

**Architecture:** Every project-scoped node gets a `project_id` (git remote origin) and optional `component` (from `forge.local.md`). All queries scope by `project_id`. `/graph-rebuild` only deletes the current project's nodes. New `update-project-graph.sh` handles incremental updates.

**Tech Stack:** Bash (graph scripts), Cypher (Neo4j queries), Markdown (contracts), Bats (tests)

**Spec:** `docs/superpowers/specs/2026-04-04-neo4j-multi-project-design.md`

---

### Task 1: Update graph schema documentation

**Files:**
- Modify: `shared/graph/schema.md`

- [ ] **Step 1: Add `project_id` and `component` to all Project* node types**

In the "Project Codebase Nodes" table, add `project_id` and `component` to every row's Properties column:

For `ProjectFile`: `path, language, size, last_modified, bug_fix_count, last_bug_fix_date, project_id, component`
For `ProjectPackage`: `name, path, project_id, component`
For `ProjectDependency`: `name, version, scope, manager, project_id, component`
For `ProjectClass`: `name, file_path, kind, project_id, component`
For `ProjectFunction`: `name, file_path, project_id, component`
For `ProjectConfig`: `project_id, component, language` (rename `project` → `project_id`)
For `ProjectLanguage`: `name, project_id`
For `DocFile`: `path, format, doc_type, last_modified, title, cross_repo, project_id, component`
For `DocSection`: `name, file_path, heading_level, start_line, end_line, content_hash, content_hash_updated, project_id`
For `DocDecision`: `id, file_path, summary, status, confidence, extracted_at, project_id`
For `DocConstraint`: `id, file_path, summary, scope, confidence, project_id`
For `DocDiagram`: `path, format, diagram_type, source_file, project_id`

- [ ] **Step 2: Add composite indexes section**

Add after the existing indexes:

```markdown
### Project-Scoped Indexes

```cypher
CREATE INDEX project_file_idx FOR (n:ProjectFile) ON (n.project_id, n.component, n.path);
CREATE INDEX project_class_idx FOR (n:ProjectClass) ON (n.project_id, n.component, n.name);
CREATE INDEX doc_file_idx FOR (n:DocFile) ON (n.project_id, n.path);
```
```

- [ ] **Step 3: Update Graph Lifecycle table**

Change the `/graph-rebuild` description from "Deletes `Project*` nodes, rebuilds from codebase" to "Deletes `Project*` nodes for the current project (scoped by `project_id`), rebuilds from codebase".

Add new row for `/graph-update`: "Incremental update for changed files (scoped by `project_id`/`component`)"

- [ ] **Step 4: Add `project_id` derivation docs**

Add a new section:

```markdown
## Project Identity

`project_id` is derived automatically:
1. **Primary:** Git remote origin — `git remote get-url origin | sed 's|.*github.com[:/]||; s|\.git$||'` → e.g., `quantumbitcz/wellplanned-be`
2. **Fallback:** Absolute path of project root (for non-git projects)

`component` comes from the `components:` key in `forge.local.md`. Single-component projects store `component: null`. Queries conditionally include the `component` filter only when non-null.
```

- [ ] **Step 5: Commit**

```bash
git add shared/graph/schema.md
git commit -m "docs: add project_id and component to graph schema"
```

---

### Task 2: Write contract test for project_id in graph scripts

**Files:**
- Create: `tests/contract/graph-project-scoping.bats`

- [ ] **Step 1: Write the test file**

```bash
#!/usr/bin/env bats
# Contract tests: graph scripts scope operations by project_id.

load '../helpers/test-helpers'

GRAPH_DIR="$PLUGIN_ROOT/shared/graph"

# ---------------------------------------------------------------------------
# 1. build-project-graph.sh accepts --project-id parameter
# ---------------------------------------------------------------------------
@test "graph-project-scoping: build-project-graph.sh accepts --project-id" {
  grep -q '\-\-project-id' "$GRAPH_DIR/build-project-graph.sh"
}

# ---------------------------------------------------------------------------
# 2. build-project-graph.sh scoped DELETE uses project_id
# ---------------------------------------------------------------------------
@test "graph-project-scoping: build-project-graph.sh DELETE scoped by project_id" {
  # Must not have unscoped DELETE of all Project* nodes
  if grep -q 'DETACH DELETE' "$GRAPH_DIR/build-project-graph.sh"; then
    # Every DETACH DELETE must reference project_id
    local unscoped
    unscoped=$(grep 'DETACH DELETE' "$GRAPH_DIR/build-project-graph.sh" | grep -v 'project_id' || true)
    if [[ -n "$unscoped" ]]; then
      fail "build-project-graph.sh has unscoped DETACH DELETE: $unscoped"
    fi
  fi
}

# ---------------------------------------------------------------------------
# 3. build-project-graph.sh CREATE statements include project_id
# ---------------------------------------------------------------------------
@test "graph-project-scoping: build-project-graph.sh CREATE includes project_id" {
  # All CREATE for Project* nodes must include project_id
  local creates
  creates=$(grep -c 'CREATE.*Project.*project_id' "$GRAPH_DIR/build-project-graph.sh" || true)
  [[ "$creates" -gt 0 ]]
}

# ---------------------------------------------------------------------------
# 4. build-project-graph.sh accepts --component parameter
# ---------------------------------------------------------------------------
@test "graph-project-scoping: build-project-graph.sh accepts --component" {
  grep -q '\-\-component' "$GRAPH_DIR/build-project-graph.sh"
}

# ---------------------------------------------------------------------------
# 5. enrich-symbols.sh includes project_id in MERGE statements
# ---------------------------------------------------------------------------
@test "graph-project-scoping: enrich-symbols.sh MERGE includes project_id" {
  local merges
  merges=$(grep -c 'MERGE.*project_id' "$GRAPH_DIR/enrich-symbols.sh" || true)
  [[ "$merges" -gt 0 ]]
}

# ---------------------------------------------------------------------------
# 6. query-patterns.md: all Project* queries include project_id filter
# ---------------------------------------------------------------------------
@test "graph-project-scoping: all project queries in query-patterns.md use project_id" {
  # Find all MATCH clauses with Project* or Doc* nodes
  local matches
  matches=$(grep -E 'MATCH.*\(.*:(Project|Doc)\w+' "$GRAPH_DIR/query-patterns.md" || true)
  if [[ -z "$matches" ]]; then
    skip "No project node matches found"
  fi
  # Each should contain project_id (either as property or WHERE clause)
  local unscoped
  unscoped=$(echo "$matches" | grep -v 'project_id' | grep -v 'seed' || true)
  if [[ -n "$unscoped" ]]; then
    fail "Unscoped project queries in query-patterns.md: $unscoped"
  fi
}

# ---------------------------------------------------------------------------
# 7. update-project-graph.sh exists and accepts --project-id
# ---------------------------------------------------------------------------
@test "graph-project-scoping: update-project-graph.sh exists" {
  [[ -f "$GRAPH_DIR/update-project-graph.sh" ]]
}

@test "graph-project-scoping: update-project-graph.sh accepts --project-id" {
  grep -q '\-\-project-id' "$GRAPH_DIR/update-project-graph.sh"
}

# ---------------------------------------------------------------------------
# 8. generate-seed.sh does NOT use project_id (seed is global)
# ---------------------------------------------------------------------------
@test "graph-project-scoping: generate-seed.sh does not use project_id" {
  ! grep -q 'project_id' "$GRAPH_DIR/generate-seed.sh"
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
./tests/lib/bats-core/bin/bats tests/contract/graph-project-scoping.bats
```

Expected: FAIL — scripts don't have `--project-id` yet

- [ ] **Step 3: Commit**

```bash
git add tests/contract/graph-project-scoping.bats
git commit -m "test: add graph project scoping contract tests (RED)"
```

---

### Task 3: Add project_id derivation helper

**Files:**
- Modify: `shared/platform.sh` (or appropriate shared script)

- [ ] **Step 1: Check where shared helpers live**

```bash
head -30 shared/platform.sh
```

- [ ] **Step 2: Add project_id derivation function**

Add to `shared/platform.sh`:

```bash
# Derive project_id from git remote origin, fallback to absolute path.
# Usage: project_id=$(derive_project_id "/path/to/project")
derive_project_id() {
  local project_root="${1:-.}"
  local remote_url
  remote_url=$(git -C "$project_root" remote get-url origin 2>/dev/null || true)
  if [[ -n "$remote_url" ]]; then
    # Strip protocol/host prefix and .git suffix
    echo "$remote_url" | sed -E 's|^.*[:/]([^/]+/[^/]+?)(\.git)?$|\1|'
  else
    # Fallback to absolute path
    cd "$project_root" && pwd
  fi
}

# Read component names from forge.local.md
# Usage: components=($(read_components "/path/to/project"))
read_components() {
  local project_root="${1:-.}"
  local config_file="${project_root}/.claude/forge.local.md"
  if [[ ! -f "$config_file" ]]; then
    echo ""
    return
  fi
  # Extract component names from YAML (2-space indented under components:)
  awk '/^components:/{found=1; next} found && /^  [a-zA-Z]/{print $1; gsub(/:$/,""); next} found && /^[^ ]/{exit}' "$config_file" | sed 's/:$//'
}
```

- [ ] **Step 3: Commit**

```bash
git add shared/platform.sh
git commit -m "feat: add derive_project_id and read_components helpers"
```

---

### Task 4: Update build-project-graph.sh with project_id scoping

**Files:**
- Modify: `shared/graph/build-project-graph.sh`

- [ ] **Step 1: Add --project-id and --component argument parsing**

In the argument parsing block, add:

```bash
    --project-id)
      PROJECT_ID="$2"
      shift 2
      ;;
    --component)
      COMPONENT="$2"
      shift 2
      ;;
```

After argument parsing, add auto-derivation:

```bash
# Auto-derive project_id if not provided
if [[ -z "${PROJECT_ID:-}" ]]; then
  PROJECT_ID=$(derive_project_id "$PROJECT_ROOT")
fi
COMPONENT="${COMPONENT:-}"
```

- [ ] **Step 2: Scope DELETE to project_id**

Find the existing deletion Cypher (which deletes ALL Project* nodes) and replace with:

```bash
# Delete only nodes belonging to this project (and component if specified)
local component_filter=""
if [[ -n "$COMPONENT" ]]; then
  component_filter=" AND n.component = '${COMPONENT}'"
fi
cat <<CYPHER
MATCH (n) WHERE (n:ProjectFile OR n:ProjectClass OR n:ProjectFunction OR n:ProjectPackage OR n:ProjectDependency OR n:ProjectConfig OR n:ProjectLanguage OR n:DocFile OR n:DocSection OR n:DocDecision OR n:DocConstraint OR n:DocDiagram) AND n.project_id = '${PROJECT_ID}'${component_filter} DETACH DELETE n;
CYPHER
```

- [ ] **Step 3: Add project_id and component to all CREATE statements**

For every Cypher `CREATE` or `MERGE` that creates a `Project*` or `Doc*` node, add `project_id` and `component` properties. Example:

Before:
```cypher
CREATE (f:ProjectFile {path: '${rel_path}', language: '${lang}', size: ${size}, last_modified: '${mod_date}'})
```

After:
```cypher
CREATE (f:ProjectFile {path: '${rel_path}', language: '${lang}', size: ${size}, last_modified: '${mod_date}', project_id: '${PROJECT_ID}', component: ${component_cypher}})
```

Where `component_cypher` is `'${COMPONENT}'` if set, or `null` if empty.

Add a helper near the top of the script:

```bash
# Cypher-safe component value: quoted string or null
if [[ -n "$COMPONENT" ]]; then
  COMPONENT_CYPHER="'${COMPONENT}'"
else
  COMPONENT_CYPHER="null"
fi
```

Apply this pattern to every `CREATE`/`MERGE` for project-scoped nodes throughout the script.

- [ ] **Step 4: Add composite index creation**

Add to the index creation section:

```cypher
CREATE INDEX project_file_idx IF NOT EXISTS FOR (n:ProjectFile) ON (n.project_id, n.component, n.path);
CREATE INDEX project_class_idx IF NOT EXISTS FOR (n:ProjectClass) ON (n.project_id, n.component, n.name);
CREATE INDEX doc_file_idx IF NOT EXISTS FOR (n:DocFile) ON (n.project_id, n.path);
```

- [ ] **Step 5: Run contract tests**

```bash
./tests/lib/bats-core/bin/bats tests/contract/graph-project-scoping.bats
```

Expected: Tests 1-4 should now PASS

- [ ] **Step 6: Commit**

```bash
git add shared/graph/build-project-graph.sh
git commit -m "feat: scope build-project-graph.sh by project_id and component"
```

---

### Task 5: Update enrich-symbols.sh with project_id scoping

**Files:**
- Modify: `shared/graph/enrich-symbols.sh`

- [ ] **Step 1: Add --project-id and --component argument parsing**

Same pattern as build-project-graph.sh:

```bash
    --project-id)
      PROJECT_ID="$2"
      shift 2
      ;;
    --component)
      COMPONENT="$2"
      shift 2
      ;;
```

Auto-derive if not provided.

- [ ] **Step 2: Add project_id to all MERGE/CREATE statements**

Every `MERGE` or `CREATE` for `ProjectClass`, `ProjectFunction`, and relationship creation must include `project_id` and `component` in the match/create properties.

Before:
```cypher
MERGE (c:ProjectClass {name: '${class_name}', file_path: '${file_path}'})
```

After:
```cypher
MERGE (c:ProjectClass {name: '${class_name}', file_path: '${file_path}', project_id: '${PROJECT_ID}', component: ${COMPONENT_CYPHER}})
```

- [ ] **Step 3: Scope IMPORTS resolution to same project first**

In the import resolution section, add project_id scope:

```cypher
MATCH (src:ProjectFile {path: '${source_path}', project_id: '${PROJECT_ID}'})
MATCH (tgt:ProjectFile {path: '${target_path}', project_id: '${PROJECT_ID}'})
MERGE (src)-[:IMPORTS]->(tgt)
```

- [ ] **Step 4: Run contract tests**

```bash
./tests/lib/bats-core/bin/bats tests/contract/graph-project-scoping.bats
```

Expected: Test 5 should now PASS

- [ ] **Step 5: Commit**

```bash
git add shared/graph/enrich-symbols.sh
git commit -m "feat: scope enrich-symbols.sh by project_id and component"
```

---

### Task 6: Create update-project-graph.sh

**Files:**
- Create: `shared/graph/update-project-graph.sh`

- [ ] **Step 1: Write the incremental update script**

```bash
#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# update-project-graph.sh — Incremental Project Graph Update
#
# Updates the graph for specific changed files instead of full rebuild.
# Used by the orchestrator at stage boundaries (post-IMPLEMENT, post-VERIFY,
# pre-REVIEW).
#
# Usage:
#   ./shared/graph/update-project-graph.sh \
#     --project-root /path/to/project \
#     --project-id quantumbitcz/wellplanned-be \
#     --component api \
#     --files "src/Main.kt,src/Service.kt" \
#     --deleted "src/OldFile.kt"
#
# Output: Cypher to stdout
# ============================================================================

PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "${PLUGIN_ROOT}/shared/platform.sh"

PROJECT_ROOT=""
PROJECT_ID=""
COMPONENT=""
CHANGED_FILES=""
DELETED_FILES=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-root) PROJECT_ROOT="$2"; shift 2 ;;
    --project-id)   PROJECT_ID="$2"; shift 2 ;;
    --component)    COMPONENT="$2"; shift 2 ;;
    --files)        CHANGED_FILES="$2"; shift 2 ;;
    --deleted)      DELETED_FILES="$2"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$PROJECT_ROOT" ]]; then
  echo "[update-project-graph] --project-root is required" >&2
  exit 1
fi

# Auto-derive project_id if not provided
if [[ -z "$PROJECT_ID" ]]; then
  PROJECT_ID=$(derive_project_id "$PROJECT_ROOT")
fi

if [[ -n "$COMPONENT" ]]; then
  COMPONENT_CYPHER="'${COMPONENT}'"
else
  COMPONENT_CYPHER="null"
fi

# --- Delete removed files ---
if [[ -n "$DELETED_FILES" ]]; then
  IFS=',' read -ra deleted_arr <<< "$DELETED_FILES"
  for file_path in "${deleted_arr[@]}"; do
    file_path=$(echo "$file_path" | xargs)  # trim whitespace
    cat <<CYPHER
MATCH (f:ProjectFile {path: '${file_path}', project_id: '${PROJECT_ID}'}) DETACH DELETE f;
MATCH (c:ProjectClass {file_path: '${file_path}', project_id: '${PROJECT_ID}'}) DETACH DELETE c;
MATCH (fn:ProjectFunction {file_path: '${file_path}', project_id: '${PROJECT_ID}'}) DETACH DELETE fn;
MATCH (ds:DocSection {file_path: '${file_path}', project_id: '${PROJECT_ID}'}) DETACH DELETE ds;
CYPHER
  done
fi

# --- Upsert changed files ---
if [[ -n "$CHANGED_FILES" ]]; then
  IFS=',' read -ra changed_arr <<< "$CHANGED_FILES"
  for file_path in "${changed_arr[@]}"; do
    file_path=$(echo "$file_path" | xargs)
    local_path="${PROJECT_ROOT}/${file_path}"

    if [[ ! -f "$local_path" ]]; then
      continue
    fi

    local size mod_date lang
    size=$(wc -c < "$local_path" | xargs)
    mod_date=$(date -r "$local_path" '+%Y-%m-%dT%H:%M:%S' 2>/dev/null || stat -c '%y' "$local_path" 2>/dev/null | cut -d. -f1)
    lang=$(detect_language "$file_path" 2>/dev/null || echo "unknown")

    cat <<CYPHER
MERGE (f:ProjectFile {path: '${file_path}', project_id: '${PROJECT_ID}'})
SET f.language = '${lang}', f.size = ${size}, f.last_modified = '${mod_date}', f.component = ${COMPONENT_CYPHER};
CYPHER
  done

  # Re-run symbol enrichment for changed files only
  echo "// Symbol enrichment for changed files"
  "${PLUGIN_ROOT}/shared/graph/enrich-symbols.sh" \
    --project-root "$PROJECT_ROOT" \
    --project-id "$PROJECT_ID" \
    --component "${COMPONENT:-}" \
    --files "$CHANGED_FILES" 2>/dev/null || true
fi
```

- [ ] **Step 2: Make executable**

```bash
chmod +x shared/graph/update-project-graph.sh
```

- [ ] **Step 3: Run contract tests**

```bash
./tests/lib/bats-core/bin/bats tests/contract/graph-project-scoping.bats
```

Expected: Tests 7-8 should now PASS

- [ ] **Step 4: Commit**

```bash
git add shared/graph/update-project-graph.sh
git commit -m "feat: add incremental update-project-graph.sh"
```

---

### Task 7: Update query patterns with project_id scoping

**Files:**
- Modify: `shared/graph/query-patterns.md`

- [ ] **Step 1: Add project_id filter to all 15 existing patterns**

For each pattern that queries `Project*` or `Doc*` nodes, add `{project_id: $project_id}` to the entry node match.

Pattern 2 (Direct Impact Analysis) — before:
```cypher
MATCH (changed:ProjectFile {path: $filePath})
```

After:
```cypher
MATCH (changed:ProjectFile {path: $filePath, project_id: $project_id})
```

Apply the same change to patterns 2-15 — every `MATCH` on a `Project*` or `Doc*` node gains `project_id: $project_id`.

Add `$project_id` to the Parameters section of each pattern:
```markdown
- `$project_id` — Project identifier (git remote origin or absolute path).
```

Pattern 1 (Stack Resolution) queries `Framework`/`Language` nodes which are global seed nodes — these do NOT get `project_id`. Only patterns querying `ProjectConfig` in pattern 1's variant need scoping.

- [ ] **Step 2: Add new cross-project patterns**

Add at the end:

```markdown
### 16. Cross-Project Impact Analysis

**Used during:** PLAN (cross-repo features)

Identifies files in the current project that import files from other projects.

\```cypher
MATCH (f:ProjectFile {project_id: $project_id})-[:IMPORTS]->(dep:ProjectFile)
WHERE dep.project_id <> $project_id
RETURN f.path, dep.project_id, dep.path
\```

**Parameters:**
- `$project_id` — Current project identifier.

---

### 17. Cross-Project Dependency Map

**Used during:** PLAN (cross-repo features)

Finds shared module dependencies across related projects.

\```cypher
MATCH (d:ProjectDependency {project_id: $project_id})-[:MAPS_TO]->(m)
WITH m
MATCH (d2:ProjectDependency)-[:MAPS_TO]->(m)
WHERE d2.project_id <> $project_id
RETURN d2.project_id, m.name, collect(d2.name) AS shared_deps
\```

**Parameters:**
- `$project_id` — Current project identifier.
```

- [ ] **Step 3: Run contract tests**

```bash
./tests/lib/bats-core/bin/bats tests/contract/graph-project-scoping.bats
```

Expected: Test 6 should now PASS. All 9 tests PASS.

- [ ] **Step 4: Commit**

```bash
git add shared/graph/query-patterns.md
git commit -m "feat: scope all query patterns by project_id, add cross-project patterns"
```

---

### Task 8: Update state schema with graph section

**Files:**
- Modify: `shared/state-schema.md`

- [ ] **Step 1: Add graph section to state.json schema**

Add after the existing `recovery` section:

```markdown
### graph (object, optional)

Tracks graph update state for incremental updates at stage boundaries.

| Field | Type | Description |
|-------|------|-------------|
| `last_update_stage` | integer | Stage number (0-9) when graph was last updated |
| `last_update_files` | string[] | Files re-indexed in the last update |
| `stale` | boolean | True when files changed since last graph update |

**Lifecycle:**
- Created at PREFLIGHT (Stage 0) when `graph.enabled` is true
- Updated at post-IMPLEMENT, post-VERIFY, pre-REVIEW by the orchestrator
- `stale` set to `true` by orchestrator when `files_changed` grows; reset to `false` after each successful update
- Reviewers querying the graph check `stale` — if `true`, log INFO but proceed
```

- [ ] **Step 2: Bump schema version**

Change `"version": "1.1.0"` to `"version": "1.2.0"` in the schema example.

- [ ] **Step 3: Commit**

```bash
git add shared/state-schema.md
git commit -m "feat: add graph section to state schema, bump to v1.2.0"
```

---

### Task 9: Update orchestrator with graph auto-update triggers

**Files:**
- Modify: `agents/fg-100-orchestrator.md`

- [ ] **Step 1: Add graph update trigger logic**

In the Stage 4 → Stage 5 transition section, add:

```markdown
### Post-IMPLEMENT Graph Update

After Stage 4 (IMPLEMENT) completes:

1. Check `graph.enabled` in `forge.local.md`
2. If enabled AND `state.json.files_changed` is non-empty:
   - Run `update-project-graph.sh --project-root $PROJECT_ROOT --project-id $project_id --component $component --files $changed_files`
   - Update `state.json.graph.last_update_stage = 4`
   - Update `state.json.graph.last_update_files = $changed_files`
   - Update `state.json.graph.stale = false`
   - Log: "Graph updated: {N} files re-indexed"
3. If update fails: log WARNING, set `state.json.graph.stale = true`, continue pipeline
```

- [ ] **Step 2: Add post-VERIFY and pre-REVIEW triggers**

Add identical logic blocks for Stage 5 → Stage 6 transition (post-VERIFY) and before Stage 6 dispatch (pre-REVIEW), with delta calculation:

```markdown
### Post-VERIFY Graph Update

After Stage 5 (VERIFY) completes, if fix iterations changed additional files:

1. Compute delta: `new_files = state.json.files_changed - state.json.graph.last_update_files`
2. If delta is non-empty: run `update-project-graph.sh` with `--files $delta`
3. Update state.json.graph fields

### Pre-REVIEW Graph Update

Before dispatching Stage 6 (REVIEW):

1. If `state.json.graph.stale == true`: run full update with current `files_changed`
2. If `state.json.graph.stale == false`: no-op
```

- [ ] **Step 3: Commit**

```bash
git add agents/fg-100-orchestrator.md
git commit -m "feat: add graph auto-update triggers to orchestrator"
```

---

### Task 10: Update skills and CLAUDE.md

**Files:**
- Modify: `skills/graph-init/SKILL.md`
- Modify: `skills/graph-rebuild/SKILL.md`
- Modify: `skills/graph-query/SKILL.md`
- Modify: `skills/graph-status/SKILL.md`
- Modify: `CLAUDE.md`

- [ ] **Step 1: Update graph-init skill**

Add `project_id` derivation and pass to build script:

```markdown
After container startup, derive project_id:
\```bash
PROJECT_ID=$(derive_project_id "$PROJECT_ROOT")
\```

Pass to build-project-graph.sh:
\```bash
./shared/graph/build-project-graph.sh --project-root "$PROJECT_ROOT" --project-id "$PROJECT_ID"
\```

For monorepo with components, iterate:
\```bash
for component in $(read_components "$PROJECT_ROOT"); do
  component_path=$(get_component_path "$PROJECT_ROOT" "$component")
  ./shared/graph/build-project-graph.sh --project-root "$PROJECT_ROOT" --project-id "$PROJECT_ID" --component "$component"
done
\```
```

- [ ] **Step 2: Update graph-rebuild skill**

Add `--component` flag support:

```markdown
Accept optional `--component <name>` argument.
- Without `--component`: rebuild all components for current project
- With `--component api`: rebuild only the `api` component

Deletion is scoped:
\```bash
# Only delete nodes for this project (never other projects)
./shared/graph/build-project-graph.sh --project-root "$PROJECT_ROOT" --project-id "$PROJECT_ID" --component "${COMPONENT:-}"
\```
```

- [ ] **Step 3: Update graph-query skill**

Add `project_id` as default parameter:

```markdown
Inject `project_id` automatically into all queries:
\```bash
PROJECT_ID=$(derive_project_id "$PROJECT_ROOT")
# Prepend parameter to user's query
echo ":param project_id => '${PROJECT_ID}'"
\```

User can override by specifying their own `:param project_id` or omit for cross-project queries.
```

- [ ] **Step 4: Update graph-status skill**

Add per-project node counts:

```markdown
Show node counts grouped by project_id:
\```cypher
MATCH (n) WHERE exists(n.project_id)
RETURN n.project_id, labels(n)[0] AS label, count(n) AS count
ORDER BY n.project_id, label
\```
```

- [ ] **Step 5: Update CLAUDE.md**

In the Knowledge Graph section, add:

```markdown
All `Project*` and `Doc*` nodes are scoped by `project_id` (git remote origin) and optional `component` (from `forge.local.md`). Multiple projects share one Neo4j instance without data collision. `/graph-rebuild` only deletes nodes for the current project. Graph auto-updates at post-IMPLEMENT, post-VERIFY, and pre-REVIEW via `update-project-graph.sh`. State tracking in `state.json.graph` (`last_update_stage`, `stale`).
```

Update state schema version reference from 1.1.0 to 1.2.0.

- [ ] **Step 6: Commit**

```bash
git add skills/graph-init/SKILL.md skills/graph-rebuild/SKILL.md skills/graph-query/SKILL.md skills/graph-status/SKILL.md CLAUDE.md
git commit -m "feat: update graph skills and CLAUDE.md with project scoping"
```

---

### Task 11: Run full test suite and verify

- [ ] **Step 1: Run graph project scoping tests**

```bash
./tests/lib/bats-core/bin/bats tests/contract/graph-project-scoping.bats
```

Expected: All 9 tests PASS

- [ ] **Step 2: Run full test suite**

```bash
./tests/run-all.sh
```

Expected: All tests PASS

- [ ] **Step 3: Commit any fixes**

```bash
git add -A
git commit -m "fix: resolve test regressions from graph project scoping"
```
