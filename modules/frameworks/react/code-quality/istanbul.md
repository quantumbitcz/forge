# React + istanbul

> Extends `modules/code-quality/istanbul.md` with React-specific integration.
> Generic istanbul conventions (c8 vs nyc, threshold config, reporters) are NOT repeated here.

## Integration Setup

React projects typically test with Vitest or Jest. Both expose Istanbul coverage natively:

**Vitest (Vite-based React projects):**
```bash
npm install --save-dev @vitest/coverage-v8
```

```ts
// vite.config.ts
import { defineConfig } from "vitest/config";
export default defineConfig({
  test: {
    environment: "jsdom",
    coverage: {
      provider: "v8",
      reporter: ["text", "lcov", "html"],
      include: ["src/**/*.{ts,tsx}"],
      exclude: ["src/**/*.stories.{ts,tsx}", "src/**/*.d.ts", "src/main.tsx"],
      thresholds: { lines: 80, branches: 70, functions: 85, statements: 80 },
    },
  },
});
```

**Jest (Create React App / custom setups):**
```json
// jest.config.json
{
  "testEnvironment": "jsdom",
  "collectCoverageFrom": ["src/**/*.{ts,tsx}", "!src/**/*.stories.*", "!src/main.tsx"],
  "coverageThreshold": {
    "global": { "lines": 80, "branches": 70, "functions": 85, "statements": 80 }
  }
}
```

## Framework-Specific Patterns

### Coverage exclusions for React boilerplate

Exclude files that have no logic to test:

```ts
exclude: [
  "src/main.tsx",          // entry point — renders <App />, no testable logic
  "src/vite-env.d.ts",     // type declarations
  "src/**/*.stories.tsx",  // Storybook files — visual, not unit tested
  "src/**/*.d.ts",
  "src/**/index.ts",       // re-export barrels — covered transitively
]
```

### Component vs. hook coverage strategy

Target higher branch coverage for custom hooks (pure logic) than for presentational components:

```ts
coverageThreshold: {
  "src/hooks/**": { branches: 85, functions: 90 },
  "src/components/**": { branches: 60, functions: 75 },
}
```

### jsdom environment requirement

All React component tests need `jsdom` (or `happy-dom`) — coverage collected without it silently excludes component renders:

```ts
// vite.config.ts
test: { environment: "jsdom" }
```

## Additional Dos

- Exclude Storybook files from coverage — they test visual appearance, not component logic.
- Collect coverage from `.tsx` explicitly — some configs default to `.ts` only.

## Additional Don'ts

- Don't set branch thresholds above 80% for UI components — not all rendering branches are reachable in unit tests (responsive breakpoints, animation states).
- Don't run coverage on every `npm test` invocation locally — use `npm run test:coverage` as a dedicated script for CI.
