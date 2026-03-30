# Angular + istanbul

> Extends `modules/code-quality/istanbul.md` with Angular-specific integration.
> Generic istanbul conventions (c8 vs nyc, threshold config, reporters) are NOT repeated here.

## Integration Setup

Angular supports both Karma (legacy) and Jest (recommended for new projects) as test runners. Both expose Istanbul coverage:

**Jest (recommended — via `jest-preset-angular`):**
```bash
npm install --save-dev jest jest-preset-angular @types/jest
```

```js
// jest.config.js
module.exports = {
  preset: "jest-preset-angular",
  setupFilesAfterFramework: ["<rootDir>/setup-jest.ts"],
  collectCoverageFrom: ["src/**/*.ts", "!src/**/*.spec.ts", "!src/main.ts", "!src/environments/**"],
  coverageThreshold: {
    global: { lines: 80, branches: 70, functions: 85, statements: 80 }
  },
  coverageReporters: ["text", "lcov", "html"],
};
```

**Karma (Angular CLI default):**
```json
// angular.json — test architect
{
  "codeCoverageExclude": ["src/main.ts", "src/environments/**", "src/**/*.module.ts"],
  "codeCoverage": true
}
```

## Framework-Specific Patterns

### Excluding Angular boilerplate

Angular CLI generates files with no testable logic — exclude them from coverage:

```
src/main.ts                    # bootstrap entry
src/environments/**            # env configs
src/app/**/*.module.ts         # NgModule declarations (standalone migration reduces these)
src/app/**/*.routes.ts         # Route definitions — integration tested separately
```

### Signal-based component coverage

Angular 17+ components using `input()`, `output()`, `computed()`, and `effect()` signals are fully testable with Jest/`@angular/core/testing`. Signal-based components typically achieve higher branch coverage than template-only tests.

### Karma vs. Jest coverage comparison

| Aspect | Karma (Istanbul) | Jest (Istanbul) |
|---|---|---|
| Speed | Slow (browser launch) | Fast (jsdom) |
| CI setup | Complex (ChromeHeadless) | Simple |
| Report format | Istanbul HTML | Istanbul HTML |

Prefer Jest for new Angular 17+ projects.

## Additional Dos

- Exclude `*.module.ts` files from coverage until NgModule → standalone migration completes — they contain declarations, not logic.
- Gate CI on `lines >= 80` minimum; set `branches >= 70` to account for template-driven conditional rendering.

## Additional Don'ts

- Don't run Karma in headed mode in CI — use `--browsers=ChromeHeadless`.
- Don't count Angular template branches in Istanbul thresholds — template conditionals are only partially instrumented.
