# Next.js + istanbul

> Extends `modules/code-quality/istanbul.md` with Next.js-specific integration.
> Generic istanbul conventions (c8 vs nyc, threshold config, reporters) are NOT repeated here.

## Integration Setup

Next.js projects use Jest (with `jest-environment-jsdom`) for client components and Vitest for utility code:

**Jest (Next.js official recommendation):**
```bash
npm install --save-dev jest jest-environment-jsdom @testing-library/react @testing-library/jest-dom
```

```js
// jest.config.js
const nextJest = require("next/jest");
const createJestConfig = nextJest({ dir: "./" });

module.exports = createJestConfig({
  testEnvironment: "jest-environment-jsdom",
  collectCoverageFrom: [
    "{app,pages,components,lib}/**/*.{ts,tsx}",
    "!**/*.d.ts",
    "!**/node_modules/**",
  ],
  coverageThreshold: {
    global: { lines: 80, branches: 70, functions: 85, statements: 80 },
  },
  coverageReporters: ["text", "lcov", "html"],
});
```

## Framework-Specific Patterns

### Server Component vs. Client Component coverage

Server Components run in Node.js (no DOM) — test them with `jest-environment-node`. Client Components need `jest-environment-jsdom`:

```js
// jest.config.js
projects: [
  {
    displayName: "server",
    testEnvironment: "node",
    testMatch: ["**/*.server.test.{ts,tsx}"],
    collectCoverageFrom: ["app/**/*.server.tsx", "app/api/**/*.ts"],
  },
  {
    displayName: "client",
    testEnvironment: "jsdom",
    testMatch: ["**/*.test.{ts,tsx}"],
    testPathIgnorePatterns: ["*.server.test.*"],
    collectCoverageFrom: ["components/**/*.tsx", "app/**/*.client.tsx"],
  },
]
```

### App Router exclusions

Next.js App Router boilerplate files have no testable logic:

```
app/layout.tsx       → exclude (root layout — structural wrapper)
app/loading.tsx      → exclude (loading UI — no logic)
app/not-found.tsx    → exclude (static error page)
pages/_app.tsx       → exclude (app wrapper)
pages/_document.tsx  → exclude (document shell)
```

### API Route coverage

Next.js API routes (`app/api/**/route.ts`, `pages/api/**`) are server-side handlers — cover with Node.js environment tests:

```ts
test("GET /api/health returns 200", async () => {
  const { GET } = await import("../app/api/health/route");
  const response = await GET(new Request("http://localhost/api/health"));
  expect(response.status).toBe(200);
});
```

## Additional Dos

- Use `next/jest` helper (`createJestConfig`) — it auto-configures SWC transform, absolute imports, and module aliases.
- Target higher thresholds for `lib/` utilities and API routes than for React component files.

## Additional Don'ts

- Don't test Server Components with `jest-environment-jsdom` — they run in Node.js and don't use DOM APIs.
- Don't exclude the entire `app/` directory — it contains both Server Components (testable in Node) and Client Components (testable in jsdom).
