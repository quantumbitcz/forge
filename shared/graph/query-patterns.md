# Cypher Query Patterns Reference

This document defines pre-built Cypher query templates used by the orchestrator for `graph_context` pre-queries. Each pattern is designed for a specific pipeline stage or plugin development workflow. The orchestrator selects and executes the relevant query before dispatching an agent, injecting the results as context into the agent's input.

---

### 1. Stack Resolution

**Used during:** PREFLIGHT

Resolves all convention bindings available for a given framework and language combination. The orchestrator runs this at the start of PREFLIGHT to determine which module files to load and in what precedence order.

```cypher
// Given a framework and language, find all available convention bindings
MATCH (f:Framework {name: $framework})-[:HAS_BINDING]->(b:FrameworkBinding)
OPTIONAL MATCH (b)-[:EXTENDS]->(m:LayerModule)
OPTIONAL MATCH (f)-[:HAS_VARIANT]->(l:Language {name: $language})
RETURN f, b, m, l ORDER BY b.layer
```

**Parameters:**
- `$framework` — Framework name as declared in `components.framework` of `forge.local.md` (e.g., `"spring"`, `"nextjs"`, `"fastapi"`).
- `$language` — Language name as declared in `components.language` (e.g., `"kotlin"`, `"typescript"`, `"python"`).

---

### 2. Direct Impact Analysis

**Used during:** PLAN

Determines which project files are directly or transitively affected when a given file is changed. The orchestrator uses this before dispatching `fg-200-planner` to scope the plan and surface hidden blast radius.

```cypher
// What project files are affected if I change a specific file?
MATCH (changed:ProjectFile {path: $filePath, project_id: $project_id})
MATCH (dependent:ProjectFile {project_id: $project_id})-[:IMPORTS]->(changed)
OPTIONAL MATCH (dependent)-[:IMPORTS*2..3]->(transitive:ProjectFile {project_id: $project_id})
RETURN changed, collect(DISTINCT dependent.path) AS direct_dependents,
       collect(DISTINCT transitive.path) AS transitive_dependents
```

**Parameters:**
- `$filePath` — Repo-relative path of the file being changed (e.g., `"src/domain/User.kt"`).
- `$project_id` — Project identifier (git remote origin or absolute path).

---

### 3. Entity Impact Analysis

**Used during:** PLAN

Identifies which files consume a specific class or entity, and which conventions those consumer files rely on. Used when a domain entity or interface is being refactored to flag potential convention violations in downstream consumers.

```cypher
// What breaks if I change a specific class/entity?
// Note: project_conventions is project-wide (USES_CONVENTION lives on ProjectConfig, not per-file)
MATCH (entity:ProjectClass {name: $className, project_id: $project_id})-[:CLASS_IN_FILE]->(f:ProjectFile {project_id: $project_id})
MATCH (consumer:ProjectFile {project_id: $project_id})-[:IMPORTS]->(f)
OPTIONAL MATCH (pc:ProjectConfig {project_id: $project_id})-[:USES_CONVENTION]->(conv)
RETURN consumer.path, collect(DISTINCT conv.name) AS project_conventions
```

**Parameters:**
- `$className` — Simple (unqualified) class name (e.g., `"UserEntity"`, `"PaymentService"`).
- `$project_id` — Project identifier (git remote origin or absolute path).

---

### 4. Gap Detection — Missing Bindings

**Used during:** Plugin development

Finds frameworks that lack a binding for a specific crosscutting layer. Used when adding a new layer module to identify which frameworks still need a binding file created.

```cypher
// Which frameworks are missing search bindings?
MATCH (f:Framework)
WHERE NOT (f)-[:HAS_BINDING]->(:FrameworkBinding {layer: 'search'})
RETURN f.name AS framework_missing_search
```

**Parameters:**
- None. The `layer` value (`'search'` in the example) is substituted inline when this pattern is used for a specific layer (e.g., `'caching'`, `'messaging'`, `'auth'`).

---

### 5. Gap Detection — Missing Canonical Pairings

**Used during:** Plugin development

Finds languages that have no canonical testing framework defined. Used during module completeness audits to identify incomplete language definitions.

```cypher
// Which languages don't have a canonical testing framework?
MATCH (l:Language)
WHERE NOT (l)-[:CANONICAL_TESTING]->(:TestingFramework)
RETURN l.name
```

**Parameters:**
- None. This query is run as-is during plugin development audits.

---

### 6. Recommendation

**Used during:** forge-init

Suggests layer modules that are commonly paired with a given framework for a specific layer. The orchestrator uses this during `/forge` to pre-populate `forge.local.md` with sensible defaults.

```cypher
// What modules are commonly paired with a framework for a given layer?
MATCH (f:Framework {name: $framework})-[:HAS_BINDING]->(b:FrameworkBinding {layer: $layer})
MATCH (b)-[:EXTENDS]->(m:LayerModule)
RETURN m.name, count(*) AS binding_count ORDER BY binding_count DESC
```

**Parameters:**
- `$framework` — Framework name (e.g., `"spring"`, `"express"`).
- `$layer` — Crosscutting layer name (e.g., `"persistence"`, `"auth"`, `"observability"`).

---

### 7. Scope Analysis / Blast Radius

**Used during:** EXPLORE

Traces the full dependency chain from a given file up to 4 hops deep. The orchestrator runs this during the EXPLORE stage to give `fg-100-orchestrator` a prioritized list of files that may need to change, ordered by proximity to the root.

```cypher
// Given a file, what's the full dependency chain?
MATCH (root:ProjectFile {path: $filePath, project_id: $project_id})
MATCH path = (root)<-[:IMPORTS*1..4]-(dependent:ProjectFile {project_id: $project_id})
RETURN nodes(path) AS impact_chain, length(path) AS depth
ORDER BY depth
```

**Parameters:**
- `$filePath` — Repo-relative path of the entry-point file being analyzed (e.g., `"src/api/UserController.kt"`).
- `$project_id` — Project identifier (git remote origin or absolute path).

---

### 8. Plugin Contract Impact

**Used during:** Plugin development

Identifies all agents that read a specific shared contract file. Used before modifying files in `shared/` (e.g., `scoring.md`, `stage-contract.md`, `state-schema.md`) to enumerate which agents will be affected and must be reviewed for downstream impact.

```cypher
// If I change a shared contract, which agents are affected?
MATCH (c:SharedContract {name: $contractName})
MATCH (a:Agent)-[:READS]->(c)
RETURN a.name, a.role
```

**Parameters:**
- `$contractName` — Name of the shared contract without path prefix or `.md` extension (e.g., `"scoring"`, `"stage-contract"`, `"state-schema"`, `"frontend-design-theory"`).

---

### 9. Documentation Impact

**Used during:** PLAN

Identifies all documentation sections, decisions, and constraints that reference a changed file. The orchestrator runs this before dispatching `fg-200-planner` so the plan includes documentation update tasks alongside code changes.

```cypher
MATCH (changed:ProjectFile {path: $filePath, project_id: $project_id})
OPTIONAL MATCH (ds:DocSection {project_id: $project_id})-[:DESCRIBES]->(changed)
OPTIONAL MATCH (ds)-[:SECTION_OF]->(df:DocFile {project_id: $project_id})
OPTIONAL MATCH (dd:DocDecision {project_id: $project_id})-[:DECIDES]->(changed)
OPTIONAL MATCH (dc:DocConstraint {project_id: $project_id})-[:CONSTRAINS]->(changed)
RETURN df.path, ds.name, dd.summary, dc.summary
```

**Parameters:**
- `$filePath` — Repo-relative path of the file being changed (e.g., `"src/domain/User.kt"`).
- `$project_id` — Project identifier (git remote origin or absolute path).

---

### 10. Stale Docs Detection

**Used during:** REVIEW

Finds documentation sections whose content hash is older than the last modification time of the code file they describe. Surfaced by the documentation reviewer to flag docs that may no longer match the implementation.

```cypher
MATCH (ds:DocSection {project_id: $project_id})-[:DESCRIBES]->(pf:ProjectFile {project_id: $project_id})
WHERE pf.last_modified > ds.content_hash_updated
RETURN ds.name, ds.file_path, pf.path AS stale_for_file
```

**Parameters:**
- `$project_id` — Project identifier (git remote origin or absolute path).

---

### 11. Decision Traceability

**Used during:** VALIDATE

Retrieves all active (non-superseded) architectural decisions that apply to a given package path or class. The orchestrator runs this before dispatching `fg-210-validator` to surface decisions the implementation must honour.

```cypher
MATCH (dd:DocDecision {project_id: $project_id})-[:DECIDES]->(target)
WHERE target.path STARTS WITH $packagePath OR target.name = $className
OPTIONAL MATCH (dd)<-[:SUPERSEDES]-(newer:DocDecision {project_id: $project_id})
WHERE newer IS NULL
RETURN dd.id, dd.summary, dd.status, dd.confidence, target.path
```

**Parameters:**
- `$packagePath` — Package path prefix to match (e.g., `"src/domain/"`). Pass an empty string to skip package matching.
- `$className` — Simple class name to match (e.g., `"PaymentService"`). Pass an empty string to skip class matching.
- `$project_id` — Project identifier (git remote origin or absolute path).

---

### 12. Contradiction Report

**Used during:** REVIEW

Returns all `CONTRADICTS` edges in the graph, showing which documentation source conflicts with which code entity. Created by the consistency reviewer during the REVIEW stage.

```cypher
MATCH (source)-[:CONTRADICTS]->(target)
WHERE source.project_id = $project_id OR source.project_id IS NULL
RETURN head(labels(source)) AS source_type, COALESCE(source.summary, source.name) AS source_desc,
       target.path AS code_target, source.file_path AS doc_source
```

**Parameters:**
- `$project_id` — Project identifier (git remote origin or absolute path).

---

### 13. Documentation Coverage Gap

**Used during:** DOCUMENTING

Finds project packages that have no documentation section describing them. The orchestrator uses this at the start of the DOCUMENTING stage to give `fg-710-post-run` a prioritized list of under-documented areas.

```cypher
MATCH (pp:ProjectPackage {project_id: $project_id})
WHERE NOT (pp)<-[:DESCRIBES]-(:DocSection {project_id: $project_id})
RETURN pp.name, pp.path ORDER BY pp.path
```

**Parameters:**
- `$project_id` — Project identifier (git remote origin or absolute path).

---

## Pattern 14 — Bug Hotspot Analysis

**Used during:** PREFLIGHT (PREEMPT), EXPLORE (bugfix mode), REVIEW (risk flagging)

**Purpose:** Identify files with recurring bug fixes to flag as hotspots for extra attention.

**Prerequisites:** `ProjectFile` nodes with `bug_fix_count` and `last_bug_fix_date` properties, populated by `fg-700-retrospective` after each bugfix run.

```cypher
MATCH (f:ProjectFile {project_id: $project_id})
WHERE f.bug_fix_count > 0
RETURN f.path, f.bug_fix_count, f.last_bug_fix_date
ORDER BY f.bug_fix_count DESC
LIMIT 20
```

**Parameters:**
- `$project_id` — Project identifier (git remote origin or absolute path).

**Consumers:** `fg-010-shaper` (risk flagging in spec), `fg-020-bug-investigator` (prioritize investigation), `fg-400-quality-gate` (stricter review for hotspots)

**Graceful degradation:** If no `bug_fix_count` properties exist yet (first run), returns empty result. Consumers treat empty as "no hotspot data available."

---

## Pattern 15 — Test Coverage by Entity

**Used during:** EXPLORE (bugfix mode), PLAN (test gap analysis), REVIEW (coverage flagging)

**Purpose:** Identify classes/entities that lack direct test coverage.

**Prerequisites:** `ProjectClass` nodes with `CLASS_IN_FILE` edges and `TESTS` edges between test files and source files, populated by `build-project-graph.sh`.

```cypher
MATCH (c:ProjectClass {project_id: $project_id})-[:CLASS_IN_FILE]->(f:ProjectFile {project_id: $project_id})
OPTIONAL MATCH (t:ProjectFile {project_id: $project_id})-[:TESTS]->(f)
WHERE t IS NULL
RETURN c.name, f.path AS source_file
```

**Parameters:**
- `$project_id` — Project identifier (git remote origin or absolute path).

**Consumers:** `fg-020-bug-investigator` (identify untested code near bug), `fg-500-test-gate` (coverage gap warnings), `fg-010-shaper` (note in spec Technical Notes)

**Graceful degradation:** If no `TESTS` edges exist, returns all classes. Consumers should limit to the affected area.

---

### 16. Cross-Project Impact Analysis

**Used during:** PLAN (cross-repo features)

Identifies files in the current project that import files from other projects.

```cypher
MATCH (f:ProjectFile {project_id: $project_id})-[:IMPORTS]->(dep:ProjectFile)
WHERE dep.project_id <> $project_id
RETURN f.path, dep.project_id, dep.path
```

**Parameters:**
- `$project_id` — Current project identifier.

---

### 17. Cross-Project Dependency Map

**Used during:** PLAN (cross-repo features)

Finds shared module dependencies across related projects.

```cypher
MATCH (d:ProjectDependency {project_id: $project_id})-[:MAPS_TO]->(m)
WITH m
MATCH (d2:ProjectDependency)-[:MAPS_TO]->(m) // cross-project: d2.project_id <> $project_id
WHERE d2.project_id <> $project_id
RETURN d2.project_id, m.name, collect(d2.name) AS shared_deps
```

**Parameters:**
- `$project_id` — Current project identifier.

---

### 18. Cross-Repo Service Discovery

**Used during:** VERIFY (Tier 5 image resolution)

Discovers related project services and their deployment configuration for full stack testing.

```cypher
MATCH (pc:ProjectConfig {project_id: $project_id})
OPTIONAL MATCH (dep:ProjectDependency {project_id: pc.project_id})-[:MAPS_TO]->(fw:Framework)
RETURN pc.project_id, pc.language, pc.component, collect(DISTINCT fw.name) AS frameworks
```

**Parameters:**
- `$project_id` — Project identifier. Pass each related project's ID to discover their stack.

---

### 19. Cross-Feature File Overlap Detection

**Used during:** ANALYZE (sprint orchestrator independence analysis)

Detects files that would be affected by multiple features in a sprint, enabling conflict detection before parallel dispatch.

```cypher
// For each feature's seed files, find all transitively affected files
MATCH (seed:ProjectFile {project_id: $project_id})
WHERE seed.path IN $feature_seed_files
MATCH (seed)<-[:IMPORTS*0..3]-(affected:ProjectFile {project_id: $project_id})
RETURN DISTINCT affected.path AS file_path, affected.component AS component
```

**Parameters:**
- `$project_id` — Current project identifier.
- `$feature_seed_files` — List of seed file paths for one feature (from requirement parsing).

**Usage:** Run once per feature, then compute set intersections between results to identify conflicts.

---

### 20. Cross-Repo Dependency Graph Traversal

**Used during:** ANALYZE (sprint orchestrator cross-repo feature planning)

Maps API contract dependencies between related projects to determine execution ordering (producers before consumers).

```cypher
// Find which project configs have dependencies that map to frameworks in other projects
MATCH (pc:ProjectConfig {project_id: $project_id})
MATCH (dep:ProjectDependency {project_id: $project_id})-[:MAPS_TO]->(target)
WHERE target:Framework OR target:LayerModule
WITH target, pc
MATCH (other_pc:ProjectConfig)-[:USES_CONVENTION]->(target)
WHERE other_pc.project_id <> $project_id
RETURN $project_id AS consumer, other_pc.project_id AS producer,
       collect(DISTINCT target.name) AS shared_conventions
```

**Parameters:**
- `$project_id` — Current project identifier.

**Usage:** If project A consumes conventions that project B produces, A depends on B. Execute B through VERIFY before starting A's IMPLEMENT.
