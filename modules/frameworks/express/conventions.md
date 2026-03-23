# Express/Node.js Framework Conventions

> Framework-specific conventions for Express/NestJS projects. Language idioms are in `modules/languages/typescript.md`. Generic testing patterns are in `modules/testing/vitest.md`.

## Architecture (Layered / Modular)

| Layer | Responsibility | Dependencies |
|-------|---------------|--------------|
| `routes` | Express routers or NestJS controllers, request parsing | middleware, controller/service |
| `controllers` | Request/response orchestration (thin) | service |
| `services` | Business logic | repository/model |
| `models` | Database schemas (Prisma, TypeORM, Mongoose) | -- |
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
| Model | `xxx.model.ts` | Prisma schema, TypeORM entity |
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

- **Prisma:** Schema in `prisma/schema.prisma`, migrations via `prisma migrate`
- **TypeORM:** Entities with decorators, migrations in `migrations/`
- Always use ORM/ODM methods or parameterized queries -- no raw string SQL
- Pagination: accept `page` and `limit`, return `{ data, total, page, limit }`

## Streaming / Backpressure

- Use Node.js streams for large file/data processing
- Implement backpressure: check `writable.write()` return value
- Use `pipeline()` from `stream/promises` instead of `.pipe()`

## Performance

- Use connection pooling for databases
- Profile with Node.js inspector before optimizing
- Use `cluster` module or process manager for multi-core utilization

## TDD Flow

scaffold -> write tests (RED) -> implement (GREEN) -> refactor

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
