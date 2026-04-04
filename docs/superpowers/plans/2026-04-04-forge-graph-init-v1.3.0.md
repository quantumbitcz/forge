# Forge Graph Enrichment & Init Automation (v1.3.0) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enrich the knowledge graph with distributed agent access and new query patterns, add smart tool recommendations with exclusive_group deduplication, create project-local plugins during init, auto-provision MCPs, and enforce runtime version resolution.

**Architecture:** Four interconnected features sharing the init skill as primary integration point. Graph enrichment gives 5 agents direct `neo4j-mcp` access with 2 new query patterns (14: Bug Hotspots, 15: Test Coverage). Smart tool recommendations add YAML frontmatter tags to ~70 code-quality modules for exclusive_group deduplication. Init automation generates a project-local plugin (`.claude/plugins/project-tools/`) with hooks, skills, and agents. MCP auto-provisioning installs missing MCPs during init. Version resolution is a cross-cutting constraint in `shared/agent-defaults.md`.

**Tech Stack:** Markdown (agents, skills, shared docs), YAML frontmatter, Cypher (graph patterns), bash (tests), bats (test framework)

**Spec:** `docs/superpowers/specs/2026-04-02-forge-redesign-design.md` — Sections 9, 10, 11, 12

---

## File Structure

### New files to create

```
shared/mcp-provisioning.md                         # MCP auto-provisioning rules and flow
shared/version-resolution.md                       # Cross-cutting version resolution constraint
tests/contract/graph-enrichment.bats               # Contract tests for graph distributed access
tests/contract/smart-recommendations.bats          # Contract tests for tool dedup
tests/contract/init-automation.bats                # Contract tests for project-local plugin
tests/contract/mcp-provisioning.bats               # Contract tests for MCP auto-install
```

### Files to modify

```
# Graph enrichment
agents/fg-010-shaper.md                            # Add neo4j-mcp to tools, graph-powered Phase 4
agents/fg-020-bug-investigator.md                  # Add neo4j-mcp already present, document patterns 14/15
agents/fg-200-planner.md                           # Add neo4j-mcp to tools
agents/fg-210-validator.md                         # Add neo4j-mcp to tools
agents/fg-400-quality-gate.md                      # Add neo4j-mcp to tools
shared/graph/query-patterns.md                     # Add patterns 14 (Bug Hotspots) and 15 (Test Coverage)
shared/graph/schema.md                             # Add bug_fix_count, last_bug_fix_date to ProjectFile

# Smart tool recommendations
modules/code-quality/*.md                          # Add frontmatter tags to ~70 files
skills/forge-init/SKILL.md                         # Rewrite Phase 1.5 with dedup algorithm

# Init automation
skills/forge-init/SKILL.md                         # Add project-local plugin generation phase

# MCP provisioning
skills/forge-init/SKILL.md                         # Add MCP provisioning phase
skills/graph-init/SKILL.md                         # Reference mcp-provisioning.md

# Version resolution
shared/agent-defaults.md                           # Add Version Resolution constraint

# Docs
CLAUDE.md                                          # Document all Phase 4 features
CONTRIBUTING.md                                    # Update for new conventions
.claude-plugin/plugin.json                         # Version bump to 1.3.0
.claude-plugin/marketplace.json                    # Version bump to 1.3.0
tests/validate-plugin.sh                           # Add structural checks
```

---

## Task 1: Add New Graph Query Patterns (14 + 15)

**Files:**
- Modify: `shared/graph/query-patterns.md`
- Modify: `shared/graph/schema.md`
- Test: `tests/contract/graph-enrichment.bats`

- [ ] **Step 1: Read current query-patterns.md to find insertion point**

Read `shared/graph/query-patterns.md` and find after Pattern 13 (Documentation Coverage Gap).

- [ ] **Step 2: Add Pattern 14 — Bug Hotspot Analysis**

Append after Pattern 13:

```markdown
## Pattern 14 — Bug Hotspot Analysis

**Used during:** PREFLIGHT (PREEMPT), EXPLORE (bugfix mode), REVIEW (risk flagging)

**Purpose:** Identify files with recurring bug fixes to flag as hotspots for extra attention.

**Prerequisites:** `ProjectFile` nodes with `bug_fix_count` and `last_bug_fix_date` properties, populated by the retrospective agent (`fg-700-retrospective`) after each bugfix run.

```cypher
MATCH (f:ProjectFile)
WHERE f.bug_fix_count > 0
RETURN f.path, f.bug_fix_count, f.last_bug_fix_date
ORDER BY f.bug_fix_count DESC
LIMIT 20
```

**Consumers:** `fg-010-shaper` (risk flagging in spec), `fg-020-bug-investigator` (prioritize investigation), `fg-400-quality-gate` (stricter review for hotspots)

**Graceful degradation:** If no `bug_fix_count` properties exist yet (first run), returns empty result. Consumers treat empty as "no hotspot data available."
```

- [ ] **Step 3: Add Pattern 15 — Test Coverage by Entity**

Append after Pattern 14:

```markdown
## Pattern 15 — Test Coverage by Entity

**Used during:** EXPLORE (bugfix mode), PLAN (test gap analysis), REVIEW (coverage flagging)

**Purpose:** Identify classes/entities that lack direct test coverage — prime candidates for bugs going undetected.

**Prerequisites:** `ProjectClass` nodes with `CLASS_IN_FILE` edges and `TESTS` edges between test files and source files, populated by `build-project-graph.sh`.

```cypher
MATCH (c:ProjectClass)
OPTIONAL MATCH (t:ProjectFile)-[:TESTS]->(f:ProjectFile)-[:CLASS_IN_FILE]->(c)
WHERE t IS NULL
RETURN c.name, f.path AS source_file
```

**Consumers:** `fg-020-bug-investigator` (identify untested code near bug), `fg-500-test-gate` (coverage gap warnings), `fg-010-shaper` (note in spec Technical Notes)

**Graceful degradation:** If no `TESTS` edges exist (graph not fully enriched), returns all classes. Consumers should limit to the affected area, not process entire result set.
```

- [ ] **Step 4: Update graph schema with new properties**

In `shared/graph/schema.md`, find the `ProjectFile` node type and add:

```markdown
| `bug_fix_count` | integer | Number of bugfix runs that modified this file. Incremented by `fg-700-retrospective` after each bugfix run. Default: 0. |
| `last_bug_fix_date` | string (ISO 8601) | Date of the most recent bugfix affecting this file. Set by `fg-700-retrospective`. Null if never fixed. |
```

- [ ] **Step 5: Write contract tests**

Create `tests/contract/graph-enrichment.bats`:

```bash
#!/usr/bin/env bash

setup() {
  load '../lib/bats-support/load'
  load '../lib/bats-assert/load'
  PLUGIN_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  QUERY_PATTERNS="$PLUGIN_ROOT/shared/graph/query-patterns.md"
  GRAPH_SCHEMA="$PLUGIN_ROOT/shared/graph/schema.md"
  SHAPER="$PLUGIN_ROOT/agents/fg-010-shaper.md"
  PLANNER="$PLUGIN_ROOT/agents/fg-200-planner.md"
  VALIDATOR="$PLUGIN_ROOT/agents/fg-210-validator.md"
  QUALITY_GATE="$PLUGIN_ROOT/agents/fg-400-quality-gate.md"
  BUG_INVESTIGATOR="$PLUGIN_ROOT/agents/fg-020-bug-investigator.md"
}

# --- Patterns ---
@test "graph: Pattern 14 (Bug Hotspot Analysis) documented" {
  grep -q "Pattern 14.*Bug Hotspot" "$QUERY_PATTERNS"
}

@test "graph: Pattern 14 has Cypher query with bug_fix_count" {
  grep -q "bug_fix_count" "$QUERY_PATTERNS"
}

@test "graph: Pattern 15 (Test Coverage by Entity) documented" {
  grep -q "Pattern 15.*Test Coverage" "$QUERY_PATTERNS"
}

@test "graph: Pattern 15 has Cypher query with TESTS edge" {
  grep -q "TESTS" "$QUERY_PATTERNS"
}

@test "graph: schema documents bug_fix_count property on ProjectFile" {
  grep -q "bug_fix_count" "$GRAPH_SCHEMA"
}

@test "graph: schema documents last_bug_fix_date property on ProjectFile" {
  grep -q "last_bug_fix_date" "$GRAPH_SCHEMA"
}

# --- Distributed access ---
@test "graph: fg-010-shaper has neo4j-mcp in tools" {
  grep -q "neo4j-mcp" "$SHAPER"
}

@test "graph: fg-200-planner has neo4j-mcp in tools" {
  grep -q "neo4j-mcp" "$PLANNER"
}

@test "graph: fg-210-validator has neo4j-mcp in tools" {
  grep -q "neo4j-mcp" "$VALIDATOR"
}

@test "graph: fg-400-quality-gate has neo4j-mcp in tools" {
  grep -q "neo4j-mcp" "$QUALITY_GATE"
}

@test "graph: fg-020-bug-investigator has neo4j-mcp in tools" {
  grep -q "neo4j-mcp" "$BUG_INVESTIGATOR"
}

# --- Graceful degradation ---
@test "graph: Pattern 14 documents graceful degradation" {
  grep -A5 "Pattern 14" "$QUERY_PATTERNS" | grep -qi "graceful\|degradation\|empty"
}

@test "graph: Pattern 15 documents graceful degradation" {
  grep -A5 "Pattern 15" "$QUERY_PATTERNS" | grep -qi "graceful\|degradation"
}
```

- [ ] **Step 6: Run tests**

Run: `tests/lib/bats-core/bin/bats tests/contract/graph-enrichment.bats`
Expected: Patterns 14/15 pass, some agent tool tests may fail (agents not yet updated — that's Task 2).

- [ ] **Step 7: Commit**

```bash
git add shared/graph/query-patterns.md shared/graph/schema.md tests/contract/graph-enrichment.bats
git commit -m "feat(graph): add patterns 14 (bug hotspots) and 15 (test coverage)"
```

---

## Task 2: Distribute neo4j-mcp to 5 Agents + Shaper Graph Enrichment

**Files:**
- Modify: `agents/fg-010-shaper.md` (add neo4j-mcp + graph-powered Phase 4)
- Modify: `agents/fg-200-planner.md` (add neo4j-mcp)
- Modify: `agents/fg-210-validator.md` (add neo4j-mcp)
- Modify: `agents/fg-400-quality-gate.md` (add neo4j-mcp)

Note: `fg-020-bug-investigator` already has `neo4j-mcp` from Phase 3.

- [ ] **Step 1: Add neo4j-mcp to fg-010-shaper tools and enrich Phase 4**

In `agents/fg-010-shaper.md`:
1. Add `'neo4j-mcp'` to the tools list in frontmatter
2. Replace the current Phase 4 (Identify Components) with the graph-powered version:

```markdown
### Phase 4 — Identify Components (Graph-Enhanced)

If `neo4j-mcp` is available (check by attempting a lightweight Cypher query `RETURN 1`):

1. **Query Pattern 7 (Blast Radius):** Search for files/packages related to the feature keywords → affected area
2. **Query Pattern 3 (Entity Impact):** For each affected entity → consumer files, dependent modules
3. **Query Pattern 11 (Decision Traceability):** Active architectural decisions constraining the affected area
4. **Query Pattern 14 (Bug Hotspots):** Files in the affected area with recurring bugs → flag risk in spec
5. **Query Pattern 15 (Test Coverage Gaps):** Entities in affected area lacking test coverage → note in spec

Synthesize graph results into the Technical Notes section of the spec.

**If graph unavailable:** Fall back to the explorer sub-agent dispatch (via Agent tool) to scan the codebase for related existing functionality. Use Grep/Glob to find related files manually.

In both cases, also:
- Identify which files, modules, or services are affected
- Check for API contracts or interfaces that would need to change
- Note existing patterns (auth guards, validation utilities, event buses) that should be reused
- Map cross-repo implications under Technical Notes
```

- [ ] **Step 2: Add neo4j-mcp to fg-200-planner, fg-210-validator, fg-400-quality-gate**

For each of these 3 agents:
1. Read the file to find the tools list in frontmatter
2. Add `'neo4j-mcp'` to the tools array
3. Add a brief note in the body about graph usage:

For **fg-200-planner**, add after the tools list or in the planning methodology:
```markdown
**Graph Context (when available):** Query patterns 2 (Direct Impact), 3 (Entity Impact), 7 (Blast Radius), 9 (Documentation Impact) to inform task decomposition and dependency ordering. Fall back to grep/glob if graph unavailable.
```

For **fg-210-validator**, add:
```markdown
**Graph Context (when available):** Query patterns 11 (Decision Traceability), 12 (Contradiction Report) to validate plan against active architectural decisions. Fall back to document search if graph unavailable.
```

For **fg-400-quality-gate**, add:
```markdown
**Graph Context (when available):** Query patterns 10 (Stale Docs), 11 (Decision Traceability), 12 (Contradiction Report) to coordinate review focus areas. Fall back to file-based analysis if graph unavailable.
```

- [ ] **Step 3: Run graph enrichment tests**

```bash
tests/lib/bats-core/bin/bats tests/contract/graph-enrichment.bats
```
Expected: All PASS (including agent tool checks).

- [ ] **Step 4: Commit**

```bash
git add agents/fg-010-shaper.md agents/fg-200-planner.md agents/fg-210-validator.md agents/fg-400-quality-gate.md
git commit -m "feat(agents): distribute neo4j-mcp to shaper, planner, validator, quality gate"
```

---

## Task 3: Add Frontmatter Tags to Code-Quality Modules

**Files:**
- Modify: ~70 files in `modules/code-quality/*.md`
- Test: `tests/contract/smart-recommendations.bats`

This is the largest task by file count. Each of the ~70 code-quality module files needs YAML frontmatter with: `name`, `categories`, `languages`, `exclusive_group`, `recommendation_score`, `detection_files`.

- [ ] **Step 1: Write contract tests first**

Create `tests/contract/smart-recommendations.bats`:

```bash
#!/usr/bin/env bash

setup() {
  load '../lib/bats-support/load'
  load '../lib/bats-assert/load'
  PLUGIN_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  CODE_QUALITY_DIR="$PLUGIN_ROOT/modules/code-quality"
  FORGE_INIT="$PLUGIN_ROOT/skills/forge-init/SKILL.md"
}

@test "smart-recs: all code-quality modules have YAML frontmatter" {
  local failures=()
  for f in "$CODE_QUALITY_DIR"/*.md; do
    if ! head -1 "$f" | grep -q "^---$"; then
      failures+=("$(basename "$f")")
    fi
  done
  if (( ${#failures[@]} > 0 )); then
    fail "Missing frontmatter: ${failures[*]}"
  fi
}

@test "smart-recs: all code-quality modules have name field" {
  local failures=()
  for f in "$CODE_QUALITY_DIR"/*.md; do
    if ! grep -q "^name:" "$f"; then
      failures+=("$(basename "$f")")
    fi
  done
  if (( ${#failures[@]} > 0 )); then
    fail "Missing name: ${failures[*]}"
  fi
}

@test "smart-recs: all code-quality modules have categories field" {
  local failures=()
  for f in "$CODE_QUALITY_DIR"/*.md; do
    if ! grep -q "^categories:" "$f"; then
      failures+=("$(basename "$f")")
    fi
  done
  if (( ${#failures[@]} > 0 )); then
    fail "Missing categories: ${failures[*]}"
  fi
}

@test "smart-recs: all code-quality modules have languages field" {
  local failures=()
  for f in "$CODE_QUALITY_DIR"/*.md; do
    if ! grep -q "^languages:" "$f"; then
      failures+=("$(basename "$f")")
    fi
  done
  if (( ${#failures[@]} > 0 )); then
    fail "Missing languages: ${failures[*]}"
  fi
}

@test "smart-recs: all code-quality modules have exclusive_group field" {
  local failures=()
  for f in "$CODE_QUALITY_DIR"/*.md; do
    if ! grep -q "^exclusive_group:" "$f"; then
      failures+=("$(basename "$f")")
    fi
  done
  if (( ${#failures[@]} > 0 )); then
    fail "Missing exclusive_group: ${failures[*]}"
  fi
}

@test "smart-recs: all code-quality modules have recommendation_score field" {
  local failures=()
  for f in "$CODE_QUALITY_DIR"/*.md; do
    if ! grep -q "^recommendation_score:" "$f"; then
      failures+=("$(basename "$f")")
    fi
  done
  if (( ${#failures[@]} > 0 )); then
    fail "Missing recommendation_score: ${failures[*]}"
  fi
}

@test "smart-recs: all code-quality modules have detection_files field" {
  local failures=()
  for f in "$CODE_QUALITY_DIR"/*.md; do
    if ! grep -q "^detection_files:" "$f"; then
      failures+=("$(basename "$f")")
    fi
  done
  if (( ${#failures[@]} > 0 )); then
    fail "Missing detection_files: ${failures[*]}"
  fi
}

@test "smart-recs: exclusive_group values include known groups" {
  # Check that at least the documented exclusive groups exist
  local groups=("kotlin-formatter" "js-formatter" "js-linter" "python-formatter" "python-linter")
  for grp in "${groups[@]}"; do
    grep -rq "exclusive_group: $grp" "$CODE_QUALITY_DIR/" \
      || fail "No module declares exclusive_group: $grp"
  done
}

@test "smart-recs: recommendation_score values are integers 1-100" {
  local failures=()
  for f in "$CODE_QUALITY_DIR"/*.md; do
    local score
    score=$(grep "^recommendation_score:" "$f" | sed 's/^recommendation_score: *//' | tr -d '[:space:]')
    if [ -n "$score" ] && ! [[ "$score" =~ ^[0-9]+$ ]] || [ "$score" -lt 1 ] || [ "$score" -gt 100 ]; then
      failures+=("$(basename "$f"): $score")
    fi
  done
  if (( ${#failures[@]} > 0 )); then
    fail "Invalid scores: ${failures[*]}"
  fi
}

@test "smart-recs: forge-init documents exclusive_group dedup algorithm" {
  grep -q "exclusive_group" "$FORGE_INIT"
}

@test "smart-recs: forge-init documents detection_files scanning" {
  grep -q "detection_files" "$FORGE_INIT"
}
```

- [ ] **Step 2: Add frontmatter to ALL ~70 code-quality modules**

This is a mechanical task. For each file in `modules/code-quality/*.md`, prepend YAML frontmatter. The frontmatter must be derived from the file's content:

1. `name:` — filename without .md
2. `categories:` — infer from Overview section (linter, formatter, coverage, doc-generator, security-scanner, mutation-tester)
3. `languages:` — infer from the tool's target languages
4. `exclusive_group:` — assign based on the tool's category + language (e.g., `kotlin-formatter` for ktlint/spotless/ktfmt)
5. `recommendation_score:` — 1-100, higher = more commonly recommended. The framework-preferred tool gets 90, alternatives get 70-80.
6. `detection_files:` — list of config files that indicate the tool is already configured

Use the exclusive groups from the spec (Section 10.2) as the reference. Tools that don't conflict with anything get their own group (e.g., `jacoco` → `java-coverage`, single member).

**Example frontmatter for key tools:**

```yaml
# detekt.md
---
name: detekt
categories: [linter]
languages: [kotlin]
exclusive_group: kotlin-linter
recommendation_score: 90
detection_files: ["detekt.yml", "detekt.yaml", "config/detekt/detekt.yml"]
---

# ktlint.md
---
name: ktlint
categories: [linter, formatter]
languages: [kotlin]
exclusive_group: kotlin-formatter
recommendation_score: 90
detection_files: [".editorconfig", ".ktlint"]
---

# prettier.md
---
name: prettier
categories: [formatter]
languages: [javascript, typescript]
exclusive_group: js-formatter
recommendation_score: 80
detection_files: [".prettierrc", ".prettierrc.json", ".prettierrc.yml", ".prettierrc.js", "prettier.config.js"]
---

# biome.md
---
name: biome
categories: [linter, formatter]
languages: [javascript, typescript]
exclusive_group: js-formatter
recommendation_score: 90
detection_files: ["biome.json", "biome.jsonc"]
---

# eslint.md
---
name: eslint
categories: [linter]
languages: [javascript, typescript]
exclusive_group: js-linter
recommendation_score: 80
detection_files: [".eslintrc", ".eslintrc.js", ".eslintrc.json", ".eslintrc.yml", "eslint.config.js", "eslint.config.mjs"]
---

# ruff.md
---
name: ruff
categories: [linter, formatter]
languages: [python]
exclusive_group: python-linter
recommendation_score: 90
detection_files: ["ruff.toml", "pyproject.toml"]
---

# jacoco.md
---
name: jacoco
categories: [coverage]
languages: [java, kotlin]
exclusive_group: jvm-coverage
recommendation_score: 90
detection_files: ["build.gradle.kts", "build.gradle", "pom.xml"]
---
```

For the full list of ~70 tools: read each file, infer the category and language from its Overview section, assign the appropriate exclusive_group, and set recommendation_score based on adoption (primary tools = 90, alternatives = 70-80, niche = 50-60).

Tools in the `security-scanner` category do NOT use exclusive_group (they're complementary) — set `exclusive_group: none`.

- [ ] **Step 3: Run tests**

```bash
tests/lib/bats-core/bin/bats tests/contract/smart-recommendations.bats
```
Expected: All PASS

- [ ] **Step 4: Commit**

```bash
git add modules/code-quality/ tests/contract/smart-recommendations.bats
git commit -m "feat(code-quality): add frontmatter tags to all 70 modules for smart dedup"
```

---

## Task 4: Rewrite forge-init Code Quality Recommendations (Phase 1.5)

**Files:**
- Modify: `skills/forge-init/SKILL.md`

- [ ] **Step 1: Read current Phase 1.5 in forge-init**

Read `skills/forge-init/SKILL.md` and find the code quality recommendations section.

- [ ] **Step 2: Replace Phase 1.5 with the dedup algorithm**

Replace the current Phase 1.5 with:

```markdown
### Phase 1.5 — Smart Code Quality Recommendations

**Input:** Framework's `code_quality_recommended` list from local-template.md + detected existing tools from Phase 1.

**Algorithm:**

1. **Load recommendations:** Read the framework's `code_quality_recommended` list
2. **Read frontmatter:** For each recommended tool, read its `modules/code-quality/{tool}.md` frontmatter to extract `exclusive_group`, `recommendation_score`, `detection_files`
3. **Detect existing:** For each tool, check if any of its `detection_files` exist in the project root. Mark as "already configured" if found.
4. **Group by exclusive_group:** Partition tools into exclusive groups. Tools with `exclusive_group: none` (security scanners) go into a "complementary" bucket.
5. **Dedup per group:**
   a. If the project already has a tool from this group → keep it, hide alternatives
   b. If no tool detected → pre-select the one with highest `recommendation_score`
   c. Mark others as "alternatives (not selected)"
6. **Present to user** via `AskUserQuestion`:

```
Header: "Code Quality Tools"
Question: "Recommended tools for your {framework} + {language} project:"

Options:
  A) Accept recommendations:
     ✅ detekt — static analysis (recommended)
     ✅ ktlint — linting + formatting (recommended)
        ↳ Alternatives: spotless, ktfmt
     ✅ jacoco — code coverage (recommended)
     ✅ dokka — documentation (recommended)
     ✅ owasp-dependency-check — security (recommended)
     ✅ pitest — mutation testing (recommended)

  B) Customize selection (per-group radio buttons + checkboxes)

  C) Skip code quality setup
```

If user selects (B), present each exclusive group as a radio-button question:

```
Header: "Kotlin Formatter"
Question: "Pick one (or none):"
Options:
  A) ktlint — fast, Kotlin-native, also lints style (recommended, score: 90)
  B) spotless — Gradle plugin, wraps multiple formatters (score: 70)
  C) ktfmt — Google's opinionated formatter (score: 60)
  D) None — skip formatter
```

For complementary groups (security scanners), use checkboxes:

```
Header: "Security Scanning"
Question: "Select any (all are complementary):"
Options:
  A) ☑ owasp-dependency-check — CVE database (recommended)
  B) ☐ snyk — SaaS-based, broader ecosystem
  C) ☐ trivy — container + filesystem scanning
```

7. **Write selections** to `forge.local.md` `code_quality:` list (string form for simple, object form for tools with external rulesets).
```

- [ ] **Step 3: Commit**

```bash
git add skills/forge-init/SKILL.md
git commit -m "feat(init): smart tool recommendations with exclusive_group dedup"
```

---

## Task 5: Add MCP Auto-Provisioning

**Files:**
- Create: `shared/mcp-provisioning.md`
- Modify: `skills/forge-init/SKILL.md`
- Test: `tests/contract/mcp-provisioning.bats`

- [ ] **Step 1: Create mcp-provisioning.md**

Create `shared/mcp-provisioning.md`:

```markdown
# MCP Auto-Provisioning

Rules for automatically installing and configuring MCP servers needed by forge workflows.

## Provisioning Flow

For each MCP the forge detects as useful for the project:

```
1. Check if MCP already configured in .mcp.json or Claude Code settings
   ├─ YES → Mark as available, skip
   └─ NO ↓
2. Check prerequisites (e.g., Docker for Neo4j)
   ├─ Missing → Ask user: "Skip {MCP}? Requires {prerequisite}"
   └─ OK ↓
3. Search internet for latest compatible package version
   - Use WebSearch to find the npm/pypi package
   - NEVER use hardcoded versions from training data
   - Verify compatibility with project's detected stack
4. Install package (npx for npm, pip for Python)
5. Write MCP config to project's .mcp.json
6. Verify connectivity (run verify command if defined)
   ├─ FAIL → Retry once, then mark as unavailable (graceful degradation)
   └─ OK → Mark as available in state.json
```

## Configuration

Declared in `forge.local.md` `mcps:` section:

```yaml
mcps:
  neo4j:
    required: false          # graph is optional
    auto_install: true       # install if missing
    package: "@neo4j/mcp"    # npm package hint (resolved at install time)
    prerequisites: [docker]  # required system tools
    verify: "RETURN 1"       # Cypher query to verify connectivity
  playwright:
    required: false
    auto_install: true
    package: "@anthropic/mcp-playwright"
    prerequisites: []
    verify: null             # no verification needed
  linear:
    required: false
    auto_install: false      # requires user's API key, don't auto-install
    package: null
    verify: null
```

## .mcp.json Format

Written to the project root:

```json
{
  "mcpServers": {
    "neo4j": {
      "command": "npx",
      "args": ["-y", "@neo4j/mcp@{resolved_version}"],
      "env": {
        "NEO4J_URI": "bolt://localhost:7687",
        "NEO4J_USERNAME": "neo4j",
        "NEO4J_PASSWORD": "forge-local"
      }
    }
  }
}
```

## Version Resolution

Package versions are NEVER hardcoded. At install time:
1. Run `npm view {package} version` or search npm registry
2. Verify compatibility with project's Node.js version (from state.json.detected_versions)
3. Use the latest compatible version

See `shared/version-resolution.md` for the cross-cutting version resolution rule.

## Graceful Degradation

- MCP installation failure → skip, mark unavailable, log WARNING
- Verification failure → retry once, then skip, mark unavailable
- Missing prerequisites → ask user, skip if they decline
- No internet → skip all auto-installations
- Recovery engine NOT invoked for MCP provisioning failures
```

- [ ] **Step 2: Add MCP provisioning phase to forge-init**

In `skills/forge-init/SKILL.md`, add after the graph-init phase (Phase 6b or similar):

```markdown
### Phase 6c — MCP Provisioning

For each MCP listed in `forge.local.md` `mcps:` section where `auto_install: true`:

1. Check if already configured (search .mcp.json in project root)
2. If not configured:
   a. Check prerequisites (e.g., Docker for Neo4j)
   b. If prerequisites met: search internet for latest package version, install, write .mcp.json, verify
   c. If prerequisites missing: ask user to skip or install prerequisite
3. Report provisioned MCPs in the init summary

Follow `shared/mcp-provisioning.md` for the detailed flow.
```

- [ ] **Step 3: Write contract tests**

Create `tests/contract/mcp-provisioning.bats`:

```bash
#!/usr/bin/env bash

setup() {
  load '../lib/bats-support/load'
  load '../lib/bats-assert/load'
  PLUGIN_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  MCP_DOC="$PLUGIN_ROOT/shared/mcp-provisioning.md"
  FORGE_INIT="$PLUGIN_ROOT/skills/forge-init/SKILL.md"
}

@test "mcp: provisioning document exists" {
  [ -f "$MCP_DOC" ]
}

@test "mcp: provisioning flow documented" {
  grep -q "Provisioning Flow" "$MCP_DOC"
}

@test "mcp: .mcp.json format documented" {
  grep -q "mcp.json" "$MCP_DOC"
}

@test "mcp: version resolution references shared doc" {
  grep -q "version-resolution.md" "$MCP_DOC"
}

@test "mcp: graceful degradation documented" {
  grep -q "Graceful Degradation" "$MCP_DOC"
}

@test "mcp: forge-init has MCP provisioning phase" {
  grep -q "MCP Provisioning\|mcp-provisioning" "$FORGE_INIT"
}

@test "mcp: neo4j MCP documented with Docker prerequisite" {
  grep -q "neo4j" "$MCP_DOC"
  grep -q "docker\|Docker" "$MCP_DOC"
}

@test "mcp: never hardcode versions rule documented" {
  grep -qi "never.*hardcode\|NEVER.*version" "$MCP_DOC"
}
```

- [ ] **Step 4: Commit**

```bash
git add shared/mcp-provisioning.md skills/forge-init/SKILL.md tests/contract/mcp-provisioning.bats
git commit -m "feat(mcp): add MCP auto-provisioning with forge-init integration"
```

---

## Task 6: Add Init Automation — Project-Local Plugin Generation

**Files:**
- Modify: `skills/forge-init/SKILL.md`
- Test: `tests/contract/init-automation.bats`

- [ ] **Step 1: Add project-local plugin generation phase to forge-init**

In `skills/forge-init/SKILL.md`, add after the MCP provisioning phase:

```markdown
### Phase 6d — Project-Local Plugin Generation

Generate a project-local Claude Code plugin at `.claude/plugins/project-tools/` tailored to the detected project.

**Skip conditions:** If `.claude/plugins/project-tools/plugin.json` already exists, ask user whether to regenerate or skip.

#### 1. Create plugin manifest

Write `.claude/plugins/project-tools/plugin.json`:
```json
{
  "name": "project-tools",
  "version": "1.0.0",
  "description": "Project-specific automations generated by /forge-init"
}
```

#### 2. Generate hooks (if no existing commit hooks detected)

If `git.commit_enforcement` is NOT `external` (no existing hooks from Phase 2a):

Write `.claude/plugins/project-tools/hooks/hooks.json`:
```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/hooks/commit-msg-guard.sh",
            "timeout": 3
          }
        ]
      }
    ]
  }
}
```

Write `.claude/plugins/project-tools/hooks/commit-msg-guard.sh` (from `shared/git-conventions.md` commit validation pattern, customized with the project's `git.commit_types` from `forge.local.md`).

Write `.claude/plugins/project-tools/hooks/branch-name-guard.sh` (from `shared/git-conventions.md` branch validation pattern, customized with the project's `git.branch_template`).

Make both scripts executable: `chmod +x`.

#### 3. Generate skills

Detect build/test/lint/deploy tools and generate wrapper skills:

| Detection | Skill | Command |
|-----------|-------|---------|
| `build.gradle.kts` or `build.gradle` | `/build` | `./gradlew build` |
| `build.gradle.kts` + test task | `/run-tests` | `./gradlew test` |
| `package.json` + vitest/jest | `/run-tests` | `npm run test` |
| `Makefile` | `/build` | `make build` |
| `pyproject.toml` + pytest | `/run-tests` | `pytest` |
| `Cargo.toml` | `/build`, `/run-tests` | `cargo build`, `cargo test` |
| `Dockerfile` + `docker-compose.yml` | `/deploy` | `docker compose up --build` |
| detekt/eslint/ruff/biome config | `/lint` | Appropriate lint command |

Each generated skill is a minimal `SKILL.md`:

```markdown
---
name: run-tests
description: Run project test suite (generated by /forge-init)
---

Run the project's test suite:

\`\`\`bash
{detected_command}
\`\`\`

Report results. If tests fail, show the failure summary.
```

#### 4. Generate commit reviewer agent (optional)

Write `.claude/plugins/project-tools/agents/commit-reviewer.md` — a lightweight agent that reviews staged changes before commit, checking for convention compliance.

#### 5. Offer implementation tasks

After generating the plugin, check if any accepted tools need implementation:

Ask user via `AskUserQuestion`:
```
Header: "Setup Tasks"
Question: "The following tools need implementation to integrate into your project:"
{list of tools that need build config changes}

Options:
  A) Run /forge-run to implement all setup tasks now
  B) Add to backlog (creates tickets in .forge/tracking/backlog/)
  C) Skip — configure manually later
```

If (A): Create tickets, dispatch `/forge-run` with bundled requirement.
If (B): Create tickets for future runs.
```

- [ ] **Step 2: Write contract tests**

Create `tests/contract/init-automation.bats`:

```bash
#!/usr/bin/env bash

setup() {
  load '../lib/bats-support/load'
  load '../lib/bats-assert/load'
  PLUGIN_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  FORGE_INIT="$PLUGIN_ROOT/skills/forge-init/SKILL.md"
}

@test "init-auto: forge-init documents project-local plugin generation" {
  grep -q "project-tools\|Project-Local Plugin" "$FORGE_INIT"
}

@test "init-auto: forge-init generates plugin.json" {
  grep -q "plugin.json" "$FORGE_INIT"
}

@test "init-auto: forge-init generates commit-msg-guard hook" {
  grep -q "commit-msg-guard" "$FORGE_INIT"
}

@test "init-auto: forge-init generates branch-name-guard hook" {
  grep -q "branch-name-guard" "$FORGE_INIT"
}

@test "init-auto: forge-init generates wrapper skills (run-tests, build, lint)" {
  grep -q "run-tests" "$FORGE_INIT"
  grep -q "/build" "$FORGE_INIT"
  grep -q "/lint" "$FORGE_INIT"
}

@test "init-auto: forge-init offers implementation tasks" {
  grep -q "Run /forge-run to implement\|setup tasks" "$FORGE_INIT"
}

@test "init-auto: forge-init respects existing hooks (commit_enforcement: external)" {
  grep -q "commit_enforcement.*external\|existing.*hooks" "$FORGE_INIT"
}

@test "init-auto: forge-init generates commit-reviewer agent" {
  grep -q "commit-reviewer" "$FORGE_INIT"
}
```

- [ ] **Step 3: Commit**

```bash
git add skills/forge-init/SKILL.md tests/contract/init-automation.bats
git commit -m "feat(init): add project-local plugin generation with hooks, skills, agents"
```

---

## Task 7: Add Version Resolution Constraint

**Files:**
- Create: `shared/version-resolution.md`
- Modify: `shared/agent-defaults.md`

- [ ] **Step 1: Create version-resolution.md**

Create `shared/version-resolution.md`:

```markdown
# Version Resolution (Cross-Cutting Constraint)

## Rule

**Agents must NEVER use versions from training data or memory.** Whenever adding, recommending, or configuring a dependency, package, plugin, MCP server, or tool version, agents must:

1. Search the internet (via `WebSearch` or `Context7 MCP`) for the current latest version
2. Verify compatibility with the project's detected stack versions (from `state.json.detected_versions`)
3. Use the verified latest compatible version

## Rationale

AI training data contains stale version information. Using it leads to:
- Installing outdated packages with known vulnerabilities
- Version conflicts with the project's existing dependencies
- Deprecated API usage

## Applies To

- `/forge-init` — all dependency recommendations, MCP package installation, code quality tool versions
- `/forge-run` — any dependency added during implementation
- `/forge-fix` — any dependency update as part of a bugfix
- `fg-050-project-bootstrapper` — all scaffold dependencies
- `fg-310-scaffolder` — all generated dependency declarations
- `fg-140-deprecation-refresh` — when checking deprecation against current versions
- Project-local plugin generation — MCP server packages, hook tool versions

## Implementation

Agents that add dependencies must have `WebSearch` in their tools list or delegate version resolution to the orchestrator (which passes resolved versions via stage notes).

If internet is unavailable:
- Warn user: "Cannot verify latest version — using last known compatible version from project config"
- Fall back to the version already in the project's manifest files
- NEVER fall back to training data versions
```

- [ ] **Step 2: Add to agent-defaults.md**

In `shared/agent-defaults.md`, add a new section:

```markdown
## Version Resolution (MANDATORY)

Never hardcode or assume dependency versions. Before writing any version number:
1. Search the internet for the latest release of the package
2. Check compatibility with detected project versions in `state.json.detected_versions`
3. Use the latest compatible version

Rationale: Training data versions are stale. Always resolve at runtime. See `shared/version-resolution.md` for full details.
```

- [ ] **Step 3: Commit**

```bash
git add shared/version-resolution.md shared/agent-defaults.md
git commit -m "docs: add version resolution cross-cutting constraint"
```

---

## Task 8: Update Documentation + Version Bump + Structural Validation

**Files:**
- Modify: `CLAUDE.md`, `CONTRIBUTING.md`
- Modify: `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`
- Modify: `tests/validate-plugin.sh`
- Modify: `shared/graph/seed.cypher` (regenerate)

- [ ] **Step 1: Update CLAUDE.md**

Add/update these sections:

1. Version: `v1.2.0` → `v1.3.0`
2. In Key entry points table, add:
   ```
   | MCP provisioning | `shared/mcp-provisioning.md` (auto-install rules)  |
   | Version resolution | `shared/version-resolution.md` (never hardcode versions) |
   ```
3. In the Knowledge Graph section, mention distributed access to 5 agents and patterns 14-15.
4. In the Check engine section, mention smart tool recommendations with exclusive_group.
5. Add a new subsection under Key conventions:
   ```markdown
   ### Init Automation (`.claude/plugins/project-tools/`)

   `/forge-init` generates a project-local plugin with hooks (commit-msg-guard, branch-name-guard), skills (/run-tests, /build, /lint, /deploy), and agents (commit-reviewer). Respects existing project hooks — never overrides. See `forge-init/SKILL.md` Phase 6d.
   ```
6. In Gotchas, add:
   ```markdown
   ### Version resolution

   Agents must NEVER use dependency versions from training data. Always search the internet for latest compatible version. See `shared/version-resolution.md`.
   ```

- [ ] **Step 2: Update CONTRIBUTING.md**

Add notes about code-quality module frontmatter, MCP provisioning, and version resolution.

- [ ] **Step 3: Version bump**

```bash
sed -i '' 's/"1.2.0"/"1.3.0"/' .claude-plugin/plugin.json .claude-plugin/marketplace.json
```

Update CLAUDE.md and README.md version references.

- [ ] **Step 4: Add structural checks**

In `tests/validate-plugin.sh`, add:

```bash
echo ""
echo "--- PHASE 4: GRAPH + INIT ---"

# mcp-provisioning.md exists
check "mcp-provisioning.md exists" "[ -f '$ROOT/shared/mcp-provisioning.md' ]"

# version-resolution.md exists
check "version-resolution.md exists" "[ -f '$ROOT/shared/version-resolution.md' ]"

# All code-quality modules have frontmatter
# (count files with --- on line 1)
fm_count=0
fm_total=0
for f in "$ROOT"/modules/code-quality/*.md; do
  fm_total=$((fm_total + 1))
  head -1 "$f" | grep -q "^---$" && fm_count=$((fm_count + 1)) || true
done
check "All code-quality modules have frontmatter ($fm_count/$fm_total)" "[ '$fm_count' -eq '$fm_total' ]"

# query-patterns.md has 15 patterns
pattern_count=$(grep -c "^## Pattern" "$ROOT/shared/graph/query-patterns.md" 2>/dev/null || echo 0)
check "query-patterns.md has 15 patterns ($pattern_count)" "[ '$pattern_count' -ge 15 ]"
```

- [ ] **Step 5: Regenerate seed.cypher**

```bash
./shared/graph/generate-seed.sh
```

- [ ] **Step 6: Run full test suite**

```bash
./tests/validate-plugin.sh && ./tests/run-all.sh
```

- [ ] **Step 7: Commit**

```bash
git add CLAUDE.md CONTRIBUTING.md .claude-plugin/ tests/validate-plugin.sh shared/graph/seed.cypher
git commit -m "docs: document Phase 4 features, bump version to 1.3.0"
```
