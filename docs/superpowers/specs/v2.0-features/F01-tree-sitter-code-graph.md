# F01: AST-Based Code Graph with Tree-sitter + SQLite (Zero Docker Dependency)

## Status
DRAFT — 2026-04-13

## Problem Statement

Forge's knowledge graph requires Neo4j + Docker. Developers without Docker (corporate lockdowns, CI runners, lightweight machines, WSL environments) lose the entire graph system — 20+ query patterns, blast radius analysis, bug hotspot tracking, and test coverage mapping all degrade to grep/glob fallbacks. This is a hard binary: Docker present = full graph, Docker absent = no graph.

Research from the Codebase-Memory paper (March 2026) demonstrates that Tree-sitter + SQLite achieves 83% of Neo4j's query quality at 10x fewer tokens with sub-millisecond traversal. Aider's RepoMap uses Tree-sitter to build ranked file maps via PageRank on the call graph. AutoCodeRover provides AST-aware search APIs (`search_class`, `search_method_in_class`, `search_references`) that outperform grep for code navigation. These approaches require zero external dependencies beyond a single binary.

The current Neo4j graph schema (`shared/graph/schema.md`) defines ProjectFile, ProjectClass, ProjectFunction nodes with IMPORTS, CLASS_IN_FILE, EXTENDS_CLASS, TESTS relationships — all of which can be derived from Tree-sitter ASTs and stored in SQLite.

## Proposed Solution

Add a zero-dependency code graph built on Tree-sitter (CLI or Python bindings) and SQLite. The graph stores at `.forge/code-graph.db`, coexists with the existing Neo4j graph, and provides AST-aware search APIs plus graph-based relevance ranking. When Neo4j is available, it remains the primary graph. When Neo4j is unavailable, the SQLite graph provides structural code intelligence rather than falling back to grep/glob.

## Detailed Design

### Architecture

```
                        +---------------------------+
                        |   Orchestrator (fg-100)   |
                        +---------------------------+
                               |           |
                   +-----------+           +-----------+
                   v                                   v
          +----------------+                  +----------------+
          |   Neo4j Graph  |                  | SQLite Graph   |
          |   (if Docker)  |                  | (always avail) |
          +----------------+                  +----------------+
                   |                                   |
          neo4j-mcp tool                    build-code-graph.sh
          (existing scripts)                (new script)
                   |                                   |
          build-project-graph.sh            Tree-sitter CLI
          enrich-symbols.sh                 (parses source)
                   |                                   |
          Neo4j container                   .forge/code-graph.db
```

**Components:**

1. **Tree-sitter parser layer** (`shared/graph/treesitter-parse.sh`) — wraps `tree-sitter` CLI or Python `tree_sitter` bindings to parse source files into ASTs for all 15 supported languages (kotlin, java, typescript, python, go, rust, swift, c, csharp, ruby, php, dart, elixir, scala, cpp)
2. **SQLite property graph** (`.forge/code-graph.db`) — stores nodes, edges, and metadata in relational tables that model a property graph
3. **Graph builder** (`shared/graph/build-code-graph.sh`) — orchestrates parsing, node extraction, edge creation, and incremental updates
4. **Search API** (`shared/graph/code-graph-query.sh`) — shell functions implementing AST-aware search (exposed to agents via stage notes or direct invocation)
5. **Relevance ranker** (`shared/graph/relevance-rank.sh`) — PageRank-inspired scoring for file/function relevance given a set of seed symbols

### Schema / Data Model

#### SQLite Tables

```sql
-- Schema version tracking
CREATE TABLE IF NOT EXISTS schema_meta (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL
);
-- Initial: INSERT INTO schema_meta VALUES ('version', '1.0.0');
-- Also stores: project_id, last_build_sha, last_build_timestamp

-- Node types: File, Module, Class, Interface, Function, Method, Variable,
--             Import, Export, Type, Enum, Constant, Decorator, Test, Fixture
CREATE TABLE IF NOT EXISTS nodes (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    kind        TEXT NOT NULL,  -- one of the 15 node types
    name        TEXT NOT NULL,
    file_path   TEXT NOT NULL,  -- project-relative path
    start_line  INTEGER NOT NULL DEFAULT 0,
    end_line    INTEGER NOT NULL DEFAULT 0,
    start_col   INTEGER NOT NULL DEFAULT 0,
    end_col     INTEGER NOT NULL DEFAULT 0,
    language    TEXT,           -- source language (kotlin, typescript, etc.)
    component   TEXT,           -- from forge.local.md components
    signature   TEXT,           -- function/method signature string
    visibility  TEXT,           -- public, private, protected, internal, package
    is_test     INTEGER NOT NULL DEFAULT 0, -- 1 if in test source tree
    properties  TEXT,           -- JSON blob for extensible metadata
    UNIQUE(kind, name, file_path, start_line)
);

-- Edge types: CALLS, IMPLEMENTS, INHERITS, IMPORTS, EXPORTS, CONTAINS,
--             REFERENCES, THROWS, READS, WRITES, TESTS, DEPENDS_ON,
--             OVERRIDES, ANNOTATED_BY, RETURNS, PARAMETERIZED_BY, INSTANTIATES
CREATE TABLE IF NOT EXISTS edges (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    edge_type   TEXT NOT NULL,  -- one of the 17 edge types
    source_id   INTEGER NOT NULL REFERENCES nodes(id) ON DELETE CASCADE,
    target_id   INTEGER NOT NULL REFERENCES nodes(id) ON DELETE CASCADE,
    weight      REAL NOT NULL DEFAULT 1.0,  -- for PageRank weighting
    properties  TEXT,           -- JSON blob for extensible metadata
    UNIQUE(edge_type, source_id, target_id)
);

-- File-level tracking for incremental updates
CREATE TABLE IF NOT EXISTS file_hashes (
    file_path       TEXT PRIMARY KEY,
    content_hash    TEXT NOT NULL,   -- SHA256 of file content
    last_parsed_at  TEXT NOT NULL,   -- ISO 8601 timestamp
    parse_duration_ms INTEGER,       -- parsing time for performance tracking
    node_count      INTEGER NOT NULL DEFAULT 0,
    edge_count      INTEGER NOT NULL DEFAULT 0
);

-- Community detection results (Louvain clustering)
CREATE TABLE IF NOT EXISTS communities (
    node_id       INTEGER NOT NULL REFERENCES nodes(id) ON DELETE CASCADE,
    community_id  INTEGER NOT NULL,
    modularity    REAL,
    computed_at   TEXT NOT NULL,     -- ISO 8601 timestamp
    PRIMARY KEY(node_id)
);

-- Indexes for query performance
CREATE INDEX IF NOT EXISTS idx_nodes_kind ON nodes(kind);
CREATE INDEX IF NOT EXISTS idx_nodes_name ON nodes(name);
CREATE INDEX IF NOT EXISTS idx_nodes_file ON nodes(file_path);
CREATE INDEX IF NOT EXISTS idx_nodes_kind_name ON nodes(kind, name);
CREATE INDEX IF NOT EXISTS idx_nodes_component ON nodes(component);
CREATE INDEX IF NOT EXISTS idx_edges_type ON edges(edge_type);
CREATE INDEX IF NOT EXISTS idx_edges_source ON edges(source_id);
CREATE INDEX IF NOT EXISTS idx_edges_target ON edges(target_id);
CREATE INDEX IF NOT EXISTS idx_edges_type_source ON edges(edge_type, source_id);
CREATE INDEX IF NOT EXISTS idx_edges_type_target ON edges(edge_type, target_id);
```

#### Node Type Enumeration

| Node Kind | Tree-sitter AST Nodes (representative) | Description |
|---|---|---|
| `File` | root | Source file entry |
| `Module` | `module_declaration`, `package_declaration` | Package/module/namespace |
| `Class` | `class_declaration`, `class_definition` | Class definition |
| `Interface` | `interface_declaration`, `trait_item`, `protocol_declaration` | Interface/trait/protocol |
| `Function` | `function_declaration`, `function_definition`, `func_literal` | Standalone function |
| `Method` | `method_declaration`, `function_item` (in impl block) | Class/struct method |
| `Variable` | `variable_declaration`, `let_declaration`, `const_item` | Variable/constant binding |
| `Import` | `import_statement`, `use_declaration`, `import_declaration` | Import/use statement |
| `Export` | `export_statement`, `pub` modifier | Exported symbol |
| `Type` | `type_alias_declaration`, `type_item` | Type alias/definition |
| `Enum` | `enum_declaration`, `enum_item` | Enum definition |
| `Constant` | `const_declaration`, `const_item` | Compile-time constant |
| `Decorator` | `annotation`, `decorator`, `attribute_item` | Annotation/decorator |
| `Test` | `function_declaration` with test annotation/naming | Test function |
| `Fixture` | `function_declaration` with fixture annotation | Test fixture/setup |

#### Edge Type Derivation

| Edge Type | Derivation Strategy |
|---|---|
| `CALLS` | Identifier resolution: function call expressions matching a known Function/Method node |
| `IMPLEMENTS` | Class/struct implementing an interface (`: Interface`, `impl Trait for`, `class X(Protocol)`) |
| `INHERITS` | Class extending another class (`: Base`, `extends Base`) |
| `IMPORTS` | Import statements resolved to target files via module resolution |
| `EXPORTS` | Public/exported symbols from a file |
| `CONTAINS` | Parent-child AST containment (Class CONTAINS Method, File CONTAINS Class) |
| `REFERENCES` | Identifier usage matching a known node (non-call references) |
| `THROWS` | Throw/raise expressions referencing exception types |
| `READS` | Variable read access (identifier in expression context) |
| `WRITES` | Variable write access (assignment target) |
| `TESTS` | Test function referencing production class/function (naming convention + import analysis) |
| `DEPENDS_ON` | Transitive closure of IMPORTS + CALLS at file level |
| `OVERRIDES` | Method override detection (same name + signature in subclass) |
| `ANNOTATED_BY` | Decorator/annotation applied to a node |
| `RETURNS` | Function/method return type referencing a Type/Class node |
| `PARAMETERIZED_BY` | Generic type parameters on classes/functions |
| `INSTANTIATES` | Constructor calls / object creation expressions |

### Language-Specific Tree-sitter Grammars

Each of the 15 supported languages requires its grammar:

| Language | Grammar Package | Key AST Nodes |
|---|---|---|
| kotlin | `tree-sitter-kotlin` | `class_declaration`, `function_declaration`, `object_declaration` |
| java | `tree-sitter-java` | `class_declaration`, `method_declaration`, `interface_declaration` |
| typescript | `tree-sitter-typescript` | `class_declaration`, `function_declaration`, `interface_declaration`, `type_alias_declaration` |
| python | `tree-sitter-python` | `class_definition`, `function_definition`, `decorated_definition` |
| go | `tree-sitter-go` | `type_declaration`, `function_declaration`, `method_declaration` |
| rust | `tree-sitter-rust` | `struct_item`, `impl_item`, `function_item`, `trait_item` |
| swift | `tree-sitter-swift` | `class_declaration`, `protocol_declaration`, `function_declaration` |
| c | `tree-sitter-c` | `function_definition`, `struct_specifier`, `type_definition` |
| csharp | `tree-sitter-c-sharp` | `class_declaration`, `method_declaration`, `interface_declaration` |
| ruby | `tree-sitter-ruby` | `class`, `method`, `module` |
| php | `tree-sitter-php` | `class_declaration`, `method_declaration`, `function_definition` |
| dart | `tree-sitter-dart` | `class_definition`, `method_signature`, `function_signature` |
| elixir | `tree-sitter-elixir` | `def`, `defmodule`, `defp` |
| scala | `tree-sitter-scala` | `class_definition`, `object_definition`, `def_definition`, `trait_definition` |
| cpp | `tree-sitter-cpp` | `class_specifier`, `function_definition`, `template_declaration` |

### Configuration

In `forge-config.md`:

```yaml
code_graph:
  enabled: true
  backend: auto                     # auto | sqlite | neo4j
  incremental: true
  community_detection: true
  relevance_ranking: true
  max_file_size_kb: 500             # Skip files larger than this
  exclude_patterns:                 # Glob patterns to exclude
    - "vendor/**"
    - "node_modules/**"
    - "*.generated.*"
    - "*.min.js"
  parse_timeout_seconds: 300        # Total parse budget per run
  per_file_timeout_ms: 5000         # Per-file parse timeout
```

| Parameter | Type | Default | Range | Description |
|---|---|---|---|---|
| `enabled` | boolean | `true` | -- | Master toggle for the code graph |
| `backend` | string | `auto` | `auto`, `sqlite`, `neo4j` | `auto` = Neo4j if available, else SQLite. `sqlite` = always SQLite. `neo4j` = always Neo4j (degrades if unavailable). |
| `incremental` | boolean | `true` | -- | Only re-parse changed files |
| `community_detection` | boolean | `true` | -- | Run Louvain clustering after build |
| `relevance_ranking` | boolean | `true` | -- | Enable PageRank-based relevance |
| `max_file_size_kb` | integer | `500` | 50-5000 | Skip files exceeding this size |
| `exclude_patterns` | string[] | `["vendor/**", "node_modules/**", "*.generated.*", "*.min.js"]` | -- | Glob patterns to exclude from parsing |
| `parse_timeout_seconds` | integer | `300` | 30-600 | Total parse time budget |
| `per_file_timeout_ms` | integer | `5000` | 1000-30000 | Per-file parse timeout |

### Data Flow

#### Initial Build (PREFLIGHT)

1. Orchestrator checks `code_graph.enabled` and `code_graph.backend`
2. If `backend: auto`: check `state.json.integrations.neo4j.available` — if true, skip SQLite build (Neo4j is primary). If false, proceed with SQLite build.
3. Invoke `shared/graph/build-code-graph.sh --project-root $PROJECT_ROOT --project-id $PROJECT_ID`
4. Script checks `.forge/code-graph.db` existence:
   - If absent: full build
   - If present: check `schema_meta.last_build_sha` against current HEAD
     - If same: skip (graph is current)
     - If different: incremental update
5. **Full build flow:**
   a. Create/reset SQLite database with schema
   b. Enumerate source files (respecting `exclude_patterns`, `max_file_size_kb`)
   c. For each file: compute SHA256, invoke Tree-sitter parser, extract nodes and edges
   d. Batch INSERT nodes and edges (SQLite transaction per 100 files for performance)
   e. Build cross-file edges (IMPORTS resolution, CALLS resolution, TESTS inference)
   f. Run community detection if enabled
   g. Store `last_build_sha`, `project_id`, `last_build_timestamp` in `schema_meta`
6. **Incremental update flow:**
   a. `git diff --name-only {last_build_sha}..HEAD` to find changed files
   b. For each changed file: compare SHA256 with `file_hashes.content_hash`
   c. If hash differs: delete old nodes/edges for that file, re-parse, insert new nodes/edges
   d. For deleted files: delete all nodes/edges referencing that file path
   e. For new files: parse and insert
   f. Rebuild cross-file edges involving changed files
   g. Recompute communities if any node changes occurred
   h. Update `last_build_sha`

#### Search API Invocations

Agents invoke search functions via the graph query script. Each function maps to a SQL query:

```bash
# search_class — find class by name across codebase
code-graph-query.sh search_class "UserService"
# SQL: SELECT * FROM nodes WHERE kind IN ('Class','Interface') AND name LIKE '%UserService%'

# search_method — find method/function globally
code-graph-query.sh search_method "createUser"
# SQL: SELECT * FROM nodes WHERE kind IN ('Function','Method') AND name LIKE '%createUser%'

# search_method_in_class — targeted search within a class
code-graph-query.sh search_method_in_class "createUser" "UserService"
# SQL: SELECT m.* FROM nodes m
#      JOIN edges e ON e.source_id = (SELECT id FROM nodes WHERE kind='Class' AND name='UserService')
#                  AND e.target_id = m.id AND e.edge_type = 'CONTAINS'
#      WHERE m.kind IN ('Function','Method') AND m.name LIKE '%createUser%'

# search_references — find all references to a symbol
code-graph-query.sh search_references "UserService"
# SQL: SELECT n2.* FROM nodes n1
#      JOIN edges e ON e.target_id = n1.id AND e.edge_type = 'REFERENCES'
#      JOIN nodes n2 ON n2.id = e.source_id
#      WHERE n1.name = 'UserService'

# search_implementations — find all implementations of an interface
code-graph-query.sh search_implementations "Repository"
# SQL: SELECT n2.* FROM nodes n1
#      JOIN edges e ON e.target_id = n1.id AND e.edge_type = 'IMPLEMENTS'
#      JOIN nodes n2 ON n2.id = e.source_id
#      WHERE n1.name = 'Repository' AND n1.kind = 'Interface'

# search_callers — reverse call graph
code-graph-query.sh search_callers "validateOrder"
# SQL: SELECT n2.* FROM nodes n1
#      JOIN edges e ON e.target_id = n1.id AND e.edge_type = 'CALLS'
#      JOIN nodes n2 ON n2.id = e.source_id
#      WHERE n1.name = 'validateOrder'
```

#### Relevance Ranking Algorithm

When the pipeline needs to identify relevant code for a requirement (e.g., at PLAN or BUG-INVESTIGATE), the ranker:

1. **Seed extraction:** Extract key nouns/entities from the requirement text (reuse plan-cache keyword extraction)
2. **Seed matching:** Find nodes whose `name` matches seed terms (fuzzy, case-insensitive)
3. **Graph walk (2 hops):** From seed nodes, follow CALLS, IMPORTS, CONTAINS, REFERENCES edges outward for 2 hops, accumulating a set of reachable nodes
4. **PageRank scoring:** Run a simplified iterative PageRank on the subgraph (10 iterations, damping factor 0.85):
   ```
   for each iteration:
     for each node n:
       rank[n] = (1 - d) / N + d * sum(rank[m] * weight(m->n) / out_degree(m) for m in inbound(n))
   ```
5. **File-level aggregation:** Sum node ranks per file to produce a file-level relevance score
6. **Output:** Top-K files (default K=20) sorted by descending relevance, with per-file score and the specific functions/classes that contributed

#### Community Detection (Louvain)

Identifies architectural module boundaries from the graph structure:

1. Build an undirected weighted graph from edges (CALLS, IMPORTS, CONTAINS)
2. Run Louvain community detection (iterative modularity optimization):
   - Phase 1: each node in own community; greedily merge into neighbor's community if modularity increases
   - Phase 2: build a new graph where nodes are communities from Phase 1
   - Repeat until no further modularity gain
3. Store community assignments in the `communities` table
4. Used by `fg-412-architecture-reviewer` to detect cross-boundary violations (a CALLS edge between nodes in different communities = potential architectural coupling)

### Integration Points

| Agent / System | Integration | Change Required |
|---|---|---|
| `fg-200-planner` | Blast radius analysis: query `search_references` + `search_callers` for files mentioned in the plan. Inject affected file count and transitive dependents into plan context. | Add graph query dispatch before planner invocation in orchestrator. |
| `fg-020-bug-investigator` | Fault localization: given the buggy behavior, query `search_callers` and `search_implementations` to identify likely root cause files. | Add graph-aware search in bug investigator dispatch. |
| `fg-300-implementer` | Affected tests: query `TESTS` edges to find test files covering changed production files. Surface as "tests to update" in implementer context. | Add test discovery query in orchestrator pre-implement. |
| `fg-400-quality-gate` | Architectural context: inject community boundaries for architecture reviewer. Files crossing community boundaries get extra scrutiny. | Add community data to quality gate context. |
| Explore cache | Augment `file_index` entries with `dependencies` derived from IMPORTS edges (currently heuristic). | Enhance explore cache update to read from code graph. |
| `fg-100-orchestrator` | Backend selection: at PREFLIGHT, determine `code_graph.backend` and record in `state.json.integrations.code_graph`. | Add code graph availability to integration detection. |
| `shared/graph/schema.md` | Document coexistence: SQLite graph is supplementary when Neo4j is available, primary when Neo4j is unavailable. | Add "Code Graph (SQLite)" section to schema.md. |
| `shared/checks/category-registry.json` | No new categories — the code graph is infrastructure, not a finding source. | None. |

#### Neo4j Coexistence

When both backends are available (`backend: auto` and Neo4j is up):

- Neo4j remains the primary graph (richer relationship model, cross-repo support, DocFile nodes)
- SQLite graph is still built but marked as `secondary` in state
- If Neo4j becomes unavailable mid-run (MCP failure), orchestrator transparently falls back to SQLite queries
- No data sync between Neo4j and SQLite — they are independently built from the same source code

When only SQLite is available:

- All graph queries route to SQLite
- DocFile/DocSection/DocDecision/DocConstraint nodes are NOT in SQLite (those are Neo4j-only)
- Bug hotspot tracking (`bug_fix_count` on ProjectFile) is available (stored in `nodes.properties` JSON)

### Error Handling

| Failure Mode | Behavior | Degradation |
|---|---|---|
| Tree-sitter CLI not installed | Log INFO: "tree-sitter CLI not found. Code graph disabled." Set `state.json.integrations.code_graph.available = false`. | Fall back to grep/glob (existing behavior). |
| Grammar missing for a language | Log WARNING: "No grammar for {language}. Skipping {N} files." Parse other languages normally. | Partial graph — queries for that language return empty. |
| SQLite DB corrupted | Delete `.forge/code-graph.db`, log WARNING, rebuild from scratch. | One-time full rebuild cost. |
| Parse timeout (per-file) | Kill parser after `per_file_timeout_ms`, log INFO, skip file. Increment `file_hashes` with `parse_duration_ms = -1` (sentinel for timeout). | File excluded from graph until next change. |
| Parse timeout (total) | Stop parsing at `parse_timeout_seconds`, log WARNING. Commit partial graph. | Partial graph — later runs complete incrementally. |
| `git diff` fails (detached HEAD, shallow clone) | Fall back to full build (no incremental). Log INFO. | Full parse on every run for that project. |
| Disk space exhaustion | SQLite write failure caught, log CRITICAL, set `code_graph.available = false`. | Fall back to grep/glob. |

## Performance Characteristics

### Parse Time Estimates (per language, per 1000 files)

| Language | Avg Parse Time (1000 files) | Avg File Size | Notes |
|---|---|---|---|
| TypeScript/JavaScript | ~3s | 5KB | Fast grammar, common in large projects |
| Python | ~2.5s | 4KB | Simple grammar |
| Java/Kotlin | ~4s | 6KB | Complex grammar (generics, annotations) |
| Rust | ~5s | 7KB | Complex grammar (lifetime annotations) |
| Go | ~2s | 4KB | Simple grammar |
| C/C++ | ~6s | 8KB | Preprocessor complexity |
| Others | ~3s | 5KB | Typical |

### Query Latency

| Operation | Expected Latency | Notes |
|---|---|---|
| `search_class(name)` | <1ms | Index lookup on `nodes(kind, name)` |
| `search_method(name)` | <1ms | Index lookup |
| `search_references(symbol)` | 1-5ms | Join on edges table |
| `search_callers(function)` | 1-5ms | Join on edges table |
| Relevance ranking (20-file project) | 10-50ms | 2-hop walk + 10 iterations PageRank |
| Relevance ranking (500-file project) | 100-500ms | Larger subgraph |
| Community detection | 1-5s | Full graph traversal (one-time per build) |

### Storage

| Project Size | Estimated DB Size | Nodes | Edges |
|---|---|---|---|
| Small (50 files) | ~500KB | ~500 | ~2,000 |
| Medium (500 files) | ~5MB | ~5,000 | ~20,000 |
| Large (5,000 files) | ~50MB | ~50,000 | ~200,000 |

### Token Impact

The code graph reduces tokens consumed by downstream agents:

- **Without graph:** agents grep for references, read entire files for context, often over-fetch
- **With graph:** agents receive pre-computed relevance-ranked file lists and specific function locations
- **Estimated savings:** 30-50% reduction in EXPLORE and PLAN stage tokens for medium-to-large projects

## Testing Approach

### Unit Tests (`tests/unit/code-graph.bats`)

1. **Schema creation:** Verify `build-code-graph.sh` creates all tables and indexes
2. **Node extraction:** Parse a known file per language, verify extracted node count and types
3. **Edge extraction:** Parse two related files, verify CALLS/IMPORTS edges
4. **Incremental update:** Build graph, modify one file, verify only that file's nodes are updated
5. **Search APIs:** Insert known data, verify each `search_*` function returns expected results
6. **File exclusion:** Verify `exclude_patterns` and `max_file_size_kb` are respected
7. **Timeout handling:** Verify per-file timeout kills parser and skips file gracefully

### Integration Tests (`tests/integration/code-graph.bats`)

1. **Full pipeline integration:** Run `/forge-run --dry-run` on a test project with `code_graph.enabled: true`, verify graph is built at PREFLIGHT
2. **Neo4j coexistence:** With Neo4j available, verify SQLite graph is built as secondary
3. **Fallback:** Disable Neo4j, verify pipeline uses SQLite graph for blast radius analysis

### Scenario Tests

1. **Large project:** Parse a 1000-file TypeScript project within `parse_timeout_seconds`
2. **Mixed languages:** Parse a project with Kotlin + TypeScript + Python, verify cross-language IMPORTS edges
3. **Corrupted DB recovery:** Corrupt the DB file, verify next run detects and rebuilds

## Acceptance Criteria

1. `build-code-graph.sh` parses source files in all 15 supported languages and creates a valid SQLite database at `.forge/code-graph.db`
2. Incremental updates re-parse only files whose SHA256 hash has changed since the last build
3. All 6 search APIs (`search_class`, `search_method`, `search_method_in_class`, `search_references`, `search_implementations`, `search_callers`) return correct results against a known test codebase
4. Relevance ranking produces a scored file list given seed terms, with files containing direct matches ranked highest
5. Community detection identifies at least 2 distinct communities in a project with clearly separated modules
6. When Neo4j is unavailable, `fg-200-planner` receives blast radius data from the SQLite graph instead of falling back to grep
7. Total parse time for a 500-file project is under 30 seconds
8. Query latency for all `search_*` APIs is under 10ms on a 500-file project
9. The graph survives `/forge-reset` (same as explore-cache and plan-cache)
10. `validate-plugin.sh` passes with the new script added
11. No Docker, Neo4j, or external service is required for the SQLite graph to function

## Migration Path

1. **v2.0.0:** Ship `build-code-graph.sh`, `code-graph-query.sh`, `relevance-rank.sh` as new files. No changes to existing Neo4j scripts or graph schema.
2. **v2.0.0:** Add `code_graph:` section to `forge-config-template.md` for all frameworks. Default: `enabled: true, backend: auto`.
3. **v2.0.0:** Update `fg-100-orchestrator.md` to include code graph availability detection at PREFLIGHT and query dispatch at PLAN/IMPLEMENT.
4. **v2.0.0:** Add `.forge/code-graph.db` to the "Survives /forge-reset" file list in `state-schema.md`.
5. **v2.1.0 (future):** Consider deprecating Neo4j requirement for projects that only need code structure (not doc graph). Neo4j remains required for `DocFile`/`DocSection`/`DocDecision` nodes.
6. **No breaking changes:** Existing Neo4j users experience zero behavior change. `backend: auto` prefers Neo4j when available.

## Dependencies

**Depends on:**
- Tree-sitter CLI (`tree-sitter` binary) or Python `tree_sitter` package — detected at PREFLIGHT, graceful degradation if absent
- SQLite3 CLI (`sqlite3` binary) — available on macOS, most Linux distros, and Windows via Git Bash

**Depended on by:**
- F06 (Confidence Scoring): uses codebase complexity metrics from the code graph
- F10 (Enhanced Security): uses AST context from the code graph for context-aware secret detection
