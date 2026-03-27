# Bun with Next.js

> Extends `modules/build-systems/bun.md` with Next.js-specific Bun patterns.
> Generic Bun conventions (runtime, package manager, bundler) are NOT repeated here.

## Integration Setup

```json
// package.json
{
  "scripts": {
    "dev": "next dev --turbopack",
    "build": "next build",
    "start": "next start",
    "lint": "next lint",
    "test": "bun test"
  }
}
```

## Framework-Specific Patterns

### Bun as Package Manager Only

```bash
bun install --frozen-lockfile
bun run next build
bun run next start
```

Next.js uses its own bundler (Webpack/Turbopack). Bun replaces npm/yarn/pnpm for dependency management only -- Next.js handles compilation and bundling.

### Bun in Docker

```dockerfile
FROM oven/bun:1 AS deps
WORKDIR /app
COPY package.json bun.lockb ./
RUN bun install --frozen-lockfile

FROM node:22-slim AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .
RUN npm run build

FROM node:22-slim
WORKDIR /app
COPY --from=builder /app/.next/standalone ./
COPY --from=builder /app/.next/static ./.next/static
COPY --from=builder /app/public ./public
CMD ["node", "server.js"]
```

Use Bun for fast dependency installation, but the Next.js build and runtime use Node.js for full compatibility.

### Turbopack for Development

```bash
bun run next dev --turbopack
```

Turbopack is Next.js's Rust-based bundler for development. Combined with Bun's fast install, this provides the fastest development startup.

## Scaffolder Patterns

```yaml
patterns:
  lockfile: "bun.lockb"
```

## Additional Dos

- DO use `bun install --frozen-lockfile` in CI for fast, deterministic installs
- DO use Turbopack with Bun for maximum development speed
- DO use Node.js runtime for `next build` and `next start` for full compatibility
- DO test that all dependencies work with Bun before adopting

## Additional Don'ts

- DON'T mix `bun.lockb` and `package-lock.json` in the same project
- DON'T use Bun runtime for `next start` in production -- use Node.js for stability
- DON'T assume Bun's bundler replaces Next.js's build pipeline
