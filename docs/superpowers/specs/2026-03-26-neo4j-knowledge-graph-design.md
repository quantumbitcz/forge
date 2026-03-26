# Neo4j Knowledge Graph for dev-pipeline

## Summary

A dual-purpose Neo4j knowledge graph that gives pipeline agents structural understanding of both the plugin's own module system and the consuming project's codebase. Agents can query "what conventions apply to this file?", "what breaks if I change this entity?", and "what's the recommended auth module for Express + TypeScript?" — all via Cypher through Neo4j MCP.

**Two logical graphs in one Neo4j instance:**

1. **Plugin knowledge graph** (static) — 166 modules, 29 agents, framework bindings, check rules, convention stacks. Pre-computed as a Cypher seed file, version-controlled, regenerated automatically when modules change.

2. **Consuming project codebase graph** (dynamic) — files, imports, packages, dependencies, classes, functions. Built at `/pipeline-init`, incrementally updated during PREFLIGHT, symbol-enriched on demand during EXPLORE.

**Key decisions:**
- Docker-managed Neo4j in `.pipeline/` with Neo4j MCP for native agent access
- Approach C: pre-computed seed + dynamic project graph
- Hybrid progressive depth: file-level always, symbol-level on demand for changed files
- Fully opt-in with graceful degradation — pipeline works without Neo4j

## Graph Schema

### Plugin Knowledge Graph (static, seeded)

**Nodes:**

| Label | Properties | Description |
|---|---|---|
| `Language` | `name`, `file_path` | Language module (kotlin, ruby, php...) |
| `Framework` | `name`, `file_path` | Framework module (spring, react, express...) |
| `TestingFramework` | `name`, `file_path` | Testing module (kotest, jest, rspec...) |
| `LayerModule` | `name`, `layer`, `file_path` | Crosscutting module (postgresql in databases, jwt in auth, kafka in messaging...) |
| `FrameworkBinding` | `name`, `framework`, `layer`, `file_path` | Framework-specific binding (spring/persistence/hibernate.md) |
| `Agent` | `name`, `role`, `file_path` | Pipeline or review agent. Review agents get dual labels `:Agent:Reviewer` |
| `SharedContract` | `name`, `file_path` | Core contracts (scoring.md, stage-contract.md, state-schema.md) |
| `CheckRule` | `id`, `severity`, `category`, `file_path` | Check engine rules (QUAL-NULL, SEC-CRED...) |
| `Learnings` | `name`, `file_path` | Per-module learnings file |

**Relationships:**

| Relationship | From | To | Description |
|---|---|---|---|
| `HAS_BINDING` | `Framework` | `FrameworkBinding` | Framework has a layer-specific binding |
| `EXTENDS` | `FrameworkBinding` | `LayerModule` | Binding extends a generic layer module |
| `HAS_VARIANT` | `Framework` | `Language` | Framework has a language-specific variant |
| `PAIRS_WITH` | `Framework` | `TestingFramework` | Framework has testing framework bindings |
| `CANONICAL_TESTING` | `Language` | `TestingFramework` | Language's canonical test framework (kotlin->kotest, ruby->rspec) |
| `CANONICAL_PERSISTENCE` | `Language` | `LayerModule` | Language's canonical ORM (ruby->active-record, elixir->ecto) |
| `READS` | `Agent` | `SharedContract` | Agent depends on a shared contract |
| `DISPATCHES` | `Agent` | `Agent` | Agent dispatches another agent |
| `REVIEWS_LAYER` | `Agent:Reviewer` | `LayerModule` | Reviewer specializes in a layer |
| `HAS_LEARNINGS` | `LayerModule` | `Learnings` | Module has a learnings file |
| `RULE_DEFINED_IN` | `CheckRule` | `LayerModule` | Check rule defined in a module's rules-override |
| `OVERRIDES_RULE` | `FrameworkBinding` | `CheckRule` | Binding overrides a check rule |

### Project Codebase Graph (dynamic, built at init)

**Nodes:**

| Label | Properties | Description |
|---|---|---|
| `ProjectFile` | `path`, `language`, `size`, `last_modified` | Source file in the consuming project |
| `ProjectClass` | `name`, `file_path`, `kind` | Class, interface, trait, struct (enriched on demand) |
| `ProjectFunction` | `name`, `file_path`, `class_name` | Function or method (enriched on demand) |
| `ProjectPackage` | `name`, `path` | Directory/module grouping |
| `ProjectDependency` | `name`, `version`, `type` | From package.json, build.gradle, etc. |

**Relationships:**

| Relationship | From | To | Description |
|---|---|---|---|
| `IMPORTS` | `ProjectFile` | `ProjectFile` | File imports another file |
| `BELONGS_TO` | `ProjectFile` | `ProjectPackage` | File is in a package/directory |
| `USES_CONVENTION` | `ProjectFile` | `FrameworkBinding` or `LayerModule` | File uses a convention module |
| `CLASS_IN_FILE` | `ProjectClass` | `ProjectFile` | Class defined in file |
| `EXTENDS_CLASS` | `ProjectClass` | `ProjectClass` | Class extends another (enriched) |
| `IMPLEMENTS` | `ProjectClass` | `ProjectClass` | Class implements interface (enriched) |
| `CALLS` | `ProjectFunction` | `ProjectFunction` | Function calls another (enriched) |
| `FUNCTION_IN_CLASS` | `ProjectFunction` | `ProjectClass` | Function defined in class |
| `MAPS_TO` | `ProjectDependency` | `LayerModule` | Links deps to our modules |

### Cross-Graph Connections

The project graph connects to the plugin graph via:
- `(:ProjectFile)-[:USES_CONVENTION]->(:FrameworkBinding|:LayerModule)` — derived from `dev-pipeline.local.md` component config
- `(:ProjectDependency)-[:MAPS_TO]->(:LayerModule)` — derived from `dependency-map.json`

## Infrastructure

### Docker Container

```yaml
# .pipeline/docker-compose.neo4j.yml (generated by pipeline-init)
services:
  neo4j:
    image: neo4j:5-community
    container_name: pipeline-neo4j
    ports:
      - "${NEO4J_PORT:-7474}:7474"
      - "${NEO4J_BOLT:-7687}:7687"
    environment:
      NEO4J_AUTH: neo4j/pipeline-local
      NEO4J_PLUGINS: '["apoc"]'
      NEO4J_server_memory_heap_initial__size: 256m
      NEO4J_server_memory_heap_max__size: 512m
      NEO4J_server_memory_pagecache_size: 256m
    volumes:
      - pipeline-neo4j-data:/data
    healthcheck:
      test: cypher-shell -u neo4j -p pipeline-local "RETURN 1"
      interval: 5s
      timeout: 5s
      retries: 10
    restart: unless-stopped

volumes:
  pipeline-neo4j-data:
```

### Neo4j MCP Configuration

Injected into consuming project's `.mcp.json` during `graph-init`:

```json
{
  "mcpServers": {
    "neo4j": {
      "command": "npx",
      "args": ["-y", "@neo4j/mcp-server"],
      "env": {
        "NEO4J_URI": "bolt://localhost:7687",
        "NEO4J_USERNAME": "neo4j",
        "NEO4J_PASSWORD": "pipeline-local"
      }
    }
  }
}
```

### Lifecycle

| Event | Action |
|---|---|
| `/pipeline-init` (with `graph.enabled: true`) | Start container, import `seed.cypher`, run `build-project-graph.sh` |
| `/pipeline-run` PREFLIGHT | `incremental-update.sh` — git diff since last build SHA, add/remove/update file nodes |
| `/pipeline-run` EXPLORE | `enrich-symbols.sh` — tree-sitter/regex parsing for files in current requirement scope |
| `/pipeline-run` IMPLEMENT | Agents query graph for impact analysis before writing code |
| `/pipeline-reset` | Destroy container + volume, clean `.pipeline/graph/` |
| Container crash | Auto-restart via Docker, or rebuild from seed + cached project snapshot |

### Configuration

```yaml
# In dev-pipeline.local.md
graph:
  enabled: true           # false = skip everything, pipeline works as before
  enrich_symbols: true    # false = file-level only, no AST parsing
  neo4j_port: 7687        # configurable if port conflicts
  neo4j_http_port: 7474   # browser UI port
```

### Graceful Degradation

If Docker isn't available, Neo4j fails to start, or `graph.enabled: false`:
- `state.json.integrations.neo4j.available` is set to `false`
- All agents fall back to grep/glob-based analysis (current behavior)
- No pipeline functionality is lost — graph is a pure enhancement

## Seed Generation

### File Structure

```
shared/graph/
├── generate-seed.sh          — scans modules/, agents/, shared/ → produces seed.cypher
├── seed.cypher               — generated, version-controlled
├── build-project-graph.sh    — scans consuming project → Cypher statements
├── incremental-update.sh     — git diff → add/remove/update nodes
├── enrich-symbols.sh         — tree-sitter/regex AST parsing for specific files
├── dependency-map.json       — maps package names to LayerModule names
└── query-patterns.md         — pre-defined Cypher templates for agents
```

### generate-seed.sh Algorithm

1. Scan `modules/languages/*.md` → create `(:Language)` nodes
2. Scan `modules/frameworks/*/` → create `(:Framework)` nodes
3. Scan `modules/frameworks/*/conventions.md` for variant refs → create `HAS_VARIANT` edges
4. Scan `modules/testing/*.md` → create `(:TestingFramework)` nodes
5. Scan `modules/{databases,persistence,migrations,...}/*.md` → create `(:LayerModule)` nodes
6. Scan `modules/frameworks/*/{layer}/*.md` → create `(:FrameworkBinding)` nodes + `EXTENDS` edges
7. Scan `agents/*.md` frontmatter → create `(:Agent)` nodes + `DISPATCHES` edges
8. Scan `shared/*.md` → create `(:SharedContract)` nodes
9. Parse `rules-override.json` files → create `(:CheckRule)` nodes + `OVERRIDES_RULE` edges
10. Map `shared/learnings/*.md` → create `(:Learnings)` nodes + `HAS_LEARNINGS` edges
11. Derive `CANONICAL_TESTING` and `CANONICAL_PERSISTENCE` edges from known pairings

### Automation

Pre-commit hook in the plugin repo regenerates `seed.cypher` when `modules/`, `agents/`, or `shared/` files change:

```bash
#!/usr/bin/env bash
if git diff --cached --name-only | grep -qE '^(modules|agents|shared)/'; then
  ./shared/graph/generate-seed.sh
  git add shared/graph/seed.cypher
fi
```

## Project Graph Builder

### build-project-graph.sh

1. Detect language from manifest files (package.json, build.gradle.kts, Cargo.toml, etc.)
2. Walk source directories (respecting `.gitignore`) → create `(:ProjectFile)` nodes
3. Parse imports per language using regex patterns:
   - Kotlin/Java: `import com.example.foo.Bar`
   - TypeScript: `import { Foo } from './services/foo'`
   - Python: `from myapp.services import UserService`
   - Go: `import "myapp/internal/repository"`
   - Rust: `use crate::services::user`
   - Ruby: `require_relative 'services/user_service'`
   - PHP: `use App\Services\UserService`
   - Elixir: `alias MyApp.UserService`
   - Scala: `import com.example.services.UserService`
   - Dart: `import 'package:myapp/services/user_service.dart'`
   - C/C++: `#include "services/user_service.h"`
   - Swift: detected via module/framework imports
   - C#: `using MyApp.Services`
4. Create `(:ProjectPackage)` nodes from directory structure
5. Parse dependency manifests → create `(:ProjectDependency)` nodes + `MAPS_TO` edges via `dependency-map.json`
6. Connect to plugin graph → `USES_CONVENTION` edges from `dev-pipeline.local.md` component config
7. Write `git rev-parse HEAD` to `.pipeline/graph/.last-build-sha`

### incremental-update.sh

Runs during PREFLIGHT:

```bash
LAST_BUILD=$(cat .pipeline/graph/.last-build-sha 2>/dev/null || echo "")
if [ -n "$LAST_BUILD" ]; then
  CHANGED=$(git diff --name-status "$LAST_BUILD"..HEAD)
  # A (added) → create node + parse imports
  # M (modified) → update metadata + re-parse imports
  # D (deleted) → detach delete node + dangling edges
  # R (renamed) → update path, preserve edges
else
  exec build-project-graph.sh  # full rebuild
fi
git rev-parse HEAD > .pipeline/graph/.last-build-sha
```

### enrich-symbols.sh

Runs during EXPLORE for files in current requirement scope:

1. Parse with tree-sitter (if available) or regex fallback
2. Extract: classes, interfaces, functions, method signatures
3. Create `(:ProjectClass)`, `(:ProjectFunction)` nodes
4. Parse method bodies for call references → `CALLS` edges
5. Parse class declarations for extends/implements → `EXTENDS_CLASS`, `IMPLEMENTS` edges
6. Record enrichment status per file to avoid re-parsing

### dependency-map.json

Maps package manager dependency names to LayerModule names:

```json
{
  "npm": {
    "pg": "postgresql", "mysql2": "mysql", "mongodb": "mongodb",
    "redis": "redis", "ioredis": "redis",
    "passport": "passport", "@auth0/nextjs-auth0": "auth0",
    "@sentry/node": "sentry", "dd-trace": "datadog",
    "kafkajs": "kafka", "amqplib": "rabbitmq",
    "prisma": "prisma", "typeorm": "typeorm", "sequelize": "sequelize",
    "elasticsearch": "elasticsearch", "typesense": "typesense",
    "@supabase/supabase-js": "supabase-auth"
  },
  "maven": {
    "org.springframework.boot:spring-boot-starter-data-jpa": "hibernate",
    "org.postgresql:postgresql": "postgresql",
    "io.sentry:sentry-spring-boot-starter": "sentry",
    "org.apache.kafka:kafka-clients": "kafka"
  },
  "pip": {
    "sqlalchemy": "sqlalchemy", "django": "django-orm",
    "psycopg2": "postgresql", "pymongo": "mongodb",
    "sentry-sdk": "sentry", "celery": "rabbitmq"
  },
  "gems": {
    "pg": "postgresql", "mysql2": "mysql",
    "activerecord": "active-record", "sequel": "postgresql",
    "sentry-ruby": "sentry", "bunny": "rabbitmq"
  },
  "hex": {
    "ecto": "ecto", "postgrex": "postgresql",
    "sentry": "sentry", "broadway_kafka": "kafka"
  },
  "cargo": {
    "sqlx": "sqlx", "diesel": "diesel", "sea-orm": "sea-orm",
    "tokio-postgres": "postgresql", "sentry": "sentry"
  },
  "nuget": {
    "Npgsql": "postgresql", "Dapper": "dapper",
    "Microsoft.EntityFrameworkCore": "efcore",
    "Sentry.AspNetCore": "sentry", "Confluent.Kafka": "kafka"
  }
}
```

## Agent Integration

### Query Patterns

Agents use pre-defined Cypher templates via Neo4j MCP:

**Stack Resolution (orchestrator, PREFLIGHT):**
```cypher
MATCH (f:Framework {name: $framework})-[:HAS_BINDING]->(b:FrameworkBinding)
WHERE b.layer IN ['persistence', 'auth', 'observability', 'testing', 'databases']
OPTIONAL MATCH (b)-[:EXTENDS]->(m:LayerModule)
OPTIONAL MATCH (f)-[:HAS_VARIANT]->(l:Language {name: $language})
RETURN f, b, m, l ORDER BY b.layer
```

**Impact Analysis (planner, implementer):**
```cypher
MATCH (changed:ProjectFile {path: $filePath})
MATCH (dependent:ProjectFile)-[:IMPORTS]->(changed)
OPTIONAL MATCH (dependent)-[:IMPORTS*2..3]->(transitive:ProjectFile)
RETURN changed, collect(DISTINCT dependent.path) AS direct_dependents,
       collect(DISTINCT transitive.path) AS transitive_dependents
```

```cypher
MATCH (entity:ProjectClass {name: $className})-[:CLASS_IN_FILE]->(f:ProjectFile)
MATCH (consumer:ProjectFile)-[:IMPORTS]->(f)
OPTIONAL MATCH (consumer)-[:USES_CONVENTION]->(conv)
RETURN consumer.path, collect(conv.name) AS conventions
```

**Gap Detection (plugin development):**
```cypher
MATCH (f:Framework)
WHERE NOT (f)-[:HAS_BINDING]->(:FrameworkBinding {layer: 'search'})
RETURN f.name AS framework_missing_search
```

```cypher
MATCH (l:Language)
WHERE NOT (l)-[:CANONICAL_TESTING]->(:TestingFramework)
RETURN l.name
```

**Recommendation (pipeline-init):**
```cypher
MATCH (f:Framework {name: $framework})-[:HAS_BINDING]->(b:FrameworkBinding {layer: $layer})
MATCH (b)-[:EXTENDS]->(m:LayerModule)
RETURN m.name, count(*) AS binding_count ORDER BY binding_count DESC
```

**Scope Analysis (planner, EXPLORE):**
```cypher
MATCH (root:ProjectFile {path: $filePath})
MATCH path = (root)<-[:IMPORTS*1..4]-(dependent:ProjectFile)
RETURN nodes(path) AS impact_chain, length(path) AS depth
ORDER BY depth
```

**Plugin Impact Analysis (plugin development):**
```cypher
MATCH (c:SharedContract {name: $contractName})
MATCH (a:Agent)-[:READS]->(c)
RETURN a.name, a.role
```

### Agent Access

**Only the orchestrator (`pl-100-orchestrator`) gets `neo4j-mcp` in its tools list.** It pre-queries common patterns at stage boundaries and passes results as `graph_context` in stage notes. This avoids adding Neo4j MCP as a dependency to all 29 agents. Specifically:

| Stage | Orchestrator pre-queries | Passed to |
|---|---|---|
| PREFLIGHT | Convention stack resolution, dependency-to-module mapping | All downstream agents via stage notes |
| EXPLORE | Blast radius for requirement scope, enriched symbol data | `pl-200-planner` |
| PLAN | Impact analysis for planned changes | `pl-210-validator`, `pl-250-contract-validator` |
| IMPLEMENT | Per-task file dependency graph | `pl-300-implementer`, `pl-310-scaffolder` |
| REVIEW | Architectural boundary graph for changed files | `pl-400-quality-gate` → review agents |

If Neo4j is unavailable, `state.json.integrations.neo4j.available` is `false` and all agents fall back to grep/glob analysis (current behavior). No agent fails due to missing graph data.

## Skills

| Skill | Trigger | Purpose |
|---|---|---|
| `graph-init` | `/graph-init` or called by `pipeline-init` when `graph.enabled: true` | Start Neo4j container, import seed, build project graph. User-facing: can be invoked standalone to set up the graph without running the full pipeline. Idempotent: skips steps already completed (container running, seed imported). Requires `pipeline-init` to have run first (needs `dev-pipeline.local.md` for component config). |
| `graph-status` | `/graph-status` | Show node counts, last build SHA, enrichment coverage, container health |
| `graph-query` | `/graph-query <cypher>` | Interactive Cypher query for ad-hoc exploration |
| `graph-rebuild` | `/graph-rebuild` | Full rebuild of project graph (when incremental gets stale) |

## Hooks

Graph updates happen at **stage boundaries**, not on every file edit:

- PREFLIGHT: `incremental-update.sh` runs once
- VERIFY: `incremental-update.sh` runs once (captures implementation changes)
- Seed regeneration: git pre-commit hook (`.githooks/pre-commit`, not the plugin's `hooks/hooks.json`) in the plugin repo when `modules/`, `agents/`, or `shared/` change. The existing `PostToolUse` hooks on `Edit|Write` are intentionally NOT extended for graph updates — stage-boundary batching is more efficient.

## Testing

| Test | File | Validates |
|---|---|---|
| `seed-freshness` | `tests/contract/graph-seed.bats` | `generate-seed.sh --dry-run` matches committed `seed.cypher` |
| `seed-syntax` | `tests/contract/graph-seed.bats` | `seed.cypher` is valid Cypher |
| `node-coverage` | `tests/contract/graph-seed.bats` | Every module file has a node in `seed.cypher` |
| `edge-integrity` | `tests/contract/graph-seed.bats` | Every `EXTENDS` edge references an existing node |
| `dependency-map` | `tests/unit/dependency-map.bats` | `dependency-map.json` is valid JSON, values reference existing modules |
| `query-patterns` | `tests/unit/query-patterns.bats` | All Cypher templates are syntactically valid |
| `graceful-degradation` | `tests/scenario/graph-degradation.bats` | Pipeline runs without graph when Neo4j is unavailable |

## Integration Points with Existing Pipeline

| Pipeline Stage | Graph Usage |
|---|---|
| PREFLIGHT | Incremental graph update; detect convention drift via graph queries |
| EXPLORE | Enrich symbols for files in scope; query blast radius for requirement |
| PLAN | Impact analysis: "what files are affected by this change?" |
| VALIDATE | Contract validator queries cross-graph for API contract consumers |
| IMPLEMENT | Agents query "what calls this method?" before refactoring |
| VERIFY | Graph update captures implementation changes; verify no orphaned imports |
| REVIEW | Reviewers query graph for architectural boundary violations |
| SHIP | PR description includes graph-derived impact summary |

## Configuration in dev-pipeline.local.md

```yaml
graph:
  enabled: true
  enrich_symbols: true
  neo4j_port: 7687
  neo4j_http_port: 7474
```

When `graph.enabled: false` or Docker is unavailable, `state.json.integrations.neo4j.available` is `false` and all graph features are skipped with zero impact on existing pipeline behavior.
