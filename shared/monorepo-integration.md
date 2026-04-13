# Monorepo Integration

Monorepo build tool detection and integration for Nx and Turborepo workspaces. Provides affected detection, scoped testing/building/review, and cache-aware task execution.

## Auto-Detection at PREFLIGHT

The orchestrator checks for monorepo config files during PREFLIGHT (Stage 0):

1. Check for `nx.json` at project root -> `tool: nx`
2. Check for `turbo.json` at project root -> `tool: turborepo`
3. If neither found: `monorepo.detected: false`, skip all monorepo logic
4. If both found: `nx` takes precedence (Nx is more specific; some projects use both)

When detected, the orchestrator populates `state.json.monorepo`:

```json
{
  "monorepo": {
    "detected": true,
    "tool": "nx",
    "tool_available": true,
    "packages": [
      { "name": "api", "path": "apps/api", "type": "application" },
      { "name": "shared-types", "path": "libs/shared-types", "type": "library" }
    ],
    "affected": ["api", "shared-types"],
    "dependency_graph": {
      "api": ["shared-types"],
      "web": ["shared-types", "ui-kit"]
    },
    "cache": {
      "remote_enabled": true,
      "provider": "nx-cloud"
    }
  }
}
```

### Tool Availability Check

Config file present does NOT mean the CLI is available:
- `nx.json` exists but `nx` not found -> `tool_available: false`, WARNING emitted, fall back to non-monorepo behavior
- `turbo.json` exists but `turbo` not found -> `tool_available: false`, WARNING emitted, fall back to non-monorepo behavior

## Affected Detection

Affected detection determines which packages are impacted by changes against a base branch.

### Nx

```bash
# List affected projects
nx show projects --affected --base=${affected_base} --json

# Run targeted tasks
nx run-many -t test -p api,shared-types
nx run-many -t build -p api,shared-types
nx run-many -t lint -p api,shared-types
```

### Turborepo

```bash
# Dry run to list affected
turbo run build --filter=...[${affected_base}] --dry-run=json

# Run targeted tasks
turbo run test --filter=api --filter=shared-types
turbo run build --filter=api --filter=shared-types
turbo run lint --filter=api --filter=shared-types
```

### Fallback Behavior

- If affected detection command fails: treat all packages as affected, emit INFO finding
- If affected list is empty but changed files exist: changes are workspace-level (root config, CI), run all tests as safety measure
- If circular dependency detected: emit `ARCH-CIRCULAR-DEP` (CRITICAL), pipeline continues

## Integration with Test Gate (Stage 5)

When `monorepo.scope_testing: true` and `monorepo.detected: true`:

1. Test gate reads `state.json.monorepo.affected`
2. Constructs scoped test command:
   - Nx: `nx run-many -t test -p {affected_packages}`
   - Turborepo: `turbo run test --filter={pkg1} --filter={pkg2}`
3. Falls back to full test run if affected detection failed
4. Build verifier similarly scopes:
   - Nx: `nx run-many -t build -p {affected_packages}`
   - Turborepo: `turbo run build --filter={pkg1} --filter={pkg2}`

### Integration with Predictive Test Selection (F14)

When both monorepo affected detection and predictive test selection are available:
1. Monorepo affected detection narrows to affected packages (coarse filter)
2. Predictive test selection further narrows to likely-failing tests within those packages (fine filter)
3. The intersection provides maximum precision: only tests in affected packages that are predicted to fail run first

## Integration with Implementer (Stage 4)

When `monorepo.scope_implementation: true`:

1. Implementer reads `state.json.monorepo.affected`
2. Scopes file modifications to directories of affected packages
3. If changes require non-affected packages (e.g., shared type updates): adds those packages to affected list and re-runs affected detection
4. Uses monorepo tool for build verification: `nx run {package}:build` instead of global build

## Integration with Review (Stage 6)

When `monorepo.scope_review: true`:

1. Quality gate reads `state.json.monorepo.affected`
2. Review agents focus on files within affected packages
3. Architecture reviewer checks cross-package import boundaries
4. For Nx: verifies `@nx/enforce-module-boundaries` compliance

## Integration with Code Graph

When Neo4j is available and `monorepo.graph_integration: true`:

1. At PREFLIGHT, import monorepo dependency graph as nodes and edges:
   - Node type: `Package` (name, path, type: app/lib)
   - Edge type: `DEPENDS_ON` between packages
2. Merge with existing code graph (function/class nodes gain a `package` property)
3. Enables graph queries scoped by package:
   - "Which functions in `api` call functions in `shared-types`?"
   - "What is the transitive dependency set of `web`?"

## Configuration

In `forge-config.md` or `forge.local.md`:

```yaml
# Monorepo (v2.0+)
monorepo:
  tool: auto                     # auto | nx | turborepo | none
  affected_base: origin/main     # Base ref for affected detection
  scope_to_affected: true        # Scope testing/building/review to affected packages
```

### Configuration Parameters

| Parameter | Range | Default | Description |
|---|---|---|---|
| `monorepo.tool` | `auto`, `nx`, `turborepo`, `none` | `auto` | Auto-detect from config files, or force a specific tool |
| `monorepo.affected_base` | valid git ref | `origin/main` | Base branch for affected detection |
| `monorepo.scope_to_affected` | boolean | `true` | Scope testing, building, and review to affected packages only |

### Overriding Auto-Detection

```yaml
# Force Nx even if turbo.json also exists
monorepo:
  tool: nx

# Disable monorepo integration entirely
monorepo:
  tool: none
```

## Error Handling

| Failure | Behavior | Finding |
|---|---|---|
| Config file present but CLI not found | Fall back to non-monorepo | WARNING |
| Affected detection command fails | Treat all packages as affected | INFO |
| Empty affected list with changed files | Run all tests (safety) | INFO |
| Circular dependency in graph | Pipeline continues, flag issue | `ARCH-CIRCULAR-DEP` (CRITICAL) |
| Stale/misconfigured config | Fall back for affected components | `CONV-*` finding |
