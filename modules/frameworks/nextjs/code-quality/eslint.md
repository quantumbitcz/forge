# Next.js + eslint

> Extends `modules/code-quality/eslint.md` with Next.js-specific integration.
> Generic eslint conventions (flat config, TypeScript setup, CI integration) are NOT repeated here.

## Integration Setup

```bash
npm install --save-dev eslint eslint-config-next @next/eslint-plugin-next
npm install --save-dev typescript-eslint eslint-plugin-react eslint-plugin-react-hooks
```

**`eslint.config.js` for Next.js + TypeScript:**
```js
import tseslint from "typescript-eslint";
import nextPlugin from "@next/eslint-plugin-next";
import reactPlugin from "eslint-plugin-react";
import reactHooks from "eslint-plugin-react-hooks";

export default tseslint.config(
  ...tseslint.configs.strictTypeChecked,
  {
    files: ["**/*.{ts,tsx}"],
    plugins: {
      "@next/next": nextPlugin,
      react: reactPlugin,
      "react-hooks": reactHooks,
    },
    rules: {
      ...nextPlugin.configs.recommended.rules,
      ...nextPlugin.configs["core-web-vitals"].rules,  // stricter CWV rules
      ...reactHooks.configs.recommended.rules,
      "react-hooks/exhaustive-deps": "error",
      "@next/next/no-html-link-for-pages": "error",
    },
    settings: { react: { version: "detect" } },
  },
  {
    ignores: [".next/**", "out/**"],
  }
);
```

## Framework-Specific Patterns

### `@next/next/no-html-link-for-pages`

Using `<a href="/page">` instead of `<Link href="/page">` breaks Next.js client-side navigation and causes full-page reloads. This rule is a CRITICAL violation:

```tsx
// BAD — full-page reload, breaks App Router prefetching
<a href="/dashboard">Dashboard</a>

// GOOD — client-side navigation with prefetching
import Link from "next/link";
<Link href="/dashboard">Dashboard</Link>
```

### Core Web Vitals rules

`eslint-config-next`'s `core-web-vitals` preset adds stricter rules than `recommended`:

- `@next/next/no-sync-scripts` — blocks synchronous `<script>` in `_document.tsx`
- `@next/next/no-css-tags` — blocks manual `<link rel="stylesheet">` (use CSS Modules or CSS-in-JS)
- `@next/next/no-page-custom-font` — blocks per-page font imports (use `next/font` for LCP optimization)

### Server Component vs. Client Component lint separation

Lint server components (`app/**/*.tsx` without `"use client"`) with stricter rules — no browser APIs, no hooks:

```js
{
  files: ["app/**/*.tsx"],
  rules: {
    // No hooks allowed in server components
    "react-hooks/rules-of-hooks": "error",
  }
}
```

## Additional Dos

- Use `eslint-config-next/core-web-vitals` (stricter) over `eslint-config-next` (baseline) for new projects.
- Exclude `.next/` from linting — it contains compiled server bundles with minified code.

## Additional Don'ts

- Don't disable `@next/next/no-html-link-for-pages` — it prevents a class of navigation performance regressions.
- Don't apply React hook rules to Server Components — they cannot use hooks by design.
