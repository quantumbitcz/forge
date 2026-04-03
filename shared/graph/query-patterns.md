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
MATCH (changed:ProjectFile {path: $filePath})
MATCH (dependent:ProjectFile)-[:IMPORTS]->(changed)
OPTIONAL MATCH (dependent)-[:IMPORTS*2..3]->(transitive:ProjectFile)
RETURN changed, collect(DISTINCT dependent.path) AS direct_dependents,
       collect(DISTINCT transitive.path) AS transitive_dependents
```

**Parameters:**
- `$filePath` — Repo-relative path of the file being changed (e.g., `"src/domain/User.kt"`).

---

### 3. Entity Impact Analysis

**Used during:** PLAN

Identifies which files consume a specific class or entity, and which conventions those consumer files rely on. Used when a domain entity or interface is being refactored to flag potential convention violations in downstream consumers.

```cypher
// What breaks if I change a specific class/entity?
// Note: project_conventions is project-wide (USES_CONVENTION lives on ProjectConfig, not per-file)
MATCH (entity:ProjectClass {name: $className})-[:CLASS_IN_FILE]->(f:ProjectFile)
MATCH (consumer:ProjectFile)-[:IMPORTS]->(f)
OPTIONAL MATCH (pc:ProjectConfig)-[:USES_CONVENTION]->(conv)
RETURN consumer.path, collect(DISTINCT conv.name) AS project_conventions
```

**Parameters:**
- `$className` — Simple (unqualified) class name (e.g., `"UserEntity"`, `"PaymentService"`).

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

Suggests layer modules that are commonly paired with a given framework for a specific layer. The orchestrator uses this during `/forge-init` to pre-populate `forge.local.md` with sensible defaults.

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
MATCH (root:ProjectFile {path: $filePath})
MATCH path = (root)<-[:IMPORTS*1..4]-(dependent:ProjectFile)
RETURN nodes(path) AS impact_chain, length(path) AS depth
ORDER BY depth
```

**Parameters:**
- `$filePath` — Repo-relative path of the entry-point file being analyzed (e.g., `"src/api/UserController.kt"`).

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
MATCH (changed:ProjectFile {path: $filePath})
OPTIONAL MATCH (ds:DocSection)-[:DESCRIBES]->(changed)
OPTIONAL MATCH (ds)-[:SECTION_OF]->(df:DocFile)
OPTIONAL MATCH (dd:DocDecision)-[:DECIDES]->(changed)
OPTIONAL MATCH (dc:DocConstraint)-[:CONSTRAINS]->(changed)
RETURN df.path, ds.name, dd.summary, dc.summary
```

**Parameters:**
- `$filePath` — Repo-relative path of the file being changed (e.g., `"src/domain/User.kt"`).

---

### 10. Stale Docs Detection

**Used during:** REVIEW

Finds documentation sections whose content hash is older than the last modification time of the code file they describe. Surfaced by the documentation reviewer to flag docs that may no longer match the implementation.

```cypher
MATCH (ds:DocSection)-[:DESCRIBES]->(pf:ProjectFile)
WHERE pf.last_modified > ds.content_hash_updated
RETURN ds.name, ds.file_path, pf.path AS stale_for_file
```

**Parameters:**
- None.

---

### 11. Decision Traceability

**Used during:** VALIDATE

Retrieves all active (non-superseded) architectural decisions that apply to a given package path or class. The orchestrator runs this before dispatching `fg-210-validator` to surface decisions the implementation must honour.

```cypher
MATCH (dd:DocDecision)-[:DECIDES]->(target)
WHERE target.path STARTS WITH $packagePath OR target.name = $className
OPTIONAL MATCH (dd)<-[:SUPERSEDES]-(newer:DocDecision)
WHERE newer IS NULL
RETURN dd.id, dd.summary, dd.status, dd.confidence, target.path
```

**Parameters:**
- `$packagePath` — Package path prefix to match (e.g., `"src/domain/"`). Pass an empty string to skip package matching.
- `$className` — Simple class name to match (e.g., `"PaymentService"`). Pass an empty string to skip class matching.

---

### 12. Contradiction Report

**Used during:** REVIEW

Returns all `CONTRADICTS` edges in the graph, showing which documentation source conflicts with which code entity. Created by the consistency reviewer during the REVIEW stage.

```cypher
MATCH (source)-[:CONTRADICTS]->(target)
RETURN head(labels(source)) AS source_type, COALESCE(source.summary, source.name) AS source_desc,
       target.path AS code_target, source.file_path AS doc_source
```

**Parameters:**
- None.

---

### 13. Documentation Coverage Gap

**Used during:** DOCUMENTING

Finds project packages that have no documentation section describing them. The orchestrator uses this at the start of the DOCUMENTING stage to give `fg-720-recap` a prioritized list of under-documented areas.

```cypher
MATCH (pp:ProjectPackage)
WHERE NOT (pp)<-[:DESCRIBES]-(:DocSection)
RETURN pp.name, pp.path ORDER BY pp.path
```

**Parameters:**
- None.
