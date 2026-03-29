# Documentation Subsystem Design

**Date:** 2026-03-30
**Status:** Approved
**Scope:** New documentation subsystem for dev-pipeline — discovery, consistency validation, generation, graph integration, standalone tooling

---

## 1. Problem Statement

Documentation in the current pipeline is a verification-only afterthought. Stage 7 (DOCUMENTING) is handled inline by the orchestrator — it checks KDoc/TSDoc on public interfaces and proposes CLAUDE.md updates, but doesn't discover existing docs, validate code-docs consistency, or generate documentation. The knowledge graph has no documentation nodes. Pipeline-init detects OpenAPI specs but ignores all other documentation.

This leaves significant gaps:
- Agents implement without awareness of documented architectural decisions or constraints
- Code can silently contradict documented patterns with no detection
- No tooling to generate or maintain business, developer, or operational documentation
- Documentation is invisible to the knowledge graph — no impact analysis possible

## 2. Goals

1. **Documentation as context source** — discover and index project docs at PREFLIGHT so all downstream agents implement consistently with documented decisions
2. **Documentation as validation target** — detect when code changes contradict, invalidate, or leave stale any existing documentation
3. **Documentation generation** — generate full-spectrum docs (business, developer, operational) both during pipeline runs and on-demand
4. **Graph integration** — section-level and semantic-level documentation nodes in Neo4j with relationships to code entities
5. **Framework-aware** — documentation conventions and templates adapt to the project's tech stack
6. **Self-healing discovery** — new docs added after init are automatically picked up on next pipeline run

## 3. Architecture Overview

### New Components

| Component | Type | Location | Purpose |
|-----------|------|----------|---------|
| `pl-130-docs-discoverer` | Agent | `agents/` | PREFLIGHT — discovers, parses, and indexes documentation into the graph |
| `docs-consistency-reviewer` | Reviewer Agent | `agents/` | REVIEW — validates code-docs consistency, flags contradictions |
| `pl-350-docs-generator` | Agent | `agents/` | DOCUMENTING — generates and updates all documentation types |
| `/docs-generate` | Skill | `skills/docs-generate/` | On-demand documentation generation independent of pipeline |
| `modules/documentation/` | Module layer | `modules/documentation/` | Framework-aware doc conventions, templates, diagram patterns |
| Framework doc bindings | Module bindings | `modules/frameworks/*/documentation/` | Per-framework documentation style and templates |
| Graph schema extension | Contract | `shared/graph/schema.md` | `Doc*` node types and relationships |
| New query patterns | Contract | `shared/graph/query-patterns.md` | 5 documentation-specific Cypher queries |

### Pipeline Stage Integration

```
PREFLIGHT ──► pl-130-docs-discoverer
                │
                ▼ (doc context flows to all stages)
EXPLORE ──► explorers receive doc discovery summary
PLAN ──► planner receives DocDecision/DocConstraint for affected scope
         planner creates ADR sub-tasks for significant choices
VALIDATE ──► 7th perspective: Documentation Consistency
IMPLEMENT ──► implementers aware of documented constraints
REVIEW ──► docs-consistency-reviewer in quality gate batch 2
DOCUMENTING ──► pl-350-docs-generator (replaces inline logic)
SHIP ──► PR body includes Documentation Coverage section
LEARN ──► retrospective tracks doc generation effectiveness
```

---

## 4. Graph Schema Extension

### New Node Types (Project Codebase Layer)

| Label | Properties | Description |
|-------|-----------|-------------|
| `DocFile` | `path`, `format`, `doc_type`, `last_modified`, `title`, `cross_repo` | A documentation file. `cross_repo` (boolean, default `false`) is `true` for docs discovered in related projects. |
| `DocSection` | `name`, `file_path`, `heading_level`, `start_line`, `end_line`, `content_hash`, `content_hash_updated` | A section within a doc file (parsed from heading hierarchy). `content_hash_updated` is an ISO8601 timestamp of when the hash was last computed. |
| `DocDecision` | `id`, `file_path`, `summary`, `status`, `confidence`, `extracted_at` | Architectural/design decision extracted from ADRs or inline markers. `extracted_at` is ISO8601 timestamp of extraction. |
| `DocConstraint` | `id`, `file_path`, `summary`, `scope`, `confidence` | Constraint/rule extracted from documentation |
| `DocDiagram` | `path`, `format`, `diagram_type`, `source_file` | Generated or discovered diagram |

**`doc_type` values:** `readme`, `adr`, `architecture`, `api-spec`, `runbook`, `onboarding`, `design-doc`, `migration-guide`, `changelog`, `contributing`, `user-guide`, `business-spec`, `other`

**`format` values:** `markdown`, `openapi-yaml`, `openapi-json`, `asciidoc`, `rst`, `plaintext`, `external-ref`

**`confidence` values:** `HIGH` (explicit markers like ADR format), `MEDIUM` (heuristic extraction), `LOW` (weak pattern matches)

**`DocDecision.status` values:** `proposed`, `accepted`, `deprecated`, `superseded`. ADRs with explicit "Status:" headers are parsed directly. Decisions without explicit status default to `accepted`.

**Confidence upgrade mechanism:** LOW → MEDIUM when the same decision/constraint is extracted consistently across 3+ pipeline runs without user override. MEDIUM → HIGH when the user explicitly confirms via `/docs-generate --confirm-decisions` (interactive review of MEDIUM-confidence extractions). Users can also downgrade or dismiss via the same command. Confidence changes are logged in `generation_history`.

### New Relationships

| Relationship | Source → Target | Description |
|-------------|----------------|-------------|
| `DESCRIBES` | `DocSection` → `ProjectFile`/`ProjectPackage`/`ProjectClass` | Documentation describes a code entity |
| `SECTION_OF` | `DocSection` → `DocFile` | Section belongs to a document |
| `DECIDES` | `DocDecision` → `ProjectFile`/`ProjectPackage` | Decision applies to code scope |
| `CONSTRAINS` | `DocConstraint` → `ProjectFile`/`ProjectPackage`/`ProjectClass` | Constraint restricts code entity evolution |
| `CONTRADICTS` | `DocSection`/`DocDecision`/`DocConstraint` → `ProjectFile`/`ProjectClass` | Detected inconsistency (created by consistency reviewer) |
| `DIAGRAMS` | `DocDiagram` → `DocFile`/`ProjectPackage` | Diagram visualizes a doc or code structure |
| `SUPERSEDES` | `DocDecision` → `DocDecision` | Later decision replaces an earlier one |
| `DOC_IMPORTS` | `DocFile` → `DocFile` | Doc references another doc (cross-links) |

### New Cypher Query Patterns

**9. Documentation Impact** (PLAN stage):
```cypher
MATCH (changed:ProjectFile {path: $filePath})
MATCH (ds:DocSection)-[:DESCRIBES]->(changed)
MATCH (ds)-[:SECTION_OF]->(df:DocFile)
OPTIONAL MATCH (dd:DocDecision)-[:DECIDES]->(changed)
OPTIONAL MATCH (dc:DocConstraint)-[:CONSTRAINS]->(changed)
RETURN df.path, ds.name, dd.summary, dc.summary
```

**10. Stale Docs Detection** (REVIEW stage):
```cypher
MATCH (ds:DocSection)-[:DESCRIBES]->(pf:ProjectFile)
WHERE pf.last_modified > ds.content_hash_updated
RETURN ds.name, ds.file_path, pf.path AS stale_for_file
```

**11. Decision Traceability** (VALIDATE stage):
```cypher
MATCH (dd:DocDecision)-[:DECIDES]->(target)
WHERE target.path STARTS WITH $packagePath OR target.name = $className
OPTIONAL MATCH (dd)<-[:SUPERSEDES]-(newer:DocDecision)
WHERE newer IS NULL
RETURN dd.id, dd.summary, dd.status, dd.confidence, target.path
```

**12. Contradiction Report** (REVIEW stage):
```cypher
MATCH (source)-[:CONTRADICTS]->(target)
RETURN labels(source)[0] AS source_type, COALESCE(source.summary, source.name) AS source_desc,
       target.path AS code_target, source.file_path AS doc_source
```

**13. Documentation Coverage Gap** (DOCUMENTING stage):
```cypher
MATCH (pp:ProjectPackage)
WHERE NOT (pp)<-[:DESCRIBES]-(:DocSection)
RETURN pp.name, pp.path ORDER BY pp.path
```

---

## 5. Agent: `pl-130-docs-discoverer`

**Stage:** PREFLIGHT (dispatched after convention stack resolution, step 14)
**Tools:** `Read`, `Glob`, `Grep`, `Bash`

### PREFLIGHT Stage Contract Change

The current stage contract declares PREFLIGHT as "inline (orchestrator logic, no sub-agent dispatch)." This design changes PREFLIGHT to dispatch `pl-130-docs-discoverer` as a sub-agent, following the precedent set by Stage 5 (VERIFY) which also mixes inline logic with agent dispatch (inline Phase A + `pl-500-test-gate` Phase B). The stage contract overview table must be updated:

```
| 0 | PREFLIGHT | inline + `pl-130-docs-discoverer` | `PREFLIGHT` | ... | ... |
```

The discoverer is dispatched **after** all inline config resolution (steps 1-13) is complete, so it receives fully resolved config as input. This maintains the principle that PREFLIGHT config resolution is deterministic and inline — only the documentation discovery step is delegated.

### No-Graph Fallback

The discoverer operates in two modes depending on Neo4j availability:

1. **Graph mode** (Neo4j available): Full processing — creates `Doc*` nodes and relationships in the graph. All Cypher queries available to downstream agents.
2. **Index mode** (Neo4j unavailable): Writes `.pipeline/docs-index.json` — a flat JSON file containing the same data that would be in the graph (files, sections, decisions, constraints, linkages). Downstream agents read this file instead of querying Neo4j. The consistency reviewer and generator both support this fallback.

```json
{
  "files": [{ "path": "docs/architecture.md", "doc_type": "architecture", "format": "markdown", "title": "..." }],
  "sections": [{ "name": "Authentication", "file_path": "docs/architecture.md", "heading_level": 2, "content_hash": "..." }],
  "decisions": [{ "id": "ADR-001", "file_path": "docs/adr/001-use-rest.md", "summary": "...", "status": "accepted", "confidence": "HIGH" }],
  "constraints": [{ "id": "CONST-001", "file_path": "docs/architecture.md", "summary": "...", "scope": "src/domain/", "confidence": "MEDIUM" }],
  "linkages": [{ "source_type": "section", "source_id": "Authentication", "target_path": "src/auth/" }]
}
```

### Discovery Scope Limits

For large monorepos, unbounded `**/*.md` scanning can be expensive. Configurable limits:

```yaml
documentation:
  discovery:
    max_files: 500          # skip discovery with WARNING if exceeded
    max_file_size_kb: 512   # skip files larger than this
    exclude_patterns:        # additional glob exclusions beyond defaults
      - "vendor/**"
      - "third_party/**"
```

If `max_files` is exceeded, the discoverer logs WARNING with the count and skips. The user can raise the limit or add exclusions. Default exclusions always apply: `node_modules/`, `.pipeline/`, `build/`, `dist/`, `.git/`.

### Discovery Targets

| Category | Detection Method |
|----------|-----------------|
| Markdown docs | Glob `**/*.md` excluding `node_modules/`, `.pipeline/`, `build/`, `dist/`, vendor dirs |
| ADRs | Pattern: `adr/`, `docs/adr/`, `docs/decisions/`, files matching `NNN-*.md` or `ADR-*.md` |
| OpenAPI specs | `openapi.{yaml,json}`, `swagger.{yaml,json}` (recursive) |
| Architecture docs | Files/dirs named `architecture`, `design`, `technical` |
| Runbooks | Files/dirs named `runbook`, `playbook`, `operations` |
| Changelogs | `CHANGELOG.md`, `CHANGES.md`, `HISTORY.md` |
| User/business docs | `docs/`, `documentation/`, `wiki/`, `guides/` directories |
| Diagrams | `*.mermaid`, `*.puml`, `*.plantuml`, `*.drawio`, embedded mermaid/plantuml in markdown |
| External doc refs | URLs in markdown pointing to Confluence, Notion, wiki — stored as `DocFile` with `format: external-ref` |
| ReStructuredText/AsciiDoc | `*.rst`, `*.adoc` |

### Processing Pipeline

1. **Scan** — collect all doc file paths + metadata (size, last modified, format)
2. **Classify** — assign `doc_type` based on path patterns + content heuristics (e.g., "# ADR" or "## Status: Accepted" → `adr`)
3. **Parse sections** — split markdown by heading hierarchy (H1 → H2 → H3). Each heading becomes a `DocSection` node with `content_hash` (SHA256 of body). OpenAPI specs get sections per path group.
4. **Extract semantics** — scan for decision/constraint markers:
   - ADR files: extract decision, status, consequences → `DocDecision` nodes
   - Architecture docs: extract constraints ("must", "never", "always" + technical terms) → `DocConstraint` nodes
   - Design docs: extract decisions from "we chose X over Y" patterns → `DocDecision` nodes
   - Confidence: explicit markers (ADR) → `HIGH`, heuristic extraction → `MEDIUM`, weak patterns → `LOW`
5. **Link to code** — for each `DocSection`, `DocDecision`, `DocConstraint`:
   - Match referenced file paths (inline code, relative links)
   - Match class/function names (backtick-wrapped identifiers → grep codebase)
   - Match package names (directory references → `ProjectPackage` nodes)
   - Create `DESCRIBES`/`DECIDES`/`CONSTRAINS` relationships
6. **Detect cross-references** — markdown links between docs → `DOC_IMPORTS` relationships
7. **Detect diagrams** — standalone diagram files + embedded mermaid/plantuml blocks → `DocDiagram` nodes

### Output

- `stage_0_docs_discovery.md` — summary: N files, N sections, N decisions, N constraints, N linkages, N gaps
- Graph populated with all `Doc*` nodes and relationships
- Unlinked sections list (docs referencing code entities not found) — flagged as warnings

### Convention Drift Detection

On subsequent runs, compare `content_hash` per `DocSection` against graph. Changed sections → re-extract. Deleted docs → tombstone nodes. New docs → full processing.

### Deferred Discovery

Orchestrator at PREFLIGHT checks `last_modified` of all markdown files against `state.json.documentation.last_discovery_timestamp`. If any newer → incremental re-discovery. Deleted files → tombstone graph nodes. Self-healing without re-init.

---

## 6. Agent: `docs-consistency-reviewer`

**Stage:** REVIEW (quality gate batch 2)
**Type:** Reviewer agent (dual-labeled `Agent:Reviewer`)
**Tools:** `Read`, `Glob`, `Grep`, `Bash`, `mcp__plugin_context7_context7__resolve-library-id`, `mcp__plugin_context7_context7__query-docs`

### Review Dimensions

| Dimension | Checks | Severity |
|-----------|--------|----------|
| Decision compliance | Code changes violate `DocDecision` | CRITICAL (HIGH confidence) / WARNING (MEDIUM) |
| Constraint violations | Changes break `DocConstraint` | CRITICAL (HIGH confidence) / WARNING (MEDIUM) |
| Stale documentation | `DocSection` describes changed files but content no longer accurate | WARNING |
| Missing documentation | New public APIs/modules with no `DESCRIBES` relationship | INFO |
| Diagram drift | `DocDiagram` covers changed packages — may need update | INFO |
| Cross-doc inconsistency | Two `DocSection` nodes describe same entity with contradictory content | WARNING |

### Finding Format

Prefix: `DOC-` (categories: `DOC-DECISION`, `DOC-CONSTRAINT`, `DOC-STALE`, `DOC-MISSING`, `DOC-DIAGRAM`, `DOC-CROSSREF`)

```
DOC-DECISION-001 [CRITICAL] Decision violation: ADR-003 states "all inter-service communication via async messaging" but OrderController.kt:45 makes synchronous HTTP call to InventoryService
DOC-STALE-001 [WARNING] Stale docs: README.md section "API Endpoints" references POST /api/orders but implementation changed to POST /api/v2/orders in OrderRoutes.kt:23
DOC-MISSING-001 [INFO] New public interface PaymentGateway.kt has no documentation coverage
DOC-CONSTRAINT-001 [CRITICAL] Constraint violation: architecture.md states "domain layer must be framework-free" but UserEntity.kt:12 imports jakarta.persistence
```

### CONTRADICTS Relationship

Confirmed contradictions (CRITICAL/WARNING) create `CONTRADICTS` relationships in the graph. Persists until doc or code is fixed — prevents re-reporting same contradiction.

### Graceful Degradation

- No Neo4j: falls back to file-based analysis — grep changed file paths in discovered docs, check obvious staleness. Reduced scope.
- No docs in project: zero findings + INFO — "No project documentation discovered. Consider `/docs-generate`."

### Quality Gate Placement

```yaml
quality_gate:
  batch_1:
    - architecture-reviewer
    - security-reviewer
  batch_2:
    - docs-consistency-reviewer
    - frontend-reviewer  # or other domain reviewers
  batch_3:
    - version-compat-reviewer
```

---

## 7. Agent: `pl-350-docs-generator`

**Stage:** DOCUMENTING (replaces inline orchestrator logic)
**Tools:** `Read`, `Glob`, `Grep`, `Bash`, `Write`, `Edit`, `Agent`, `Skill`, `mcp__plugin_context7_context7__resolve-library-id`, `mcp__plugin_context7_context7__query-docs`

### Modes

| Mode | Trigger | Scope |
|------|---------|-------|
| Pipeline | Dispatched at Stage 7 by orchestrator | Changes in current run |
| Standalone | Via `/docs-generate` skill | Full project or selected types |

### Generation Capabilities

| Type | Generates | Sources |
|------|-----------|---------|
| README | Project overview, setup, usage, API summary, architecture | Code structure, manifests, existing README (merge) |
| Architecture doc | System overview, component diagram (Mermaid), layers, data flow | Graph nodes, import relationships, framework conventions |
| ADRs | Decision records for significant implementation choices | Plan stage notes (Challenge Brief), validator findings |
| API documentation | OpenAPI spec generation/update, endpoint docs, examples | Controller/route annotations, DTOs, existing spec (merge) |
| Onboarding guide | Dev setup, codebase tour, key concepts, "where things live" | Graph structure, build/test commands, conventions |
| Runbooks | Deploy procedures, rollback, monitoring, common issues | CI/CD config, Docker, infra docs, health checks |
| Migration guides | Breaking changes, upgrade steps | Migration files, version diffs, deprecation findings |
| Changelogs | Structured history (Keep a Changelog format) | Git diff, plan stage notes, PR descriptions |
| Business/domain docs | Domain models, glossary, business rule catalog | Domain entities, use cases, acceptance criteria |
| Diagrams | C4 (context, container, component), sequence, ER as Mermaid | Graph relationships, class hierarchy, API flows |
| User guides | Feature docs, how-to guides | Acceptance criteria, UI components, API endpoints |

### Worktree Context

In pipeline mode, the generator runs at Stage 7 inside `.pipeline/worktree` — the same worktree used by the implementer. All generated/updated documentation files are written to the worktree, not the user's working tree. This ensures:
- Documentation changes are included in the PR alongside code changes
- The user's working tree is never modified (existing contract)
- Documentation and code changes are atomically committed together

In standalone mode (`/docs-generate`), the generator writes directly to the user's working tree since there is no pipeline worktree.

### Pipeline Mode Generation Guardrails

Pipeline mode is **conservative by default** — it prioritizes updating existing docs over creating new ones. This prevents unexpected file creation during automated runs.

**Always (unconditional):**
- Update existing docs affected by changed files (graph-guided)
- Verify KDoc/TSDoc on all new public interfaces
- Update changelog with this run's changes
- Update OpenAPI spec if API endpoints changed

**Conditional creation (only when `auto_generate.<type>` is `true` in config):**
- Generate ADRs for significant decisions (see criteria below)
- Generate missing docs for new modules/packages
- Generate diagrams for new architecture components

**Never in pipeline mode:**
- Full documentation suite bootstrap (use `/docs-generate --all` for that)
- Runbook or user guide creation (always standalone-only)

This replaces the old inline rule "Do NOT create new documentation files unless explicitly requested" with a configurable approach.

### ADR Significance Criteria

The planner creates "Generate ADR" sub-tasks when a decision meets **2+ of these criteria**:

1. **Alternatives evaluated** — the Challenge Brief documents 2+ considered alternatives
2. **Cross-cutting impact** — the decision affects 3+ packages or 2+ architectural layers
3. **Irreversibility** — the decision would be expensive to reverse (new framework, data model change, API contract change)
4. **Security/compliance** — the decision has security or compliance implications
5. **Precedent-setting** — the decision establishes a pattern that future work should follow

Single-file refactors or routine implementation choices do not generate ADRs.

### Generation Strategy

1. **Assess** — read graph `DocFile` nodes (or `.pipeline/docs-index.json` in index mode), check existing coverage
2. **Determine need** — pipeline mode: diff-driven with guardrails above. Standalone mode: coverage-driven, user-selected types
3. **Plan** — build doc plan: files to create/update, sections needed
4. **Generate** — for each document:
   - Read source code (graph-guided or file-scan in index mode)
   - Read framework doc conventions (`modules/documentation/` + binding)
   - Generate using template
   - For updates: merge with existing, preserve user-maintained fences
5. **Diagrams** — Mermaid embedded in markdown. C4 for architecture, sequence for flows, ER for domain. Validate Mermaid syntax with `mmdc --validate` if mermaid-cli is available; skip validation with INFO if not installed.
6. **Update graph** — create/update `Doc*` nodes and relationships (or update `.pipeline/docs-index.json`)
7. **Export** — push to external systems via MCP if configured

### User-Maintained Section Protection

Content inside `<!-- user-maintained -->` / `<!-- /user-maintained -->` fences is never modified. Auto-generated sections include: `<!-- generated by dev-pipeline docs-generator — do not edit above user-maintained fences -->`.

### External System Export

```yaml
documentation:
  export:
    confluence:
      enabled: true
      space_key: "PROJ"
      parent_page_id: "12345"
    notion:
      enabled: false
```

Export is extensible via MCP. No built-in Confluence/Notion MCPs exist today — export requires the user to configure compatible MCP servers in their `.mcp.json`. When `export.<target>.enabled` is `true` but no matching MCP is available, the generator writes files locally and logs WARNING — "Export target '{target}' configured but no MCP server available. Files written to `{output_dir}` instead."

Future MCP servers for Confluence/Notion/wiki platforms can be integrated without spec changes — the generator calls them via the standard MCP tool pattern. The `export` config maps target names to MCP server tool prefixes.

### External Reference Validation

`DocFile` nodes with `format: external-ref` store URLs discovered in project documentation. During discovery:
- URLs are stored but NOT validated (no HTTP calls during PREFLIGHT — too slow and may require auth)
- The `/docs-generate --coverage` report includes external refs with a note: "External references not validated — verify accessibility manually"
- Future enhancement: optional `--validate-external-refs` flag on `/docs-generate` that HEAD-requests each URL and reports dead links

### Cross-Repo Documentation Awareness

If `related_projects` are configured (from `pipeline-init` cross-repo discovery):
- The discoverer scans related project roots for `README.md` and `docs/` (shallow scan, not full discovery)
- Creates `DocFile` nodes with a `cross_repo: true` property for cross-repo docs
- The consistency reviewer can flag when changes in the current project contradict documentation in a related project (e.g., changing an API endpoint that a related frontend project's docs reference)
- Cross-repo doc findings are always WARNING (never CRITICAL) — the current project shouldn't fail its pipeline for another project's docs

### Output

- Generated/updated doc files in `docs/` (or configured path)
- `stage_7_notes_{storyId}.md` — what was generated/updated, coverage metrics
- Updated graph nodes

---

## 8. Skill: `/docs-generate`

### Definition

```yaml
name: docs-generate
description: >
  Generate or update project documentation on demand. Bootstraps full suites
  for undocumented codebases or updates specific types. Supports README,
  architecture, ADRs, API docs, onboarding, runbooks, changelogs, diagrams,
  business docs, user guides, migration guides.
```

### Arguments

| Argument | Example | Behavior |
|----------|---------|----------|
| (none) | `/docs-generate` | Interactive — asks what to generate, shows coverage gaps |
| `--all` | `/docs-generate --all` | Full documentation suite |
| `--type <type>` | `/docs-generate --type architecture` | Specific doc type |
| `--type <type> --type <type>` | `/docs-generate --type adr --type changelog` | Multiple types |
| `--export` | `/docs-generate --all --export` | Generate + push to external systems |
| `--coverage` | `/docs-generate --coverage` | Report only — coverage gaps, no generation |
| `--from-code <path>` | `/docs-generate --from-code src/domain/` | Generate docs from specific code path |
| `--confirm-decisions` | `/docs-generate --confirm-decisions` | Interactive review of MEDIUM-confidence decisions/constraints — upgrade to HIGH or dismiss |

### Interactive Flow (no arguments)

1. Run discovery if graph stale/empty
2. Present coverage report:
   ```
   Documentation Coverage Report

   Documented:
     README.md              — project overview (last updated: 2026-03-15)
     docs/api-spec.yaml     — OpenAPI 3.1 (47 endpoints)

   Missing:
     Architecture doc       — no architecture.md found
     ADRs                   — no decision records found
     Onboarding guide       — no setup guide found
     Domain model docs      — 12 domain entities undocumented
     Diagrams               — no architecture diagrams found

   Stale:
     README.md "API Endpoints" section — references removed endpoints
   ```
3. Ask: "What would you like to generate? (all / pick from list / specific type)"
4. Dispatch `pl-350-docs-generator` in standalone mode

### Standalone Framework Detection

When running without pipeline config (`dev-pipeline.local.md` absent), the skill needs to determine which framework doc conventions to load:

1. **If `dev-pipeline.local.md` exists:** read `components.framework` directly — exact match.
2. **If absent:** run the same stack detection logic from `pipeline-init` Phase 1 (marker file scan) to infer the framework. Use the detected framework's doc conventions.
3. **If detection fails:** fall back to `modules/documentation/conventions.md` (generic conventions only, no framework binding). Log INFO — "No framework detected. Using generic documentation conventions."

This ensures `/docs-generate` works in any project, even without prior `/pipeline-init`.

### Independence

No worktrees, no state.json dependency. Reads `dev-pipeline.local.md` if present for output paths, framework, and export targets. Works without it via auto-detection (see above).

---

## 9. Module Layer: `modules/documentation/`

### Structure

```
modules/documentation/
├── conventions.md              # Generic doc conventions (all frameworks)
├── templates/
│   ├── readme.md               # README template skeleton
│   ├── architecture.md         # Architecture doc template
│   ├── adr.md                  # ADR template (Michael Nygard format)
│   ├── onboarding.md           # Onboarding guide template
│   ├── runbook.md              # Runbook template
│   ├── changelog.md            # Changelog template (Keep a Changelog)
│   ├── domain-model.md         # Domain/business doc template
│   └── user-guide.md           # User guide template
└── diagram-patterns.md         # Mermaid/PlantUML patterns for C4, sequence, ER
```

### Framework Bindings

```
modules/frameworks/spring/documentation/
├── conventions.md              # KDoc, hexagonal layers, JPA entities
└── templates/
    └── api-spec.md             # Spring OpenAPI generation patterns

modules/frameworks/react/documentation/
├── conventions.md              # Component docs, hook docs, Storybook refs
└── templates/
    └── component-doc.md        # Component documentation template

modules/frameworks/fastapi/documentation/
├── conventions.md              # Pydantic models, auto-generated OpenAPI
└── templates/
    └── api-spec.md             # FastAPI-specific OpenAPI patterns
```

Bindings created for all 21 frameworks. Each contains at minimum `conventions.md`.

### Generic Conventions (key rules)

- **Tone:** Technical, precise, no filler. Write for the maintainer in 6 months.
- **Structure:** Lead with "what and why", then "how". Every doc starts with one-paragraph summary.
- **Code references:** Backtick-wrapped identifiers with relative paths. Never reference line numbers.
- **Diagrams:** Mermaid preferred (renders in GitHub). One diagram per concept.
- **User-maintained fences:** Preserve `<!-- user-maintained -->` blocks. Never generate inside them.
- **Staleness markers:** Auto-generated sections include `<!-- generated by dev-pipeline docs-generator -->`.
- **ADR format:** Michael Nygard: Title, Status, Context, Decision, Consequences.
- **Changelog:** Keep a Changelog format.

### Convention Composition Order

`framework-documentation-binding > generic documentation > framework conventions`

### Learnings

- New: `shared/learnings/documentation.md`
- Existing framework learnings files get doc-generation effectiveness tracking

---

## 10. Pipeline Integration

### Orchestrator Changes

**PREFLIGHT additions (after step 13):**

14. Dispatch `pl-130-docs-discoverer` — discover docs, populate graph
15. Write discovery summary to `stage_0_docs_discovery.md`
16. Store metrics in `state.json.documentation`

**EXPLORE additions:**
- Explorers receive doc discovery summary as input
- If architecture docs exist, explorers validate code against documented architecture

**PLAN additions:**
- Planner receives `DocDecision`/`DocConstraint` for affected packages
- Graph pre-query "Decision Traceability" before planner dispatch
- Planner notes when tasks conflict with existing decisions → creates ADR sub-task
- Significant architectural choices → "Generate ADR" sub-task

**VALIDATE additions:**
- 7th validation perspective: Documentation Consistency
- Validator receives `DocDecision`/`DocConstraint` for affected scope
- Plan contradicting HIGH-confidence decision without superseding → REVISE

**REVIEW additions:**
- `docs-consistency-reviewer` in quality gate batch 2
- Pre-queries: "Documentation Impact" and "Stale Docs Detection"

**DOCUMENTING — full replacement:**

Dispatch `pl-350-docs-generator` with:
- Changed files, quality verdict, plan stage notes, doc discovery summary, documentation config
- Mode: pipeline
- Rules: update affected docs, generate ADRs for significant decisions, update changelog, update OpenAPI if endpoints changed, verify KDoc/TSDoc, generate missing docs for new modules, respect user-maintained fences, export if configured

**Stage contract update:**
- Stage 7 agent: `inline` → `pl-350-docs-generator`
- Exit condition: "Documentation updated. No new public interfaces lack documentation. Coverage gaps reduced or explained in stage notes."

**SHIP addition:**
- PR body includes Documentation Coverage section alongside Quality Gate and Test Plan

### Pipeline-Init Changes

**Phase 1 DETECT — expanded discovery:**

After OpenAPI detection, scan for all doc types. Present:
```
Documentation:      14 files (3 ADRs, 1 OpenAPI, 2 runbooks, 8 guides)
External docs:      Confluence (2 spaces referenced)
Doc coverage:       ~60% of packages have documentation
```

**New prompt after stack confirmation:**
> "Found 14 documentation files. Are there additional docs I should know about? (external wikis, Confluence, Notion, shared drives) You can add these later — the pipeline picks up new docs automatically."

User-provided URLs stored in `documentation.external_sources`.

**Phase 2 CONFIGURE — new `documentation:` section:**

```yaml
documentation:
  enabled: true
  output_dir: docs/
  auto_generate:
    readme: true
    architecture: true
    adrs: true
    api_docs: true
    onboarding: true
    changelogs: true
    diagrams: true
    domain_docs: true
    runbooks: false
    user_guides: false
    migration_guides: true
  external_sources: []
  discovery:
    max_files: 500
    max_file_size_kb: 512
    exclude_patterns: []
  export:
    confluence:
      enabled: false
    notion:
      enabled: false
  user_maintained_marker: "<!-- user-maintained -->"
```

**Phase 6b GRAPH:** `pl-130-docs-discoverer` runs as part of initial graph build.

---

## 11. State Schema v2.0.0

Clean break from v1.1.0. Requires `/pipeline-reset`.

### New `.pipeline/` files

| File | Created By | Purpose |
|------|-----------|---------|
| `docs-index.json` | `pl-130-docs-discoverer` | Flat JSON index of discovered docs — fallback when Neo4j unavailable |
| `stage_0_docs_discovery.md` | `pl-130-docs-discoverer` | Human-readable discovery summary |

### New `documentation` field

```json
{
  "documentation": {
    "last_discovery_timestamp": "2026-03-30T10:00:00Z",
    "files_discovered": 14,
    "sections_parsed": 87,
    "decisions_extracted": 5,
    "constraints_extracted": 12,
    "code_linkages": 43,
    "coverage_gaps": ["src/domain/payment/", "src/api/v2/"],
    "stale_sections": 3,
    "external_refs": ["https://confluence.company.com/wiki/PROJECT"],
    "generation_history": [
      {
        "run_id": "abc123",
        "timestamp": "2026-03-30T10:30:00Z",
        "files_created": ["docs/architecture.md", "docs/adr/ADR-004.md"],
        "files_updated": ["README.md", "docs/api-spec.yaml"],
        "diagrams_generated": 3,
        "coverage_before": 0.60,
        "coverage_after": 0.78
      }
    ]
  }
}
```

---

## 12. Scoring

`DOC-*` findings follow standard scoring formula (`100 - 20*CRITICAL - 5*WARNING - 2*INFO`):

| Finding | Severity | Deduction |
|---------|----------|-----------|
| `DOC-DECISION-*` | CRITICAL (HIGH confidence) / WARNING (MEDIUM) | -20 / -5 |
| `DOC-CONSTRAINT-*` | CRITICAL (HIGH confidence) / WARNING (MEDIUM) | -20 / -5 |
| `DOC-STALE-*` | WARNING | -5 |
| `DOC-MISSING-*` | INFO | -2 |
| `DOC-DIAGRAM-*` | INFO | -2 |
| `DOC-CROSSREF-*` | WARNING | -5 |

LOW confidence extractions appear as `SCOUT-DOC-*` (no deduction, informational) until confidence upgraded.

### Coverage Metrics (non-scoring)

Tracked in stage notes, reported in PR body:
```
Documentation Coverage: 78% (+18% from this run)
  Packages documented: 14/18
  Public APIs documented: 47/52
  ADRs: 5 (1 new)
  Diagrams: 6 (3 new)
```

---

## 13. CLAUDE.md Updates

- Agent count: 29 → 32 (`pl-130-docs-discoverer`, `docs-consistency-reviewer`, `pl-350-docs-generator`)
- Skills count: 17 → 18 (`docs-generate`)
- Stage 7 agent: `inline` → `pl-350-docs-generator`
- New `modules/documentation/` layer
- New `documentation:` config section
- State schema: v1.1.0 → v2.0.0 (clean break)
- Graph schema: new `Doc*` nodes and relationships
- `LayerModule.layer` values: add `documentation`
- Validation perspectives: 6 → 7 (Documentation Consistency)
- New `DOC-*` finding category
- Gotcha: "State schema v2.0.0 is a clean break — run `/pipeline-reset`"

---

## 14. Test Plan

### Structural Checks (new)

- `pl-130-docs-discoverer.md` exists with correct frontmatter
- `docs-consistency-reviewer.md` exists with `Agent:Reviewer` dual label
- `pl-350-docs-generator.md` exists with correct frontmatter
- `skills/docs-generate/` exists with `SKILL.md`
- `modules/documentation/conventions.md` exists
- `modules/documentation/templates/` contains required templates
- All framework doc bindings have `conventions.md`

### Contract Tests (new)

- Orchestrator dispatches `pl-130-docs-discoverer` at PREFLIGHT
- Orchestrator dispatches `pl-350-docs-generator` at DOCUMENTING (not inline)
- Stage contract Stage 0 agent field includes `pl-130-docs-discoverer`
- Quality gate batch includes `docs-consistency-reviewer`
- Stage contract Stage 7 agent is `pl-350-docs-generator`
- State schema version is `2.0.0`
- State schema includes `documentation` field with all required subfields
- Graph schema includes `DocFile` (with `cross_repo`), `DocSection` (with `content_hash_updated`), `DocDecision` (with `extracted_at`, `status`), `DocConstraint`, `DocDiagram` nodes
- Graph schema includes all 8 new relationships
- Query patterns include 5 new documentation Cypher queries
- Scoring handles `DOC-*` finding categories
- Scoring handles `SCOUT-DOC-*` (no deduction) for LOW confidence
- Validation has 7 perspectives including Documentation Consistency
- `docs-index.json` schema matches graph node structure
- Pipeline-init `documentation:` config includes `discovery:` limits

### Scenario Tests (new)

- Discoverer finds docs and populates graph
- Discoverer writes `docs-index.json` when Neo4j unavailable
- Discoverer respects `max_files` limit and logs WARNING when exceeded
- Discoverer classifies ADRs by content heuristic ("## Status: Accepted")
- Discoverer extracts DocDecision with correct status enum values
- Consistency reviewer detects decision violation → CRITICAL
- Consistency reviewer detects stale doc → WARNING
- Consistency reviewer flags cross-repo doc inconsistency → WARNING (not CRITICAL)
- Consistency reviewer falls back to file-based analysis without Neo4j
- Generator creates README from undocumented codebase
- Generator respects user-maintained fences
- Generator writes to worktree in pipeline mode, working tree in standalone mode
- Generator skips runbook/user-guide creation in pipeline mode
- Generator validates Mermaid syntax when mermaid-cli available
- `/docs-generate --coverage` reports gaps without generating
- `/docs-generate --confirm-decisions` upgrades MEDIUM → HIGH confidence
- `/docs-generate` auto-detects framework without `dev-pipeline.local.md`
- Deferred discovery catches newly added docs on next run
- Graceful degradation: no Neo4j → `docs-index.json` fallback
- ADR significance: planner creates ADR task when 2+ criteria met
- ADR significance: planner does not create ADR for single-file refactor

### Existing Test Updates

- `module-lists.bash`: add `MIN_DOCUMENTATION_BINDINGS` count guard
- Update agent count assertions (29 → 32)
- Update skill count assertions (17 → 18)
- Update validation perspective count (6 → 7)

---

## 15. Contributing.md Update

Add "Adding documentation bindings" section — same pattern as other framework bindings:
1. Create `modules/frameworks/{name}/documentation/conventions.md`
2. Optionally add `templates/` with framework-specific templates
3. Update `shared/learnings/{name}.md` with doc generation tracking
