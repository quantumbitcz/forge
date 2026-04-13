# Turborepo — Build System

## Overview

Turborepo is a high-performance monorepo build system with remote caching. Configured via `turbo.json` at the workspace root.

## Architecture

- `turbo.json`: pipeline definitions with task dependencies and caching rules
- Task hashing: content-aware hashing of inputs for deterministic caching
- Remote cache: Vercel Remote Cache or self-hosted for CI sharing

## Config

- `turbo.json`: `tasks` (formerly `pipeline`) defines task dependencies and outputs
- `inputs`/`outputs`: file patterns that affect task hash and cache storage
- `env`/`globalEnv`: environment variables included in task hashing

## Performance

- Enable remote caching for shared CI cache hits
- Use `--filter` to scope task execution to affected packages
- Configure `outputs` precisely — over-broad patterns waste cache space

## Security

- Remote cache tokens should be environment variables
- Review `globalPassThroughEnv` — secrets in env vars may affect cache keys

## Testing

- Use `turbo run test --filter=...[origin/main]` for affected-only testing
- Configure `dependsOn` for test tasks that depend on build outputs

## Dos

- Define explicit `outputs` for every cacheable task
- Use `dependsOn` with `^` prefix for topological task ordering
- Pin Turborepo version in `package.json`

## Don'ts

- Don't cache non-deterministic tasks (e.g., tasks that read system time)
- Don't use `--force` in CI — defeats the purpose of caching
