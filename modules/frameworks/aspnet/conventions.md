# ASP.NET Core Framework Conventions
> Support tier: contract-verified
> Language-agnostic ASP.NET Core patterns. Language-specific idioms (nullable reference types, records, etc.)
> are in `modules/languages/csharp.md`. Framework-language integration is in `variants/csharp.md`.

## Architecture (Clean Architecture)

| Layer | Responsibility | Dependencies |
|-------|---------------|--------------|
| `Controllers/` | HTTP endpoints, request validation, response mapping | Application services |
| `Application/` | Business logic, use cases, service interfaces | Domain |
| `Domain/` | Entities, value objects, domain exceptions | None |
| `Infrastructure/` | Database context, repositories, external integrations | Application, Domain |
| `Program.cs` | Entry point, DI composition, middleware pipeline | All |

**Dependency rule:** Domain never imports from Application or Infrastructure. Application depends on Domain only. Controllers depend on Application services, never on Infrastructure directly. Domain entities never leak into API responses — always map to DTOs/response models.

## Naming

| Artifact | Pattern | Annotation / Attribute |
|----------|---------|----------------------|
| Controller | `XxxController` | `[ApiController]` + `[Route]` |
| Service interface | `IXxxService` | — |
| Service impl | `XxxService` | Registered in DI container |
| Repository interface | `IXxxRepository` | — |
| Repository impl | `XxxRepository` | Registered as `Scoped` |
| Entity | `Xxx` (no suffix) | Persistence conventions or `[Table]` |
| Request DTO | `CreateXxxRequest` / `UpdateXxxRequest` | Validation attributes |
| Response DTO | `XxxResponse` | `record` preferred |
| Mapper | `XxxMappingProfile` (AutoMapper) or `XxxMapper` (static) | — |
| Config | `XxxOptions` | `IOptions<T>` pattern |
| Exception | `XxxException` | extends `AppException` or domain base |

## Code Quality

- Methods: max ~30 lines, prefer ~20 for controllers and service methods
- Max 3 nesting levels per method
- File size: max ~400 lines, prefer ~200 per component
- All public interfaces and services must have XML doc comments explaining WHY, not WHAT
- No `Console.Write*` / `Debug.Write*` in production code — use `ILogger<T>`
- No entity objects in controller responses — always map to response DTOs
- Max line length: 120 characters

## Error Handling

Global exception handling via middleware (`IExceptionHandler` in .NET 8+, or `UseExceptionHandler`). Return consistent `ProblemDetails` responses (RFC 7807 — built into ASP.NET Core).

| Domain Exception | HTTP Status |
|-----------------|-------------|
| `NotFoundException` (custom) | 404 |
| `ValidationException` / `ArgumentException` | 400 |
| `ConflictException` (custom) | 409 |
| `ForbiddenException` / `UnauthorizedException` | 403 / 401 |
| Unhandled | 500 |

Map domain exceptions in the global exception handler middleware. Services throw domain-specific exceptions; controllers never catch exceptions directly.

## Security

- Configure auth in `Program.cs` via `AddAuthentication()` / `AddAuthorization()` — never roll custom auth middleware
- JWT Bearer: `AddJwtBearer()` with explicit validation parameters; extract claims via `HttpContext.User`
- Policy-based authorization: `RequireAuthorizationPolicy` or `[Authorize(Policy = "...")]`
- `[Authorize]` on all controller classes; `[AllowAnonymous]` on public endpoints explicitly
- HTTPS: enforce via `UseHttpsRedirection()` and `UseHsts()` in production
- CORS: configure restrictively with explicit origins in `AddCors()` — never use `AllowAnyOrigin` with `AllowCredentials`
- Anti-forgery: enabled automatically for form POSTs; use `[ValidateAntiForgeryToken]` on form actions
- Input validation: `[Required]`, `[MaxLength]`, `[RegularExpression]` on request models; `ModelState.IsValid` automatic with `[ApiController]`
- Never trust user-supplied IDs for authorization — always verify resource ownership server-side
- Secrets: User Secrets (dev) / Azure Key Vault or environment variables (prod) — never appsettings.json

## Performance

### Connection Pooling
- Configure connection pooling via the persistence layer; tune `MaxPoolSize` / pool sizes in the connection string
- For high-throughput apps: tune min and max pool sizes based on workload
- Monitor with health checks and persistence-layer metrics

### N+1 Prevention
- Eagerly load related data needed in a single query (depends on `persistence:` choice — see persistence binding file for specifics)
- Use projections to avoid loading full entities when only a subset of columns is needed
- Avoid lazy-loading proxies in production APIs — they silently trigger N+1 queries
- Use read-only/no-tracking modes for queries that don't need change tracking (depends on `persistence:` choice)
- Rule: if a loop calls the database, you likely have N+1 — extract to a single batch query

### Caching
- Use `IMemoryCache` for in-process caching; `IDistributedCache` (Redis) for multi-instance apps
- Use output caching (`AddOutputCache`) for cacheable endpoints in .NET 7+
- Use response caching (`UseResponseCaching`) with explicit cache headers
- Always set expiry — never cache indefinitely

### Async
- All controller actions and service methods performing I/O must be `async Task<T>`
- Never use `.Result` or `.Wait()` — can deadlock with ASP.NET synchronization context
- Use `CancellationToken` (from action parameters) and pass it through all I/O calls

## API Design

- Use `[ApiController]` attribute — enables automatic model validation, binding source inference
- Return `ActionResult<T>` or `IActionResult` with specific status codes (`Ok()`, `Created()`, `NoContent()`, `NotFound()`)
- Pagination: accept `page` / `pageSize` query parameters; return paginated wrapper with total count
- Versioning: via URL path (`/api/v1/...`) or `Asp.Versioning.Mvc` package — not query parameter
- Content negotiation: return JSON by default; configure with `AddControllers().AddJsonOptions()`
- Validate all external input at the controller layer — `[ApiController]` handles `ModelState` automatically
- Use `CreatedAtAction()` for 201 responses — includes `Location` header pointing to the created resource
- Minimal APIs for simple endpoints: `app.MapGet("/ping", () => "pong")` — no controller overhead

## Database

> Specific ORM/data-access patterns (EF Core, Dapper, etc.) are in the `persistence/` binding files. This section covers generic database conventions.

### Migrations
- Use code-first or SQL-based migrations depending on `persistence:` choice
- Never modify an applied migration — create a new one
- Migration naming: descriptive PascalCase — `AddUserEmailIndex`, `CreateOrdersTable`
- Run migrations at app startup only in development; use dedicated migration tooling in production

### Data Context
- One data context per bounded context — never share across application modules
- Register as `Scoped` — never Singleton or Transient
- Use context pooling for high-throughput scenarios (if supported by the persistence layer)
- Never use the data context directly in controllers — go through repositories or services

### Data Access
- Parameterized queries only — never string-concatenate SQL fragments
- Use read-only/no-tracking modes for queries that don't modify data (depends on `persistence:` choice)
- Use explicit or eager loading for associations — avoid lazy loading in production APIs
- Audit fields (`CreatedAt`/`UpdatedAt`): implement via persistence-layer interceptors or overrides
- Return composable query types from repository interfaces only when callers need further composition

### Transactions
- Most persistence layers wrap each save operation in a transaction automatically
- Multi-step operations needing atomicity: use explicit transactions via the persistence layer's transaction API
- Keep transaction scope minimal — wrap in a service method
- Never swallow exceptions in a transaction scope — this prevents rollback

## Dependency Injection

- **Constructor injection only** — never property injection or service locator (`IServiceProvider.GetService`)
- Lifetimes: `Scoped` for services with per-request state (e.g., repositories, data context wrappers); `Transient` for stateless; `Singleton` for thread-safe, truly shared instances
- Register dependencies in `Program.cs` or via extension methods (`services.AddApplicationServices()`)
- Use `IOptions<T>` for configuration objects — inject `IOptions<MyOptions>` not raw `IConfiguration`
- Avoid `IServiceProvider` in application code — it is the service-locator anti-pattern

## Testing

### Test Framework
- **xUnit** (preferred) or **NUnit** for unit and integration tests
- **FluentAssertions** for readable, expressive assertions
- **WebApplicationFactory<Program>** for in-process integration tests against the full ASP.NET pipeline
- **Testcontainers** (`Testcontainers.MsSql` / `Testcontainers.PostgreSql`) for database integration tests

### Integration Test Patterns
- Use `WebApplicationFactory<Program>` to spin up the app in-process — no TCP server needed
- Override services via `WithWebHostBuilder(b => b.ConfigureServices(...))` for test isolation
- Use `HttpClient` from the factory to test full request/response cycles through middleware and controllers
- Test persistence repositories against a real database via Testcontainers — avoid mocking the data context
- Use `IOptions<T>` overrides for test-specific configuration

### What to Test
- Service-layer business logic with mocked repository interfaces (primary focus)
- Controller endpoint contracts: status codes, ProblemDetails responses, validation errors
- Authorization policies: verify 401/403 responses for unauthorized/forbidden requests
- Repository queries: correct query translation, include paths, pagination (depends on `persistence:` choice)
- Global exception handler: verify ProblemDetails shape for domain exceptions

### What NOT to Test
- ASP.NET returns 404 for unmatched routes or 405 for wrong HTTP methods — the framework does this
- Model binding deserializes JSON to DTOs — `[ApiController]` handles this automatically
- Persistence-layer conventions (table naming, key detection) — tested by the library vendor
- `ILogger<T>` formats log messages correctly
- FluentValidation / DataAnnotation attribute validation for standard rules (Required, MaxLength)

### Example Test Structure
```
Tests/
  UnitTests/
    Services/
      UserServiceTests.cs          # unit tests with mocked repos
  IntegrationTests/
    Controllers/
      UserControllerTests.cs       # WebApplicationFactory tests
    Repositories/
      UserRepositoryTests.cs       # Testcontainers DB tests
    Helpers/
      CustomWebApplicationFactory.cs
```

For general xUnit/NUnit patterns, see `modules/testing/xunit-nunit.md`.
For Testcontainers usage, see `modules/testing/testcontainers.md`.

## TDD Flow

```
scaffold -> write tests (RED) -> implement (GREEN) -> refactor
```

1. **Scaffold**: create interfaces and empty implementations
2. **RED**: write the test expressing expected behavior — must fail
3. **GREEN**: implement the minimum code to pass
4. **Refactor**: clean up, extract, optimize — tests must still pass

## Smart Test Rules

- Test behavior, not implementation — tests should survive internal refactoring
- No duplicate scenarios — each test covers a distinct case
- Do not test framework internals (ASP.NET model binding, persistence-layer conventions)
- One logical assertion concept per test; use FluentAssertions for readability
- Prefer integration tests for controller layer via `WebApplicationFactory<Program>`
- Use in-memory databases or Testcontainers for repository tests — avoid mocking the data context

## Logging and Monitoring

- `ILogger<T>` for all logging — never `Console.Write*` or `Trace.Write*`
- Structured logging: use `{PlaceholderNames}` in message templates — not string interpolation
- Log levels: Critical (app crash), Error (action needed), Warning (degraded), Information (business events), Debug (dev only)
- Never log sensitive data: passwords, tokens, PII, request bodies
- Health checks: `AddHealthChecks()` with DB, cache, and external dependency checks; expose `/health`
- Use `app.UseRequestLogging()` (Serilog) or `LoggingMiddleware` for request/response logging

## Boy Scout Rule

Improve touched code if: safe, small (<10 lines), local (same file), convention-aligned.
NOT in scope: refactoring unrelated files, changing APIs, fixing pre-existing bugs.

## Dos and Don'ts

### Do
- Use constructor injection exclusively — never service locator or property injection
- Return specific response DTOs from controllers, never persistence entities
- Use `async Task<T>` for all I/O-bound methods — propagate `CancellationToken`
- Use `[ApiController]` on all API controllers — enables automatic validation and binding
- Validate all input at the controller layer with data annotations or FluentValidation
- Use `IOptions<T>` for configuration — not raw `IConfiguration` injection
- Register the persistence data context with Scoped lifetime (depends on `persistence:` choice — see persistence binding file)
- Configure connection pooling explicitly for production workloads
- Use `ProblemDetails` for all error responses — never return raw strings or custom shapes
- Use read-only/no-tracking modes for all read-only queries (depends on `persistence:` choice)

### Don't
- Don't use `.Result` or `.Wait()` on async tasks — risks deadlock in ASP.NET contexts
- Don't put business logic in controllers — controllers validate, delegate, and map only
- Don't expose persistence entity IDs as sequential integers — use UUIDs
- Don't use lazy-loading proxies in production — silently causes N+1 queries
- Don't use `Console.Write*` — use `ILogger<T>`
- Don't use `IServiceProvider.GetService()` in application code — use constructor injection
- Don't use Singleton lifetime for services with scoped persistence dependencies (e.g., data context) — will cause concurrency issues
- Don't catch `Exception` broadly in controllers — let the global exception handler middleware manage it
- Don't store secrets in `appsettings.json` — use User Secrets or environment variables
- Don't use `AllowAnyOrigin()` combined with `AllowCredentials()` in CORS — it is rejected by browsers and is a security risk
