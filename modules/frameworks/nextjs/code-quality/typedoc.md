# Next.js + typedoc

> Extends `modules/code-quality/typedoc.md` with Next.js-specific integration.
> Generic typedoc conventions (installation, `typedoc.json`, entryPoints) are NOT repeated here.

## Integration Setup

TypeDoc is most useful for Next.js **shared libraries** (internal packages in monorepos) and custom hooks. For application pages and components, TypeDoc is less valuable — inline Storybook or `next-docs` is more appropriate.

```bash
npm install --save-dev typedoc typedoc-plugin-markdown
```

**`typedoc.json` for a Next.js shared lib:**
```json
{
  "$schema": "https://typedoc.org/schema.json",
  "entryPoints": ["lib/index.ts"],
  "entryPointStrategy": "expand",
  "out": "docs/api",
  "tsconfig": "./tsconfig.json",
  "excludePrivate": true,
  "excludeInternal": true,
  "name": "My Next.js Library"
}
```

## Framework-Specific Patterns

### Documenting custom hooks

Next.js applications commonly extract custom hooks for data fetching and routing. Document the return type explicitly:

```ts
/**
 * Fetches paginated product list with SWR.
 * @param category - Product category slug
 * @returns SWR response with typed product data and pagination metadata
 */
export function useProducts(category: string): ProductsResponse { ... }
```

### Server Action documentation

Next.js Server Actions are async functions with the `"use server"` directive. Document their input/output contracts — these are the API surface between client components and server logic:

```ts
/**
 * Creates a new order from the current cart.
 * Server Action — runs exclusively in Node.js, not the browser.
 * @param formData - Form submission containing product IDs and quantities
 * @returns Created order ID or validation error
 */
export async function createOrder(formData: FormData): Promise<OrderResult> { ... }
```

### Monorepo package documentation

In Next.js Turborepo/monorepo setups, use TypeDoc per internal package rather than per application:

```
packages/ui/        → TypeDoc entryPoint: packages/ui/src/index.ts
packages/auth/      → TypeDoc entryPoint: packages/auth/src/index.ts
apps/web/           → No TypeDoc (application, not library)
```

## Additional Dos

- Document Server Actions' input validation rules in JSDoc `@throws` — callers need to know what errors to handle.
- Use TypeDoc for internal `packages/` in monorepos; skip TypeDoc for `apps/` applications.

## Additional Don'ts

- Don't document Next.js page components (`app/**/page.tsx`) with TypeDoc — pages have no reusable API surface.
- Don't include route handlers (`app/api/**/route.ts`) in TypeDoc entryPoints — these are HTTP endpoints, not importable modules.
