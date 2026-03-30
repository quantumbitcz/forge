# NestJS + eslint

> Extends `modules/code-quality/eslint.md` with NestJS-specific integration.
> Generic eslint conventions (flat config, typescript-eslint, CI setup) are NOT repeated here.

## Integration Setup

```bash
npm install --save-dev eslint @eslint/js typescript-eslint
npm install --save-dev @darraghor/eslint-plugin-nestjs-typed   # NestJS-specific rules
```

**`eslint.config.js` for NestJS:**

```js
import js from "@eslint/js";
import tseslint from "typescript-eslint";
import nestjsTyped from "@darraghor/eslint-plugin-nestjs-typed";

export default tseslint.config(
  js.configs.recommended,
  ...tseslint.configs.strictTypeChecked,
  {
    files: ["src/**/*.ts"],
    plugins: { "@nestjs-typed": nestjsTyped },
    languageOptions: {
      parserOptions: {
        project: "./tsconfig.json",
        tsconfigRootDir: import.meta.dirname,
      },
    },
    rules: {
      "@typescript-eslint/no-floating-promises": "error",
      "@typescript-eslint/no-misused-promises": "error",
      "@typescript-eslint/no-explicit-any": "error",
      // NestJS-specific rules
      "@nestjs-typed/injectable-should-be-provided": "error",
      "@nestjs-typed/no-injectable-should-not-be-provided": "warn",
      "@nestjs-typed/provided-injected-should-match-factory-parameters": "error",
    },
  },
  {
    files: ["src/**/*.controller.ts"],
    rules: {
      // Controllers are thin — warn if they contain business logic
      "max-lines-per-function": ["warn", { max: 25 }],
    },
  },
  {
    files: ["**/*.spec.ts", "**/*.e2e-spec.ts"],
    rules: {
      "@typescript-eslint/no-explicit-any": "warn",
      "@typescript-eslint/no-non-null-assertion": "off",
    },
  },
  {
    ignores: ["dist/**", "node_modules/**"],
  }
);
```

## Framework-Specific Patterns

### Decorator and Module Lint Rules

NestJS relies heavily on decorators. `@darraghor/eslint-plugin-nestjs-typed` enforces correct DI wiring:

- `injectable-should-be-provided` — catches `@Injectable()` classes not registered in any module
- `provided-injected-should-match-factory-parameters` — catches `useFactory` parameter count mismatches

### Module Structure Enforcement

Enforce that controllers stay thin via line-count rules:

```js
// eslint.config.js controller override
{
  files: ["src/**/*.controller.ts"],
  rules: {
    "max-lines-per-function": ["warn", { max: 25 }],
  },
}
```

### Unused Decorator Parameters

NestJS guards and interceptors have required `context` and `next` parameters. Suppress unused-vars for common NestJS patterns:

```js
rules: {
  "@typescript-eslint/no-unused-vars": ["error", {
    argsIgnorePattern: "^(context|next|request|response)$"
  }],
}
```

## Additional Dos

- Use `@darraghor/eslint-plugin-nestjs-typed` — it catches DI configuration errors at lint time that would otherwise surface as runtime `NotFoundException`.
- Override `max-lines-per-function` for controller files — a warning-level limit enforces the "thin controller" pattern without breaking builds during gradual refactors.
- Configure stricter rules for `src/services/` — services contain business logic where type safety and async correctness matter most.

## Additional Don'ts

- Don't disable `no-floating-promises` in controllers — unhandled promise rejections in NestJS async handlers bypass the global `ExceptionFilter`.
- Don't use `@ts-ignore` in module files — DI type errors indicate a real wiring problem; fix the module registration instead of suppressing.
- Don't apply the same loose rules to services as to DTOs — DTOs use decorators heavily and need `@typescript-eslint/no-explicit-any: "off"` in limited cases; services should stay strict.
