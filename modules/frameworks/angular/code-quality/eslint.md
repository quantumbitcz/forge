# Angular + eslint

> Extends `modules/code-quality/eslint.md` with Angular-specific integration.
> Generic eslint conventions (flat config, TypeScript setup, CI integration) are NOT repeated here.

## Integration Setup

```bash
npm install --save-dev @angular-eslint/eslint-plugin @angular-eslint/eslint-plugin-template
npm install --save-dev @angular-eslint/template-parser typescript-eslint
```

**`eslint.config.js` for Angular:**
```js
import tseslint from "typescript-eslint";
import angular from "@angular-eslint/eslint-plugin";
import angularTemplate from "@angular-eslint/eslint-plugin-template";
import angularTemplateParser from "@angular-eslint/template-parser";

export default tseslint.config(
  ...tseslint.configs.strictTypeChecked,
  {
    files: ["**/*.ts"],
    plugins: { "@angular-eslint": angular },
    rules: {
      ...angular.configs.recommended.rules,
      "@angular-eslint/component-selector": ["error", { type: "element", prefix: "app", style: "kebab-case" }],
      "@angular-eslint/directive-selector": ["error", { type: "attribute", prefix: "app", style: "camelCase" }],
      "@angular-eslint/prefer-standalone": "error",
      "@angular-eslint/prefer-on-push-component-change-detection": "error",
      "@angular-eslint/no-lifecycle-call": "error",
      "@angular-eslint/use-injectable-provided-in": "error",
    },
  },
  {
    files: ["**/*.html"],
    plugins: { "@angular-eslint/template": angularTemplate },
    languageOptions: { parser: angularTemplateParser },
    rules: {
      ...angularTemplate.configs.recommended.rules,
      "@angular-eslint/template/no-negated-async": "error",
      "@angular-eslint/template/use-track-by-function": "error",
    },
  }
);
```

## Framework-Specific Patterns

### Standalone components enforcement

`@angular-eslint/prefer-standalone` enforces Angular 17+ standalone component pattern, eliminating NgModule declarations:

```ts
// BAD — @angular-eslint/prefer-standalone violation
@Component({ selector: "app-hero", templateUrl: "..." })
export class HeroComponent {}   // no standalone: true

// GOOD
@Component({ standalone: true, selector: "app-hero", templateUrl: "..." })
export class HeroComponent {}
```

### OnPush change detection

`@angular-eslint/prefer-on-push-component-change-detection` enforces performance-safe rendering:

```ts
@Component({
  standalone: true,
  changeDetection: ChangeDetectionStrategy.OnPush,  // required
})
export class MyComponent {}
```

### Signal-based inputs

Angular 17.1+ signal inputs work with the template linter — enable `@angular-eslint/template/no-negated-async` to avoid signal misuse in templates:

```html
<!-- BAD — negated async -->
<div *ngIf="!data$ | async">Loading</div>

<!-- GOOD -->
@if (data$ | async; as data) { ... } @else { <app-loading /> }
```

## Additional Dos

- Enable `@angular-eslint/template/use-track-by-function` for all `*ngFor` / `@for` loops — prevents full list re-render.
- Use `@angular-eslint/use-injectable-provided-in` to ensure all services declare `providedIn` for tree-shaking.

## Additional Don'ts

- Don't skip the HTML template linter — template bugs (missing track functions, negated async) are as harmful as TS bugs.
- Don't disable `prefer-standalone` for legacy NgModule code — migrate incrementally; mixed codebases incur higher complexity.
