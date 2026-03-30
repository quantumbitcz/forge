# SvelteKit + eslint

> Extends `modules/code-quality/eslint.md` with SvelteKit-specific integration.
> Generic eslint conventions (flat config, TypeScript setup, CI integration) are NOT repeated here.

## Integration Setup

```bash
npm install --save-dev eslint eslint-plugin-svelte svelte-eslint-parser typescript-eslint
```

**`eslint.config.js` for SvelteKit + TypeScript:**
```js
import tseslint from "typescript-eslint";
import sveltePlugin from "eslint-plugin-svelte";
import svelteParser from "svelte-eslint-parser";

export default tseslint.config(
  ...tseslint.configs.recommendedTypeChecked,
  ...sveltePlugin.configs["flat/recommended"],
  {
    files: ["**/*.svelte"],
    languageOptions: {
      parser: svelteParser,
      parserOptions: {
        parser: tseslint.parser,
        project: "./tsconfig.json",
        extraFileExtensions: [".svelte"],
        svelteFeatures: { runes: true },
      },
    },
    rules: {
      "svelte/valid-compile": "error",
    },
  },
  {
    // SvelteKit server-side files — disable browser-only rules
    files: ["src/routes/**/*.server.ts", "src/hooks.server.ts"],
    rules: {
      "@typescript-eslint/no-floating-promises": "error",
    },
  },
  {
    ignores: [".svelte-kit/**", "build/**"],
  }
);
```

## Framework-Specific Patterns

### Server vs. client file rules

SvelteKit separates server (`*.server.ts`, `+page.server.ts`, `+layout.server.ts`) and client files. Apply stricter promise-handling rules to server files:

```js
// Server files — promises must be awaited; unhandled rejections crash the server
files: ["src/routes/**/*.server.ts"],
rules: { "@typescript-eslint/no-floating-promises": "error" }
```

### Generated file exclusion

SvelteKit generates `.svelte-kit/` on every dev server start — exclude it from linting:

```js
ignores: [".svelte-kit/**", "build/**", "src/app.d.ts"]
```

### SvelteKit-specific `eslint-plugin-svelte` rules

Additional rules useful for SvelteKit `+page.svelte` / `+layout.svelte` patterns:

```js
rules: {
  "svelte/no-unused-svelte-ignore": "error",
  "svelte/prefer-writable-derived": "error",
}
```

## Additional Dos

- Exclude `.svelte-kit/` from linting — it contains auto-generated TypeScript type definitions that change on every `vite dev` run.
- Apply `@typescript-eslint/no-floating-promises` to server files — SvelteKit load functions and API handlers run in Node.js where unhandled promise rejections are fatal.

## Additional Don'ts

- Don't apply browser-DOM ESLint rules to `*.server.ts` files — server code runs in Node.js, not a browser.
- Don't lint `src/app.d.ts` — it's a SvelteKit-generated ambient type declaration file.
