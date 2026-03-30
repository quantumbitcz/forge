# Angular + biome

> Extends `modules/code-quality/biome.md` with Angular-specific integration.
> Generic biome conventions (installation, rule categories, CI integration) are NOT repeated here.

## Integration Setup

Biome covers Angular's TypeScript files. Angular's `.html` templates are NOT supported by Biome — use `@angular-eslint/eslint-plugin-template` for template linting alongside Biome:

```json
{
  "$schema": "https://biomejs.org/schemas/1.9.4/schema.json",
  "files": {
    "include": ["src/**/*.ts"],
    "ignore": ["src/**/*.spec.ts", "**/*.d.ts"]
  },
  "linter": {
    "rules": {
      "correctness": { "recommended": true },
      "suspicious": { "recommended": true },
      "style": { "noNonNullAssertion": "warn" }
    }
  },
  "formatter": {
    "indentStyle": "space",
    "indentWidth": 2,
    "lineWidth": 140
  }
}
```

## Framework-Specific Patterns

### Biome + @angular-eslint split responsibility

Use Biome for TypeScript logic rules; use `@angular-eslint` for Angular decorator and template rules. They do not conflict:

| Tool | Scope |
|---|---|
| Biome | TS logic, imports, style, formatting |
| @angular-eslint | Decorators, templates, Angular lifecycle |

### Angular decorator patterns

Biome's `noNonNullAssertion` (`style/noNonNullAssertion`) will flag `@ViewChild()!` — these are expected Angular patterns. Set to `"warn"` rather than `"error"` and review individually:

```ts
@ViewChild(MatSort) sort!: MatSort;  // biome: noNonNullAssertion warn
```

### Class field initialization

Angular uses class field declarations without initialization (injected via constructor DI). Biome's `correctness/noUndeclaredDependencies` does not affect DI-injected fields.

## Additional Dos

- Apply Biome to `src/**/*.ts` only — Angular `.html` templates use a custom Angular template syntax unsupported by Biome.
- Use Biome's import sorting alongside `@angular-eslint`'s import rules to avoid conflicts — configure `organizeImports: { enabled: true }`.

## Additional Don'ts

- Don't apply Biome to `.html` files — it will fail on Angular template syntax (`*ngIf`, `@if`, `(click)`, `[ngClass]`).
- Don't use Biome as a full `@angular-eslint` replacement — Angular-specific decorator rules are not in Biome's rule set.
