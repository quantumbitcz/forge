# Next.js + stryker

> Extends `modules/code-quality/stryker.md` with Next.js-specific integration.
> Generic stryker conventions (installation, runners, threshold config) are NOT repeated here.

## Integration Setup

```bash
npm install --save-dev @stryker-mutator/core @stryker-mutator/jest-runner
```

**`stryker.config.mjs` for Next.js + Jest:**
```js
/** @type {import('@stryker-mutator/api/core').PartialStrykerOptions} */
export default {
  testRunner: "jest",
  coverageAnalysis: "perTest",
  mutate: [
    "lib/**/*.ts",
    "app/api/**/*.ts",
    "hooks/**/*.{ts,tsx}",
    "!**/*.{test,spec}.{ts,tsx}",
    "!**/*.d.ts",
  ],
  jest: { configFile: "jest.config.js", enableFindRelatedTests: true },
  thresholds: { high: 80, low: 60, break: 50 },
  reporters: ["html", "clear-text", "progress"],
  htmlReporter: { fileName: "reports/mutation/index.html" },
};
```

## Framework-Specific Patterns

### Server vs. client component mutation scope

Separate mutation targets by execution environment:

```js
// Focus mutation on logic-dense files
mutate: [
  "lib/**/*.ts",              // shared utility logic — high value
  "app/api/**/*.ts",          // route handlers + Server Actions — high value
  "hooks/**/*.{ts,tsx}",      // custom hooks — high value
  // Skip page and layout components — minimal logic
]
```

### Server Action mutation

Server Actions contain form validation and business logic — prime mutation targets:

```ts
// server-action.ts — mutate this
export async function updateProfile(data: ProfileData) {
  if (!data.email.includes("@")) throw new ValidationError("Invalid email");
  if (data.name.length < 2) throw new ValidationError("Name too short");
  return await db.users.update({ where: { id: data.id }, data });
}
```

### jest-environment split for Stryker

Stryker uses the Jest config — if the project uses multiple Jest environments (`node` for server, `jsdom` for client), Stryker runs both as configured:

```js
jest: {
  configFile: "jest.config.js",
  // jest.config.js uses `projects` array with server + client environments
}
```

### Mutation score targets

| File type | Target score |
|---|---|
| `lib/` utilities | >= 85% |
| `app/api/` route handlers | >= 80% |
| Custom hooks | >= 80% |
| Server Actions | >= 80% |
| React components | >= 50% (optional) |

## Additional Dos

- Focus Stryker on `lib/`, `app/api/`, and `hooks/` — these have the highest logic density and the clearest test boundaries.
- Use `enableFindRelatedTests: true` to speed up runs by only running tests that cover the mutant.

## Additional Don'ts

- Don't mutate `app/**/page.tsx` or `app/**/layout.tsx` — these are structural components with minimal logic.
- Don't set `break: 0` for `lib/` files — utilities with 0% mutation score indicate tests that only check the happy path.
