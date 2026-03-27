# Bun with React

> Extends `modules/build-systems/bun.md` with React + Vite build patterns.
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
    "lint": "bunx eslint . && bunx tsc --noEmit",
    "format": "bunx prettier --write ."
  }
}
```

Bun's `--bun` flag forces Vite to use Bun's runtime instead of Node, providing faster HMR and build times. Omit it if any Vite plugins require Node-specific APIs.

## Framework-Specific Patterns

### Vite Configuration with React

```typescript
// vite.config.ts
import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

export default defineConfig({
  plugins: [react()],
  build: {
    target: "esnext",
    sourcemap: true,
    rollupOptions: {
      output: {
        manualChunks: {
          vendor: ["react", "react-dom"],
        },
      },
    },
  },
});
```

### Dependency Installation

```bash
bun install                    # install all deps (uses bun.lockb)
bun add react react-dom        # add production deps
bun add -d vitest @testing-library/react  # add dev deps
```

Bun resolves and installs packages faster than npm/yarn. The binary lockfile (`bun.lockb`) is not human-readable -- commit it for reproducible builds. Run `bun install --frozen-lockfile` in CI to enforce lockfile consistency.

### Path Aliases

```typescript
// vite.config.ts
import path from "path";

export default defineConfig({
  resolve: {
    alias: {
      "@": path.resolve(__dirname, "./src"),
    },
  },
});
```

```json
// tsconfig.json (must match)
{
  "compilerOptions": {
    "paths": { "@/*": ["./src/*"] }
  }
}
```

## Scaffolder Patterns

```yaml
patterns:
  package_json: "package.json"
  vite_config: "vite.config.ts"
  tsconfig: "tsconfig.json"
```

## Additional Dos

- DO use `bunx --bun vite` for faster dev server and builds when all plugins are Bun-compatible
- DO commit `bun.lockb` for reproducible installs across environments
- DO use `--frozen-lockfile` in CI to prevent lockfile drift
- DO configure `manualChunks` in Vite to separate vendor bundles from application code

## Additional Don'ts

- DON'T mix `bun.lockb` with `package-lock.json` or `yarn.lock` -- choose one package manager
- DON'T use `bun run` for Vite scripts if you need Node.js compatibility -- use `bunx` without `--bun`
- DON'T install platform-specific native modules with Bun in CI without matching the target OS
