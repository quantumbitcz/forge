# Nx — Build System

## Overview

Nx is a smart monorepo build system with computation caching and affected detection. Configured via `nx.json` and `project.json` per project.

## Architecture

- Workspace: `nx.json` root config, per-project `project.json` or `package.json` targets
- Task graph: Nx computes task dependency graph from project dependencies
- Cache: local (`.nx/cache`) and remote (Nx Cloud) computation caching

## Config

- `nx.json`: task runners, default settings, named inputs, target defaults
- `project.json`: per-project targets (build, test, lint, serve)
- `nx affected`: runs only tasks affected by changes since base

## Performance

- Enable remote caching via Nx Cloud for CI speed
- Use `--parallel` for independent tasks
- Configure `namedInputs` to avoid unnecessary cache invalidation

## Security

- Nx Cloud tokens should be environment variables, never committed
- Review `implicitDependencies` — incorrect values can skip affected detection

## Testing

- Use `nx affected:test` in CI to run only affected tests
- Configure test targets per project in `project.json`

## Dos

- Use `nx affected` for CI builds — avoids rebuilding unchanged projects
- Configure `cacheableOperations` for all deterministic targets
- Pin Nx version across the workspace

## Don'ts

- Don't use glob-based task definitions when Nx task graph suffices
- Don't skip `nx migrate` when upgrading — it handles breaking changes automatically
