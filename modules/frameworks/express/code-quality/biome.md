# Express + biome

> Extends `modules/code-quality/biome.md` with Express-specific integration.
> Generic biome conventions (installation, rule categories, CI setup) are NOT repeated here.

## Integration Setup

Biome requires no Express-specific plugins — it works out of the box for TypeScript Node.js projects:

```bash
npm install --save-dev --save-exact @biomejs/biome
npx biome init
```

**`biome.json` tuned for Express:**

```json
{
  "$schema": "https://biomejs.dev/schemas/1.9.0/schema.json",
  "organizeImports": { "enabled": true },
  "linter": {
    "enabled": true,
    "rules": {
      "recommended": true,
      "security": {
        "noGlobalEval": "error"
      },
      "correctness": {
        "noUnusedVariables": "warn",
        "useExhaustiveDependencies": "off"   // React-only rule
      }
    }
  },
  "formatter": {
    "enabled": true,
    "indentStyle": "space",
    "indentWidth": 2,
    "lineWidth": 100
  },
  "files": {
    "ignore": ["dist/**", "coverage/**", "node_modules/**"]
  }
}
```

## Framework-Specific Patterns

### Unused Parameters in Middleware

Express 4-parameter error handlers require `err, req, res, next` even when some are unused. Biome's `noUnusedVariables` fires on unused `next`. Use underscore prefix:

```ts
// Error handler — next is required for Express to recognize this as error middleware
const errorHandler = (err: AppError, _req: Request, res: Response, _next: NextFunction) => {
  res.status(err.status ?? 500).json({ error: err.message });
};
```

### No-eval in Dynamic Routes

Biome's `noGlobalEval` catches dynamic route handlers that use `eval` — common in poorly-generated code or legacy Express adapters. Prefer explicit route registration.

## Additional Dos

- Set `useExhaustiveDependencies: "off"` — this React Hooks rule is irrelevant in Express/Node.js contexts and produces false positives.
- Use Biome as a Prettier replacement for Express projects — removes the need to coordinate ESLint+Prettier formatting rule conflicts.
- Run `biome check --write src/` in pre-commit hooks to auto-fix and format in one pass.

## Additional Don'ts

- Don't use Biome's import sorting to override Node.js module resolution order — ordering side-effectful imports (e.g., `import "reflect-metadata"` for DI decorators) matters; mark them with a comment to prevent reordering.
- Don't rely on Biome alone for Express security patterns (path traversal, object injection) — supplement with `eslint-plugin-security` or a SAST tool.
