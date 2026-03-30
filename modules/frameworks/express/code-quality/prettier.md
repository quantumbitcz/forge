# Express + prettier

> Extends `modules/code-quality/prettier.md` with Express-specific integration.
> Generic prettier conventions (config format, ignore patterns, CI setup) are NOT repeated here.

## Integration Setup

```bash
npm install --save-dev prettier
```

**`.prettierrc.json` for Express/Node.js:**

```json
{
  "semi": true,
  "singleQuote": true,
  "trailingComma": "all",
  "printWidth": 100,
  "tabWidth": 2,
  "arrowParens": "always"
}
```

**`.prettierignore`:**

```
dist/
coverage/
*.generated.ts
node_modules/
```

**`package.json` scripts:**

```json
{
  "scripts": {
    "format": "prettier --write src/",
    "format:check": "prettier --check src/"
  },
  "lint-staged": {
    "*.{ts,js,json}": ["prettier --write"]
  }
}
```

## Framework-Specific Patterns

### JSON Response Formatting

Prettier does not affect runtime JSON serialization. Keep Prettier for source files only — do not run it on API response fixtures or test snapshots that need to match exact whitespace:

```json
// .prettierignore
tests/fixtures/**/*.json     # snapshot files — maintain exact format
```

### Config Files

Express projects often have multiple config files (`app.ts`, `server.ts`, `config/`). Run Prettier on all `.ts` and `.js` files including config — consistent formatting reduces diffs in PR reviews.

## Additional Dos

- Enable `trailingComma: "all"` — reduces diff noise when adding parameters to Express middleware chains.
- Add `prettier --check src/` to CI before linting — catch formatting violations before type errors, keeping CI feedback fast.
- Use `lint-staged` to auto-format on commit — avoids formatting PRs that mix logic and style changes.

## Additional Don'ts

- Don't configure Prettier's `semi: false` in Express projects unless the entire team is aligned — Express error messages reference line numbers and semicolon-free code shifts line numbers unpredictably in stack traces.
- Don't run Prettier on generated OpenAPI/Swagger client files — they are auto-generated and formatting them wastes CI time.
