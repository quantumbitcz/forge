# TypeScript/Node.js Agent Conventions Reference

> Full details in project CLAUDE.md. This is a curated subset for agent consumption.

## Architecture (Layered / Modular)

| Layer | Responsibility | Dependencies |
|-------|---------------|--------------|
| `routes` | Express routers or NestJS controllers, request parsing | middleware, controller/service |
| `controllers` | Request/response orchestration (thin) | service |
| `services` | Business logic | repository/model |
| `models` | Database schemas (Prisma, TypeORM, Mongoose) | — |
| `middleware` | Auth, validation, error handling, logging | — |
| `config` | Environment variables, app configuration | — |

**Dependency rule:** Routes/controllers depend on services, never on database models/repositories directly. Services encapsulate data access logic.

## Express Patterns

### Router Structure
- One router file per resource: `xxx.routes.ts`
- Mount routers in a central `routes/index.ts` or `app.ts`
- Use `Router()` from express, not app-level route definitions
- Group related routes: `router.get('/', list)`, `router.get('/:id', getById)`, etc.

### Middleware
- Error handling middleware: 4-parameter signature `(err, req, res, next)`
- Always call `next(err)` in catch blocks to propagate errors to the error handler
- Authentication middleware validates JWT/session before route handlers
- Validation middleware (e.g., Zod, Joi, class-validator) runs before controller logic
- Order matters: auth -> validation -> handler -> error handler

### Async Route Handlers
- Wrap async handlers to catch rejected promises: use `express-async-errors` or a wrapper function
- Never leave unhandled promise rejections in route handlers
- Pattern: `router.get('/', asyncHandler(async (req, res) => { ... }))`

## NestJS Patterns

### Module Structure
- Feature modules: `XxxModule` with `@Module({ controllers, providers, imports, exports })`
- Dependency injection via constructor parameters (auto-wired by type)
- Use `@Injectable()` for services, `@Controller()` for controllers
- Guard classes for auth: `@UseGuards(AuthGuard)` on controllers or routes

### Decorators
- `@Body()`, `@Param()`, `@Query()` for request data extraction
- `@UseInterceptors()` for cross-cutting concerns (logging, transform)
- `@UsePipes(ValidationPipe)` for DTO validation with class-validator

## Naming Patterns

| Artifact | Pattern | Notes |
|----------|---------|-------|
| Router | `xxx.routes.ts` | Express router |
| Controller | `xxx.controller.ts` | NestJS or thin Express controller |
| Service | `xxx.service.ts` | Business logic |
| Middleware | `xxx.middleware.ts` | Express middleware function |
| Model | `xxx.model.ts` | Prisma schema, TypeORM entity, or Mongoose model |
| DTO / Schema | `xxx.dto.ts` or `xxx.schema.ts` | Zod schemas or class-validator DTOs |
| Config | `xxx.config.ts` | Environment and app configuration |
| Test | `xxx.test.ts` or `xxx.spec.ts` | Co-located or in `__tests__/` |

## Project Structure

```
src/
  routes/              # Express routers (or controllers/ for NestJS)
  controllers/         # Thin request/response handling (Express)
  services/            # Business logic
  models/              # Database models/entities
  middleware/           # Auth, error handling, validation
  dto/                 # Request/response schemas (Zod or class-validator)
  config/              # Environment config, constants
  utils/               # Shared utilities
  app.ts               # Express app setup or NestJS bootstrap
  server.ts            # HTTP server entry point
```

## Environment Configuration

- Use `dotenv` or NestJS `ConfigModule` — never hardcode secrets
- Validate env vars at startup (e.g., Zod schema or `envalid`)
- Type-safe config object: `config.ts` exports typed configuration
- Separate `.env.development`, `.env.test`, `.env.production`
- Never commit `.env` files — use `.env.example` as a template

## Error Handling

Express global error handler:

```typescript
app.use((err: Error, req: Request, res: Response, next: NextFunction) => {
  const status = err instanceof AppError ? err.statusCode : 500;
  res.status(status).json({ error: err.message });
});
```

| Exception | HTTP Status |
|-----------|-------------|
| `NotFoundError` | 404 |
| `ValidationError` | 400 |
| `UnauthorizedError` | 401 |
| `ForbiddenError` | 403 |
| `ConflictError` | 409 |

Custom error classes extend a base `AppError` with `statusCode` property.

## Security

- Input sanitization: never pass raw `req.body` or `req.params` to database queries
- SQL injection: use parameterized queries or ORM methods — never string interpolation
- Rate limiting: `express-rate-limit` on auth endpoints
- Helmet middleware for security headers
- CORS: configure explicitly, never use `cors({ origin: '*' })` in production
- JWT: validate signature and expiration; extract user from token, never trust request body

## Code Quality

- Functions: max ~40 lines, max 3 nesting levels
- JSDoc on exported service functions — explain WHY, not WHAT
- ESM imports (`import`), not CommonJS `require()` in TypeScript projects
- Strict TypeScript: `strict: true` in tsconfig, no `any` unless explicitly justified
- No `console.log` in production — use a structured logger (winston, pino)
- Prefer `const` over `let`; never use `var`

## Testing

- **Unit tests:** Vitest or Jest for service layer with mocked dependencies
- **Integration tests:** Supertest + test database (Testcontainers or in-memory SQLite)
- **E2E tests (NestJS):** `@nestjs/testing` with `Test.createTestingModule`
- **Naming:** `describe('XxxService', () => { it('should do X when Y', ...) })`
- **Mocking:** `vi.mock()` or `jest.mock()` for external dependencies
- **Rules:** Test behavior not implementation, one logical assertion per test

## Data Access

- **Prisma:** Schema in `prisma/schema.prisma`, migrations via `prisma migrate`
- **TypeORM:** Entities with decorators, migrations in `migrations/` directory
- **Mongoose:** Schemas with `Schema()`, models with `model()`
- Always use ORM/ODM methods or parameterized queries — no raw string SQL
- Pagination: accept `page` and `limit` query params, return `{ data, total, page, limit }`

## TDD Flow

scaffold -> write tests (RED) -> implement (GREEN) -> refactor

## Boy Scout Rule

Improve touched code if: safe, small (<10 lines), local (same file), convention-aligned.
NOT in scope: refactoring unrelated files, changing APIs, fixing pre-existing bugs.

## Dos and Don'ts

### Do
- Use `async/await` over raw Promise chains for readability
- Use `zod` or `joi` for runtime input validation at API boundaries
- Use `AbortController` for cancellable operations (HTTP requests, long tasks)
- Handle `unhandledRejection` and `uncaughtException` at process level
- Use environment variables for all configuration — never hardcode secrets
- Use `pino` or `winston` for structured JSON logging

### Don't
- Don't use `any` type — use `unknown` and narrow with type guards
- Don't use `require()` in ESM projects — use `import`
- Don't use `eval()`, `new Function()`, or `vm.runInNewContext()` — security and performance risk
- Don't use `process.exit()` in library code — only in CLI entry points
- Don't mix callbacks and promises — convert callbacks with `util.promisify()`
- Don't use `setTimeout(fn, 0)` for "async" — use `setImmediate()` or `queueMicrotask()`

## Async Anti-Patterns

- **Unhandled rejections:** Every `async` function must have error handling or propagate with `await`
- **Promise.all vs Promise.allSettled:** Use `Promise.all` when all must succeed, `Promise.allSettled` when partial results are acceptable
- **Concurrent limits:** Use `p-limit` or manual semaphore for rate-limited APIs — don't fire 1000 concurrent requests

## Streaming / Backpressure

- Use Node.js streams for large file/data processing — don't load entire files into memory
- Implement backpressure: check `writable.write()` return value, pause on `false`, resume on `drain`
- Use `pipeline()` (from `stream/promises`) instead of `.pipe()` — handles errors and cleanup
