# Angular + typedoc

> Extends `modules/code-quality/typedoc.md` with Angular-specific integration.
> Generic typedoc conventions (installation, `typedoc.json`, entryPoints) are NOT repeated here.

## Integration Setup

TypeDoc is most valuable for Angular **libraries** (publishable via ng-packagr). For Angular **applications**, prefer Compodoc which understands Angular metadata.

```bash
# For Angular libraries
npm install --save-dev typedoc

# For Angular applications — consider Compodoc instead
npm install --save-dev @compodoc/compodoc
```

**`typedoc.json` for an Angular library:**
```json
{
  "$schema": "https://typedoc.org/schema.json",
  "entryPoints": ["projects/my-lib/src/public-api.ts"],
  "entryPointStrategy": "expand",
  "out": "docs/api",
  "tsconfig": "projects/my-lib/tsconfig.lib.json",
  "excludePrivate": true,
  "excludeInternal": true,
  "name": "My Angular Library"
}
```

## Framework-Specific Patterns

### Library public API documentation

Angular libraries export their public surface via `public-api.ts`. Point TypeDoc at this file to document only the public API:

```ts
// projects/my-lib/src/public-api.ts
export * from "./lib/components/my-component.component";
export * from "./lib/services/my-service.service";
export * from "./lib/models/my-model";
```

### Service documentation

Document Angular services with their injection scope and key responsibilities:

```ts
/**
 * Manages user authentication state.
 * Provided in root — single instance across the application.
 * @injectable providedIn: 'root'
 */
@Injectable({ providedIn: "root" })
export class AuthService { ... }
```

### Application documentation with Compodoc

For Angular applications, Compodoc provides richer documentation (component tree, module graph, routing):

```bash
npx compodoc -p tsconfig.json -d docs --theme material --hideGenerator
```

## Additional Dos

- Use TypeDoc for Angular library packages (npm-published); use Compodoc for monorepo application documentation.
- Document `@Input()` and `@Output()` properties in the class JSDoc — TypeDoc extracts these from decorators.

## Additional Don'ts

- Don't run TypeDoc on Angular application code — component metadata (templates, styles) is not captured; Compodoc is more appropriate.
- Don't document `*.spec.ts` or `*.stories.ts` files — exclude test artifacts from public API docs.
