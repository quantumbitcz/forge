# Phase 1: Crosscutting Module Architecture — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the module system to support 11 new crosscutting convention layers (database, persistence, migrations, api-protocols, messaging, caching, search, storage, auth, observability) and multi-service monorepo configs — without creating any actual module content yet.

**Architecture:** The existing `components:` config gains optional fields for each new layer. PREFLIGHT auto-derives convention paths from field values. The check engine caches merged rules per component at PREFLIGHT time. State schema bumps to v1.1.0 (additive, non-breaking).

**Tech Stack:** Bash (check engine, validation), Markdown (agent instructions, contracts, docs)

**Spec:** `docs/superpowers/specs/2026-03-24-crosscutting-modules-design.md`

---

### Task 1: Create Module Layer Directory Skeleton

**Files:**
- Create: `modules/databases/.gitkeep`
- Create: `modules/persistence/.gitkeep`
- Create: `modules/migrations/.gitkeep`
- Create: `modules/api-protocols/.gitkeep`
- Create: `modules/messaging/.gitkeep`
- Create: `modules/caching/.gitkeep`
- Create: `modules/search/.gitkeep`
- Create: `modules/storage/.gitkeep`
- Create: `modules/auth/.gitkeep`
- Create: `modules/observability/.gitkeep`

- [ ] **Step 1: Create all 10 new layer directories with .gitkeep**

```bash
for layer in databases persistence migrations api-protocols messaging caching search storage auth observability; do
  mkdir -p "modules/$layer"
  touch "modules/$layer/.gitkeep"
done
```

- [ ] **Step 2: Verify directory structure**

Run: `ls -d modules/*/`
Expected: 13 directories (languages, frameworks, testing + 10 new)

- [ ] **Step 3: Commit**

```bash
git add modules/databases modules/persistence modules/migrations modules/api-protocols modules/messaging modules/caching modules/search modules/storage modules/auth modules/observability
git commit -m "chore: create empty module layer directories for crosscutting concerns"
```

---

### Task 2: Update State Schema to v1.1.0

**Files:**
- Modify: `shared/state-schema.md`

- [ ] **Step 1: Read the current state-schema.md**

Read `shared/state-schema.md` fully. Identify:
- The `version` field documentation (line ~152)
- The `components` field documentation (line ~60-79)
- The `detected_versions` field documentation (line ~134-140)

- [ ] **Step 2: Update the version field documentation**

Change the version field description from `"1.0.0"` to `"1.1.0"`. Add a note: "v1.1.0 extends v1.0.0 with `convention_stack` arrays per component and `key_dependencies` in `detected_versions`. Old v1.0.0 state files are forward-compatible — missing fields default to empty."

- [ ] **Step 3: Extend the `components` schema**

Add documentation for new optional fields per component entry:

```json
"components": {
  "backend": {
    "path": "services/user-service",
    "convention_stack": [
      "modules/languages/kotlin.md",
      "modules/frameworks/spring/conventions.md",
      "modules/frameworks/spring/variants/kotlin.md",
      "modules/databases/postgresql.md",
      "modules/frameworks/spring/databases/postgresql.md",
      "modules/persistence/exposed.md",
      "modules/frameworks/spring/persistence/exposed.md",
      "modules/messaging/kafka.md",
      "modules/frameworks/spring/messaging/kafka.md",
      "modules/testing/kotest.md",
      "modules/frameworks/spring/testing/kotest.md"
    ],
    "story_state": "PREFLIGHT",
    "conventions_hash": "",
    "conventions_section_hashes": {},
    "detected_versions": {
      "language_version": "2.1.0",
      "framework_version": "3.4.1"
    }
  }
}
```

Document `convention_stack` as: "Array of resolved convention file paths in composition order. Populated by PREFLIGHT. Empty array if not yet resolved."

Document `path` as: "Relative path prefix for this component. Used by the check engine for per-file convention routing. Required in multi-service mode. Defaults to project root in single-service mode."

- [ ] **Step 4: Extend the `detected_versions` schema**

Document that `key_dependencies` is a map of dependency-name → version-string for all detected libraries across all layers:

```json
"detected_versions": {
  "language": "kotlin",
  "language_version": "2.1.0",
  "framework": "spring",
  "framework_version": "3.4.1",
  "key_dependencies": {
    "exposed-core": "0.48.0",
    "kafka-clients": "3.7.0",
    "flyway-core": "10.8.1",
    "caffeine": "3.1.8"
  }
}
```

- [ ] **Step 5: Commit**

```bash
git add shared/state-schema.md
git commit -m "docs(shared): bump state schema to v1.1.0 with convention_stack and key_dependencies"
```

---

### Task 3: Extend PREFLIGHT Convention Resolution in Orchestrator

**Files:**
- Modify: `agents/pl-100-orchestrator.md` (Section 3.5b, ~lines 329-390)

- [ ] **Step 1: Read the orchestrator's PREFLIGHT section**

Read `agents/pl-100-orchestrator.md` lines 168-540 (Stage 0: PREFLIGHT). Identify Section 3.5b "Multi-Component Convention Resolution" (~line 329).

- [ ] **Step 2: Define the 11 optional layer fields**

Add a reference table after the existing convention resolution steps:

```markdown
### Optional Layer Fields in `components:`

| Field | Module Directory | Binding Directory |
|-------|-----------------|-------------------|
| `database` | `modules/databases/{value}.md` | `modules/frameworks/{fw}/databases/{value}.md` |
| `persistence` | `modules/persistence/{value}.md` | `modules/frameworks/{fw}/persistence/{value}.md` |
| `migrations` | `modules/migrations/{value}.md` | `modules/frameworks/{fw}/migrations/{value}.md` |
| `api_protocol` | `modules/api-protocols/{value}.md` | `modules/frameworks/{fw}/api-protocols/{value}.md` |
| `messaging` | `modules/messaging/{value}.md` | `modules/frameworks/{fw}/messaging/{value}.md` |
| `caching` | `modules/caching/{value}.md` | `modules/frameworks/{fw}/caching/{value}.md` |
| `search` | `modules/search/{value}.md` | `modules/frameworks/{fw}/search/{value}.md` |
| `storage` | `modules/storage/{value}.md` | `modules/frameworks/{fw}/storage/{value}.md` |
| `auth` | `modules/auth/{value}.md` | `modules/frameworks/{fw}/auth/{value}.md` |
| `observability` | `modules/observability/{value}.md` | `modules/frameworks/{fw}/observability/{value}.md` |
```

- [ ] **Step 3: Extend the convention resolution algorithm**

After the existing 5 resolution steps (language, framework, variant, framework-testing, generic-testing), add:

```markdown
6. **Optional layer resolution:** For each optional field present in the component config (`database`, `persistence`, `migrations`, `api_protocol`, `messaging`, `caching`, `search`, `storage`, `auth`, `observability`):
   a. Generic module: `${CLAUDE_PLUGIN_ROOT}/modules/{layer}/{value}.md` — add to stack if file exists.
   b. Framework binding: `${CLAUDE_PLUGIN_ROOT}/modules/frameworks/{framework}/{layer}/{value}.md` — add to stack if file exists.

   Files that do not exist are silently skipped (layers are populated incrementally across phases).
```

- [ ] **Step 4: Add layer combination validation**

After convention resolution, add:

```markdown
7. **Layer combination validation:** Check for nonsensical configurations and log WARNINGs (do not block):
   - Frontend frameworks (react, nextjs, sveltekit, svelte, angular, vue) with `database:` or `persistence:` → WARN
   - SQL persistence (hibernate, jooq, exposed, sqlalchemy, prisma, typeorm, drizzle, django-orm) with document database (mongodb, dynamodb, cassandra) → WARN
   - Mobile frameworks (swiftui, jetpack-compose) with `messaging:` → WARN
   - Infra frameworks (k8s) with any layer except `observability:` → WARN
```

- [ ] **Step 5: Add config mode detection**

Add before the convention resolution section:

```markdown
### 3.5a Config Mode Detection

Detect whether `components:` is flat (single-service) or nested (multi-service):
- **Flat mode:** `components:` contains scalar fields (`language`, `framework`, etc.). Wrap in a default component named after `project_type` (e.g., `backend`).
- **Multi-service mode:** `components:` contains named entries, each with a `path:` field. Resolve each component independently.

Both modes produce the same `state.json.components` structure with named entries.
```

- [ ] **Step 6: Add PREFLIGHT rule cache generation**

Add after convention resolution:

```markdown
### 3.5c Check Engine Rule Cache

After resolving all convention stacks, generate per-component rule caches for the check engine:

1. For each component, collect all `rules-override.json` files from the convention stack:
   - Framework: `modules/frameworks/{fw}/rules-override.json`
   - Each active layer binding: `modules/frameworks/{fw}/{layer}/{value}.rules-override.json` (if exists)
   - Each active generic layer: `modules/{layer}/{value}.rules-override.json` (if exists)
2. Deep-merge all collected rules (later layers override earlier ones).
3. Write merged result to `.pipeline/.rules-cache-{component}.json`.
4. Write component path mapping to `.pipeline/.component-cache` (format: `path_prefix=component_name`).
```

- [ ] **Step 7: Commit**

```bash
git add agents/pl-100-orchestrator.md
git commit -m "feat(agents): extend orchestrator PREFLIGHT with crosscutting layer resolution"
```

---

### Task 4: Update Check Engine for Multi-Layer Rule Loading

**Files:**
- Modify: `shared/checks/engine.sh` (resolve_component function, ~lines 95-262)

- [ ] **Step 1: Read the current engine.sh**

Read `shared/checks/engine.sh` fully. Identify `resolve_component()` (lines 95-262) and `run_layer1()` (lines 264-278).

- [ ] **Step 2: Update resolve_component() to return component name**

Currently returns a framework name. Change to return the component name from `.pipeline/.component-cache`:
- Cache format changes from `path_prefix=framework` to `path_prefix=component_name`.
- The function returns the component name (e.g., `backend`, `user-service`).

- [ ] **Step 3: Update run_layer1() to load cached rules**

Currently loads a single `rules-override.json` from the framework module. Change to:
1. Get component name from `resolve_component()`.
2. If `.pipeline/.rules-cache-{component}.json` exists, load it.
3. Otherwise, fall back to framework `rules-override.json` (backward compatibility).

- [ ] **Step 4: Test the engine changes**

Run: `shared/checks/test-engine.sh`
Expected: All existing tests pass (the cached rules file does not exist in the test fixture, so fallback behavior is exercised).

- [ ] **Step 5: Commit**

```bash
git add shared/checks/engine.sh
git commit -m "feat(checks): update engine to load per-component cached rules"
```

---

### Task 5: Update Stage Contract

**Files:**
- Modify: `shared/stage-contract.md` (Stage 0: PREFLIGHT section, ~lines 28-60)

- [ ] **Step 1: Read the current stage-contract.md**

Read `shared/stage-contract.md`. Identify Stage 0: PREFLIGHT section.

- [ ] **Step 2: Extend PREFLIGHT actions**

Add to the PREFLIGHT Actions list:

```markdown
8. Detect config mode (flat vs. multi-service components:)
9. Resolve convention stacks per component (language, framework, variant, testing + optional layers)
10. Run layer combination validation, log warnings
11. Detect versions for all layers from manifest files, store in detected_versions.key_dependencies
12. Generate per-component rule cache (.pipeline/.rules-cache-{component}.json)
13. Write component path mapping (.pipeline/.component-cache)
```

- [ ] **Step 3: Update exit condition**

Extend exit condition from "Config loaded, state initialized" to:
"Config loaded, convention stacks resolved per component, rule caches generated, state initialized."

- [ ] **Step 4: Commit**

```bash
git add shared/stage-contract.md
git commit -m "docs(shared): extend PREFLIGHT contract with crosscutting layer resolution"
```

---

### Task 6: Update Structural Validation

**Files:**
- Modify: `tests/validate-plugin.sh`

- [ ] **Step 1: Read the current validate-plugin.sh**

Read `tests/validate-plugin.sh` fully. Identify the FRAMEWORKS array and module directory checks.

- [ ] **Step 2: Add new layer directory checks**

After the existing framework/language/testing validation, add:

```bash
# --- CROSSCUTTING LAYERS ---
echo ""
echo "--- CROSSCUTTING LAYERS ---"

LAYERS=(databases persistence migrations api-protocols messaging caching search storage auth observability)

# Check layer directories exist
check28_fail=0
for layer in "${LAYERS[@]}"; do
  if [[ ! -d "$ROOT/modules/$layer" ]]; then
    echo "    Missing layer directory: modules/$layer"
    check28_fail=1
  fi
done
check "All crosscutting layer directories exist" "$check28_fail"
```

- [ ] **Step 3: Update the total check count in the header comment**

Change "27 checks" to "28 checks" (or however many checks exist after the addition).

- [ ] **Step 4: Run validation to confirm**

Run: `./tests/validate-plugin.sh`
Expected: All checks pass including the new one.

- [ ] **Step 5: Commit**

```bash
git add tests/validate-plugin.sh
git commit -m "test: add structural validation for crosscutting layer directories"
```

---

### Task 7: Update CLAUDE.md

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Read the current CLAUDE.md**

Read `CLAUDE.md` fully. Identify the Architecture section, the module composition order, and the "Adding a new framework" section.

- [ ] **Step 2: Update the Architecture section**

In the three-layer architecture description, add the new module sublayers:

```markdown
2. **Module layer** (`modules/`) — five sublayers for convention composition:
   - `modules/languages/` — 9 language files
   - `modules/frameworks/` — 21 framework directories (17 existing + 4 planned)
   - `modules/testing/` — 11 generic testing framework files
   - `modules/databases/` — database engine best practices (PostgreSQL, MySQL, MongoDB, etc.)
   - `modules/persistence/` — ORM/mapping patterns (Hibernate, Exposed, Prisma, etc.)
   - `modules/migrations/` — schema migration tool patterns (Flyway, Alembic, etc.)
   - `modules/api-protocols/` — API protocol patterns (REST, GraphQL, gRPC, WebSocket)
   - `modules/messaging/` — event-driven patterns (Kafka, RabbitMQ, etc.)
   - `modules/caching/` — cache strategy patterns (Redis, Caffeine, etc.)
   - `modules/search/` — full-text search patterns (Elasticsearch, etc.)
   - `modules/storage/` — object storage patterns (S3, GCS, etc.)
   - `modules/auth/` — authentication/authorization patterns (OAuth2, JWT, etc.)
   - `modules/observability/` — metrics, tracing, logging patterns (OTLP, Micrometer, etc.)
```

- [ ] **Step 3: Update the convention composition order**

Change from:
```
variant > framework-testing > framework > language > testing
```

To:
```
variant > framework-binding > framework > language > generic-layer > testing
```

Add note: "framework-testing is a specific case of framework-binding. All framework subdirectory bindings (testing/, persistence/, messaging/, etc.) share the same precedence level."

- [ ] **Step 4: Add "Adding a new layer module" section**

After the existing "Adding a new framework" section, add:

```markdown
## Adding a new layer module

Create `modules/{layer}/{name}.md` with the standard structure (Overview, Architecture Patterns, Configuration, Performance, Security, Testing, Dos, Don'ts). Optionally add `{name}.rules-override.json` and `{name}.known-deprecations.json`.

Create framework bindings under `modules/frameworks/{fw}/{layer}/{name}.md` for each applicable framework (see the binding matrix in the design spec).

Add a learnings file at `shared/learnings/{name}.md`.
```

- [ ] **Step 5: Update the components: documentation**

Add documentation for the new optional fields in `components:`:

```markdown
- `components:` structure supports optional crosscutting layer fields: `database`, `persistence`, `migrations`, `api_protocol`, `messaging`, `caching`, `search`, `storage`, `auth`, `observability`. All are optional — omit to skip the layer.
- Multi-service mode: `components:` entries with `path:` fields for monorepo per-service stacks.
```

- [ ] **Step 6: Update the state schema reference**

Change state schema version from "1.0.0" to "1.1.0". **Important:** preserve the existing "v1.0.0 is a clean break" language (which refers to pre-1.0 → 1.0). Add: "v1.1.0 is an additive extension of v1.0.0 — no `/pipeline-reset` required. Missing fields default to empty."

- [ ] **Step 7: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md for crosscutting module layers and multi-service config"
```

---

### Task 8: Add Multi-Service Task Routing to Orchestrator

**Files:**
- Modify: `agents/pl-100-orchestrator.md` (PLAN, IMPLEMENT, and REVIEW stage sections)

- [ ] **Step 1: Read the PLAN stage section**

Read `agents/pl-100-orchestrator.md` Section 5 (Stage 2: PLAN). Identify how requirements are decomposed into tasks.

- [ ] **Step 2: Add multi-service task decomposition to PLAN**

Add after the existing plan decomposition instructions:

```markdown
### Multi-Service Task Decomposition

In multi-service mode (components with `path:` entries), the planner must:
1. Identify which services are affected by the requirement.
2. Create per-service tasks — each task targets exactly one service.
3. Tag each task with its `component` name (e.g., `component: user-service`).
4. Note cross-service dependencies in the task ordering (e.g., "payment-service event schema" must be defined before "notification-service consumer").
5. Shared libraries (`shared:` component) get their own tasks if the requirement affects them.
```

- [ ] **Step 3: Add per-service context to IMPLEMENT**

Read the IMPLEMENT section (~Section 7). Add:

```markdown
### Multi-Service Implementation Context

When dispatching implementers for multi-service tasks:
1. Set working directory context to the task's component `path:` (e.g., `services/user-service`).
2. Load the component's `convention_stack` from `state.json.components[task.component]`.
3. Pass the correct scaffolder patterns, build commands, and test commands for that component.
4. The implementer must not touch files outside its component's path unless the task explicitly spans components.
```

- [ ] **Step 4: Add per-file convention annotation to REVIEW**

Read the REVIEW section (~Section 9). Add:

```markdown
### Multi-Service Review Context

When dispatching quality gate reviewers:
1. For each changed file, resolve its owning component via path-prefix matching.
2. Annotate each file with its component's convention_stack in the dispatch prompt.
3. Reviewers apply the correct rules per file — a PR touching both Kotlin and TypeScript services gets the right conventions for each file.
4. Cross-service consistency checks: if the requirement spans services, verify event schemas match, API contracts align, and shared types are consistent.
```

- [ ] **Step 5: Add runtime convention lookup algorithm**

Add to the orchestrator's shared utilities section (or after PREFLIGHT):

```markdown
### Runtime Convention Lookup

When any stage needs conventions for a specific file path:
1. Match the file path against `state.json.components` entries by longest `path:` prefix match.
2. If matched: use that component's `convention_stack`.
3. If not matched: check for a `shared:` component. If present, use its stack.
4. If still not matched: use language-level conventions only (safe default).
```

- [ ] **Step 6: Commit**

```bash
git add agents/pl-100-orchestrator.md
git commit -m "feat(agents): add multi-service task routing to PLAN, IMPLEMENT, and REVIEW stages"
```

---

### Task 9: Update Deprecation Refresh Agent

**Files:**
- Modify: `agents/pl-140-deprecation-refresh.md`

- [ ] **Step 1: Read the current deprecation refresh agent**

Read `agents/pl-140-deprecation-refresh.md`. Identify the registry discovery section.

- [ ] **Step 2: Extend registry discovery to scan new layer paths**

Add to the discovery/scan instructions:

```markdown
### Extended Registry Discovery

In addition to scanning `modules/frameworks/{fw}/known-deprecations.json`, also scan:
1. Generic layer registries: `modules/{layer}/{value}.known-deprecations.json` for each active layer in the component's config.
2. Framework binding registries: `modules/frameworks/{fw}/{layer}/{value}.known-deprecations.json` for each active binding.

Discovery order: framework registry → binding registries → generic layer registries.

In multi-service mode, run discovery per-component using each component's detected versions for gating.
```

- [ ] **Step 3: Commit**

```bash
git add agents/pl-140-deprecation-refresh.md
git commit -m "feat(agents): extend deprecation refresh to scan crosscutting layer registries"
```

---

### Task 10: Document Convention Merge Semantics

**Files:**
- Modify: `shared/agent-communication.md`

- [ ] **Step 1: Read the current agent-communication.md**

Read `shared/agent-communication.md`. Identify where data flow contracts are documented.

- [ ] **Step 2: Add convention merge semantics section**

Add a new section:

```markdown
## Convention File Composition

When an agent receives a convention stack with both generic and framework-binding files for the same layer (e.g., `modules/persistence/exposed.md` + `modules/frameworks/spring/persistence/exposed.md`), compose them as follows:

- **Additive sections** (Dos, Don'ts, Patterns, Architecture Patterns): binding entries are appended to generic entries. Both apply.
- **Override sections** (Configuration, Integration Setup, Scaffolder Patterns): binding content replaces generic content for that section.
- **Contradiction rule:** when the binding explicitly contradicts the generic (e.g., different implementation strategy), the binding wins. When the binding adds without contradicting, both apply.

Agents read BOTH files: generic first (for foundational patterns), then binding (for framework-specific adaptations).
```

- [ ] **Step 3: Commit**

```bash
git add shared/agent-communication.md
git commit -m "docs(shared): add convention file composition semantics to agent communication"
```

---

### Task 11: Update CONTRIBUTING.md and README.md

**Files:**
- Modify: `CONTRIBUTING.md`
- Modify: `README.md`

- [ ] **Step 1: Update CONTRIBUTING.md**

Add a "Adding a new layer module" section after "Adding a new module":

```markdown
### Adding a new layer module (database, persistence, messaging, etc.)

1. Create `modules/{layer}/{name}.md` with the required structure (Overview, Architecture Patterns, Configuration, Performance, Security, Testing, Dos, Don'ts).
2. Optionally add `{name}.rules-override.json` and `{name}.known-deprecations.json` alongside the `.md` file.
3. Create framework bindings: `modules/frameworks/{fw}/{layer}/{name}.md` for each applicable framework.
4. Add `shared/learnings/{name}.md` for per-layer learnings.
5. Run `./tests/run-all.sh` to verify structural integrity.
```

- [ ] **Step 2: Update README.md**

In the "Available modules" section, add the new layer directories:

```markdown
10 crosscutting layer directories under `modules/` for databases, persistence, migrations, API protocols, messaging, caching, search, storage, auth, and observability. Each layer contains technology-specific best practices with optional framework bindings.
```

Update the file inventory `<details>` block to include the new directories.

- [ ] **Step 3: Commit**

```bash
git add CONTRIBUTING.md README.md
git commit -m "docs: update CONTRIBUTING.md and README.md for crosscutting module layers"
```

---

### Task 12: Run Full Test Suite and Verify

**Files:**
- None (verification only)

- [ ] **Step 1: Run structural validation**

Run: `./tests/validate-plugin.sh`
Expected: All checks pass (28+ checks).

- [ ] **Step 2: Run full test suite**

Run: `./tests/run-all.sh`
Expected: All tests pass (~248+ tests).

- [ ] **Step 3: Verify check engine**

Run: `shared/checks/engine.sh --dry-run`
Expected: Engine runs without errors.

- [ ] **Step 4: Verify no regressions with bash syntax check**

Run: `find shared/ hooks/ -name '*.sh' -exec bash -n {} \; -print`
Expected: All files print without errors.

- [ ] **Step 5: Final commit if any fixes needed**

```bash
# Stage only specific files that needed fixes
git add <specific-files>
git commit -m "fix: address test failures from Phase 1 architecture changes"
```

---

## Deferred to Later Phases

The following items from the spec are intentionally NOT in Phase 1:

- **`/pipeline-init` detection enhancement** (spec Section 12): detection of database, persistence, messaging dependencies. Deferred until Phase 2+ when actual module content exists.
- **Stricter validation** (spec Section 13.1): checking that each layer directory has at least one `.md` file. Deferred until Phase 2 populates the directories.
- **Local-template.md updates** with commented examples of new optional fields. Deferred until Phase 2 when the fields have actual module content to reference.
- **New framework modules** (Angular, NestJS, Vue/Nuxt, Svelte). Deferred to Phase 6.
- **Check engine test for new code path**: The `.rules-cache-{component}.json` loading path in `engine.sh` is not exercised by existing test fixtures. A test should be added when Phase 2 creates actual rule override files.

---

## Summary

| Task | What | Files |
|------|------|-------|
| 1 | Directory skeleton | 10 new dirs |
| 2 | State schema v1.1.0 | `shared/state-schema.md` |
| 3 | Orchestrator PREFLIGHT | `agents/pl-100-orchestrator.md` |
| 4 | Check engine | `shared/checks/engine.sh` |
| 5 | Stage contract | `shared/stage-contract.md` |
| 6 | Structural validation | `tests/validate-plugin.sh` |
| 7 | CLAUDE.md | `CLAUDE.md` |
| 8 | Multi-service task routing | `agents/pl-100-orchestrator.md` (PLAN, IMPLEMENT, REVIEW) |
| 9 | Deprecation refresh | `agents/pl-140-deprecation-refresh.md` |
| 10 | Convention merge semantics | `shared/agent-communication.md` |
| 11 | CONTRIBUTING + README | `CONTRIBUTING.md`, `README.md` |
| 12 | Verification | (run tests) |
