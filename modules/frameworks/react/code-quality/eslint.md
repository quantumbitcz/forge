# React + eslint

> Extends `modules/code-quality/eslint.md` with React-specific integration.
> Generic eslint conventions (flat config, TypeScript setup, CI integration) are NOT repeated here.

## Integration Setup

```bash
npm install --save-dev eslint eslint-plugin-react eslint-plugin-react-hooks eslint-plugin-jsx-a11y
# TypeScript support
npm install --save-dev typescript-eslint
```

**`eslint.config.js` for React + TypeScript:**
```js
import js from "@eslint/js";
import tseslint from "typescript-eslint";
import reactPlugin from "eslint-plugin-react";
import reactHooks from "eslint-plugin-react-hooks";
import jsxA11y from "eslint-plugin-jsx-a11y";

export default tseslint.config(
  js.configs.recommended,
  ...tseslint.configs.strictTypeChecked,
  reactPlugin.configs.flat.recommended,
  reactPlugin.configs.flat["jsx-runtime"],  // React 17+ JSX transform
  jsxA11y.flatConfigs.recommended,
  {
    files: ["**/*.{ts,tsx}"],
    plugins: { "react-hooks": reactHooks },
    rules: {
      ...reactHooks.configs.recommended.rules,
      "react-hooks/exhaustive-deps": "error",   // warn is too weak — fix deps
    },
    settings: { react: { version: "detect" } },
  }
);
```

## Framework-Specific Patterns

### exhaustive-deps enforcement

The `react-hooks/exhaustive-deps` rule must be `"error"` (not `"warn"`). Stale closure bugs are runtime failures, not style issues. Disable per-line only for intentional mount-only effects with an explanatory comment:

```tsx
useEffect(() => {
  fetchInitialData();
  // eslint-disable-next-line react-hooks/exhaustive-deps
  // intentionally runs once on mount — fetchInitialData is stable (useCallback)
}, []);
```

### JSX accessibility rules

`eslint-plugin-jsx-a11y` ships with recommended rules enabled. Add interactive handler checks:

```js
rules: {
  "jsx-a11y/click-events-have-key-events": "error",
  "jsx-a11y/no-static-element-interactions": "error",
  "jsx-a11y/anchor-is-valid": ["error", { components: ["Link"], aspects: ["invalidHref"] }],
}
```

### Rules of Hooks

Never conditionally call hooks. The `react-hooks/rules-of-hooks` rule catches this statically — do not disable it:

```tsx
// BAD — ESLint error
if (condition) {
  const [state, setState] = useState(false);
}

// GOOD — hoist hook, conditionally use value
const [state, setState] = useState(false);
if (!condition) return null;
```

## Additional Dos

- Enable `react/jsx-no-leaked-render` to prevent `{count && <Component />}` rendering `0` when `count` is `0`.
- Use `react/display-name` to name memoized components — improves React DevTools stack traces.
- Enable `react/no-array-index-key` — index keys cause reconciliation bugs with dynamic lists.

## Additional Don'ts

- Don't disable `react-hooks/exhaustive-deps` globally — stale closures are silent runtime bugs.
- Don't skip `jsx-a11y` in production code — accessibility is a legal requirement in many jurisdictions.
- Don't use `eslint-plugin-react` formatting rules (spacing, indent) — these are deprecated; use Prettier.
