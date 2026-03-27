# Bun with Vue / Nuxt

> Extends `modules/build-systems/bun.md` with Vue 3 / Nuxt 3 build patterns.
> Generic Bun conventions (workspaces, lockfile, script runner) are NOT repeated here.

## Integration Setup

```json
// package.json (Nuxt 3)
{
  "scripts": {
    "dev": "nuxt dev",
    "build": "nuxt build",
    "preview": "nuxt preview",
    "generate": "nuxt generate",
    "test": "bunx vitest run",
    "lint": "bunx eslint .",
    "format": "bunx prettier --write .",
    "postinstall": "nuxt prepare"
  }
}
```

Nuxt CLI requires Node.js internally. Bun accelerates dependency installation and script launching, but `nuxt build` delegates to Nitro/Vite under the hood.

## Framework-Specific Patterns

### Dependency Installation

```bash
bun install                       # install all deps (bun.lockb)
bun add vue nuxt                  # add production deps
bun add -d vitest @vue/test-utils # add dev deps
```

Commit `bun.lockb` for reproducible builds. Use `bun install --frozen-lockfile` in CI.

### Nuxt Build Modes

```bash
bun run build      # SSR server bundle (adapter-node by default)
bun run generate   # Static site generation (pre-rendered HTML)
```

- `nuxt build` produces a Node.js server for SSR. Deploy with `node .output/server/index.mjs`.
- `nuxt generate` produces static HTML. Deploy to any static host or nginx.

### Standalone Vue (No Nuxt)

```json
// package.json (Vue + Vite)
{
  "scripts": {
    "dev": "bunx --bun vite",
    "build": "bunx --bun vite build",
    "test": "bunx vitest run"
  }
}
```

For non-Nuxt Vue projects, Vite is the build tool. `--bun` flag uses Bun's runtime for faster builds.

## Scaffolder Patterns

```yaml
patterns:
  package_json: "package.json"
  nuxt_config: "nuxt.config.ts"
  tsconfig: "tsconfig.json"
```

## Additional Dos

- DO use Bun for dependency installation speed while keeping Nuxt CLI for builds
- DO commit `bun.lockb` and use `--frozen-lockfile` in CI
- DO run `nuxt prepare` as a `postinstall` script for auto-generated types
- DO choose between `nuxt build` (SSR) and `nuxt generate` (static) based on deployment target

## Additional Don'ts

- DON'T replace `nuxt build` with a custom Vite setup -- Nuxt handles SSR, Nitro, and auto-imports
- DON'T mix `bun.lockb` with other lockfiles -- choose one package manager
- DON'T use `--bun` flag with Nuxt commands -- Nuxt requires Node.js internals
