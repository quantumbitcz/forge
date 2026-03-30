# Express + istanbul

> Extends `modules/code-quality/istanbul.md` with Express-specific integration.
> Generic istanbul/c8 conventions (thresholds, reporters, CI integration) are NOT repeated here.

## Integration Setup

Use `c8` (V8 native coverage) with Jest or Vitest for Express TypeScript projects:

```bash
npm install --save-dev c8 vitest @vitest/coverage-v8
# or with Jest:
npm install --save-dev c8 jest @types/jest ts-jest
```

**`vitest.config.ts` for Express:**

```ts
import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    coverage: {
      provider: "v8",
      reporter: ["text", "html", "lcov"],
      reportsDirectory: "coverage",
      thresholds: {
        lines: 80,
        branches: 70,
        functions: 85,
        statements: 80,
      },
      include: ["src/**/*.ts"],
      exclude: [
        "src/**/*.d.ts",
        "src/**/*.test.ts",
        "src/**/*.spec.ts",
        "src/app.ts",          // app bootstrap — tested via integration tests
        "src/server.ts",       // server start — excluded from unit coverage
        "src/config/**",       // config loading — no business logic
      ],
    },
  },
});
```

## Framework-Specific Patterns

### Separating Unit and Integration Coverage

Express apps typically have both unit tests (service logic) and integration tests (route handlers via supertest). Merge coverage from both:

```json
{
  "scripts": {
    "test:unit": "vitest run --coverage src/services src/middleware",
    "test:integration": "vitest run --coverage src/routes",
    "test:coverage": "c8 --check-coverage vitest run"
  }
}
```

### Route Handler Coverage

Route handler coverage requires HTTP-layer tests using `supertest`. Pure unit testing of route files is insufficient — the framework wiring is not exercised:

```ts
import request from "supertest";
import app from "../../src/app";

describe("GET /users/:id", () => {
  it("returns 404 for unknown user", async () => {
    await request(app).get("/users/unknown").expect(404);
  });
});
```

### Excluding Bootstrap Files

`server.ts` (calls `app.listen()`) and `app.ts` (wires middleware) are untestable in unit coverage without starting a real server. Exclude them and cover them via integration/e2e tests:

```ts
// vitest.config.ts
exclude: [
  "src/server.ts",
  "src/app.ts",
]
```

## Additional Dos

- Exclude `src/server.ts` and `src/app.ts` from unit coverage — they contain framework bootstrap code, not business logic.
- Use `supertest` for route handler coverage — it exercises Express middleware chains without spawning a real HTTP server.
- Track coverage separately for unit vs. integration test runs to identify gaps in business logic vs. route wiring.

## Additional Don'ts

- Don't count supertest integration tests toward unit coverage thresholds — they inflate coverage and mask missing unit tests.
- Don't exclude `src/middleware/` from coverage — middleware logic (validation, auth, error handling) is critical and must be unit tested.
- Don't set `branches` threshold above 70% for Express route files — error branches (404, 500) require explicit test cases that are often added gradually.
