# SvelteKit + istanbul

> Extends `modules/code-quality/istanbul.md` with SvelteKit-specific integration.
> Generic istanbul conventions (c8 vs nyc, threshold config, reporters) are NOT repeated here.

## Integration Setup

```bash
npm install --save-dev @vitest/coverage-v8 @testing-library/svelte @testing-library/jest-dom
```

```ts
// vite.config.ts
import { defineConfig } from "vitest/config";
import { sveltekit } from "@sveltejs/kit/vite";

export default defineConfig({
  plugins: [sveltekit()],
  test: {
    environment: "jsdom",
    setupFiles: ["./src/test/setup.ts"],
    include: ["src/**/*.{test,spec}.{ts,js}"],
    coverage: {
      provider: "v8",
      reporter: ["text", "lcov", "html"],
      include: ["src/**/*.{ts,svelte}"],
      exclude: [
        ".svelte-kit/**",
        "src/app.d.ts",
        "src/app.html",
        "src/**/*.d.ts",
        "src/hooks.client.ts",  // typically thin, integration tested
      ],
      thresholds: { lines: 75, branches: 65, functions: 80, statements: 75 },
    },
  },
});
```

## Framework-Specific Patterns

### Server vs. client coverage split

SvelteKit projects benefit from separate coverage targets for server and client code:

```ts
coverageThreshold: {
  // Server load functions — high logic density, pure TS
  "src/routes/**/*.server.ts": { lines: 85, branches: 75, functions: 90 },
  "src/lib/server/**/*.ts": { lines: 85, branches: 75 },
  // Client components — template partially instrumented
  "src/**/*.svelte": { lines: 65, branches: 55 },
}
```

### Testing SvelteKit load functions

Load functions in `+page.server.ts` are the highest-value coverage target — they contain data fetching and auth logic:

```ts
// Direct unit test of load function — no SvelteKit server required
import { load } from "./+page.server";
test("redirects unauthenticated users", async () => {
  await expect(load({ locals: { user: null }, ...mockEvent })).rejects.toMatchObject({ status: 302 });
});
```

### API route coverage

SvelteKit API routes (`+server.ts`) are pure TypeScript handlers — cover them with unit tests:

```ts
import { GET } from "./+server";
test("returns 200 for valid request", async () => {
  const response = await GET({ request: new Request("/api/items") } as RequestEvent);
  expect(response.status).toBe(200);
});
```

## Additional Dos

- Prioritize coverage for `+page.server.ts` load functions and `+server.ts` API handlers — these contain the most critical business logic.
- Use separate `coverageThreshold` entries for server files vs. Svelte components.

## Additional Don'ts

- Don't include `.svelte-kit/` in coverage — it's generated TypeScript types, not application logic.
- Don't rely on E2E tests (Playwright) for Istanbul coverage — c8/V8 coverage only captures unit and integration test runs.
