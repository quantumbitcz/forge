# Nx Monorepo Conventions

> Support tier: community

## Overview

Nx is a monorepo build orchestration tool that manages task execution, caching, affected detection, and dependency graph traversal across multiple packages in a workspace. Nx sits above package managers (npm, pnpm, yarn) — it does not replace them, it orchestrates them. Nx provides two workspace styles: integrated (Nx-managed project structure with `project.json` per project) and package-based (standard npm workspaces with `package.json` per project).

- **Use for:** JavaScript/TypeScript monorepos with 5+ packages, polyglot monorepos using Nx plugins, projects requiring smart affected detection and remote caching, teams that need enforced module boundaries and project graph visualization
- **Avoid for:** single-package projects (overhead exceeds benefit), projects already using Bazel (Bazel provides stronger hermeticity), projects with no shared code between packages
- **vs Turborepo:** Nx has richer plugin ecosystem, code generators, module boundary enforcement, and project graph visualization. Turborepo is simpler to adopt for basic task orchestration and caching.

## Workspace Structure

- `nx.json` — workspace configuration (target defaults, plugins, named inputs, task pipeline, cache settings)
- `project.json` — per-project targets in integrated workspaces (build, test, lint, serve)
- `workspace.json` — legacy workspace config (Nx <13), replaced by `nx.json` + inferred project config
- Packages typically in `apps/`, `libs/`, `packages/`, `tools/`
- `.nx/` — local cache directory (gitignored)

### Integrated Workspace

```
monorepo/
  nx.json
  tsconfig.base.json
  apps/
    web/
      project.json
      src/
    api/
      project.json
      src/
  libs/
    shared-types/
      project.json
      src/
    ui-kit/
      project.json
      src/
  tools/
    scripts/
```

### Package-Based Workspace

```
monorepo/
  nx.json
  package.json          (npm/pnpm/yarn workspaces)
  packages/
    web/
      package.json
      src/
    api/
      package.json
      src/
    shared-types/
      package.json
      src/
```

## Key Commands

| Purpose | Command |
|---|---|
| Affected test | `nx affected -t test --base=origin/main` |
| Affected build | `nx affected -t build --base=origin/main` |
| Affected lint | `nx affected -t lint --base=origin/main` |
| Run target for specific projects | `nx run-many -t test -p api,shared-types` |
| Project graph (JSON) | `nx graph --file=output.json` |
| List all projects | `nx show projects` |
| List affected projects | `nx show projects --affected --base=origin/main` |
| Run single project target | `nx run api:build` |
| Generate code | `nx generate @nx/react:component --project=ui-kit` |

## Affected Detection

Nx's affected detection compares the current state against a base ref (typically `origin/main`) and determines which projects are affected by file changes. It uses the project dependency graph — if `shared-types` changes, all projects that depend on it are marked as affected.

```bash
# Show affected projects
nx show projects --affected --base=origin/main

# Run tests only for affected projects
nx affected -t test --base=origin/main

# Dry run — show what would execute
nx affected -t build --base=origin/main --dry-run
```

Named inputs in `nx.json` control what file changes trigger cache invalidation:
```json
{
  "namedInputs": {
    "default": ["{projectRoot}/**/*", "sharedGlobals"],
    "sharedGlobals": ["{workspaceRoot}/tsconfig.base.json"],
    "production": ["default", "!{projectRoot}/**/*.spec.ts"]
  }
}
```

## Task Pipeline

The `targetDefaults` in `nx.json` defines task dependencies:
```json
{
  "targetDefaults": {
    "build": {
      "dependsOn": ["^build"],
      "inputs": ["production", "^production"],
      "outputs": ["{projectRoot}/dist"]
    },
    "test": {
      "dependsOn": ["build"],
      "inputs": ["default", "^production"]
    },
    "lint": {
      "inputs": ["default"]
    }
  }
}
```

The `^` prefix means "dependencies first" — `^build` means all dependency projects must build before the current project builds.

## Remote Caching

Nx supports remote caching via Nx Cloud or custom runners:
- Check `nx.json` for `nxCloudAccessToken` or `tasksRunnerOptions` with remote runner
- Local cache: `.nx/cache/` directory
- Remote cache: shared across CI and developer machines

```json
{
  "nxCloudAccessToken": "...",
  "tasksRunnerOptions": {
    "default": {
      "runner": "nx-cloud",
      "options": {
        "accessToken": "..."
      }
    }
  }
}
```

## Module Boundaries

Nx provides `@nx/enforce-module-boundaries` ESLint rule to enforce architectural constraints:
```json
{
  "rules": {
    "@nx/enforce-module-boundaries": [
      "error",
      {
        "depConstraints": [
          { "sourceTag": "type:app", "onlyDependOnLibsWithTags": ["type:lib"] },
          { "sourceTag": "scope:api", "onlyDependOnLibsWithTags": ["scope:shared", "scope:api"] }
        ]
      }
    ]
  }
}
```

Projects are tagged in `project.json`:
```json
{
  "tags": ["type:lib", "scope:shared"]
}
```

## Generators and Executors

- **Generators** scaffold code consistently: `nx generate @nx/react:component Button --project=ui-kit`
- **Executors** run targets: build, test, lint, serve. Configured in `project.json` or inferred from `package.json` scripts.
- Custom generators/executors in `tools/` extend Nx for project-specific patterns.

## Dos

- Use `nx affected` for targeted task execution — never run all tasks when only a subset of packages changed
- Respect Nx task pipeline (`dependsOn` in `targetDefaults`) — dependent tasks run in correct order automatically
- Use Nx generators for scaffolding new projects and components to maintain consistency
- Pin Nx version across the workspace using `package.json` — version mismatches between `nx` and `@nx/*` plugins cause hard-to-debug failures
- Use `@nx/enforce-module-boundaries` lint rule to enforce import restrictions between projects
- Configure `namedInputs` to control cache granularity — avoid over-broad inputs that invalidate cache unnecessarily
- Use project tags (`tags` in `project.json`) to categorize projects by type (app/lib) and scope (feature domain)
- Run `nx graph` to visualize and verify the project dependency graph before major refactors
- Configure `outputs` in `targetDefaults` so Nx knows which files to cache per target
- Use `nx migrate` for Nx version upgrades — it generates migration scripts for breaking changes

## Don'ts

- Don't run `npm test` or `npm run build` at root — use `nx run-many` or `nx affected` to preserve caching and dependency ordering
- Don't bypass Nx cache unless explicitly debugging — running tools directly (e.g., `jest`, `tsc`, `eslint`) skips caching and may execute in wrong order
- Don't create circular dependencies between projects — Nx detects these and errors. Circular deps indicate an architectural boundary violation
- Don't import from project internals — use the public API (`index.ts` barrel file). Internal imports bypass module boundary enforcement
- Don't use `workspace.json` in new projects — it is a legacy format. Use `nx.json` with inferred project configuration
- Don't hardcode absolute paths in `project.json` targets — use `{projectRoot}` and `{workspaceRoot}` tokens for portability
- Don't ignore `@nx/enforce-module-boundaries` violations — they indicate architectural drift that compounds over time
- Don't run `nx affected` without specifying `--base` in CI — the default base may not match the PR base branch
