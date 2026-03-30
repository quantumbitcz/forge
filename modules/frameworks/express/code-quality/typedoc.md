# Express + typedoc

> Extends `modules/code-quality/typedoc.md` with Express-specific integration.
> Generic typedoc conventions (installation, typedoc.json, CI) are NOT repeated here.

## Integration Setup

```bash
npm install --save-dev typedoc typedoc-plugin-markdown
```

**`typedoc.json` for Express:**

```json
{
  "$schema": "https://typedoc.org/schema.json",
  "entryPoints": ["src/routes", "src/services", "src/middleware", "src/types"],
  "entryPointStrategy": "expand",
  "out": "docs/api",
  "tsconfig": "./tsconfig.json",
  "name": "Express API",
  "readme": "README.md",
  "includeVersion": true,
  "excludePrivate": true,
  "excludeInternal": true,
  "exclude": [
    "src/server.ts",
    "src/app.ts",
    "src/**/*.test.ts",
    "src/**/*.spec.ts",
    "src/config/**"
  ],
  "categorizeByGroup": true,
  "categoryOrder": ["Routes", "Services", "Middleware", "Types", "*"]
}
```

## Framework-Specific Patterns

### Documenting Route Handlers

Document the route contract — parameters, response shapes, and error codes — not the Express plumbing:

```ts
/**
 * Retrieves a user by ID.
 *
 * @route GET /users/:id
 * @param req.params.id - UUID of the user to retrieve
 * @returns 200 with {@link UserResponse} on success
 * @returns 404 if user is not found
 * @returns 401 if authentication token is missing or invalid
 * @category Routes
 */
export const getUser: RequestHandler = async (req, res, next) => { ... };
```

### Documenting Middleware

Error middleware and validation middleware are part of the public API contract for consumers of this module:

```ts
/**
 * Global error handler middleware.
 * Must be registered last in the Express middleware chain.
 *
 * @remarks
 * Normalizes all thrown errors to `{ error: string, code?: string }` responses.
 * Errors without a `status` field default to HTTP 500.
 * @category Middleware
 */
export const errorHandler: ErrorRequestHandler = (err, _req, res, _next) => { ... };
```

### Entry Points Selection

Exclude `app.ts` and `server.ts` from documentation — they are wiring, not API surface. Include `types/` for shared interfaces used in route contracts.

## Additional Dos

- Use `@route` JSDoc tag to document HTTP method and path alongside TypeScript handler types — TypeDoc renders this as part of the function summary.
- Include `src/types/` or `src/interfaces/` in entry points — these define the API contract consumed by frontend or downstream services.
- Add `@category` tags to group routes, services, and middleware in the generated docs navigation.

## Additional Don'ts

- Don't generate TypeDoc for `src/config/` — configuration loading code has no public API surface.
- Don't document Express app wiring (`app.use(...)` calls) — document the middleware function itself, not where it is mounted.
