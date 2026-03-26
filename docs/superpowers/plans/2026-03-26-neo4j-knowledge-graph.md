# Neo4j Knowledge Graph Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a dual-purpose Neo4j knowledge graph that maps the plugin's module relationships (static seed) and consuming projects' codebases (dynamic), enabling agents to query impact analysis, convention stacks, and blast radius via Cypher.

**Architecture:** Docker-managed Neo4j in `.pipeline/` with Neo4j MCP integration. Plugin graph pre-computed as a Cypher seed file (regenerated on module changes). Project graph built at init, incrementally updated at PREFLIGHT/VERIFY, symbol-enriched on demand. Fully opt-in with graceful degradation.

**Tech Stack:** Neo4j 5 Community (Docker), Neo4j MCP server (`@neo4j/mcp-server`), Bash scripts, bats tests.

**Spec:** `docs/superpowers/specs/2026-03-26-neo4j-knowledge-graph-design.md`

---

## File Structure

```
shared/graph/                          — NEW directory (all graph scripts and data)
├── generate-seed.sh                   — scans plugin modules → produces seed.cypher
├── seed.cypher                        — generated Cypher, version-controlled
├── build-project-graph.sh             — scans consuming project → Cypher statements
├── incremental-update.sh              — git diff → add/remove/update project nodes
├── enrich-symbols.sh                  — regex-based class/function extraction for specific files
├── dependency-map.json                — maps package names to LayerModule names
├── canonical-pairings.json            — language→testing, language→persistence known pairings
├── query-patterns.md                  — pre-defined Cypher templates for agents
├── neo4j-health.sh                    — checks container health, returns status
└── docker-compose.neo4j.yml           — template for consuming project's .pipeline/

skills/graph-init/SKILL.md             — NEW skill: start Neo4j, seed, build project graph
skills/graph-status/SKILL.md           — NEW skill: show graph stats
skills/graph-query/SKILL.md            — NEW skill: interactive Cypher queries
skills/graph-rebuild/SKILL.md          — NEW skill: full project graph rebuild

tests/contract/graph-seed.bats         — NEW: seed freshness, syntax, node coverage, edge integrity
tests/unit/dependency-map.bats         — NEW: dependency-map.json validation
tests/unit/query-patterns.bats         — NEW: query-patterns.md structural validation
tests/scenario/graph-degradation.bats  — NEW: pipeline works without Neo4j

.githooks/pre-commit                   — NEW: regenerate seed on module changes

agents/pl-100-orchestrator.md          — MODIFY: add neo4j-mcp to tools, graph_context in stage notes
shared/state-schema.md                 — MODIFY: add neo4j to integrations object
skills/pipeline-init/SKILL.md          — MODIFY: call graph-init when graph.enabled
skills/pipeline-reset/SKILL.md         — MODIFY: destroy Neo4j container + volume
modules/frameworks/*/local-template.md — MODIFY (all 21): add graph: section to templates
CLAUDE.md                              — MODIFY: document graph feature
```

---

### Task 1: Create `shared/graph/` directory structure and dependency-map.json

**Files:**
- Create: `shared/graph/dependency-map.json`
- Create: `shared/graph/canonical-pairings.json`

- [ ] **Step 1: Create the `shared/graph/` directory**

```bash
mkdir -p shared/graph
```

- [ ] **Step 2: Write `dependency-map.json`**

Copy the dependency map from the spec (lines 267-308) into `shared/graph/dependency-map.json`. This maps package manager dependency names to LayerModule names across npm, maven, pip, gems, hex, cargo, nuget.

- [ ] **Step 3: Write `canonical-pairings.json`**

```json
{
  "canonical_testing": {
    "kotlin": "kotest",
    "java": "junit5",
    "typescript": "vitest",
    "python": "pytest",
    "go": "go-testing",
    "rust": "rust-test",
    "swift": "xctest",
    "csharp": "xunit-nunit",
    "ruby": "rspec",
    "php": "phpunit",
    "dart": "flutter-test",
    "elixir": "exunit",
    "scala": "scalatest"
  },
  "canonical_persistence": {
    "ruby": "active-record",
    "elixir": "ecto",
    "python": "sqlalchemy",
    "rust": "diesel",
    "go": "gorm",
    "csharp": "efcore",
    "kotlin": "exposed",
    "java": "hibernate",
    "typescript": "prisma",
    "swift": "fluent",
    "php": "eloquent"
  }
}
```

- [ ] **Step 4: Commit**

```bash
git add shared/graph/dependency-map.json shared/graph/canonical-pairings.json
git commit -m "feat(graph): add dependency-map and canonical-pairings data files"
```

---

### Task 2: Write `generate-seed.sh` — plugin knowledge graph seed generator

**Files:**
- Create: `shared/graph/generate-seed.sh`

- [ ] **Step 1: Write the seed generator script**

The script scans the plugin's own files and outputs valid Cypher to stdout (or to `shared/graph/seed.cypher` without `--dry-run`).

Must implement all 11 steps from the spec (lines 185-195):
1. Scan `modules/languages/*.md` → `CREATE (:Language {name: '...', file_path: '...'});`
2. Scan `modules/frameworks/*/` → `CREATE (:Framework {name: '...', file_path: '...'});`
3. Scan `modules/frameworks/*/variants/*.md` → `CREATE ... -[:HAS_VARIANT]-> ...`
4. Scan `modules/testing/*.md` → `CREATE (:TestingFramework ...)`
5. Scan `modules/{databases,persistence,...}/*.md` → `CREATE (:LayerModule {name: '...', layer: '...', file_path: '...'})`
6. Scan `modules/frameworks/*/{layer}/*.md` → `CREATE (:FrameworkBinding ...)` + `EXTENDS` edges
7. Scan `agents/*.md` frontmatter → `CREATE (:Agent ...)` + `DISPATCHES` edges (parse `tools:` for `Agent` refs) + dual `:Agent:Reviewer` labels for review agents
8. Scan `shared/*.md` → `CREATE (:SharedContract ...)`
9. Parse `modules/frameworks/*/rules-override.json` → `CREATE (:CheckRule ...)` + `OVERRIDES_RULE`
10. Map `shared/learnings/*.md` → `CREATE (:Learnings ...)` + `HAS_LEARNINGS`
11. Read `canonical-pairings.json` → `CANONICAL_TESTING` + `CANONICAL_PERSISTENCE` edges

Interface:
```bash
./shared/graph/generate-seed.sh              # writes to shared/graph/seed.cypher
./shared/graph/generate-seed.sh --dry-run    # prints to stdout (for test comparison)
```

Script must be `#!/usr/bin/env bash`, `chmod +x`, deterministic output (sorted), and use `PLUGIN_ROOT` as the base path (auto-detected from script location).

- [ ] **Step 2: Make it executable**

```bash
chmod +x shared/graph/generate-seed.sh
```

- [ ] **Step 3: Run it and verify output**

```bash
./shared/graph/generate-seed.sh --dry-run | head -30
# Verify: CREATE statements for Language, Framework, etc.
./shared/graph/generate-seed.sh --dry-run | grep -c "CREATE"
# Expect: 400+ CREATE statements (nodes + relationships)
```

- [ ] **Step 4: Generate the seed file**

```bash
./shared/graph/generate-seed.sh
cat shared/graph/seed.cypher | head -5
# Verify: file exists with Cypher content
```

- [ ] **Step 5: Commit**

```bash
git add shared/graph/generate-seed.sh shared/graph/seed.cypher
git commit -m "feat(graph): add generate-seed.sh and initial seed.cypher"
```

---

### Task 3: Write seed validation tests

**Files:**
- Create: `tests/contract/graph-seed.bats`

- [ ] **Step 1: Write the test file**

Tests to implement:
1. `seed-freshness`: Run `generate-seed.sh --dry-run`, compare hash against committed `seed.cypher`
2. `node-coverage`: For every `modules/languages/*.md`, assert a `CREATE (:Language {name: '...'` line exists in seed. Same for frameworks, testing, all layer modules.
3. `edge-integrity`: For every `EXTENDS` edge, assert both the source `FrameworkBinding` and target `LayerModule` have corresponding `CREATE` nodes.
4. `agent-coverage`: For every `agents/*.md`, assert a `CREATE (:Agent` line exists.
5. `learnings-coverage`: For every `shared/learnings/*.md`, assert a `CREATE (:Learnings` line exists.

Use `load '../helpers/test-helpers'` and reference `$PLUGIN_ROOT`.

- [ ] **Step 2: Run the tests**

```bash
bats tests/contract/graph-seed.bats
```
Expected: All pass.

- [ ] **Step 3: Commit**

```bash
git add tests/contract/graph-seed.bats
git commit -m "test(graph): add seed validation contract tests"
```

---

### Task 4: Write `dependency-map.json` validation test

**Files:**
- Create: `tests/unit/dependency-map.bats`

- [ ] **Step 1: Write the test file**

Tests:
1. `dependency-map.json is valid JSON`: Parse with `python3 -m json.tool`.
2. `all mapped module names reference existing modules`: For each value in every package manager key, assert `modules/{layer}/{value}.md` exists for at least one layer directory. Use a helper that searches across all layer directories.
3. `canonical-pairings.json is valid JSON`: Parse with `python3 -m json.tool`.
4. `canonical testing pairings reference existing modules`: For each value in `canonical_testing`, assert `modules/testing/{value}.md` exists.
5. `canonical persistence pairings reference existing modules`: For each value in `canonical_persistence`, search across all persistence-related directories (`modules/persistence/`, `modules/frameworks/*/persistence/`) for a file matching the name. Some canonical pairings (e.g., `eloquent`) may not have a standalone module yet — the test should warn but not fail for missing entries, only fail if the JSON is malformed.

- [ ] **Step 2: Write query-patterns validation test**

Create `tests/unit/query-patterns.bats`:
1. `query-patterns.md exists`: Assert `shared/graph/query-patterns.md` exists and is non-empty.
2. `all Cypher blocks have valid syntax`: Extract all ` ```cypher ` blocks, check each contains `MATCH` or `CREATE` and has balanced parentheses/brackets. (Full Cypher syntax validation requires Neo4j — this is a lightweight structural check.)

- [ ] **Step 3: Run the tests**

```bash
bats tests/unit/dependency-map.bats tests/unit/query-patterns.bats
```
Expected: All pass.

- [ ] **Step 4: Commit**

```bash
git add tests/unit/dependency-map.bats tests/unit/query-patterns.bats
git commit -m "test(graph): add dependency-map and query-patterns validation tests"
```

---

### Task 5: Write `build-project-graph.sh` — project codebase graph builder

**Files:**
- Create: `shared/graph/build-project-graph.sh`

- [ ] **Step 1: Write the project graph builder**

The script takes a `--project-root` argument and outputs Cypher statements to stdout. Steps:
1. Detect language from manifest files (package.json → typescript, build.gradle.kts → kotlin, etc.)
2. Walk source directories via `git ls-files` (respects .gitignore) → `CREATE (:ProjectFile ...)` nodes
3. Parse imports per language using regex — **best-effort, partial resolution only**:
   - TypeScript/JavaScript: `import ... from './relative/path'` — resolve relative imports to files. Skip `node_modules` imports (those become `ProjectDependency` nodes instead).
   - Python: `from myapp.services import X` — convert dot-notation to path, resolve against project root. Skip stdlib imports.
   - Kotlin/Java: `import com.example.foo.Bar` — convert package to path using `src/main/kotlin/` or `src/main/java/` base. JVM imports that don't resolve to project files are silently skipped.
   - Go: `import "myproject/internal/repo"` — resolve against `go.mod` module path. Skip stdlib and external modules.
   - Ruby/PHP/Elixir/Scala/Rust/C/C++/Swift/Dart/C#: Extract import statements via regex. Attempt file resolution where path mapping is straightforward (relative imports, PSR-4 for PHP). **Skip unresolvable imports** — the graph will be incomplete for complex resolution cases (Scala SBT multi-module, Swift module maps) but still useful for the imports that do resolve.
4. For resolved imports, create `IMPORTS` edges. Unresolvable imports are logged to `.pipeline/graph/.unresolved-imports.log` for debugging but do not cause failures.
5. Create `(:ProjectPackage)` nodes from directory structure
6. Parse dependency manifests → `(:ProjectDependency)` nodes with `MAPS_TO` edges using `dependency-map.json`
7. Read `dev-pipeline.local.md` (if exists) → `USES_CONVENTION` edges
8. Write SHA to `.pipeline/graph/.last-build-sha`

Interface:
```bash
./shared/graph/build-project-graph.sh --project-root /path/to/project
# Outputs Cypher to stdout, writes .last-build-sha
```

- [ ] **Step 2: Make it executable**

```bash
chmod +x shared/graph/build-project-graph.sh
```

- [ ] **Step 3: Commit**

```bash
git add shared/graph/build-project-graph.sh
git commit -m "feat(graph): add build-project-graph.sh for consuming project graph"
```

---

### Task 6: Write `incremental-update.sh` and `enrich-symbols.sh`

**Files:**
- Create: `shared/graph/incremental-update.sh`
- Create: `shared/graph/enrich-symbols.sh`

- [ ] **Step 1: Write incremental-update.sh**

Reads `.pipeline/graph/.last-build-sha`, runs `git diff --name-status` against it, and generates Cypher for:
- `A` (added): create node + parse imports
- `M` (modified): `DETACH DELETE` old edges, re-create with updated imports
- `D` (deleted): `DETACH DELETE` node
- `R` (renamed): update `path` property

Falls back to full `build-project-graph.sh` if no `.last-build-sha` exists.

Interface:
```bash
./shared/graph/incremental-update.sh --project-root /path/to/project
# Outputs Cypher to stdout
```

- [ ] **Step 2: Write enrich-symbols.sh**

Takes a list of files as arguments. For each file, extracts classes/interfaces/functions using **regex only** (tree-sitter is out of scope — this is a bash-only plugin). Language-specific patterns:
- Kotlin/Java: `class Foo`, `interface Bar`, `fun baz(`, `object Qux`
- TypeScript: `class Foo`, `interface Bar`, `function baz`, `export const`
- Python: `class Foo`, `def bar(`
- Go: `type Foo struct`, `func Bar(`
- Rust: `struct Foo`, `impl Foo`, `fn bar(`
- (etc. for other languages)

Creates `(:ProjectClass)` and `(:ProjectFunction)` nodes with `CLASS_IN_FILE` and `FUNCTION_IN_CLASS` edges. Also detects `extends`/`implements` keywords for `EXTENDS_CLASS`/`IMPLEMENTS` edges.

Interface:
```bash
./shared/graph/enrich-symbols.sh --project-root /path/to/project file1.kt file2.ts
# Outputs Cypher to stdout
```

- [ ] **Step 3: Make both executable**

```bash
chmod +x shared/graph/incremental-update.sh shared/graph/enrich-symbols.sh
```

- [ ] **Step 4: Commit**

```bash
git add shared/graph/incremental-update.sh shared/graph/enrich-symbols.sh
git commit -m "feat(graph): add incremental-update and enrich-symbols scripts"
```

---

### Task 7: Write `neo4j-health.sh` and Docker Compose template

**Files:**
- Create: `shared/graph/neo4j-health.sh`
- Create: `shared/graph/docker-compose.neo4j.yml`

- [ ] **Step 1: Write neo4j-health.sh**

Checks if the `pipeline-neo4j` Docker container is running and healthy. Returns exit code 0 if healthy, 1 if not. Outputs JSON status:
```json
{"available": true, "container": "running", "bolt_port": 7687}
```
or
```json
{"available": false, "reason": "container not running"}
```

- [ ] **Step 2: Write docker-compose.neo4j.yml**

Copy the Docker Compose template from spec (lines 90-116). This is a template that `graph-init` copies to `.pipeline/docker-compose.neo4j.yml` in the consuming project.

- [ ] **Step 3: Make health script executable**

```bash
chmod +x shared/graph/neo4j-health.sh
```

- [ ] **Step 4: Commit**

```bash
git add shared/graph/neo4j-health.sh shared/graph/docker-compose.neo4j.yml
git commit -m "feat(graph): add Neo4j health check and Docker Compose template"
```

---

### Task 8: Write query-patterns.md

**Files:**
- Create: `shared/graph/query-patterns.md`

- [ ] **Step 1: Write the query patterns reference**

Copy all 7 Cypher query patterns from the spec (lines 317-374): Stack Resolution, Impact Analysis (2 variants), Gap Detection (2 variants), Recommendation, Scope Analysis, Plugin Impact Analysis.

Add a header explaining this is a reference for the orchestrator's `graph_context` pre-queries.

- [ ] **Step 2: Commit**

```bash
git add shared/graph/query-patterns.md
git commit -m "docs(graph): add Cypher query patterns reference for agents"
```

---

### Task 9: Create graph skills (graph-init, graph-status, graph-query, graph-rebuild)

**Files:**
- Create: `skills/graph-init/SKILL.md`
- Create: `skills/graph-status/SKILL.md`
- Create: `skills/graph-query/SKILL.md`
- Create: `skills/graph-rebuild/SKILL.md`

- [ ] **Step 1: Write graph-init skill**

The skill must:
1. Check Docker is available (`docker info`)
2. Copy `docker-compose.neo4j.yml` to `.pipeline/docker-compose.neo4j.yml` (with port substitution from config)
3. Start the container (`docker compose -f .pipeline/docker-compose.neo4j.yml up -d`)
4. Wait for health (`neo4j-health.sh`)
5. Import seed (`cat shared/graph/seed.cypher | docker exec -i pipeline-neo4j cypher-shell -u neo4j -p pipeline-local`)
6. Build project graph (`build-project-graph.sh --project-root . | docker exec -i pipeline-neo4j cypher-shell -u neo4j -p pipeline-local`)
7. Inject Neo4j MCP config into `.mcp.json` (merge, don't overwrite)
8. Update `state.json` with `integrations.neo4j.available: true`

Must be idempotent (skip steps already done). Must handle errors gracefully (report and set `available: false`).

Frontmatter: `name: graph-init`, `description: Initialize Neo4j knowledge graph...`

- [ ] **Step 2: Write graph-status skill**

Query Neo4j for node/relationship counts per label, show `.last-build-sha`, container health, enrichment coverage.

- [ ] **Step 3: Write graph-query skill**

Accept a Cypher query as argument, execute via `cypher-shell`, return formatted results.

- [ ] **Step 4: Write graph-rebuild skill**

Drop all `ProjectFile`, `ProjectClass`, `ProjectFunction`, `ProjectPackage`, `ProjectDependency` nodes. Re-run `build-project-graph.sh`. Keep plugin graph (seed) intact.

- [ ] **Step 5: Commit**

```bash
git add skills/graph-init/SKILL.md skills/graph-status/SKILL.md skills/graph-query/SKILL.md skills/graph-rebuild/SKILL.md
git commit -m "feat(graph): add graph-init, graph-status, graph-query, graph-rebuild skills"
```

---

### Task 10: Write graceful-degradation scenario test

**Files:**
- Create: `tests/scenario/graph-degradation.bats`

- [ ] **Step 1: Write the test file**

Tests:
1. `neo4j-health.sh returns available:false when no container running`: Run health check without Docker container. Expect exit code 1, JSON with `available: false`.
2. `incremental-update.sh produces no output when neo4j unavailable`: Run with `--project-root` pointing to temp dir, no Neo4j. Expect empty output or graceful skip message.
3. `generate-seed.sh works without Neo4j`: Run seed generator. Expect valid Cypher output (it doesn't need Neo4j to generate — it only scans files).

- [ ] **Step 2: Run tests**

```bash
bats tests/scenario/graph-degradation.bats
```
Expected: All pass (these tests don't need Neo4j running).

- [ ] **Step 3: Commit**

```bash
git add tests/scenario/graph-degradation.bats
git commit -m "test(graph): add graceful-degradation scenario tests"
```

---

### Task 11: Wire graph into pipeline — orchestrator, state schema, pipeline-init, pipeline-reset

**Files:**
- Modify: `agents/pl-100-orchestrator.md`
- Modify: `shared/state-schema.md`
- Modify: `skills/pipeline-init/SKILL.md`
- Modify: `skills/pipeline-reset/SKILL.md`

- [ ] **Step 1: Add neo4j-mcp to orchestrator tools**

In `agents/pl-100-orchestrator.md`, add `neo4j-mcp` to the `tools:` frontmatter list (conditional — only used if `integrations.neo4j.available` is true in state).

Add a new section documenting graph_context pre-queries at each stage boundary (from spec lines 381-387).

- [ ] **Step 2: Add neo4j to state-schema.md integrations**

In the `integrations` object documentation, add:
```
"neo4j": { "available": false, "last_build_sha": "", "node_count": 0 }
```

- [ ] **Step 3: Add graph-init call to pipeline-init**

In `skills/pipeline-init/SKILL.md`, add a conditional step after config generation:
```
If graph.enabled is true in dev-pipeline.local.md:
  Invoke /graph-init to set up Neo4j knowledge graph
```

- [ ] **Step 4: Add graph cleanup to pipeline-reset**

In `skills/pipeline-reset/SKILL.md`, add Docker cleanup **before** the existing `rm -rf .pipeline/` step (otherwise the container and volume are orphaned):
```
# Add BEFORE the existing rm -rf .pipeline/ step:
If .pipeline/docker-compose.neo4j.yml exists:
  docker compose -f .pipeline/docker-compose.neo4j.yml down -v
# Then the existing rm -rf .pipeline/ handles the rest
```

- [ ] **Step 5: Commit**

```bash
git add agents/pl-100-orchestrator.md shared/state-schema.md skills/pipeline-init/SKILL.md skills/pipeline-reset/SKILL.md
git commit -m "feat(graph): wire Neo4j into orchestrator, state schema, pipeline-init/reset"
```

---

### Task 12: Add graph config to framework local-templates and update CLAUDE.md

**Files:**
- Modify: `modules/frameworks/*/local-template.md` (all 21)
- Modify: `CLAUDE.md`

- [ ] **Step 1: Add `graph:` section to all 21 local-template.md files**

Append to each local-template.md (opt-in, disabled by default):
```yaml
graph:
  enabled: false          # set to true to enable Neo4j knowledge graph
  enrich_symbols: true
  neo4j_port: 7687
  neo4j_http_port: 7474
```

Use a script to batch-update all 21 files.

- [ ] **Step 2: Update CLAUDE.md**

Add to Architecture section (after Integrations):
```markdown
### Knowledge Graph (optional, `graph:` in `dev-pipeline.local.md`)

Neo4j-based knowledge graph mapping plugin modules and consuming project codebases. Enables impact analysis, convention stack resolution, gap detection, and recommendation queries. Docker-managed in `.pipeline/`, accessed via Neo4j MCP. Opt-in — set `graph.enabled: true` in local config. See `shared/graph/query-patterns.md` for Cypher templates.
```

Add `graph-init`, `graph-status`, `graph-query`, `graph-rebuild` to the Skills list.

Add `shared/graph/` description to the Architecture section.

- [ ] **Step 3: Commit**

```bash
git add modules/frameworks/*/local-template.md CLAUDE.md
git commit -m "feat(graph): add graph config to all local-templates and document in CLAUDE.md"
```

---

### Task 13: Add git pre-commit hook for seed regeneration

**Files:**
- Create: `.githooks/pre-commit`

- [ ] **Step 1: Write the pre-commit hook**

```bash
#!/usr/bin/env bash
# Regenerate seed.cypher when plugin modules change
if git diff --cached --name-only | grep -qE '^(modules|agents|shared)/'; then
  if [ -x "./shared/graph/generate-seed.sh" ]; then
    ./shared/graph/generate-seed.sh
    git add shared/graph/seed.cypher
  fi
fi
```

- [ ] **Step 2: Make it executable**

```bash
chmod +x .githooks/pre-commit
```

- [ ] **Step 3: Document in CONTRIBUTING.md or CLAUDE.md**

Add a note about configuring the git hooks path:
```bash
git config core.hooksPath .githooks
```

- [ ] **Step 4: Commit**

```bash
git add .githooks/pre-commit
git commit -m "feat(graph): add pre-commit hook for automatic seed regeneration"
```

---

### Task 14: Run full test suite and final validation

**Files:** None (validation only)

- [ ] **Step 1: Run structural tests**

```bash
./tests/run-all.sh structural
```
Expected: All pass (28+ checks).

- [ ] **Step 2: Run contract tests (including new graph-seed.bats)**

```bash
./tests/run-all.sh contract
```
Expected: All pass (previous 95 + new graph tests).

- [ ] **Step 3: Run unit tests (including new dependency-map.bats)**

```bash
./tests/run-all.sh unit
```
Expected: All pass.

- [ ] **Step 4: Run scenario tests (including new graph-degradation.bats)**

```bash
./tests/run-all.sh scenario
```
Expected: All pass.

- [ ] **Step 5: Run full suite**

```bash
./tests/run-all.sh
```
Expected: `All tiers passed.`

- [ ] **Step 6: Verify seed.cypher is up-to-date**

```bash
./shared/graph/generate-seed.sh --dry-run | shasum
shasum shared/graph/seed.cypher
# Hashes should match
```

- [ ] **Step 7: Final commit if any fixes needed**

```bash
# Stage only the specific files that needed fixes
git add <fixed-files> && git commit -m "fix: final validation fixes for Neo4j knowledge graph"
```
