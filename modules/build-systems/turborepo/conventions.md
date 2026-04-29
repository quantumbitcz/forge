# Turborepo Monorepo Conventions

> Support tier: community

## Overview

Turborepo is a high-performance build system for JavaScript and TypeScript monorepos. It orchestrates task execution across workspace packages, providing intelligent caching (local and remote), parallel execution, and task dependency management. Turborepo builds on top of npm/pnpm/yarn workspaces — it does not replace the package manager, it accelerates task execution.

- **Use for:** JavaScript/TypeScript monorepos needing fast task orchestration and caching, teams wanting minimal configuration with immediate performance gains, projects using npm/pnpm/yarn workspaces that need affected detection and parallel execution
- **Avoid for:** polyglot monorepos (Turborepo is JS/TS focused), projects requiring code generators or module boundary enforcement (use Nx instead), single-package projects (no benefit)
- **vs Nx:** Turborepo is simpler to adopt (single `turbo.json` config file) and focuses on task orchestration. Nx provides richer features (generators, module boundaries, project graph UI, plugins). Choose Turborepo for simplicity, Nx for ecosystem.

## Workspace Structure

- `turbo.json` — pipeline configuration (tasks, dependencies, outputs, inputs, environment variables)
- Uses npm/pnpm/yarn workspaces for package resolution (configured in root `package.json`)
- Packages typically in `apps/`, `packages/`
- `node_modules/.cache/turbo/` — local cache directory

### Typical Layout

```
monorepo/
  turbo.json
  package.json            (workspaces: ["apps/*", "packages/*"])
  apps/
    web/
      package.json
      src/
    api/
      package.json
      src/
  packages/
    ui/
      package.json
      src/
    shared-types/
      package.json
      src/
    eslint-config/
      package.json
      index.js
    tsconfig/
      package.json
      base.json
```

## Key Commands

| Purpose | Command |
|---|---|
| Affected test | `turbo run test --filter=...[origin/main]` |
| Affected build | `turbo run build --filter=...[origin/main]` |
| Affected lint | `turbo run lint --filter=...[origin/main]` |
| Run task for specific packages | `turbo run test --filter=api --filter=shared-types` |
| Dry run (list affected) | `turbo run build --filter=...[origin/main] --dry-run=json` |
| Package graph | `turbo run build --graph=output.json` |
| Run in single package | `turbo run build --filter=web` |
| Run in package and deps | `turbo run build --filter=web...` |

## Filter Syntax

Turborepo's `--filter` flag supports rich package selection:

```bash
# Packages affected since origin/main
turbo run test --filter=...[origin/main]

# Specific package
turbo run build --filter=web

# Package and all its dependencies
turbo run build --filter=web...

# Package and all its dependents (consumers)
turbo run build --filter=...web

# Multiple filters (union)
turbo run test --filter=api --filter=shared-types

# Packages in a directory
turbo run lint --filter=./apps/*

# Exclude a package
turbo run build --filter=!docs
```

## Pipeline Configuration

`turbo.json` defines task dependencies, outputs, and caching behavior:

```json
{
  "$schema": "https://turbo.build/schema.json",
  "tasks": {
    "build": {
      "dependsOn": ["^build"],
      "outputs": ["dist/**", ".next/**", "!.next/cache/**"],
      "inputs": ["src/**", "package.json", "tsconfig.json"]
    },
    "test": {
      "dependsOn": ["build"],
      "inputs": ["src/**", "test/**", "package.json"],
      "outputs": ["coverage/**"],
      "env": ["CI", "NODE_ENV"]
    },
    "lint": {
      "inputs": ["src/**", "*.config.*"],
      "outputs": []
    },
    "dev": {
      "cache": false,
      "persistent": true
    }
  }
}
```

The `^` prefix in `dependsOn` means "run this task in dependency packages first" — `^build` means all dependency packages must build before the current package builds.

## Environment Variables

Turborepo hashes environment variables as part of the cache key. Declare them in `turbo.json`:

```json
{
  "globalEnv": ["CI", "TURBO_TOKEN", "TURBO_TEAM"],
  "tasks": {
    "build": {
      "env": ["API_URL", "NODE_ENV"],
      "passThroughEnv": ["AWS_SECRET_ACCESS_KEY"]
    }
  }
}
```

- `env` — included in cache hash (different values = cache miss)
- `passThroughEnv` — passed to task but not included in cache hash
- `globalEnv` — included in cache hash for all tasks

## Remote Caching

Turborepo supports remote caching via Vercel or self-hosted:
- Check for `TURBO_TOKEN` and `TURBO_TEAM` environment variables
- Or `turbo.json` `remoteCache` configuration
- Local cache: `node_modules/.cache/turbo/`

```bash
# Login to Vercel remote cache
turbo login

# Link workspace to remote cache
turbo link
```

Self-hosted remote cache:
```json
{
  "remoteCache": {
    "enabled": true,
    "signature": true
  }
}
```

## Dos

- Use `turbo run` for all task execution — never run `npm run build` or `pnpm run test` directly at the workspace root, as this bypasses caching and dependency ordering
- Respect task pipeline in `turbo.json` (`dependsOn` declarations) — topological dependencies ensure correct build order
- Use `--filter` for package-scoped execution — `turbo run test --filter=api` runs only the api package's tests (plus any dependsOn requirements)
- Configure `outputs` in `turbo.json` for correct cache behavior — without `outputs`, Turborepo cannot cache task results properly
- Use `--dry-run=json` to preview affected packages before running tasks
- Declare all environment variables that affect build output in `env` or `globalEnv` — undeclared env vars cause cache poisoning (cache hit returns stale output built with different env)
- Configure `inputs` to narrow what triggers cache invalidation — default is all files in the package, which may be too broad
- Use workspace protocol (`workspace:*`) for internal package dependencies in `package.json`
- Use `cache: false` for development tasks like `dev` and `start` — caching long-running processes wastes disk space
- Use `persistent: true` for long-running tasks (dev servers) — tells Turborepo not to expect these tasks to exit

## Don'ts

- Don't run tasks outside `turbo run` — this bypasses caching and dependency ordering, leading to stale builds and incorrect execution order
- Don't use `*` glob in `turbo.json` outputs — overly broad output patterns cache unnecessary files, wasting disk space and slowing cache restore
- Don't create workspace-internal dependencies without declaring them in `turbo.json` task `dependsOn` — undeclared dependencies cause race conditions in parallel execution
- Don't commit the cache directory (`node_modules/.cache/turbo/`) to version control — it is machine-specific and can be massive
- Don't use `--force` in CI unless debugging — `--force` disables caching entirely, defeating the purpose of Turborepo
- Don't forget to declare environment variables in `turbo.json` — undeclared env vars that affect output cause cache correctness issues where a cache hit returns output from a different environment
- Don't put `devDependencies` that are only used by one package in the root `package.json` — this creates implicit dependencies that Turborepo cannot track
- Don't ignore `turbo.json` `inputs` configuration — without explicit inputs, any file change in a package invalidates its cache, including documentation and test files for build tasks
