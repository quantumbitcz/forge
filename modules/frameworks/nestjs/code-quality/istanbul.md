# NestJS + istanbul

> Extends `modules/code-quality/istanbul.md` with NestJS-specific integration.
> Generic istanbul/c8 conventions (thresholds, reporters, CI integration) are NOT repeated here.

## Integration Setup

NestJS uses Jest by default. Configure coverage via Jest config:

```bash
npm install --save-dev jest @types/jest ts-jest
# Or with Vitest:
npm install --save-dev vitest @vitest/coverage-v8
```

**`jest.config.js` for NestJS:**

```js
module.exports = {
  moduleFileExtensions: ["js", "json", "ts"],
  rootDir: "src",
  testRegex: ".*\\.spec\\.ts$",
  transform: { "^.+\\.(t|j)s$": "ts-jest" },
  collectCoverageFrom: [
    "**/*.(t|j)s",
    "!**/*.module.ts",       // DI wiring — covered by e2e tests
    "!main.ts",
    "!**/*.dto.ts",          // data shapes — no logic
    "!**/*.entity.ts",       // persistence models — covered by integration tests
    "!**/*.interface.ts",
    "!**/index.ts",
  ],
  coverageDirectory: "../coverage",
  coverageReporters: ["text", "html", "lcov"],
  coverageThreshold: {
    global: {
      lines: 80,
      branches: 70,
      functions: 85,
      statements: 80,
    },
  },
  testEnvironment: "node",
};
```

## Framework-Specific Patterns

### Unit + E2E Coverage Merge

NestJS projects have both unit specs (`*.spec.ts` in `src/`) and e2e specs (`*.e2e-spec.ts` in `test/`). Merge both to get accurate overall coverage:

```json
{
  "scripts": {
    "test": "jest",
    "test:e2e": "jest --config ./test/jest-e2e.json",
    "test:cov": "jest --coverage",
    "test:cov:merged": "jest --coverage && jest --config ./test/jest-e2e.json --coverage --coverageDirectory coverage-e2e"
  }
}
```

Use `c8` to merge LCOV reports from both runs when comparing coverage trends.

### Excluding Module Files

`*.module.ts` files are DI wiring declarations — they contain no business logic and are not unit-testable in isolation. Exclude them from unit coverage; they are implicitly covered by e2e tests:

```js
collectCoverageFrom: [
  "**/*.(t|j)s",
  "!**/*.module.ts",
]
```

### Guard and Interceptor Coverage

Guards and interceptors are often undertested. Ensure each has a dedicated unit spec:

```ts
// auth.guard.spec.ts
describe("JwtAuthGuard", () => {
  it("returns true for valid token", () => { ... });
  it("throws UnauthorizedException for missing token", () => { ... });
  it("throws UnauthorizedException for expired token", () => { ... });
});
```

## Additional Dos

- Exclude `*.module.ts` from unit coverage — module files are DI declarations, not logic; cover them via e2e tests instead.
- Exclude `*.dto.ts` and `*.entity.ts` — these are data shapes; validation logic in DTOs is tested through the controller test layer.
- Set separate coverage thresholds for services (`functions: 90`) vs. overall (`functions: 85`) — service logic is the critical path.

## Additional Don'ts

- Don't exclude guards and interceptors from coverage — they contain auth and transformation logic that must be unit tested.
- Don't merge unit and e2e coverage into a single threshold without separating them — e2e coverage inflates function counts and masks missing unit tests.
- Don't set `branches: 80` for NestJS services that handle many HTTP error conditions — each HTTP error branch requires an explicit negative test case; 70% is realistic initially.
