# Angular + prettier

> Extends `modules/code-quality/prettier.md` with Angular-specific integration.
> Generic prettier conventions (installation, `.prettierrc`, CI integration) are NOT repeated here.

## Integration Setup

```bash
npm install --save-dev prettier prettier-plugin-angular
```

**`.prettierrc` for Angular:**
```json
{
  "semi": true,
  "singleQuote": true,
  "printWidth": 120,
  "tabWidth": 2,
  "trailingComma": "all",
  "bracketSpacing": true,
  "plugins": ["prettier-plugin-angular"],
  "overrides": [
    {
      "files": "*.html",
      "options": { "parser": "angular" }
    }
  ]
}
```

## Framework-Specific Patterns

### Angular HTML template formatting

`prettier-plugin-angular` formats Angular-specific template syntax: `*ngIf`, `@if`/`@for` control flow, `[(ngModel)]`, `(click)`, `[routerLink]`:

```html
<!-- Before Prettier -->
<button [disabled]="isLoading" (click)="handleSubmit()">{{isLoading ? 'Saving...' : 'Submit'}}</button>

<!-- After Prettier -->
<button [disabled]="isLoading" (click)="handleSubmit()">
  {{ isLoading ? "Saving..." : "Submit" }}
</button>
```

### Print width for Angular templates

Angular templates with structural directives get verbose. Use `printWidth: 120` for Angular projects — the default 80 causes excessive line wrapping in templates with multiple bindings.

### Ignoring generated files

Angular CLI generates boilerplate that should not be reformatted:

```
# .prettierignore
dist/
.angular/
src/app/**/*.spec.ts    # optional — include if specs are messy
```

## Additional Dos

- Use `"parser": "angular"` in overrides for `.html` files — Prettier's default HTML parser does not handle Angular syntax.
- Include `.html` in pre-commit hooks: `prettier --write "src/**/*.{ts,html,scss,css}"`.

## Additional Don'ts

- Don't use `prettier-plugin-tailwindcss` in Angular projects using Angular Material — they use incompatible class systems.
- Don't run Prettier on `.angular/` cache directory — it contains generated JSON/JS that changes on every build.
