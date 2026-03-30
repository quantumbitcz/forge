# React + prettier

> Extends `modules/code-quality/prettier.md` with React-specific integration.
> Generic prettier conventions (installation, `.prettierrc`, CI integration) are NOT repeated here.

## Integration Setup

No React-specific Prettier plugins are needed — Prettier formats JSX natively. Install `prettier-plugin-tailwindcss` if Tailwind is in use:

```bash
npm install --save-dev prettier prettier-plugin-tailwindcss
```

**`.prettierrc` additions for React projects:**
```json
{
  "jsxSingleQuote": false,
  "bracketSameLine": false,
  "plugins": ["prettier-plugin-tailwindcss"]
}
```

## Framework-Specific Patterns

### JSX formatting conventions

`bracketSameLine: false` keeps JSX closing `>` on its own line, matching the React community default:

```tsx
// bracketSameLine: false (recommended)
<Button
  variant="primary"
  onClick={handleClick}
>
  Submit
</Button>

// bracketSameLine: true — avoid, deviates from community standard
<Button variant="primary" onClick={handleClick}>
```

### Tailwind class ordering

`prettier-plugin-tailwindcss` auto-sorts Tailwind utility classes on save. Enforce via pre-commit:

```bash
npx prettier --write "src/**/*.{ts,tsx}"
```

### Conflict with ESLint JSX rules

Remove all JSX formatting rules from ESLint when Prettier is active — `eslint-config-prettier` disables conflicting rules:

```bash
npm install --save-dev eslint-config-prettier
```

```js
// eslint.config.js
import prettierConfig from "eslint-config-prettier";
export default [...existingConfigs, prettierConfig];
```

## Additional Dos

- Set `jsxSingleQuote: false` — double quotes in JSX attributes match HTML conventions and the React community default.
- Include `.tsx` in Prettier's `--write` glob — JSX files without explicit extension matching are sometimes missed.

## Additional Don'ts

- Don't install `@prettier/plugin-babel` for React — Prettier handles JSX natively without Babel.
- Don't use Prettier for logic formatting decisions (ternary branches, conditional rendering) — those are ESLint/readability concerns.
