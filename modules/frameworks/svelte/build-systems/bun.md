# Bun with Svelte 5 (Standalone SPA)

> Extends `modules/build-systems/bun.md` with Svelte 5 + Vite build patterns.
> Generic Bun conventions (workspaces, lockfile, script runner) are NOT repeated here.

## Integration Setup

```json
// package.json
{
  "scripts": {
    "dev": "bunx --bun vite",
    "build": "bunx --bun vite build",
    "preview": "bunx --bun vite preview",
    "test": "bunx vitest run",
    "lint": "bunx eslint . && bunx svelte-check --tsconfig ./tsconfig.json",
    "format": "bunx prettier --write ."
  }
}
```

Svelte 5 standalone uses Vite as its build tool. `--bun` flag enables Bun's runtime for faster dev server and builds.

## Framework-Specific Patterns

### Vite Configuration with Svelte

```typescript
// vite.config.ts
import { defineConfig } from "vite";
import { svelte } from "@sveltejs/vite-plugin-svelte";

export default defineConfig({
  plugins: [svelte()],
  build: {
    target: "esnext",
    sourcemap: true,
  },
});
```

### Dependency Installation

```bash
bun install                              # install all deps
bun add svelte                           # add Svelte 5
bun add -d @sveltejs/vite-plugin-svelte  # Vite plugin
bun add -d vitest @testing-library/svelte  # testing
```

### Svelte Check (Type Validation)

```bash
bunx svelte-check --tsconfig ./tsconfig.json
```

`svelte-check` validates TypeScript types within `.svelte` files. It catches errors that `tsc` alone misses because `tsc` does not understand Svelte's template syntax.

## Scaffolder Patterns

```yaml
patterns:
  package_json: "package.json"
  vite_config: "vite.config.ts"
  svelte_config: "svelte.config.js"
  tsconfig: "tsconfig.json"
```

## Additional Dos

- DO use `bunx --bun vite` for faster Vite dev server and builds
- DO run `svelte-check` alongside `eslint` for complete type validation
- DO commit `bun.lockb` and use `--frozen-lockfile` in CI
- DO use `@sveltejs/vite-plugin-svelte` (not the deprecated `rollup-plugin-svelte`)

## Additional Don'ts

- DON'T confuse standalone Svelte with SvelteKit -- this is Vite-only, no SSR or file-based routing
- DON'T skip `svelte-check` -- `tsc` alone cannot validate `.svelte` template types
- DON'T mix lockfiles -- choose one package manager per project
