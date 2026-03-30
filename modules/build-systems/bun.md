# Bun

## Overview

All-in-one JS/TS toolkit — runtime, bundler, test runner, and package manager in a single native binary (Zig + JavaScriptCore). Package installs 10-30x faster than npm, bundling 10-100x faster than webpack/esbuild, test runner starts in milliseconds. Drop-in Node.js replacement (~95% npm compatibility).

- **Use for:** new JS/TS projects wanting minimal toolchain, monorepos needing fast installs/builds, teams eliminating webpack+Jest+npm config overhead
- **Avoid for:** projects needing full Node.js API coverage (native addons, some stream edge cases), environments limited to Node.js (AWS Lambda default, many PaaS), strict production stability requirements
- **vs Node.js ecosystem:** single binary replaces 4-5 tools, native-speed transpiler/bundler, first-class TypeScript (no tsc/ts-node), built-in SQLite, compile-time macros

## Architecture Patterns

### Bun as Runtime and Bundler

Bun serves two roles: a JavaScript/TypeScript runtime (replacing Node.js) and a bundler (replacing webpack/Vite/esbuild). These roles can be used independently -- Bun as runtime with Vite as bundler, or Node.js as runtime with Bun as bundler -- but the integrated experience is the primary design target.

**Project structure:**
```
project-root/
  bunfig.toml              (Bun configuration)
  package.json
  tsconfig.json
  src/
    index.ts               (application entrypoint)
    server.ts              (HTTP server)
    routes/
      users.ts
    lib/
      database.ts
      auth.ts
  tests/
    server.test.ts
    routes/
      users.test.ts
  public/
    index.html
    styles/
```

**Running TypeScript directly (no compilation step):**
```bash
# Run a TypeScript file directly
bun run src/index.ts

# Run with watch mode (restart on file changes)
bun --watch src/index.ts

# Run with hot module reload
bun --hot src/index.ts
```

Bun transpiles TypeScript on the fly using its native transpiler. There is no separate compilation step, no `tsc --watch`, and no `ts-node` wrapper. The transpiler handles JSX, TSX, decorators, and type stripping natively. However, Bun does not type-check -- it strips types and transpiles. Use `tsc --noEmit` in CI for type checking.

**Bun's HTTP server (built-in, no Express needed for simple APIs):**
```typescript
// src/server.ts
const server = Bun.serve({
  port: 8080,
  fetch(req) {
    const url = new URL(req.url);

    if (url.pathname === "/api/health") {
      return Response.json({ status: "ok" });
    }

    if (url.pathname === "/api/users" && req.method === "GET") {
      return Response.json({ users: [] });
    }

    return new Response("Not Found", { status: 404 });
  },
});

console.log(`Listening on ${server.url}`);
```

`Bun.serve()` uses the Web Standard Request/Response API, making handlers portable to Cloudflare Workers, Deno, and other standards-compliant runtimes. For complex routing, use frameworks built for Bun (Hono, Elysia) or Node.js-compatible frameworks (Express, Fastify) which Bun runs with its Node.js compatibility layer.

**`bun build` -- the bundler:**
```bash
# Bundle for production
bun build src/index.ts \
  --outdir=dist \
  --target=browser \
  --minify \
  --splitting \
  --sourcemap=external

# Bundle for Node.js (server-side)
bun build src/server.ts \
  --outdir=dist \
  --target=node \
  --minify

# Bundle as a standalone executable
bun build src/cli.ts \
  --compile \
  --outfile=my-cli
```

The `--compile` flag produces a self-contained executable that includes the Bun runtime -- the output runs on machines without Bun installed. This is Bun's equivalent of Go's static binaries or GraalVM native images for JavaScript.

**Bundler configuration via `bunfig.toml`:**
```toml
[build]
# Default build settings
target = "browser"
outdir = "dist"
splitting = true
sourcemap = "external"
minify = true

# Define macros
# Macros run at bundle time, replacing function calls with their return values
[build.define]
"process.env.NODE_ENV" = "'production'"
"__APP_VERSION__" = "'1.0.0'"

# External packages (not bundled)
[build.external]
packages = ["fsevents"]
```

**Bundler comparison (Bun vs webpack vs esbuild vs Vite):**
- Bun: native, zero-config for common cases, fastest for TypeScript-heavy projects.
- esbuild: native (Go), similar speed, broader plugin ecosystem, more battle-tested.
- Vite: uses esbuild for dev and Rollup for production, best DX for frontend frameworks (React, Vue, Svelte).
- webpack: JavaScript-based, slowest, but most configurable and largest plugin ecosystem.

For frontend projects using React/Vue/Svelte, Vite remains the better choice due to its framework-specific plugins, HMR implementation, and dev server. Bun's bundler is strongest for library bundling, server-side code, and projects that do not need framework-specific dev server features.

### Workspace Management

Bun workspaces manage monorepo dependencies -- hoisting shared dependencies, linking local packages, and running scripts across all packages. They are compatible with npm/pnpm workspace declarations in `package.json`.

**Root `package.json` -- workspace declaration:**
```json
{
  "name": "my-monorepo",
  "private": true,
  "workspaces": [
    "packages/*",
    "apps/*"
  ],
  "scripts": {
    "build": "bun run --filter '*' build",
    "test": "bun run --filter '*' test",
    "lint": "bun run --filter '*' lint",
    "typecheck": "bun run --filter '*' typecheck"
  },
  "devDependencies": {
    "typescript": "5.7.3",
    "@types/bun": "latest"
  }
}
```

**Monorepo directory structure:**
```
monorepo/
  package.json              (root workspace config)
  bunfig.toml
  packages/
    shared-types/
      package.json
      src/index.ts
    ui-components/
      package.json
      src/index.ts
    api-client/
      package.json
      src/index.ts
  apps/
    web-app/
      package.json
      src/index.tsx
    api-server/
      package.json
      src/index.ts
```

**Package `package.json` with workspace dependencies:**
```json
{
  "name": "@myorg/api-server",
  "version": "1.0.0",
  "dependencies": {
    "@myorg/shared-types": "workspace:*",
    "@myorg/api-client": "workspace:*",
    "hono": "4.6.14"
  },
  "scripts": {
    "dev": "bun --watch src/index.ts",
    "build": "bun build src/index.ts --outdir=dist --target=bun",
    "test": "bun test",
    "typecheck": "tsc --noEmit"
  }
}
```

The `"workspace:*"` protocol tells Bun to link the local package rather than downloading from the registry. Changes to `@myorg/shared-types` are immediately visible to `@myorg/api-server` without publishing or reinstalling. Bun resolves workspace dependencies using symlinks (like pnpm), ensuring that `node_modules/@myorg/shared-types` points to the local source.

**Workspace commands:**
```bash
# Install all workspace dependencies (including cross-links)
bun install

# Run a script in all workspaces
bun run --filter '*' build

# Run a script in specific workspaces
bun run --filter '@myorg/api-*' test

# Run a script in a single workspace
bun run --filter '@myorg/web-app' dev

# Add a dependency to a specific workspace
bun add hono --filter '@myorg/api-server'
```

Bun's workspace installs are dramatically faster than npm or yarn -- a monorepo with 500 packages that takes 90 seconds with npm installs in 5-10 seconds with Bun, because Bun uses hardlinks, parallel downloads, and a binary lockfile format.

### Test Runner

Bun's built-in test runner (`bun test`) provides Jest-compatible syntax with native execution speed. Tests run without any devDependencies -- no Jest, no Vitest, no test framework installation needed.

**Test file (`tests/server.test.ts`):**
```typescript
import { describe, it, expect, beforeAll, afterAll } from "bun:test";

describe("UserService", () => {
  it("should create a user with valid email", () => {
    const user = createUser({ email: "test@example.com", name: "Test" });
    expect(user.email).toBe("test@example.com");
    expect(user.id).toBeDefined();
  });

  it("should reject invalid email", () => {
    expect(() => createUser({ email: "invalid", name: "Test" }))
      .toThrow("Invalid email");
  });

  it("should hash password", async () => {
    const user = await createUser({
      email: "test@example.com",
      name: "Test",
      password: "secret123",
    });
    expect(user.passwordHash).not.toBe("secret123");
    expect(user.passwordHash).toStartWith("$argon2");
  });
});

describe("HTTP API", () => {
  let baseUrl: string;

  beforeAll(async () => {
    const server = Bun.serve({
      port: 0, // random available port
      fetch: app.fetch,
    });
    baseUrl = `http://localhost:${server.port}`;
  });

  it("should return health check", async () => {
    const res = await fetch(`${baseUrl}/api/health`);
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ status: "ok" });
  });

  it("should return 404 for unknown routes", async () => {
    const res = await fetch(`${baseUrl}/api/nonexistent`);
    expect(res.status).toBe(404);
  });
});
```

Bun's test runner supports `describe`, `it`/`test`, `expect`, `beforeAll`/`afterAll`/`beforeEach`/`afterEach`, `mock`, and snapshot testing -- all from `bun:test` without external dependencies.

**Running tests:**
```bash
# Run all tests
bun test

# Run specific test file
bun test tests/server.test.ts

# Run tests matching a pattern
bun test --grep "UserService"

# Run with coverage
bun test --coverage

# Run in watch mode
bun test --watch

# Run with timeout
bun test --timeout 30000

# Run with bail (stop on first failure)
bun test --bail
```

**Mocking:**
```typescript
import { mock, spyOn } from "bun:test";

// Mock a module
mock.module("./database", () => ({
  query: mock(() => Promise.resolve([{ id: 1, name: "Test" }])),
}));

// Spy on object methods
const consoleSpy = spyOn(console, "log");
doSomething();
expect(consoleSpy).toHaveBeenCalledWith("expected output");
```

### Migration from Node.js Stack

Migrating from the traditional Node.js stack (npm + webpack + Jest) to Bun is incremental -- Bun's Node.js compatibility means most code runs without changes.

**Migration path:**

**Step 1 -- Replace npm with Bun for package management:**
```bash
# Remove node_modules and lockfile
rm -rf node_modules package-lock.json

# Install with Bun (generates bun.lockb)
bun install

# Verify all packages resolve
bun pm ls
```

`bun.lockb` is a binary lockfile (faster to read/write than JSON). It replaces `package-lock.json`. Commit it to version control. If you need to maintain npm compatibility during migration, use `bun install --yarn` to generate a `yarn.lock` instead.

**Step 2 -- Replace Jest/Vitest with Bun test:**
```bash
# Remove test framework dependencies
bun remove jest @types/jest ts-jest vitest

# Update import paths in test files
# From: import { describe, it, expect } from '@jest/globals'
# To:   import { describe, it, expect } from 'bun:test'

# Run tests
bun test
```

Most Jest tests work with `bun:test` after changing the import. Key differences:
- `jest.fn()` becomes `mock()`
- `jest.spyOn()` becomes `spyOn()`
- `jest.mock()` becomes `mock.module()`
- Timer mocking: `jest.useFakeTimers()` has `bun:test` timer mock equivalents
- Custom matchers: install `bun-bagel` or write custom expect extensions

**Step 3 -- Replace webpack/Vite with Bun build (for non-framework projects):**
```bash
# For library/server projects:
# Replace webpack config with bun build command
bun build src/index.ts --outdir=dist --target=node --sourcemap=external

# For frontend projects with React/Vue/Svelte:
# Keep Vite for dev server and HMR, use Bun only as package manager
# Vite's framework plugins (React Fast Refresh, Vue SFC compiler) are not
# replicated by Bun's bundler
```

**Step 4 -- Replace Node.js runtime with Bun (optional):**
```json
{
  "scripts": {
    "start": "bun run src/index.ts",
    "dev": "bun --watch src/index.ts"
  }
}
```

This step is optional and the most risky -- it changes the production runtime. Test thoroughly before deploying with Bun as the runtime. Many teams use Bun for development (fast installs, fast tests) while keeping Node.js for production (proven stability, broader hosting support).

**Dockerfile for Bun:**
```dockerfile
FROM oven/bun:1.1-alpine AS builder
WORKDIR /app
COPY package.json bun.lockb ./
RUN bun install --frozen-lockfile --production

COPY src/ src/
RUN bun build src/index.ts --outdir=dist --target=bun --minify

FROM oven/bun:1.1-alpine
WORKDIR /app
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/node_modules ./node_modules
EXPOSE 8080
CMD ["bun", "run", "dist/index.js"]
```

## Configuration

### Development

**`bunfig.toml` -- Bun's configuration file:**
```toml
# Package management
[install]
# Use exact versions by default (no ^, no ~)
exact = true
# Disable lifecycle scripts for security
lifecycle = false

[install.scopes]
# Registry for private packages
"@myorg" = "https://npm.internal.example.com/"

# Test runner configuration
[test]
coverage = false
timeout = 10000
root = "tests/"

# TypeScript configuration
[build]
target = "bun"
sourcemap = "external"
```

**`tsconfig.json` -- TypeScript configuration for Bun:**
```json
{
  "compilerOptions": {
    "target": "ESNext",
    "module": "ESNext",
    "moduleResolution": "bundler",
    "types": ["bun-types"],
    "strict": true,
    "noEmit": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "resolveJsonModule": true,
    "isolatedModules": true,
    "jsx": "react-jsx"
  },
  "include": ["src/**/*", "tests/**/*"],
  "exclude": ["node_modules", "dist"]
}
```

`"types": ["bun-types"]` provides TypeScript definitions for Bun-specific APIs (Bun.serve, Bun.file, bun:test, bun:sqlite). Install with `bun add -d @types/bun`.

**Development scripts in `package.json`:**
```json
{
  "scripts": {
    "dev": "bun --watch src/index.ts",
    "build": "bun build src/index.ts --outdir=dist --target=bun --minify",
    "test": "bun test",
    "test:watch": "bun test --watch",
    "test:coverage": "bun test --coverage",
    "typecheck": "tsc --noEmit",
    "lint": "bunx @biomejs/biome check src/ tests/",
    "format": "bunx @biomejs/biome format --write src/ tests/"
  }
}
```

`bunx` is Bun's equivalent of `npx` -- it runs a package binary without installing it globally. Use `bunx @biomejs/biome` instead of installing biome as a devDependency when it is only used in scripts.

### Production

**CI pipeline invocation:**
```bash
# Install dependencies (frozen lockfile for reproducibility)
bun install --frozen-lockfile

# Type check
bunx tsc --noEmit

# Lint
bunx @biomejs/biome check src/ tests/

# Test
bun test --coverage

# Build
bun build src/index.ts --outdir=dist --target=bun --minify --sourcemap=external
```

**GitHub Actions example:**
```yaml
- name: Setup Bun
  uses: oven-sh/setup-bun@v2
  with:
    bun-version: '1.1.42'

- name: Install dependencies
  run: bun install --frozen-lockfile

- name: Type check
  run: bunx tsc --noEmit

- name: Test
  run: bun test --coverage

- name: Build
  run: bun build src/index.ts --outdir=dist --target=bun --minify
```

The `oven-sh/setup-bun` action installs the pinned Bun version and caches it across runs. Pin the Bun version explicitly -- unlike Node.js (which changes slowly), Bun releases frequently with potential behavior changes.

**`--frozen-lockfile`** -- the CI must use this flag. It prevents `bun install` from modifying `bun.lockb` during CI runs. If the lockfile is out of date (someone forgot to commit it after adding a dependency), the build fails immediately rather than silently updating the lockfile and producing a non-reproducible build.

## Performance

**Package installation speed** -- Bun's package manager is 10-30x faster than npm because:
- It uses hardlinks from a global cache rather than copying files into node_modules.
- Downloads happen in parallel using Zig's event loop.
- The binary lockfile (bun.lockb) is faster to parse than JSON.
- Resolution and download are pipelined -- downloading starts before resolution completes.

```bash
# Clean install performance comparison (typical monorepo, 500 packages)
# npm:  90 seconds
# pnpm: 15 seconds
# bun:  5 seconds
```

**Bundler speed** -- Bun's bundler is native (Zig), avoiding the overhead of JavaScript-based bundlers. For TypeScript-heavy projects, Bun's bundler is 10-100x faster than webpack because it does not parse TypeScript through a JavaScript-based compiler -- it uses a native parser and transpiler.

**Runtime speed** -- Bun uses JavaScriptCore (WebKit's engine), which has different performance characteristics than V8 (Node.js). For most server workloads, performance is comparable. Bun's native implementations of fetch, WebSocket, file I/O, and SQLite are faster than their Node.js equivalents because they are implemented in Zig rather than JavaScript/C++.

**Test runner speed** -- Bun's test runner starts in milliseconds (no JIT warmup needed for the test framework itself). For projects with 1000+ tests, the startup time difference between Bun (50ms) and Jest (3-5 seconds) is significant for developer feedback loops.

**Performance optimization:**
- Use `--target=bun` when building for Bun runtime (enables Bun-specific optimizations).
- Use `--minify` for production builds to reduce bundle size and improve load time.
- Use `--splitting` for browser targets to enable code splitting (shared chunks between routes).
- Use `Bun.file()` instead of `fs.readFile()` for faster file I/O.
- Use `bun:sqlite` instead of npm SQLite packages for embedded database access.

**Monitoring build performance:**
```bash
# Time the build
time bun build src/index.ts --outdir=dist --target=bun --minify

# Bundle size analysis
ls -la dist/
du -sh dist/

# Dependency analysis
bun pm ls --all | wc -l  # Total package count
```

## Security

**Lockfile integrity** -- `bun.lockb` is a binary lockfile that pins exact dependency versions. Commit it to version control and use `--frozen-lockfile` in CI. The binary format is tamper-resistant (harder to modify than JSON), but always review dependency changes via `bun install --dry-run` before committing lockfile updates.

**Disable lifecycle scripts by default:**
```toml
# bunfig.toml
[install]
lifecycle = false
```

npm lifecycle scripts (postinstall, preinstall) are a common supply chain attack vector -- a malicious package can run arbitrary code during install. Bun disables them with `lifecycle = false`. Enable selectively for packages that legitimately need them (native addon compilation).

**Private registry configuration:**
```toml
# bunfig.toml
[install.scopes]
"@myorg" = { url = "https://npm.internal.example.com/", token = "$NPM_TOKEN" }
```

Use environment variable interpolation (`$NPM_TOKEN`) for authentication tokens. Never hardcode tokens in bunfig.toml.

**Dependency auditing:**
```bash
# Check for known vulnerabilities (uses npm audit API)
bunx npm-audit-resolver

# List all installed packages with versions
bun pm ls --all
```

Bun does not have a built-in `bun audit` command (as of 1.1.x). Use `bunx npm-audit-resolver` or integrate with Snyk/Dependabot for vulnerability scanning.

**No secrets in source code:**
```typescript
// Read from environment variables
const apiKey = Bun.env.API_KEY;
if (!apiKey) {
  throw new Error("API_KEY environment variable is required");
}

// Or use Bun's .env file support (built-in, no dotenv package needed)
// .env files are loaded automatically by Bun
```

Bun loads `.env`, `.env.local`, `.env.production`, and `.env.development` automatically (based on NODE_ENV). No dotenv package needed. Ensure .env files containing secrets are gitignored.

**Supply chain hardening checklist:**
- Use `--frozen-lockfile` in CI to prevent lockfile modification.
- Disable lifecycle scripts (`lifecycle = false` in bunfig.toml).
- Pin the Bun version in CI (oven-sh/setup-bun with explicit version).
- Use `bun install --exact` (or `exact = true` in bunfig.toml) to prevent version range resolution drift.
- Configure private registries for internal packages via scoped registry configuration.
- Audit dependencies regularly with `bunx npm-audit-resolver` or Snyk.
- Gitignore all .env files containing secrets.
- Use `--target=bun` or `--target=node` (not `--target=browser`) for server-side builds to avoid exposing server-only code in browser bundles.

## Testing

**Running tests:**
```bash
# Run all tests (discovers *.test.ts, *.spec.ts, *.test.tsx, etc.)
bun test

# Run specific file
bun test tests/server.test.ts

# Run tests matching a name pattern
bun test --grep "should create user"

# Run with coverage report
bun test --coverage

# Watch mode (re-runs on file changes)
bun test --watch

# Bail on first failure
bun test --bail

# Set timeout (milliseconds)
bun test --timeout 30000

# Run tests in specific directory
bun test tests/unit/
```

**Snapshot testing:**
```typescript
import { test, expect } from "bun:test";

test("renders user card", () => {
  const html = renderUserCard({ name: "Alice", role: "admin" });
  expect(html).toMatchSnapshot();
});
```

Snapshots are stored in `__snapshots__/` directories next to test files. Update with `bun test --update-snapshots`.

**Lifecycle hooks and setup:**
```typescript
import { beforeAll, afterAll, afterEach } from "bun:test";

// Global setup (runs once before all tests in this file)
let db: Database;

beforeAll(async () => {
  db = await Database.connect(":memory:");
  await db.migrate();
});

afterEach(async () => {
  await db.run("DELETE FROM users");
});

afterAll(async () => {
  await db.close();
});
```

**Coverage reporting:**
```bash
bun test --coverage

# Output example:
# ----------|---------|----------|---------|---------|---
# File      | % Stmts | % Branch | % Funcs | % Lines |
# ----------|---------|----------|---------|---------|---
# src/      |   92.5  |   87.3   |   95.0  |   92.5  |
# ----------|---------|----------|---------|---------|---
```

Bun's built-in coverage uses V8-style coverage collection and outputs a summary table. For CI integration, combine with `--coverageReporter=lcov` to generate LCOV reports consumable by Codecov, Coveralls, or SonarQube.

**Comparison with Jest migration:**

| Feature | Jest | Bun test |
|---------|------|----------|
| Import | `@jest/globals` | `bun:test` |
| Mock function | `jest.fn()` | `mock()` |
| Spy | `jest.spyOn()` | `spyOn()` |
| Module mock | `jest.mock()` | `mock.module()` |
| Timer mock | `jest.useFakeTimers()` | Supported |
| Snapshot | Built-in | Built-in |
| Coverage | Built-in | Built-in |
| Watch | `--watch` | `--watch` |
| Startup | 3-5 seconds | Under 100ms |

## Dos

- Use `--frozen-lockfile` in all CI pipelines. This prevents `bun install` from modifying the lockfile, ensuring builds are reproducible. If the lockfile is stale, the build fails immediately rather than silently resolving different versions.
- Use Bun's built-in test runner (`bun test`) for new projects instead of adding Jest or Vitest as dependencies. It provides the same API with zero configuration and native execution speed.
- Use `bunfig.toml` for project-level Bun configuration instead of CLI flags scattered across package.json scripts. The TOML file is the single source of truth for Bun's behavior.
- Pin the Bun version in CI using `oven-sh/setup-bun` with an explicit version. Bun releases frequently -- unpinned versions can introduce unexpected behavior changes.
- Use `bun:test` imports (not `@jest/globals` or `vitest`) to avoid unnecessary dependencies. Bun's test API is built into the runtime and available without installation.
- Use `workspace:*` protocol for monorepo internal dependencies. This creates symlinks to local packages, providing instant feedback without publishing or reinstalling.
- Run `tsc --noEmit` separately for type checking. Bun transpiles TypeScript but does not type-check -- tsc is still needed for catching type errors. Include type checking in CI as a separate step.
- Use `Bun.serve()` with the Web Standard Request/Response API for HTTP servers. This makes handlers portable across Bun, Cloudflare Workers, Deno, and other WinterCG-compatible runtimes.
- Disable lifecycle scripts (`lifecycle = false` in bunfig.toml) and enable them selectively for packages that need native addon compilation. This prevents supply chain attacks through malicious postinstall scripts.
- Use `bun build --compile` for CLI tools to produce self-contained executables. The output runs on machines without Bun installed, simplifying distribution.

## Don'ts

- Don't assume all Node.js APIs are available in Bun. While approximately 95% of npm packages work, some Node.js-specific behaviors (certain stream edge cases, worker_threads specifics, some node: module implementations) differ. Test critical paths before deploying with Bun as the production runtime.
- Don't use Bun's bundler for framework-specific frontend development (React, Vue, Svelte). Vite provides framework-specific plugins (React Fast Refresh, Vue SFC compiler, Svelte preprocessor) and HMR that Bun's bundler does not replicate. Use Bun as the package manager and test runner alongside Vite as the dev server and bundler.
- Don't hardcode tokens or credentials in bunfig.toml. Use environment variable interpolation (`$NPM_TOKEN`) for registry authentication. The TOML file is committed to version control.
- Don't commit node_modules/ -- Bun uses the same node_modules directory as npm. The lockfile (bun.lockb) ensures reproducible installs. Committing node_modules wastes repository space and prevents lockfile-driven resolution.
- Don't skip type checking because Bun handles TypeScript. Bun strips types -- it does not validate them. A TypeScript error that tsc catches (wrong argument type, missing property, incompatible interface) passes through Bun's transpiler silently. Always run `tsc --noEmit` in CI.
- Don't use bun.lockb and package-lock.json simultaneously. Choose one package manager per project. If migrating incrementally, delete the old lockfile and generate the new one. Dual lockfiles drift and cause confusion.
- Don't use bunx for frequently used tools in CI -- install them as devDependencies. bunx downloads the package on every invocation, adding network latency and non-reproducibility. Reserve bunx for one-off commands.
- Don't rely on Bun's .env loading for production secrets. Bun loads .env files automatically, which is convenient for development but creates a risk of accidentally including .env files in Docker images or deployments. Use environment variables injected by the deployment platform.
- Don't mix bun test and Jest/Vitest in the same project. Choose one test runner and migrate fully. Mixed test runners create confusion about which tests use which assertions, mocking APIs, and configuration.
- Don't use `latest` as the Bun version in CI. Bun's release cadence is fast -- unpinned versions can introduce breaking changes between CI runs. Pin to a specific version and upgrade deliberately.
