# eslint

## Overview

JavaScript and TypeScript linter enforcing code quality, potential bugs, and style conventions. ESLint v9+ uses flat config (`eslint.config.js`) — the legacy `.eslintrc.*` format is deprecated and removed in v9. Formatting rules (spacing, indentation) are deprecated in ESLint v9 — delegate formatting to Prettier or Biome and use ESLint only for logic/quality rules. Pair `@typescript-eslint` for TypeScript-aware rules that catch type errors and unsafe patterns beyond what `tsc` reports.

## Architecture Patterns

### Installation & Setup

```bash
npm install --save-dev eslint @eslint/js
# TypeScript support:
npm install --save-dev typescript-eslint
# React support:
npm install --save-dev eslint-plugin-react eslint-plugin-react-hooks
# Import ordering:
npm install --save-dev eslint-plugin-import
```

**Flat config (`eslint.config.js`) — ESLint v9+:**

```js
// eslint.config.js
import js from "@eslint/js";
import tseslint from "typescript-eslint";
import reactPlugin from "eslint-plugin-react";
import reactHooks from "eslint-plugin-react-hooks";

export default tseslint.config(
  js.configs.recommended,
  ...tseslint.configs.strictTypeChecked,
  {
    files: ["**/*.{ts,tsx}"],
    languageOptions: {
      parserOptions: {
        project: "./tsconfig.json",
        tsconfigRootDir: import.meta.dirname,
      },
    },
    plugins: {
      react: reactPlugin,
      "react-hooks": reactHooks,
    },
    rules: {
      ...reactPlugin.configs.recommended.rules,
      ...reactHooks.configs.recommended.rules,
      "@typescript-eslint/no-explicit-any": "error",
      "@typescript-eslint/no-floating-promises": "error",
      "@typescript-eslint/no-misused-promises": "error",
      "no-console": ["warn", { allow: ["warn", "error"] }],
    },
    settings: {
      react: { version: "detect" },
    },
  },
  {
    ignores: ["dist/**", "build/**", "node_modules/**", "*.generated.*"],
  }
);
```

For projects still on ESLint v8 (legacy `.eslintrc.js`), note that migration to flat config is required before upgrading to v9.

### Rule Categories

| Category | Plugin | Key Rules | Pipeline Severity |
|---|---|---|---|
| Type safety | `@typescript-eslint` | `no-explicit-any`, `no-unsafe-*`, `no-floating-promises` | CRITICAL |
| Correctness | `eslint` core | `no-undef`, `no-unused-vars`, `eqeqeq` | CRITICAL/WARNING |
| React hooks | `eslint-plugin-react-hooks` | `rules-of-hooks`, `exhaustive-deps` | CRITICAL |
| Imports | `eslint-plugin-import` | `no-cycle`, `no-unresolved`, `order` | WARNING |
| Style/naming | `@typescript-eslint` | `naming-convention`, `consistent-type-imports` | INFO |

### Configuration Patterns

**Per-file overrides in flat config:**
```js
export default [
  // Base config for all files
  js.configs.recommended,
  // Stricter rules for source files only
  {
    files: ["src/**/*.ts"],
    rules: { "@typescript-eslint/no-explicit-any": "error" },
  },
  // Relaxed rules for tests
  {
    files: ["**/*.test.ts", "**/*.spec.ts"],
    rules: {
      "@typescript-eslint/no-explicit-any": "warn",
      "@typescript-eslint/no-non-null-assertion": "off",
    },
  },
];
```

**Inline suppression (use sparingly with justification comment):**
```ts
// eslint-disable-next-line @typescript-eslint/no-explicit-any -- legacy API returns untyped data
const result: any = legacyApi.fetch();
```

**`eslint.config.js` for monorepos** — use `files` globs to scope rules to each package directory rather than maintaining separate configs per package.

### CI Integration

```yaml
# .github/workflows/quality.yml
- name: ESLint
  run: npx eslint . --format sarif --output-file eslint-results.sarif --max-warnings 0

- name: Upload ESLint SARIF
  if: always()
  uses: github/codeql-action/upload-sarif@v3
  with:
    sarif_file: eslint-results.sarif
    category: eslint
```

`--max-warnings 0` promotes all warnings to failures. Omit for teams gradually adopting new rules — allow warnings temporarily with a roadmap to zero.

**Pre-commit hook via lint-staged:**
```json
// package.json
{
  "lint-staged": {
    "*.{js,ts,jsx,tsx}": ["eslint --fix --max-warnings 0"]
  }
}
```

## Performance

- Type-aware rules (`@typescript-eslint/no-floating-promises`, `no-misused-promises`) require full TypeScript program initialization — adds 3-10s for large projects. Disable in `--fix` runs if not needed.
- Use `eslint --cache --cache-location .eslintcache` to skip unchanged files. Cache is invalidated when config or rules change.
- Flat config has no glob-based config cascade overhead — it's faster than `eslintrc` for large monorepos.
- Run `eslint src/` (explicit paths) rather than `.` in CI to avoid scanning `node_modules`, `dist`, etc. that `ignores` may not fully exclude.

## Security

ESLint catches several security-adjacent patterns:

- `no-eval` / `no-new-Function` — prevents dynamic code execution
- `@typescript-eslint/no-unsafe-*` rules — blocks implicit `any` chains that hide injection vectors
- `eslint-plugin-security` (optional) — detects `fs` path traversal patterns, unsafe `RegExp` inputs, `child_process` misuse

Install security plugin for sensitive projects:
```bash
npm install --save-dev eslint-plugin-security
```
```js
import security from "eslint-plugin-security";
export default [security.configs.recommended, ...];
```

## Testing

```bash
# Check all files, fail on any warning
npx eslint . --max-warnings 0

# Fix auto-fixable issues in place
npx eslint . --fix

# Print config for a specific file (debug rule conflicts)
npx eslint --print-config src/index.ts

# Check which rules apply to a file
npx eslint --debug src/index.ts 2>&1 | grep "Rule"

# Lint only changed files (fast local loop)
git diff --name-only --diff-filter=ACM | grep -E '\.(js|ts|tsx)$' | xargs npx eslint
```

## Dos

- Use flat config (`eslint.config.js`) — the legacy `eslintrc` format is unsupported in ESLint v9.
- Enable `strictTypeChecked` from `typescript-eslint` — it catches async bugs (`no-floating-promises`) that TypeScript itself does not.
- Set `--max-warnings 0` in CI — warnings that never fail are ignored by developers.
- Pin the ESLint version in `package.json` and lock with `package-lock.json` or `pnpm-lock.yaml` — rule behavior changes between minor versions.
- Use `eslint-plugin-import/no-cycle` for large codebases — circular imports cause subtle initialization bugs.
- Separate lint from format: delegate spacing/indentation to Prettier or Biome and keep ESLint for logic rules only.

## Don'ts

- Don't use formatting rules (`indent`, `quotes`, `semi`) in ESLint v9 — they are deprecated and conflict with Prettier/Biome.
- Don't use `/* eslint-disable */` file-wide suppressions — they hide real issues. Prefer per-line suppression with a comment explaining why.
- Don't run ESLint without `--cache` in local development — cold runs on large projects take 30-60s and discourage frequent use.
- Don't enable `no-console` as CRITICAL in development environments — gate it via `process.env.NODE_ENV` or disable for test files.
- Don't rely on ESLint alone for type errors — `tsc --noEmit` must run separately; ESLint with `@typescript-eslint` is an additional layer, not a compiler replacement.
- Don't mix `eslintrc` and flat config in the same project — ESLint v9 ignores `.eslintrc.*` entirely when `eslint.config.js` exists.
