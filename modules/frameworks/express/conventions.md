# Express/Node.js Framework Conventions
> Support tier: contract-verified
> Framework-specific conventions for Express/NestJS projects. Language idioms are in `modules/languages/typescript.md`. Generic testing patterns are in `modules/testing/vitest.md`.

## Architecture (Layered / Modular)

| Layer | Responsibility | Dependencies |
|-------|---------------|--------------|
| `routes` | Express routers or NestJS controllers, request parsing | middleware, controller/service |
| `controllers` | Request/response orchestration (thin) | service |
| `services` | Business logic | repository/model |
| `models` | Database models/schemas (depends on `persistence:` choice) | -- |
| `middleware` | Auth, validation, error handling, logging | -- |
| `config` | Environment variables, app configuration | -- |

**Dependency rule:** Routes/controllers depend on services, never on database models/repositories directly.

## Express Patterns

### Router Structure
- One router file per resource: `xxx.routes.ts`
- Mount routers in a central `routes/index.ts` or `app.ts`
- Use `Router()` from express, not app-level route definitions
- Group related routes: `router.get('/', list)`, `router.get('/:id', getById)`

### Middleware
- Error handling middleware: 4-parameter signature `(err, req, res, next)`
- Always call `next(err)` in catch blocks to propagate errors
- Auth middleware validates JWT/session before route handlers
- Validation middleware (Zod, Joi, class-validator) runs before controller logic
- Order matters: auth -> validation -> handler -> error handler

### Async Route Handlers
- Wrap async handlers to catch rejected promises: use `express-async-errors` or wrapper
- Never leave unhandled promise rejections in route handlers

## NestJS Patterns

### Module Structure
- Feature modules: `XxxModule` with `@Module({ controllers, providers, imports, exports })`
- Dependency injection via constructor parameters (auto-wired by type)
- Use `@Injectable()` for services, `@Controller()` for controllers
- Guard classes for auth: `@UseGuards(AuthGuard)`

### Decorators
- `@Body()`, `@Param()`, `@Query()` for request data extraction
- `@UseInterceptors()` for cross-cutting concerns
- `@UsePipes(ValidationPipe)` for DTO validation

## Naming Patterns

| Artifact | Pattern | Notes |
|----------|---------|-------|
| Router | `xxx.routes.ts` | Express router |
| Controller | `xxx.controller.ts` | NestJS or thin Express controller |
| Service | `xxx.service.ts` | Business logic |
| Middleware | `xxx.middleware.ts` | Express middleware function |
| Model | `xxx.model.ts` | Database model/entity (depends on `persistence:` choice) |
| DTO / Schema | `xxx.dto.ts` or `xxx.schema.ts` | Zod schemas or class-validator DTOs |

## Environment Configuration

- Use `dotenv` or NestJS `ConfigModule` -- never hardcode secrets
- Validate env vars at startup (Zod schema or `envalid`)
- Type-safe config object: `config.ts` exports typed configuration
- Never commit `.env` files -- use `.env.example` as template

## Error Handling

- Custom error classes extend a base `AppError` with `statusCode` property
- Express global error handler as final middleware

| Exception | HTTP Status |
|-----------|-------------|
| `NotFoundError` | 404 |
| `ValidationError` | 400 |
| `UnauthorizedError` | 401 |
| `ForbiddenError` | 403 |
| `ConflictError` | 409 |

## Security

- Input sanitization: never pass raw `req.body` or `req.params` to database queries
- SQL injection: use parameterized queries or ORM methods -- never string interpolation
- Rate limiting: `express-rate-limit` on auth endpoints
- Helmet middleware for security headers
- CORS: configure explicitly, never `cors({ origin: '*' })` in production
- JWT: validate signature and expiration
- Never use dynamic code execution functions -- security and performance risk

## Code Quality

- Functions: max ~40 lines, max 3 nesting levels
- ESM imports (`import`), not CommonJS `require()` in TypeScript
- Strict TypeScript: `strict: true`, no `any` unless explicitly justified
- No `console.log` in production -- use structured logger (winston, pino)

## Data Access

> Specific ORM/ODM patterns are in the `persistence/` binding files. This section covers generic data access conventions.

- Always use ORM/ODM methods or parameterized queries -- no raw string SQL
- Pagination: accept `page` and `limit`, return `{ data, total, page, limit }`
- See the persistence binding file for schema definition, migration, and query patterns specific to your `persistence:` choice

## Streaming / Backpressure

- Use Node.js streams for large file/data processing
- Implement backpressure: check `writable.write()` return value
- Use `pipeline()` from `stream/promises` instead of `.pipe()`

## Performance

- Use connection pooling for databases
- Profile with Node.js inspector before optimizing
- Use `cluster` module or process manager for multi-core utilization

## Testing

### Test Framework
- **Vitest** (preferred) or **Jest** as the test runner
- **supertest** for HTTP integration tests against Express/NestJS apps
- **MSW** (Mock Service Worker) for mocking external API calls at the network level

### Integration Test Patterns
- Use `supertest(app)` to test full request/response cycles through Express middleware and routes
- NestJS: use `Test.createTestingModule()` to build isolated modules with overridden providers
- Test middleware in isolation by constructing mock `req`/`res`/`next` objects
- Use **Testcontainers** for database integration tests; use persistence-layer test utilities for schema setup (depends on `persistence:` choice)

### What to Test
- Service-layer business logic with mocked repositories (primary focus)
- API endpoint contracts: status codes, response shapes, validation error responses
- Middleware behavior: auth rejection, validation failure, error transformation
- Error handling: verify global error handler produces structured error responses

### What NOT to Test
- Express calls middleware in the correct order (Express guarantees this)
- Express parses JSON bodies (built-in `express.json()` is tested by Express itself)
- NestJS DI container resolves providers correctly
- Zod/Joi schema parsing for basic types — test complex cross-field validations only

### Example Test Structure
```
src/
  routes/user.routes.ts
  services/user.service.ts
  services/user.service.test.ts      # co-located unit test
tests/
  integration/
    user.api.test.ts                  # supertest integration
  helpers/
    app.ts                            # test app factory
```

For general Vitest patterns, see `modules/testing/vitest.md`.

## Smart Test Rules

- No duplicate tests — grep existing tests before writing new ones
- Test business behavior, not implementation details
- Do NOT test framework guarantees (e.g., Express calls middleware in order, NestJS resolves providers)
- Do NOT test basic Zod/Joi type validation or Express body parsing
- Each test scenario covers a unique code path
- Fewer meaningful tests > high coverage of trivial code

## TDD Flow

scaffold -> write tests (RED) -> implement (GREEN) -> refactor

## Boy Scout Rule

Improve touched code if: safe, small (<10 lines), local (same file), convention-aligned.
NOT in scope: refactoring unrelated routes, changing middleware contracts, restructuring error handlers.

## Dos and Don'ts

### Do
- Use `async/await` over raw Promise chains for readability
- Use `zod` or `joi` for runtime input validation at API boundaries
- Use `AbortController` for cancellable operations
- Handle `unhandledRejection` and `uncaughtException` at process level
- Use environment variables for all configuration

### Don't
- Don't use `require()` in ESM projects -- use `import`
- Don't execute arbitrary dynamic code -- use safe alternatives (JSON.parse for data)
- Don't use `process.exit()` in library code -- only in CLI entry points
- Don't mix callbacks and promises -- convert with `util.promisify()`
- Don't use `setTimeout(fn, 0)` for "async" -- use `setImmediate()` or `queueMicrotask()`
