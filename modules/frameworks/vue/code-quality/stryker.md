# Vue + stryker

> Extends `modules/code-quality/stryker.md` with Vue-specific integration.
> Generic stryker conventions (installation, runners, threshold config) are NOT repeated here.

## Integration Setup

```bash
npm install --save-dev @stryker-mutator/core @stryker-mutator/vitest-runner
```

**`stryker.config.mjs` for Vue + Vitest:**
```js
/** @type {import('@stryker-mutator/api/core').PartialStrykerOptions} */
export default {
  testRunner: "vitest",
  coverageAnalysis: "perTest",
  mutate: [
    "src/composables/**/*.ts",
    "src/stores/**/*.ts",
    "src/utils/**/*.ts",
    "!src/**/*.spec.ts",
    "!src/**/*.test.ts",
  ],
  vitest: { configFile: "vite.config.ts" },
  thresholds: { high: 80, low: 60, break: 50 },
  reporters: ["html", "clear-text", "progress"],
};
```

## Framework-Specific Patterns

### Focusing on composables and stores

Vue components are primarily declarative — mutation testing is most valuable on composables and Pinia stores where logic is imperative:

| File type | Mutation value | Target score |
|---|---|---|
| Composables (`src/composables/`) | High | >= 80% |
| Pinia stores (`src/stores/`) | High | >= 80% |
| Utility functions | High | >= 85% |
| Vue components | Low | Skip or >= 50% |

### Vue SFC mutation support

Stryker's Vitest runner can mutate `.vue` files via Vitest's Vue transform. Include `.vue` only for components with substantial `<script setup>` logic:

```js
mutate: [
  "src/composables/**/*.ts",
  "src/stores/**/*.ts",
  // optional — only for logic-heavy components
  // "src/components/forms/**/*.vue",
]
```

### Pinia store mutation patterns

Pinia actions are the primary mutation targets in stores — actions contain business logic branches:

```ts
// Stryker will mutate boolean conditions, early returns, and numeric comparisons
actions: {
  setPage(page: number) {
    if (page < 1 || page > this.totalPages) return;  // two branches to kill
    this.currentPage = page;
  }
}
```

## Additional Dos

- Run Stryker exclusively on `src/composables/` and `src/stores/` in CI — highest logic density, fastest feedback.
- Use `coverageAnalysis: "perTest"` to skip mutants not covered by any test.

## Additional Don'ts

- Don't mutate `src/router/` — route definitions are configuration, not logic.
- Don't set `break` thresholds for `.vue` component files — template branches inflate survivor counts unfairly.
