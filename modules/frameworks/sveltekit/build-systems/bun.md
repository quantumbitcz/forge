# Bun with SvelteKit

> Extends `modules/build-systems/bun.md` with SvelteKit build patterns.
> Generic Bun conventions (workspaces, lockfile, script runner) are NOT repeated here.

## Integration Setup

```json
// package.json
{
  "scripts": {
    "dev": "vite dev",
    "build": "vite build",
    "preview": "vite preview",
    "test": "bunx vitest run",
    "lint": "bunx eslint . && bunx svelte-check --tsconfig ./tsconfig.json",
    "format": "bunx prettier --write ."
  }
}
```

SvelteKit uses Vite internally. The build command is `vite build`, which triggers the SvelteKit plugin and selected adapter.

## Framework-Specific Patterns

### Adapter Selection

```bash
bun add -d @sveltejs/adapter-node     # for Docker/server deployment
bun add -d @sveltejs/adapter-static   # for CDN/static hosting
bun add -d @sveltejs/adapter-auto     # auto-detect platform
```

```javascript
// svelte.config.js
import adapter from "@sveltejs/adapter-node";
import { vitePreprocess } from "@sveltejs/vite-plugin-svelte";

export default {
  kit: {
    adapter: adapter({ out: "build" }),
  },
  preprocess: vitePreprocess(),
};
```

The adapter determines the output format:
- `adapter-node`: Node.js server in `build/` -- for Docker deployment
- `adapter-static`: Static HTML in `build/` -- for CDN/nginx
- `adapter-auto`: Auto-detects platform (Vercel, Netlify, etc.)

### Dependency Installation

```bash
bun install                        # install all deps
bun add svelte @sveltejs/kit       # core deps
bun add -d @sveltejs/adapter-node  # adapter
```

### Svelte Check

```bash
bunx svelte-check --tsconfig ./tsconfig.json
```

Validates TypeScript types within `.svelte` files and SvelteKit-generated types ($app/*, $env/*).

## Scaffolder Patterns

```yaml
patterns:
  package_json: "package.json"
  svelte_config: "svelte.config.js"
  vite_config: "vite.config.ts"
  tsconfig: "tsconfig.json"
```

## Additional Dos

- DO choose the adapter matching your deployment target before building
- DO run `svelte-check` for SvelteKit-specific type validation ($app, $env, load functions)
- DO commit `bun.lockb` and use `--frozen-lockfile` in CI
- DO use `adapter-node` for Docker deployments and `adapter-static` for CDN

## Additional Don'ts

- DON'T use `adapter-auto` in production -- explicitly choose the target adapter
- DON'T skip `svelte-check` -- it validates SvelteKit-generated types that `tsc` cannot
- DON'T mix lockfiles -- choose one package manager per project
