# biome

## Overview

All-in-one Rust-based toolchain for JavaScript and TypeScript: linter, formatter, and import organizer in a single binary with no plugins or external dependencies. Biome is 10-100x faster than ESLint + Prettier for equivalent checks. No plugin system — rules are built-in and curated. Position as a full ESLint+Prettier replacement for greenfield projects or teams that value speed and simplicity. For projects requiring ESLint's plugin ecosystem (e.g., `eslint-plugin-import/no-cycle`, framework-specific plugins), Biome covers the common subset but cannot replace every ESLint plugin.

## Architecture Patterns

### Installation & Setup

```bash
npm install --save-dev --save-exact @biomejs/biome
npx biome init   # generates biome.json with defaults
```

**Verify installation:**
```bash
npx biome --version   # e.g., 1.9.x
```

Single binary, no Node.js runtime overhead after install. Can also run as a standalone binary:
```bash
# macOS/Linux
curl -L https://github.com/biomejs/biome/releases/latest/download/biome-darwin-arm64 -o /usr/local/bin/biome
chmod +x /usr/local/bin/biome
```

### Rule Categories

Biome organizes rules into domains — no external plugins required:

| Domain | Key Rules | Pipeline Severity |
|---|---|---|
| `lint/correctness` | `noUnusedVariables`, `noInvalidUseBeforeDeclaration`, `useExhaustiveDependencies` | CRITICAL |
| `lint/suspicious` | `noDoubleEquals`, `noExplicitAny`, `noFallthroughSwitchClause` | CRITICAL |
| `lint/security` | `noDangerouslySetInnerHtml`, `noGlobalEval` | CRITICAL |
| `lint/style` | `useConst`, `useTemplate`, `noNegationElse` | WARNING |
| `lint/complexity` | `noForEach` (prefer `for-of`), `useFlatMap` | INFO |
| `lint/a11y` | `useAltText`, `useButtonType`, `noAutofocus` | WARNING |
| `format` | Indentation, quotes, semicolons, line width | auto-fix |
| `assist/source` | organize-imports: auto-sorts and deduplicates | auto-fix |

### Configuration Patterns

**`biome.json` (recommended over `biome.jsonc`):**

```json
{
  "$schema": "https://biomejs.dev/schemas/1.9.4/schema.json",
  "vcs": {
    "enabled": true,
    "clientKind": "git",
    "useIgnoreFile": true
  },
  "files": {
    "ignoreUnknown": false,
    "ignore": ["dist/**", "build/**", "*.generated.*", "coverage/**"]
  },
  "formatter": {
    "enabled": true,
    "indentStyle": "space",
    "indentWidth": 2,
    "lineWidth": 100
  },
  "organizeImports": {
    "enabled": true
  },
  "linter": {
    "enabled": true,
    "rules": {
      "recommended": true,
      "correctness": {
        "noUnusedVariables": "error",
        "useExhaustiveDependencies": "error"
      },
      "suspicious": {
        "noExplicitAny": "error"
      },
      "style": {
        "useConst": "error",
        "useTemplate": "warn"
      },
      "a11y": {
        "useAltText": "error",
        "useButtonType": "error"
      }
    }
  },
  "javascript": {
    "formatter": {
      "quoteStyle": "double",
      "semicolons": "always",
      "trailingCommas": "all"
    }
  }
}
```

**Inline suppression:**
```ts
// biome-ignore lint/suspicious/noExplicitAny: legacy API returns untyped data
const result: any = legacyApi.fetch();

// biome-ignore format: manually aligned table
const matrix = [
  [1, 0, 0],
  [0, 1, 0],
  [0, 0, 1],
];
```

**Per-directory overrides:**
```json
{
  "overrides": [
    {
      "include": ["**/*.test.ts", "**/*.spec.ts"],
      "linter": {
        "rules": {
          "suspicious": { "noExplicitAny": "warn" }
        }
      }
    }
  ]
}
```

### CI Integration

```yaml
# .github/workflows/quality.yml
- name: Biome check
  run: npx biome ci --reporter=github

- name: Biome check (JSON output for tooling)
  run: npx biome ci --reporter=json > biome-results.json
```

`biome ci` runs lint + format check + import organize check without applying fixes. Exit code 1 if any issue found. The `--reporter=github` flag emits GitHub Actions annotations directly in PR diffs.

**Pre-commit hook via lint-staged:**
```json
{
  "lint-staged": {
    "*.{js,ts,jsx,tsx,json,css}": ["biome check --write --no-errors-on-unmatched"]
  }
}
```

## Performance

- Biome processes ~200k lines/second on a modern laptop — a 500k-line monorepo lints in under 3 seconds.
- No plugin loading, no rule compilation, no spawning external processes — the binary is self-contained.
- `biome check --changed` (v1.8+) uses VCS integration to lint only modified files — near-instant in local dev.
- Cache is automatic and file-based — unchanged files are skipped without any configuration.
- Comparison: ESLint + Prettier on a 100k-line TypeScript project typically takes 30-90s cold; Biome takes 1-3s.

## Security

Built-in security rules without plugins:

- `lint/security/noDangerouslySetInnerHtml` — blocks React XSS vectors
- `lint/security/noGlobalEval` — bans dynamic code execution via global `eval` and the `Function` constructor
- `lint/suspicious/noSelfCompare` — catches NaN comparison bugs
- `lint/correctness/noInvalidUseBeforeDeclaration` — prevents TDZ-related runtime errors

Biome does not perform deep dataflow analysis — for injection detection beyond pattern matching, supplement with `semgrep` or `codeql`.

## Testing

```bash
# Full check (lint + format + imports) — CI mode, no auto-fix
npx biome ci .

# Check and auto-fix everything
npx biome check --write .

# Format only
npx biome format --write .

# Lint only (no format check)
npx biome lint .

# Check a single file
npx biome check src/index.ts

# Explain a specific rule
npx biome explain noExplicitAny

# List all available rules
npx biome explain --list-all
```

**Migrate from ESLint + Prettier:**
```bash
npx @biomejs/biome migrate eslint --write    # imports .eslintrc rules where possible
npx @biomejs/biome migrate prettier --write  # imports .prettierrc settings
```

## Dos

- Run `biome ci` (not `biome check`) in CI — `ci` never modifies files and has clear exit codes.
- Enable VCS integration (`vcs.enabled: true`, `vcs.useIgnoreFile: true`) to respect `.gitignore` and enable `--changed` mode.
- Pin the exact version with `--save-exact` — Biome does not use semantic versioning for stability guarantees across patch versions.
- Use `biome check --write` as a pre-commit hook — it runs lint + format + import organization in one pass.
- Commit `biome.json` to version control — it is the single source of truth for all formatting and linting config.
- Consider Biome as the primary tool for JS/TS-only projects; evaluate the ESLint plugin gap for framework-heavy stacks before fully replacing ESLint.

## Don'ts

- Don't mix Biome formatter with Prettier in the same project — they have conflicting opinions on trailing commas, quote style, and bracket spacing. Choose one.
- Don't use `biome check --write` in CI — it silently fixes issues and exits 0, hiding violations from review.
- Don't assume ESLint plugin coverage parity — Biome lacks equivalents for `eslint-plugin-import/no-cycle`, `eslint-plugin-sonarjs`, and many framework-specific plugins. Audit your ESLint rule list before migrating.
- Don't enable `recommended: true` and also list individual rules from the same category as `"off"` — use `recommended: false` at the category level and enable rules selectively instead.
- Don't skip the `$schema` field in `biome.json` — IDE autocompletion depends on it and schema validation catches config errors before CI.
- Don't run Biome on generated files (OpenAPI clients, GraphQL types, Prisma client) — add them to `files.ignore` to avoid confusing violations and churn.
