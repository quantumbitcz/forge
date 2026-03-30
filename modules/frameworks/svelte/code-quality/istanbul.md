# Svelte + istanbul

> Extends `modules/code-quality/istanbul.md` with Svelte-specific integration.
> Generic istanbul conventions (c8 vs nyc, threshold config, reporters) are NOT repeated here.

## Integration Setup

Svelte projects use Vitest with `@sveltejs/vite-plugin-svelte` for component testing:

```bash
npm install --save-dev @vitest/coverage-v8 @testing-library/svelte @testing-library/jest-dom
```

```ts
// vite.config.ts
import { defineConfig } from "vitest/config";
import { svelte } from "@sveltejs/vite-plugin-svelte";

export default defineConfig({
  plugins: [svelte({ hot: !process.env.VITEST })],
  test: {
    environment: "jsdom",
    setupFiles: ["./src/test/setup.ts"],
    coverage: {
      provider: "v8",
      reporter: ["text", "lcov", "html"],
      include: ["src/**/*.{ts,svelte}"],
      exclude: ["src/app.html", "src/**/*.d.ts"],
      thresholds: { lines: 75, branches: 65, functions: 80, statements: 75 },
    },
  },
});
```

## Framework-Specific Patterns

### Svelte 5 runes coverage

V8 coverage instruments Svelte 5 rune expressions (`$state`, `$derived`, `$effect`) within `<script>` blocks. Coverage of rune-based reactive logic behaves like regular TS — fully instrumented:

```ts
// This branch is covered by Istanbul/V8
let count = $state(0);
const isPositive = $derived(count > 0);   // branch: true/false
```

### Svelte stores coverage

Pure Svelte stores (`writable`, `derived`) in `.ts` files have full Istanbul coverage — include them:

```ts
include: [
  "src/lib/**/*.ts",       // stores, utilities
  "src/components/**/*.svelte",
]
```

### Threshold adjustment for Svelte components

Svelte components mix template (markup) and logic (`<script>`) — Istanbul instruments only the script block. Reduce branch thresholds for component files:

```ts
coverageThreshold: {
  "src/lib/**/*.ts": { branches: 85, lines: 85 },      // pure TS — high threshold
  "src/components/**/*.svelte": { branches: 60, lines: 70 },  // template not fully instrumented
}
```

## Additional Dos

- Include `.svelte` in the `include` glob — V8 instruments `<script>` blocks within `.svelte` files.
- Test Svelte stores independently of components — higher coverage, faster tests.

## Additional Don'ts

- Don't expect 100% branch coverage from `.svelte` files — template expressions (`{#if}`, `{:else}`) aren't fully instrumented by V8.
- Don't disable `hot: !process.env.VITEST` in the Svelte plugin config — HMR interferes with test isolation.
