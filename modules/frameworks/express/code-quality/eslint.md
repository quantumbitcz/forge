# Express + eslint

> Extends `modules/code-quality/eslint.md` with Express-specific integration.
> Generic eslint conventions (flat config, typescript-eslint, CI setup) are NOT repeated here.

## Integration Setup

Install Express-relevant ESLint plugins alongside the base setup:

```bash
npm install --save-dev eslint @eslint/js typescript-eslint
npm install --save-dev eslint-plugin-security   # path traversal, eval, child_process
npm install --save-dev eslint-plugin-node        # Node.js best practices
```

**`eslint.config.js` for Express/Node.js:**

```js
import js from "@eslint/js";
import tseslint from "typescript-eslint";
import security from "eslint-plugin-security";
import node from "eslint-plugin-node";

export default tseslint.config(
  js.configs.recommended,
  ...tseslint.configs.strictTypeChecked,
  security.configs.recommended,
  {
    files: ["src/**/*.ts"],
    plugins: { node },
    languageOptions: {
      parserOptions: {
        project: "./tsconfig.json",
        tsconfigRootDir: import.meta.dirname,
      },
    },
    rules: {
      "@typescript-eslint/no-floating-promises": "error",
      "@typescript-eslint/no-misused-promises": "error",
      "no-console": ["warn", { allow: ["warn", "error"] }],
      "node/no-process-exit": "error",           // use graceful shutdown instead
      "node/no-missing-require": "off",          // handled by TypeScript
    },
  },
  {
    // Relaxed rules for Express error handlers (4-param signature is intentional)
    files: ["src/**/middleware/*.ts", "src/**/error*.ts"],
    rules: {
      "@typescript-eslint/no-unused-vars": ["error", { argsIgnorePattern: "^(err|next)$" }],
    },
  },
  {
    ignores: ["dist/**", "node_modules/**"],
  }
);
```

## Framework-Specific Patterns

### 4-Parameter Error Handler

Express error middleware requires exactly 4 parameters. ESLint flags unused `next` — suppress with an `argsIgnorePattern`:

```ts
// src/middleware/error-handler.ts
import type { ErrorRequestHandler } from "express";

const errorHandler: ErrorRequestHandler = (err, _req, res, _next) => {
  res.status(err.status ?? 500).json({ error: err.message });
};
```

Use `_` prefix for unused parameters instead of eslint-disable comments.

### Async Route Handler Safety

```ts
// Wrap async routes — eslint-plugin-node does not catch missing wrappers
// Use express-async-errors or a wrapper:
const asyncHandler =
  (fn: RequestHandler): RequestHandler =>
  (req, res, next) => {
    Promise.resolve(fn(req, res, next)).catch(next);
  };
```

### Security Plugin Rules

`eslint-plugin-security` fires on Express patterns that are legitimate — tune selectively:

```js
rules: {
  "security/detect-object-injection": "warn",  // object[param] is common in Express; review manually
  "security/detect-non-literal-regexp": "error",
  "security/detect-possible-timing-attacks": "error",
}
```

## Additional Dos

- Enable `eslint-plugin-security` for Express APIs — it catches `fs` path traversal, unsafe RegExp, and `child_process` misuse patterns common in middleware code.
- Use `argsIgnorePattern: "^(err|next)$"` for unused-vars — Express middleware signatures require all 4 parameters even when `next` is not called.
- Lint `src/` only, not the project root — avoids scanning config files that legitimately use `require` or `process.env`.

## Additional Don'ts

- Don't disable `no-floating-promises` for route handlers — unhandled async rejections crash the Express process.
- Don't use file-wide `/* eslint-disable security/* */` — review each security finding; `object[param]` is sometimes safe, sometimes not.
- Don't use `eslint-plugin-node` rules for module resolution with TypeScript paths — TypeScript handles this; the plugin produces false positives.
