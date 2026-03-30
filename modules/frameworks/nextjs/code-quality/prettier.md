# Next.js + prettier

> Extends `modules/code-quality/prettier.md` with Next.js-specific integration.
> Generic prettier conventions (installation, `.prettierrc`, CI integration) are NOT repeated here.

## Integration Setup

```bash
npm install --save-dev prettier
# Optional: Tailwind class sorting (common in Next.js + Tailwind projects)
npm install --save-dev prettier-plugin-tailwindcss
```

**`.prettierrc` for Next.js:**
```json
{
  "semi": true,
  "singleQuote": false,
  "printWidth": 100,
  "tabWidth": 2,
  "trailingComma": "all",
  "bracketSpacing": true,
  "jsxSingleQuote": false,
  "bracketSameLine": false,
  "plugins": ["prettier-plugin-tailwindcss"]
}
```

## Framework-Specific Patterns

### `.prettierignore` for Next.js

```
.next/
out/
public/
node_modules/
```

Do NOT ignore `app/`, `pages/`, or `components/` — these are core application directories.

### `bracketSameLine: false` for JSX

Next.js components follow the React JSX community convention — closing `>` on its own line:

```tsx
// bracketSameLine: false (recommended)
export default function Page({
  params,
}: {
  params: { slug: string };
}) {
  return <article>{params.slug}</article>;
}
```

### Tailwind integration

`prettier-plugin-tailwindcss` sorts Tailwind utility classes alphabetically by layer. Works with App Router and Pages Router components equally:

```tsx
// Before — unsorted
<div className="text-sm flex items-center gap-2 bg-white rounded-lg p-4">

// After — sorted by Tailwind layer
<div className="flex items-center gap-2 rounded-lg bg-white p-4 text-sm">
```

### MDX formatting

Next.js projects with MDX content can format `.mdx` files via Prettier's built-in Markdown parser:

```json
{
  "overrides": [{ "files": "*.mdx", "options": { "parser": "mdx" } }]
}
```

## Additional Dos

- Include `app/**/*.{tsx,ts}` and `pages/**/*.{tsx,ts}` in Prettier's write glob.
- Use `jsxSingleQuote: false` — matches HTML attribute convention and React community default.

## Additional Don'ts

- Don't format `.next/` — it contains minified production build artifacts.
- Don't use `prettier-plugin-tailwindcss` without confirming Tailwind is actually in use — the plugin throws on projects without a `tailwind.config.js`.
