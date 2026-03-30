# prettier

## Overview

Opinionated JS/TS/CSS/HTML/JSON/YAML/Markdown formatter. Prettier enforces a consistent style by reprinting the AST — not by patching text. Zero linting logic: it formats, nothing else. Delegate all quality rules to ESLint/Biome and use Prettier only for formatting. Prettier v3 requires Node.js 14+ and ships with native ESM support. The `--write` flag mutates files in place; use `--check` in CI to fail on unformatted code without writing.

## Architecture Patterns

### Installation & Setup

```bash
npm install --save-dev prettier

# Optional plugins
npm install --save-dev prettier-plugin-svelte
npm install --save-dev prettier-plugin-tailwindcss   # sorts Tailwind classes
npm install --save-dev @prettier/plugin-xml
```

**`.prettierrc` (JSON — recommended for editor tooling compatibility):**
```json
{
  "semi": true,
  "singleQuote": false,
  "printWidth": 100,
  "tabWidth": 2,
  "useTabs": false,
  "trailingComma": "all",
  "bracketSpacing": true,
  "arrowParens": "always",
  "endOfLine": "lf",
  "plugins": ["prettier-plugin-tailwindcss"]
}
```

**Per-language overrides in `.prettierrc`:**
```json
{
  "semi": true,
  "overrides": [
    {
      "files": "*.md",
      "options": { "proseWrap": "always", "printWidth": 80 }
    },
    {
      "files": ["*.yaml", "*.yml"],
      "options": { "tabWidth": 2, "singleQuote": false }
    },
    {
      "files": "*.svelte",
      "options": { "parser": "svelte" }
    }
  ]
}
```

**`.prettierignore`:**
```
dist/
build/
.next/
coverage/
*.generated.*
*.min.js
package-lock.json
pnpm-lock.yaml
```

### Rule Categories

| Option | Default | Recommendation | Impact |
|---|---|---|---|
| `semi` | `true` | Keep `true` — avoids ASI pitfalls | Syntax |
| `singleQuote` | `false` | Team preference — pick one and enforce | Style |
| `printWidth` | `80` | `100` for modern monitors | Readability |
| `trailingComma` | `"all"` (v3) | Keep `"all"` — cleaner diffs | Diffs |
| `endOfLine` | `"lf"` | `"lf"` always — prevents CRLF noise on Windows | Cross-platform |

### Configuration Patterns

**`package.json` scripts:**
```json
{
  "scripts": {
    "format": "prettier --write .",
    "format:check": "prettier --check ."
  }
}
```

**ESLint integration — disable conflicting rules:**
```bash
npm install --save-dev eslint-config-prettier
```
```js
// eslint.config.js
import prettierConfig from "eslint-config-prettier";
export default [
  ...tseslint.configs.recommended,
  prettierConfig,  // must be last — disables all ESLint formatting rules
];
```

### CI Integration

```yaml
# .github/workflows/quality.yml
- name: Prettier check
  run: npx prettier --check .
```

**Pre-commit via lint-staged (recommended):**
```json
// package.json
{
  "lint-staged": {
    "*.{js,ts,jsx,tsx,css,scss,json,md,yaml,yml}": ["prettier --write"]
  }
}
```

**Pre-commit hook config (`.pre-commit-config.yaml`):**
```yaml
repos:
  - repo: https://github.com/pre-commit/mirrors-prettier
    rev: v3.1.0
    hooks:
      - id: prettier
        additional_dependencies:
          - prettier-plugin-tailwindcss
```

## Performance

- Prettier is fast for individual files but can be slow on large repos (>10k files) without scoping.
- Use `prettier --write src/` rather than `.` to avoid scanning `node_modules` and `dist` even with `.prettierignore`.
- `lint-staged` integration ensures only staged files are formatted — no full-repo scan on commit.
- Prettier has no caching built in — rely on lint-staged's file filtering for speed in local dev.
- For monorepos, run Prettier from each package root or use workspace glob patterns: `prettier --write "packages/*/src/**"`.

## Security

Prettier has no security surface — it reads and writes source files. Key considerations:

- Pin the Prettier version in `package.json` — style changes between versions can produce large noisy diffs on upgrade.
- The `prettier-plugin-*` ecosystem is community-maintained — review plugin permissions before installing; plugins have full read access to the files being formatted.
- Do not run `prettier --write` on generated files (protobuf output, GraphQL schema dumps) — it can silently corrupt formatting that downstream tools depend on.

## Testing

```bash
# Check all files without writing (CI mode)
npx prettier --check .

# Format all files in place (local fix)
npx prettier --write .

# Format a specific file
npx prettier --write src/index.ts

# Check a single file
npx prettier --check src/index.ts

# Show diff without writing
npx prettier --check . 2>&1

# Print Prettier's resolved config for a file (debug)
npx prettier --find-config-path src/index.ts
npx prettier --config-precedence prefer-file --check src/index.ts

# List files Prettier would process (verify .prettierignore)
npx prettier --list-different .
```

## Dos

- Run `prettier --check` in CI as a gate — format failures should block merges, not just warn.
- Use `eslint-config-prettier` to disable all ESLint formatting rules — running both without this causes conflicts and confusing errors.
- Commit `.prettierrc` and `.prettierignore` — formatting must be reproducible across all developer machines and CI.
- Add `prettier-plugin-tailwindcss` for Tailwind projects — it enforces canonical class ordering and prevents review churn from arbitrary class sequences.
- Set `"endOfLine": "lf"` explicitly — prevents Windows developers from committing CRLF line endings that pollute diffs.
- Use `lint-staged` so pre-commit hooks only format changed files — full-repo formatting on every commit is too slow.

## Don'ts

- Don't configure ESLint formatting rules (`indent`, `quotes`, `semi`) when using Prettier — the two conflict and ESLint formatting rules are deprecated in v9.
- Don't run `prettier --write` in CI — use `--check` only; auto-commits from CI bots cause git history noise and can mask real failures.
- Don't set `printWidth` above `120` — very long lines defeat the purpose of Prettier and reduce readability in split views.
- Don't add `package-lock.json` or `pnpm-lock.yaml` to Prettier's scope — formatting lock files is a no-op that wastes time and produces misleading diffs.
- Don't use Prettier for Svelte files without `prettier-plugin-svelte` — the default HTML parser mangles Svelte template syntax.
- Don't configure `trailingComma: "none"` — trailing commas on multiline structures produce smaller, cleaner diffs and are standard in modern JS/TS.
