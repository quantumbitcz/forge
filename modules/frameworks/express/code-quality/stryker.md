# Express + stryker

> Extends `modules/code-quality/stryker.md` with Express-specific integration.
> Generic stryker conventions (installation, mutation operators, thresholds, CI) are NOT repeated here.

## Integration Setup

```bash
npm install --save-dev @stryker-mutator/core @stryker-mutator/vitest-runner
# or for Jest:
npm install --save-dev @stryker-mutator/core @stryker-mutator/jest-runner
```

**`stryker.conf.js` for Express:**

```js
/** @type {import('@stryker-mutator/api/core').PartialStrykerOptions} */
module.exports = {
  packageManager: "npm",
  reporters: ["html", "clear-text", "progress"],
  testRunner: "vitest",
  coverageAnalysis: "perTest",
  mutate: [
    "src/services/**/*.ts",     // business logic — primary mutation target
    "src/middleware/**/*.ts",   // validation, auth, error handling
    "!src/**/*.test.ts",
    "!src/**/*.spec.ts",
    "!src/**/*.d.ts",
    "!src/app.ts",              // framework wiring — not a mutation target
    "!src/server.ts",
    "!src/config/**",
  ],
  thresholds: {
    high: 80,
    low: 60,
    break: 50,
  },
};
```

## Framework-Specific Patterns

### Mutate Services, Not Routes

Express route handlers orchestrate — they call services and return HTTP responses. Business logic lives in services. Focus Stryker on `src/services/`:

```js
mutate: [
  "src/services/**/*.ts",
  "src/middleware/validation/**/*.ts",
  // Skip route handlers — they are integration-tested via supertest, not unit-tested
  "!src/routes/**/*.ts",
]
```

### Middleware Mutation Value

Validation and auth middleware contain critical conditional logic. These are worth mutating:

- Status code decisions in error middleware (`err.status ?? 500`) — mutations catch tests that don't verify error codes
- JWT verification conditionals — mutations catch tests that don't assert on auth failures
- Input validation boundary conditions — mutations catch tests missing edge cases

### Avoiding Route File Noise

Route files wire handlers to URLs — mutating them produces high noise (many equivalent mutants about URL strings). Use `!src/routes/**` and validate route wiring via integration tests instead.

## Additional Dos

- Target `src/services/` and `src/middleware/` for mutation — these contain the logic most likely to have missing negative-path test cases.
- Use `coverageAnalysis: "perTest"` to skip running mutants against tests that don't cover them — Express test suites with `supertest` can be slow; this optimization is significant.
- Run Stryker only on changed files in PRs via `--mutate` flag override — full suite on large Express services can take 20+ minutes.

## Additional Don'ts

- Don't mutate `src/routes/` files — route definitions are structural and produce many equivalent mutants (string path changes that still match).
- Don't include `src/app.ts` in mutation targets — middleware registration order matters but is integration-tested, not unit-tested.
- Don't set `break` below 50 for Express services with complex business logic — a low floor masks tests that pass only because of type coercion or default behavior.
