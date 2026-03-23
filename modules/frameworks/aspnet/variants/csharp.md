# ASP.NET Core + C# Variant

> Extends `modules/frameworks/aspnet/conventions.md` with C#-specific ASP.NET patterns.
> General C# idioms are in `modules/languages/csharp.md` — not duplicated here.

## Nullable Reference Types in Controllers

- Enable `<Nullable>enable</Nullable>` project-wide — makes null intent explicit in action parameters and return types
- Action parameters from `[FromBody]` are non-nullable by default; use `T?` for optional body fields
- Use `ArgumentNullException.ThrowIfNull(param)` at service boundaries for defensive validation
- Never suppress `null!` in controller/service code without an explanatory comment

## Record DTOs

- Use `record` for all request and response DTOs — compiler-generated `Equals`, `GetHashCode`, immutability
- `record class` for reference-type DTOs (API requests/responses)
- `record struct` for small value objects (e.g., pagination parameters, coordinate pairs)
- Combine `record` with `required` properties (C# 11+) for mandatory fields:
  ```csharp
  public record CreateUserRequest
  {
      public required string Name { get; init; }
      public required string Email { get; init; }
  }
  ```
- Use primary constructors (C# 12+) for concise service definitions:
  ```csharp
  public class UserService(IUserRepository repo, ILogger<UserService> logger) : IUserService { ... }
  ```

## Global Usings

- Declare framework-wide global usings in a `GlobalUsings.cs` file at project root:
  ```csharp
  global using Microsoft.AspNetCore.Mvc;
  global using Microsoft.EntityFrameworkCore;
  global using Application.Interfaces;
  ```
- Use global usings for frequently imported namespaces — avoids repetition, not a substitute for understanding dependencies

## Pattern Matching in Services

- Use `switch` expressions for mapping domain enums to HTTP status codes or string values
- Use property patterns for conditional service logic: `if (order is { Status: OrderStatus.Pending })`
- Use `is null` / `is not null` instead of `== null` — more readable and null-state analysis friendly

## Async Conventions

- All controller actions performing I/O: `async Task<ActionResult<T>>`
- Accept `CancellationToken cancellationToken` as the last parameter; pass it to all `async` calls
- Never use `.Result` / `.Wait()` — deadlocks with ASP.NET's synchronization context
- Use `IAsyncEnumerable<T>` for streaming responses (large collections, server-sent events)

## Configuration with Options Pattern

- Bind configuration sections to strongly-typed classes:
  ```csharp
  builder.Services.Configure<JwtOptions>(builder.Configuration.GetSection("Jwt"));
  ```
- Inject `IOptions<T>` (singleton), `IOptionsSnapshot<T>` (scoped, reloads per request), or `IOptionsMonitor<T>` (reloads on change)
- Validate options at startup: `services.AddOptions<MyOptions>().ValidateDataAnnotations().ValidateOnStart()`

## Minimal APIs vs. Controllers

- **Controllers (`[ApiController]`):** prefer for complex domains with many endpoints, versioning, filters, and middleware
- **Minimal APIs:** prefer for simple endpoints, microservices, low-overhead scenarios
- Organize Minimal API endpoints in extension methods by feature area:
  ```csharp
  public static class UserEndpoints
  {
      public static WebApplication MapUserEndpoints(this WebApplication app) { ... }
  }
  ```
- Do not mix controllers and Minimal APIs in the same bounded context

## LINQ in EF Core Queries

- Use method syntax for EF Core LINQ — composable and consistent
- Call `AsNoTracking()` on all read-only queries before projection
- Use `Select()` projections to DTO types at the query boundary — avoids over-fetching
- Materialize with `ToListAsync()` / `FirstOrDefaultAsync()` — never enumerate `IQueryable` in a loop

## Package Structure

```
src/
  MyApp.Api/            # Controllers, Minimal API endpoints, Program.cs
  MyApp.Application/    # Service interfaces, use cases, DTOs
  MyApp.Domain/         # Entities, value objects, domain exceptions
  MyApp.Infrastructure/ # EF Core DbContext, repositories, external clients
tests/
  MyApp.Api.Tests/      # Integration tests (WebApplicationFactory)
  MyApp.Application.Tests/  # Unit tests (mocked repos)
  MyApp.Infrastructure.Tests/  # Repository tests (Testcontainers)
```
