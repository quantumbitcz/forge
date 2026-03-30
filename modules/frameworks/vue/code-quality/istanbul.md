# Vue + istanbul

> Extends `modules/code-quality/istanbul.md` with Vue-specific integration.
> Generic istanbul conventions (c8 vs nyc, threshold config, reporters) are NOT repeated here.

## Integration Setup

Vue projects use Vitest as the primary test runner:

```bash
npm install --save-dev @vitest/coverage-v8 @vue/test-utils
```

```ts
// vite.config.ts
import { defineConfig } from "vitest/config";
import vue from "@vitejs/plugin-vue";

export default defineConfig({
  plugins: [vue()],
  test: {
    environment: "jsdom",
    coverage: {
      provider: "v8",
      reporter: ["text", "lcov", "html"],
      include: ["src/**/*.{ts,vue}"],
      exclude: [
        "src/main.ts",
        "src/**/*.d.ts",
        "src/router/index.ts",        // routing config
        "src/stores/index.ts",        // store barrel re-exports
      ],
      thresholds: { lines: 80, branches: 70, functions: 85, statements: 80 },
    },
  },
});
```

## Framework-Specific Patterns

### Vue SFC coverage

V8 coverage instruments `.vue` files when using Vitest + `@vitejs/plugin-vue`. Both `<script setup>` and `<template>` branches are instrumented (template branches partially):

```ts
// vite.config.ts
include: ["src/**/*.{ts,vue}"]   // include .vue for SFC coverage
```

### Pinia store coverage

Pinia stores are pure TypeScript — they should achieve higher thresholds than components:

```ts
coverageThreshold: {
  "src/stores/**": { branches: 85, functions: 90, lines: 90 },
  "src/composables/**": { branches: 85, functions: 90 },
  "src/components/**": { branches: 60, functions: 75 },
}
```

### Composable testing pattern

Test composables in isolation using `@vue/test-utils`'s `withSetup` helper for composables that depend on Vue lifecycle:

```ts
// Coverage-friendly composable test
test("increments count", () => {
  const { count, increment } = useCounter(0);
  increment();
  expect(count.value).toBe(1);
});
```

## Additional Dos

- Include `.vue` in the `include` glob — Istanbul via V8 instruments SFC script blocks.
- Target higher thresholds for Pinia stores and composables than for components.

## Additional Don'ts

- Don't expect full branch coverage from template conditionals (`v-if`, `v-show`) — Vue's template compiler generates complex branching that Istanbul partially instruments.
- Don't run `vitest --coverage` on every local test run — dedicate a `test:coverage` script for CI.
