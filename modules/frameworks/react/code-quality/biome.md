# React + biome

> Extends `modules/code-quality/biome.md` with React-specific integration.
> Generic biome conventions (installation, rule categories, CI integration) are NOT repeated here.

## Integration Setup

Biome natively understands JSX — no additional plugins needed:

```json
{
  "$schema": "https://biomejs.org/schemas/1.9.4/schema.json",
  "files": {
    "include": ["src/**/*.{ts,tsx,js,jsx}"],
    "ignore": ["src/**/*.generated.ts", "dist/**"]
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

### Hook dependency checking

Biome's `useExhaustiveDependencies` is the built-in equivalent of `react-hooks/exhaustive-deps`. Enable as `"error"` — not `"warn"`:

```json
{
  "linter": {
    "rules": {
      "correctness": {
        "useExhaustiveDependencies": "error"
      }
    }
  }
}
```

Custom hooks not in React's built-in list must be declared explicitly:

```json
{
  "linter": {
    "rules": {
      "correctness": {
        "useExhaustiveDependencies": {
          "level": "error",
          "options": {
            "hooks": [
              { "name": "useMyCustomEffect", "closureIndex": 0, "dependenciesIndex": 1 }
            ]
          }
        }
      }
    }
  }
}
```

### XSS-prone JSX patterns

`noDangerouslySetInnerHtml` fires on any JSX attribute named `dangerouslySetInnerHTML`. When direct HTML injection is unavoidable, sanitize with DOMPurify first, then suppress per-line with justification:

```tsx
// biome-ignore lint/security/noDangerouslySetInnerHtml: sanitized via DOMPurify before assignment
<div dangerouslySetInnerHTML={{ __html: sanitizedHtml }} />
```

## Additional Dos

- Enable `a11y/recommended` — Biome's a11y rules cover the same ground as `eslint-plugin-jsx-a11y` for most common violations.
- Use Biome as the sole formatter (replaces Prettier) — consistent config reduces tooling overhead.

## Additional Don'ts

- Don't use Biome alongside `eslint-plugin-react-hooks` for hook rules — pick one linter for hook checking to avoid conflicting messages.
- Don't ignore `src/**/*.test.tsx` from linting — test files also need hook and a11y compliance.
