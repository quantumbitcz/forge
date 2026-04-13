# F20: Monorepo Build System Modules (Nx, Turborepo)

## Status
DRAFT — 2026-04-13

## Problem Statement

Forge supports 7 build systems: Gradle, Maven, npm, Cargo, Go, CMake, and Bazel. However, it lacks modules for the two dominant monorepo orchestration tools: **Nx** (16M+ weekly downloads) and **Turborepo** (5M+ weekly downloads). These tools sit *above* package managers — they manage task execution, caching, affected detection, and dependency graph traversal across multiple packages in a monorepo.

**Impact of missing support:**
- **Test selection:** Without affected detection, Forge runs all tests instead of only tests for changed packages. This wastes tokens and time in large monorepos.
- **Build scoping:** The implementer modifies files across the entire repo instead of scoping to affected packages.
- **Caching unawareness:** Forge may re-build packages that Nx/Turborepo have already cached, or worse, invalidate caches by running builds in non-standard ways.
- **Project graph ignorance:** Monorepo dependency graphs reveal which packages are affected by a change — critical for review scoping and regression detection.

**Scale of the problem:** Companies using Nx or Turborepo typically have 5-50+ packages in a workspace. Running full tests across all packages when only 2 are affected is a 5-25x overhead.

## Proposed Solution

Add two new build system modules (`modules/build-systems/nx/` and `modules/build-systems/turborepo/`) with conventions, affected detection integration, cache awareness, and project graph support. Auto-detect at PREFLIGHT and integrate with test gate, implementer, and review scoping.

## Detailed Design

### Architecture

```
PREFLIGHT (Stage 0)
     |
     +-- Detect nx.json or turbo.json in project root
     +-- Load appropriate module
     +-- Extract workspace package list
     +-- Determine affected packages (against base branch)
     |
     v
state.json.monorepo = {
  tool: "nx" | "turborepo",
  packages: [...],
  affected: [...],
  dependency_graph: {...}
}
     |
     v
IMPLEMENTING (Stage 4)          VERIFYING (Stage 5)           REVIEWING (Stage 6)
  +-- Scope to affected           +-- Run affected tests       +-- Scope review to
      packages only                    only                         affected packages
```

### Module: Nx (`modules/build-systems/nx/`)

**`conventions.md`:**

```markdown
# Nx Monorepo Conventions

## Workspace Structure
- `nx.json` — workspace configuration (target defaults, plugins, task pipeline)
- `project.json` — per-project targets (build, test, lint, serve)
- `workspace.json` or inferred from directory structure
- Packages typically in `apps/`, `libs/`, `packages/`

## Dos
- Use `nx affected` for targeted task execution
- Respect Nx task pipeline (dependent tasks run in correct order)
- Use Nx generators for scaffolding (maintain consistency)
- Pin Nx version across the workspace
- Use `@nx/enforce-module-boundaries` lint rule for import restrictions

## Don'ts
- Don't run `npm test` at root — use `nx run-many` or `nx affected`
- Don't bypass Nx cache (unless explicitly debugging)
- Don't create circular dependencies between projects
- Don't import from project internals — use public API (index.ts)
```

**Key Nx commands:**

| Purpose | Command |
|---|---|
| Affected test | `nx affected -t test --base=origin/main` |
| Affected build | `nx affected -t build --base=origin/main` |
| Affected lint | `nx affected -t lint --base=origin/main` |
| Project graph (JSON) | `nx graph --file=output.json` |
| List projects | `nx show projects` |
| List affected | `nx show projects --affected --base=origin/main` |

**Cache awareness:**
- Nx remote cache (Nx Cloud or custom): check `nx.json` for `tasksRunnerOptions` or `nxCloudAccessToken`
- Local cache: `.nx/cache/` directory
- When running builds via Forge, pass through Nx so caching is preserved
- Never run underlying build tools directly (e.g., `tsc`, `jest`) — always go through `nx run {project}:{target}`

### Module: Turborepo (`modules/build-systems/turborepo/`)

**`conventions.md`:**

```markdown
# Turborepo Monorepo Conventions

## Workspace Structure
- `turbo.json` — pipeline configuration (tasks, dependencies, outputs, inputs)
- Uses npm/yarn/pnpm workspaces for package resolution
- Packages typically in `apps/`, `packages/`

## Dos
- Use `turbo run` for all task execution
- Respect task pipeline in `turbo.json` (topological dependencies)
- Use `--filter` for package-scoped execution
- Configure `outputs` in turbo.json for correct cache behavior
- Use `--dry-run` to preview affected packages

## Don'ts
- Don't run tasks outside turbo (bypasses caching and dependency order)
- Don't use `*` glob in turbo.json outputs (too broad, cache invalidation)
- Don't create workspace-internal dependencies without declaring in turbo.json
```

**Key Turborepo commands:**

| Purpose | Command |
|---|---|
| Affected test | `turbo run test --filter=...[origin/main]` |
| Affected build | `turbo run build --filter=...[origin/main]` |
| Affected lint | `turbo run lint --filter=...[origin/main]` |
| Dry run (list affected) | `turbo run build --filter=...[origin/main] --dry-run=json` |
| Package graph | `turbo run build --graph=output.json` |

**Cache awareness:**
- Remote cache: check for `TURBO_TOKEN` and `TURBO_TEAM` env vars or `turbo.json` `remoteCache` config
- Local cache: `node_modules/.cache/turbo/` directory
- Forge must always run tasks through `turbo run` to preserve cache integrity

### Schema / Data Model

**Monorepo state** (new section in `state.json`):

```json
{
  "monorepo": {
    "detected": true,
    "tool": "nx",
    "tool_version": "19.8.0",
    "workspace_root": "/Users/dev/project",
    "packages": [
      { "name": "api", "path": "apps/api", "type": "application" },
      { "name": "web", "path": "apps/web", "type": "application" },
      { "name": "shared-types", "path": "libs/shared-types", "type": "library" },
      { "name": "ui-kit", "path": "libs/ui-kit", "type": "library" }
    ],
    "affected": ["api", "shared-types"],
    "dependency_graph": {
      "api": ["shared-types"],
      "web": ["shared-types", "ui-kit"],
      "shared-types": [],
      "ui-kit": ["shared-types"]
    },
    "cache": {
      "remote_enabled": true,
      "provider": "nx-cloud"
    }
  }
}
```

### Configuration

In `forge-config.md`:

```yaml
# Monorepo tooling (v2.0+)
monorepo:
  enabled: auto                  # Auto-detect from nx.json / turbo.json. Or explicit: nx, turborepo, false.
  affected_base: origin/main     # Base ref for affected detection. Default: origin/main.
  scope_implementation: true     # Scope implementer to affected packages only. Default: true.
  scope_testing: true            # Run tests only for affected packages. Default: true.
  scope_review: true             # Scope review to affected packages. Default: true.
  respect_cache: true            # Always run tasks through monorepo tool (preserve cache). Default: true.
  graph_integration: true        # Import monorepo dependency graph into code graph (if Neo4j enabled). Default: true.
```

**PREFLIGHT validation constraints:**

| Parameter | Range | Default | Rationale |
|---|---|---|---|
| `monorepo.enabled` | `auto`, `nx`, `turborepo`, `false` | `auto` | Auto-detection is reliable (check for config files) |
| `monorepo.affected_base` | valid git ref | `origin/main` | Must be a reachable ref |
| `monorepo.scope_implementation` | boolean | `true` | Core value prop: targeted implementation |
| `monorepo.scope_testing` | boolean | `true` | Core value prop: targeted testing |

### Data Flow

**PREFLIGHT — detection and affected analysis:**

1. Orchestrator checks for `nx.json` at project root -> `tool: nx`
2. Or checks for `turbo.json` at project root -> `tool: turborepo`
3. If neither found: `monorepo.detected: false`, skip monorepo logic
4. Run affected detection:
   - Nx: `nx show projects --affected --base={affected_base} --json`
   - Turborepo: `turbo run build --filter=...[{affected_base}] --dry-run=json`
5. Extract package list and dependency graph
6. Store in `state.json.monorepo`

**IMPLEMENTING — scoped implementation:**

1. Implementer reads `state.json.monorepo.affected`
2. Limits file modifications to directories of affected packages
3. If changes are needed in non-affected packages (shared type updates), add those packages to the affected list and re-run affected detection
4. Uses monorepo tool for build verification: `nx run {package}:build` instead of global build

**VERIFYING — targeted testing:**

1. Test gate reads `state.json.monorepo.affected`
2. Constructs test command using monorepo tool:
   - Nx: `nx run-many -t test -p api,shared-types`
   - Turborepo: `turbo run test --filter=api --filter=shared-types`
3. Falls back to full test run if affected detection fails
4. Build verifier uses monorepo tool:
   - Nx: `nx run-many -t build -p api,shared-types`
   - Turborepo: `turbo run build --filter=api --filter=shared-types`

**REVIEWING — scoped review:**

1. Quality gate reads `state.json.monorepo.affected`
2. Review agents focus on files within affected packages
3. Architecture reviewer checks cross-package import boundaries
4. If Nx: verify `@nx/enforce-module-boundaries` compliance

### Code Graph Integration

When Neo4j is available and `graph_integration: true`:

1. At PREFLIGHT, import monorepo dependency graph as nodes and edges:
   - Node type: `Package` with properties: name, path, type (app/lib)
   - Edge type: `DEPENDS_ON` between packages
2. Merge with existing code graph (function/class nodes gain a `package` property)
3. Graph queries can now scope by package:
   - "Which functions in `api` call functions in `shared-types`?"
   - "What is the transitive dependency set of `web`?"

### Integration Points

| File | Change |
|---|---|
| `modules/build-systems/nx/` | NEW — module directory with `conventions.md`, `rules-override.json`, `known-deprecations.json` |
| `modules/build-systems/turborepo/` | NEW — module directory with `conventions.md`, `rules-override.json`, `known-deprecations.json` |
| `agents/fg-100-orchestrator.md` | Add PREFLIGHT step for monorepo detection and affected analysis. Pass `monorepo` state to all downstream agents. |
| `agents/fg-300-implementer.md` | Read `state.json.monorepo.affected` to scope file modifications. Use monorepo tool for builds. |
| `agents/fg-505-build-verifier.md` | Use monorepo-scoped build commands when `monorepo.detected`. |
| `agents/fg-500-test-gate.md` | Use monorepo-scoped test commands when `monorepo.detected`. |
| `agents/fg-400-quality-gate.md` | Scope review to affected packages when `monorepo.scope_review`. |
| `agents/fg-412-architecture-reviewer.md` | Check cross-package import boundaries. Verify module boundary lint rules. |
| `shared/state-schema.md` | Document `monorepo` section in state.json. |
| `shared/learnings/nx.md` | NEW — learnings file for Nx patterns. |
| `shared/learnings/turborepo.md` | NEW — learnings file for Turborepo patterns. |
| `shared/graph/schema.md` | Add `Package` node type and `DEPENDS_ON` edge for monorepo graph. |
| `modules/frameworks/*/forge-config-template.md` | Add `monorepo:` section. |
| `CLAUDE.md` | Update build system count from 7 to 9. |
| `tests/lib/module-lists.bash` | Bump `MIN_BUILD_SYSTEMS` from 7 to 9. |

### Error Handling

**Failure mode 1: nx.json or turbo.json present but tool not installed.**
- Detection: Config file exists but `nx`/`turbo` command not found
- Behavior: Set `monorepo.detected: true` but `monorepo.tool_available: false`. Fall back to non-monorepo behavior. Emit WARNING: "Nx/Turborepo config detected but CLI not available. Install with `npm install -g nx` / `npx turbo`. Running without monorepo scoping."

**Failure mode 2: Affected detection fails.**
- Detection: `nx show projects --affected` or `turbo run --dry-run` returns error
- Behavior: Fall back to treating all packages as affected. Emit INFO: "Affected detection failed. Running tests for all packages."

**Failure mode 3: Affected list is empty.**
- Detection: No packages are affected (e.g., only root config changed)
- Behavior: If changed files exist but no packages are affected, the changes are likely workspace-level (root config, CI files). Run all tests as a safety measure.

**Failure mode 4: Circular dependency in monorepo graph.**
- Detection: Nx/Turborepo reports circular dependency error
- Behavior: Emit `ARCH-CIRCULAR-DEP` (CRITICAL): "Circular dependency detected between packages: {list}". Pipeline continues but flags the architectural issue.

**Failure mode 5: Monorepo config is stale or misconfigured.**
- Detection: `nx.json` references projects that don't exist, or `turbo.json` pipeline references unknown tasks
- Behavior: Emit CONV finding for the specific misconfiguration. Fall back to non-monorepo behavior for affected components.

## Performance Characteristics

**Affected detection:**

| Tool | Time | Notes |
|---|---|---|
| `nx show projects --affected` | 2-10s | Depends on workspace size and Nx daemon status |
| `turbo run --dry-run` | 1-5s | Depends on workspace size |
| Graph extraction | 1-5s | JSON output from nx/turbo |
| **Total PREFLIGHT overhead** | **4-20s** | One-time per run |

**Net savings from scoped execution:**

| Scenario | Without Monorepo | With Monorepo | Savings |
|---|---|---|---|
| 20-package workspace, 2 affected | Run all 20 packages | Run 2 packages | ~90% |
| 10-package workspace, 4 affected | Run all 10 packages | Run 4 packages | ~60% |
| 5-package workspace, 3 affected | Run all 5 packages | Run 3 packages | ~40% |

The 4-20s PREFLIGHT overhead is recouped many times over by scoped testing and building.

## Testing Approach

### Structural Tests (`tests/structural/`)

1. **Module structure:** `modules/build-systems/nx/` and `modules/build-systems/turborepo/` contain required files (`conventions.md`, `rules-override.json`, `known-deprecations.json`)
2. **Module count:** `MIN_BUILD_SYSTEMS` in `module-lists.bash` is 9
3. **Learnings files:** `shared/learnings/nx.md` and `shared/learnings/turborepo.md` exist
4. **Config template:** All `forge-config-template.md` files include `monorepo:` section

### Unit Tests (`tests/unit/`)

1. **`monorepo-detection.bats`:**
   - `nx.json` present: detected as Nx
   - `turbo.json` present: detected as Turborepo
   - Neither present: `monorepo.detected: false`
   - Both present: Nx takes precedence (it is more specific)
   - Config `monorepo.enabled: false` overrides auto-detection

2. **`monorepo-scoping.bats`:**
   - Test command uses `nx run-many -t test -p {affected}` for Nx workspaces
   - Test command uses `turbo run test --filter={affected}` for Turborepo workspaces
   - Empty affected list falls back to full test run
   - `scope_testing: false` runs all packages regardless

3. **`monorepo-conventions.bats`:**
   - Nx conventions file includes Dos and Don'ts sections
   - Turborepo conventions file includes Dos and Don'ts sections
   - Known deprecations JSON validates against v2 schema

## Acceptance Criteria

1. Nx workspace auto-detected from `nx.json` at PREFLIGHT
2. Turborepo workspace auto-detected from `turbo.json` at PREFLIGHT
3. Affected packages determined using monorepo tool's native affected detection
4. Test gate runs tests only for affected packages (when `scope_testing: true`)
5. Build verifier runs builds only for affected packages
6. Implementer scopes file modifications to affected packages (when `scope_implementation: true`)
7. Review agents scope analysis to affected packages (when `scope_review: true`)
8. All tasks run through monorepo tool to preserve cache (when `respect_cache: true`)
9. Monorepo dependency graph imported into Neo4j code graph (when available)
10. Graceful fallback when monorepo tool is not installed (non-monorepo behavior)
11. Convention files follow existing build system module structure
12. Learnings files created for both Nx and Turborepo

## Migration Path

**From v1.20.1 to v2.0:**

1. **Zero breaking changes.** Monorepo detection is additive. Projects without `nx.json` or `turbo.json` are completely unaffected.
2. **New modules:** Two directories added to `modules/build-systems/`. Existing modules untouched.
3. **Auto-detection default:** `monorepo.enabled: auto` means existing projects gain monorepo support automatically if they have the config files.
4. **Agent updates:** Orchestrator, implementer, test gate, build verifier, and quality gate gain conditional monorepo logic. When `monorepo.detected: false`, all new code paths are skipped.
5. **Build system count:** CLAUDE.md updated from 7 to 9. Test threshold bumped.
6. **Graph schema:** New `Package` node type added. Existing node types unchanged.
7. **No new external dependencies.** Nx and Turborepo are project dependencies, not plugin dependencies.

## Dependencies

**This feature depends on:**
- PREFLIGHT file detection (already scans for `build.gradle`, `pom.xml`, `package.json`, etc.)
- `fg-500-test-gate` test command configuration (already supports custom test commands)
- `fg-505-build-verifier` build command configuration
- Neo4j graph schema (optional, for dependency graph import)

**Other features that benefit from this:**
- F17 (Performance Tracking): monorepo-scoped metrics (per-package build time, test duration)
- F14 (Predictive Test Selection, if implemented): affected detection provides a strong signal for test selection
- Sprint orchestration: monorepo package boundaries can inform feature isolation for parallel sprints
