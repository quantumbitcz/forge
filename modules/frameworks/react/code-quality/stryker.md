# React + stryker

> Extends `modules/code-quality/stryker.md` with React-specific integration.
> Generic stryker conventions (installation, runners, threshold config) are NOT repeated here.

## Integration Setup

```bash
npm install --save-dev @stryker-mutator/core @stryker-mutator/vitest-runner
# or for Jest-based projects:
npm install --save-dev @stryker-mutator/core @stryker-mutator/jest-runner
```

**`stryker.config.mjs` for Vitest + React:**
```js
/** @type {import('@stryker-mutator/api/core').PartialStrykerOptions} */
export default {
  testRunner: "vitest",
  coverageAnalysis: "perTest",
  mutate: [
    "src/**/*.{ts,tsx}",
    "!src/**/*.{test,spec}.{ts,tsx}",
    "!src/**/*.stories.{ts,tsx}",
    "!src/main.tsx",
    "!src/**/*.d.ts",
  ],
  vitest: { configFile: "vite.config.ts" },
  thresholds: { high: 80, low: 60, break: 50 },
  reporters: ["html", "clear-text", "progress"],
  htmlReporter: { fileName: "reports/mutation/index.html" },
};
```

## Framework-Specific Patterns

### Excluding UI-only files

Stryker wastes time mutating presentational components with no logic. Scope mutation to files with meaningful branches:

```js
mutate: [
  "src/hooks/**/*.ts",          // pure logic — high mutation value
  "src/utils/**/*.ts",          // utility functions — high mutation value
  "src/components/**/*.tsx",    // include for prop validation + conditional render
  "!src/components/**/*.stories.tsx",
  "!src/components/icons/**",   // SVG wrappers — no testable logic
]
```

### React Testing Library compatibility

Stryker works with RTL tests — no special config needed. Ensure test environment is `jsdom`:

```ts
// vite.config.ts — ensure jsdom for component tests
test: {
  environment: "jsdom",
  setupFiles: ["./src/test/setup.ts"],
}
```

### Mutation score targets by file type

| File type | Target mutation score |
|---|---|
| Custom hooks (`src/hooks/`) | >= 80% |
| Utility functions (`src/utils/`) | >= 85% |
| Component logic | >= 60% |
| Context providers | >= 70% |

## Additional Dos

- Run Stryker only on `src/hooks/` and `src/utils/` in CI — component mutation is slow and less informative.
- Use `coverageAnalysis: "perTest"` — dramatically reduces runtime by skipping mutants not covered by any test.

## Additional Don'ts

- Don't mutate Storybook files — they have no associated test runner in Stryker.
- Don't set `break` below 50 for hook files — hooks are the highest-value mutation target in React apps.
