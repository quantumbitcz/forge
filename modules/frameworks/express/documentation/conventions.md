# Express Documentation Conventions

> Extends `modules/documentation/conventions.md` with Express-specific patterns.

## Code Documentation

- Use TSDoc (`/** */`) for all route handlers, middleware functions, and service class methods.
- Route handlers: document the HTTP method, path, request body shape, response shape, and error codes.
- Middleware: document what it reads from `req`, what it attaches to `req`, and when it calls `next(err)`.
- Service classes: document public methods with `@param`, `@returns`, and `@throws`.
- Zod / Joi schemas (if used): keep validation schemas co-located with their TSDoc. The schema IS the documentation for request shapes.

```typescript
/**
 * Creates a new user account.
 *
 * `POST /users`
 *
 * @param req - Body: `{ email: string; name: string }`
 * @param res - `201` with `UserResponse` on success; `409` if email taken
 */
export async function createUser(req: Request, res: Response): Promise<void> { ... }
```

## Architecture Documentation

- Document the middleware stack in `app.ts` / `server.ts` — list registered middleware in order with a one-line purpose for each.
- Document the router module structure: which files export which routers and how they are mounted.
- OpenAPI: maintain an `openapi.yaml` or use `swagger-jsdoc` annotations. Document the spec file location in `README.md`.
- ORM / persistence (Prisma / TypeORM): document the schema file location and how to run migrations.

## Diagram Guidance

- **Middleware pipeline:** Sequence diagram showing request flow through key middleware layers.
- **Module dependencies:** Class diagram for service layer dependencies if using DI container.

## Dos

- Document the middleware stack order — it is not obvious from reading route files
- Use `openapi.yaml` or `swagger-jsdoc` — keep API contracts machine-readable
- TSDoc `@throws` for service methods that can reject with typed errors

## Don'ts

- Don't document Express built-in request/response properties — document your custom extensions only
- Don't maintain a separate "API reference" that duplicates OpenAPI — the spec is the reference
