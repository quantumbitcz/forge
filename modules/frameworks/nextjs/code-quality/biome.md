# Next.js + biome

> Extends `modules/code-quality/biome.md` with Next.js-specific integration.
> Generic biome conventions (installation, rule categories, CI integration) are NOT repeated here.

## Integration Setup

Biome natively understands TSX/JSX — no additional plugins needed for Next.js:

```json
{
  "$schema": "https://biomejs.org/schemas/1.9.4/schema.json",
  "files": {
    "include": ["src/**/*.{ts,tsx}", "app/**/*.{ts,tsx}", "pages/**/*.{ts,tsx}"],
    "ignore": [".next/**", "out/**", "**/*.d.ts"]
  },
  "linter": {
    "rules": {
      "a11y": { "recommended": true },
      "correctness": {
        "useExhaustiveDependencies": "error",
        "useHookAtTopLevel": "error"
      },
      "security": {
        "noDangerouslySetInnerHtml": "error"
      }
    }
  }
}
```

## Framework-Specific Patterns

### App Router file structure

Next.js 13+ App Router places components in `app/`. Configure Biome to cover both App Router and Pages Router layouts:

```json
{
  "files": {
    "include": [
      "app/**/*.{ts,tsx}",
      "pages/**/*.{ts,tsx}",
      "components/**/*.{ts,tsx}",
      "lib/**/*.ts"
    ]
  }
}
```

### Server Component constraints via Biome

Biome's `useHookAtTopLevel` rule flags hook calls in non-hook functions. For Server Components (no `"use client"` directive), this catches accidental hook usage — pair with `@next/next/no-html-link-for-pages` from `eslint-config-next` for full coverage:

| Tool | Rule |
|---|---|
| Biome | `useHookAtTopLevel`, `useExhaustiveDependencies`, formatting |
| @next/eslint-plugin-next | `no-html-link-for-pages`, CWV rules, Next.js-specific patterns |

### `noDangerouslySetInnerHtml` in server components

Server Components that render HTML from a CMS must sanitize before injection. Biome's `noDangerouslySetInnerHtml` fires regardless of server vs. client component context — always sanitize with DOMPurify or equivalent server-side sanitizer before rendering.

## Additional Dos

- Run Biome alongside `eslint-config-next` — Biome covers general TS/React quality; `eslint-config-next` covers Next.js-specific navigation and performance rules.
- Exclude `.next/` — it contains compiled RSC bundles and compiled route handlers with minified code.

## Additional Don'ts

- Don't use Biome as a complete replacement for `eslint-config-next` — Next.js-specific rules (`no-html-link-for-pages`, `no-page-custom-font`) are not in Biome.
- Don't ignore hook rules for Server Components — they cannot use hooks at all; Biome catching this early prevents confusing RSC runtime errors.
