# Angular + stryker

> Extends `modules/code-quality/stryker.md` with Angular-specific integration.
> Generic stryker conventions (installation, runners, threshold config) are NOT repeated here.

## Integration Setup

```bash
npm install --save-dev @stryker-mutator/core @stryker-mutator/jest-runner
# or for Karma:
npm install --save-dev @stryker-mutator/core @stryker-mutator/karma-runner
```

**`stryker.config.mjs` for Angular + Jest:**
```js
/** @type {import('@stryker-mutator/api/core').PartialStrykerOptions} */
export default {
  testRunner: "jest",
  coverageAnalysis: "perTest",
  mutate: [
    "src/app/**/*.ts",
    "!src/app/**/*.spec.ts",
    "!src/app/**/*.module.ts",
    "!src/app/**/*.routes.ts",
    "!src/environments/**",
    "!src/main.ts",
  ],
  jest: { configFile: "jest.config.js", enableFindRelatedTests: true },
  thresholds: { high: 80, low: 60, break: 50 },
  reporters: ["html", "clear-text", "progress"],
};
```

## Framework-Specific Patterns

### Excluding Angular boilerplate from mutation

Angular generates non-logic files that inflate mutation counts without meaningful test value:

```js
mutate: [
  "src/app/services/**/*.ts",       // high value — business logic
  "src/app/store/**/*.ts",          // high value — state logic
  "!src/app/**/*.module.ts",        // NgModule declarations — not logic
  "!src/app/**/*.routes.ts",        // routing config — not logic
  "!src/app/**/*.component.ts",     // components — prefer RTL integration tests
]
```

### Signal-based services

Angular 17+ signal-based services with `computed()` and `effect()` mutations produce higher kill rates than Observable chains — signal derivation logic is fully synchronous and easy to test:

```ts
// Easy to mutate — computed signal
readonly isLoggedIn = computed(() => this.currentUser() !== null);
```

### Karma runner (legacy)

If the project still uses Karma, configure with `@stryker-mutator/karma-runner`. Note Karma is slower than Jest — run Stryker only on targeted service files rather than the full `src/app/`:

```js
testRunner: "karma",
karma: { configFile: "karma.conf.js", projectType: "angular-cli" },
```

## Additional Dos

- Focus mutation on services and store reducers/selectors — these have the highest test ROI.
- Run Stryker on a dedicated `stryker` CI step, not as part of the standard test pipeline — it's too slow for every commit.

## Additional Don'ts

- Don't mutate `*.module.ts` or `*.routes.ts` — these are configuration, not logic; mutations produce meaningless survivors.
- Don't expect high mutation scores on components with minimal TS logic (only template bindings) — that's expected, not a gap.
