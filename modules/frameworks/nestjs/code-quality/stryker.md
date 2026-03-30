# NestJS + stryker

> Extends `modules/code-quality/stryker.md` with NestJS-specific integration.
> Generic stryker conventions (installation, mutation operators, thresholds, CI) are NOT repeated here.

## Integration Setup

```bash
npm install --save-dev @stryker-mutator/core @stryker-mutator/jest-runner
# NestJS CLI generates jest by default; switch runner if using Vitest
```

**`stryker.conf.js` for NestJS:**

```js
/** @type {import('@stryker-mutator/api/core').PartialStrykerOptions} */
module.exports = {
  packageManager: "npm",
  reporters: ["html", "clear-text", "progress"],
  testRunner: "jest",
  coverageAnalysis: "perTest",
  jest: {
    configFile: "jest.config.js",
  },
  mutate: [
    "src/**/*.service.ts",        // business logic — primary target
    "src/**/*.guard.ts",          // auth/role logic
    "src/**/*.pipe.ts",           // validation transformation
    "!src/**/*.module.ts",        // DI wiring — not a mutation target
    "!src/**/*.controller.ts",    // thin orchestration — covered by e2e
    "!src/**/*.dto.ts",
    "!src/**/*.entity.ts",
    "!src/**/*.spec.ts",
    "!src/main.ts",
  ],
  thresholds: {
    high: 80,
    low: 60,
    break: 50,
  },
};
```

## Framework-Specific Patterns

### Focus on Services, Guards, and Pipes

NestJS follows a strict separation of concerns. Map mutation targets to NestJS artifact types:

| Artifact | Mutate? | Rationale |
|---|---|---|
| `*.service.ts` | Yes | Business logic, primary mutation target |
| `*.guard.ts` | Yes | Auth conditions — must kill mutations |
| `*.pipe.ts` | Yes | Input transformation/validation logic |
| `*.interceptor.ts` | Selective | Transform logic yes; logging wiring no |
| `*.controller.ts` | No | Thin — orchestration covered by e2e |
| `*.module.ts` | No | DI declarations — no logic |
| `*.dto.ts` | No | Data shapes + decorators — no logic |
| `*.filter.ts` | Selective | Exception mapping logic worth mutating |

### Guard Mutation Value

Guards contain critical `canActivate` boolean logic. Stryker mutations that flip `true`/`false` should always be killed by tests:

```ts
// Each conditional must have a matching test case
canActivate(context: ExecutionContext): boolean {
  const request = context.switchToHttp().getRequest();
  return request.user?.roles?.includes(this.role) ?? false;
}
```

A surviving mutant on a guard means the test does not assert on the authorization failure case.

### Excluding NestJS Test Application Setup

NestJS e2e tests use `Test.createTestingModule()`. This setup code produces many equivalent mutants — exclude it:

```js
mutate: [
  "src/**/*.service.ts",
  "!src/**/*.spec.ts",
  // Stryker runs unit specs only; e2e specs in test/ are excluded by default
]
```

## Additional Dos

- Include `*.guard.ts` in mutation targets — auth logic with surviving mutations is a security gap, not just a coverage gap.
- Include `*.pipe.ts` — validation transformation logic (type coercion, trimming, parsing) produces many boundary-condition mutants worth killing.
- Use `coverageAnalysis: "perTest"` — NestJS service suites can have many tests; this avoids running the full suite against every mutant.

## Additional Don'ts

- Don't mutate `*.controller.ts` — controllers are thin by design and should be covered by e2e/integration tests, not mutation tests.
- Don't include `*.module.ts` or `*.dto.ts` in mutation targets — they produce high noise (structural mutations with no logic impact).
- Don't set `break: 40` or lower for NestJS services — a mutation score below 50 for service classes indicates systemically weak test assertions, not acceptable coverage.
