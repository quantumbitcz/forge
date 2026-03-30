# NestJS + biome

> Extends `modules/code-quality/biome.md` with NestJS-specific integration.
> Generic biome conventions (installation, rule categories, CI) are NOT repeated here.

## Integration Setup

```bash
npm install --save-dev --save-exact @biomejs/biome
npx biome init
```

**`biome.json` tuned for NestJS:**

```json
{
  "$schema": "https://biomejs.dev/schemas/1.9.0/schema.json",
  "organizeImports": { "enabled": true },
  "linter": {
    "enabled": true,
    "rules": {
      "recommended": true,
      "correctness": {
        "noUnusedVariables": "warn",
        "useExhaustiveDependencies": "off"
      },
      "style": {
        "useNamingConvention": {
          "level": "warn",
          "options": {
            "strictCase": false,
            "conventions": [
              { "selector": { "kind": "class" }, "formats": ["PascalCase"] },
              { "selector": { "kind": "classProperty" }, "formats": ["camelCase"] }
            ]
          }
        }
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

### Import Order and `reflect-metadata`

NestJS requires `import "reflect-metadata"` as the first import in `main.ts`. Biome's import organizer reorders imports alphabetically — this breaks NestJS decorator metadata:

```ts
// main.ts — mark as side-effect import to prevent reordering
import "reflect-metadata"; // biome-ignore lint/correctness/noUnusedImports: required for decorators
import { NestFactory } from "@nestjs/core";
```

Add to `biome.json`:

```json
{
  "assist": {
    "actions": {
      "source": {
        "organizeImports": {
          "level": "off"   // Disable auto-organize for main.ts if reflect-metadata ordering is an issue
        }
      }
    }
  }
}
```

### Unused Parameters in Guards and Interceptors

NestJS `CanActivate` and `NestInterceptor` interfaces require `context` and `next` parameters:

```ts
// Prefix with underscore to satisfy Biome's noUnusedVariables
canActivate(_context: ExecutionContext): boolean {
  return true;
}
```

## Additional Dos

- Disable `useExhaustiveDependencies` — this is a React-specific rule with no meaning in NestJS.
- Prefix unused Guard/Interceptor parameters with `_` rather than disabling `noUnusedVariables` globally.
- Use Biome for formatting NestJS projects — it handles TypeScript decorators correctly and is significantly faster than Prettier for large module files.

## Additional Don'ts

- Don't let Biome reorganize imports in `main.ts` — `reflect-metadata` must be the first import for decorator metadata to work.
- Don't use Biome as a full replacement for `@darraghor/eslint-plugin-nestjs-typed` — Biome cannot statically verify NestJS module DI wiring.
