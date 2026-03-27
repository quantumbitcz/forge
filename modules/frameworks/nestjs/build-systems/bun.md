# Bun with NestJS

> Extends `modules/build-systems/bun.md` with NestJS-specific Bun patterns.
> Generic Bun conventions (runtime, package manager, bundler) are NOT repeated here.

## Integration Setup

```json
// package.json
{
  "scripts": {
    "build": "nest build",
    "start": "bun run dist/main.js",
    "start:dev": "nest start --watch",
    "test": "bun test",
    "lint": "eslint \"{src,apps,libs,test}/**/*.ts\""
  }
}
```

## Framework-Specific Patterns

### Bun as Package Manager with Nest CLI

```bash
# Install dependencies
bun install

# Build with Nest CLI (uses tsc/swc under the hood)
bun run nest build

# Run tests with Bun's built-in test runner
bun test
```

Nest CLI's `nest build` uses `tsc` or `swc` for compilation. Bun replaces `npm` for dependency management and can run the compiled output, but Nest CLI handles the TypeScript compilation.

### Bun Runtime in Docker

```dockerfile
FROM oven/bun:1 AS builder
WORKDIR /app
COPY package.json bun.lockb ./
RUN bun install --frozen-lockfile
COPY . .
RUN bun run nest build

FROM oven/bun:1-slim
WORKDIR /app
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/dist ./dist
COPY package.json ./

USER bun
EXPOSE 3000
CMD ["bun", "run", "dist/main.js"]
```

### SWC Compilation for Faster Builds

```json
// nest-cli.json
{
  "compilerOptions": {
    "builder": "swc",
    "typeCheck": true
  }
}
```

Use SWC with Bun for maximum build speed. SWC compiles TypeScript 20x faster than tsc. Enable `typeCheck` to run tsc in parallel for type verification.

## Scaffolder Patterns

```yaml
patterns:
  lockfile: "bun.lockb"
  nest_cli: "nest-cli.json"
```

## Additional Dos

- DO use `bun install --frozen-lockfile` in CI for deterministic installs
- DO use SWC compiler with Nest CLI for faster builds
- DO use `bun run` for script execution instead of `npx`
- DO test Bun compatibility with NestJS dependencies before adopting

## Additional Don'ts

- DON'T mix `bun.lockb` and `package-lock.json` in the same project
- DON'T use Bun's bundler for NestJS builds -- use `nest build` (tsc/swc)
- DON'T assume all npm packages work with Bun runtime -- test Node.js native modules
