# ASP.NET Core Documentation Conventions

> Support tier: community

> Extends `modules/documentation/conventions.md` with ASP.NET Core-specific patterns.

## Code Documentation

- Use XML doc comments (`/// <summary>`) for all public controllers, service interfaces, and domain types.
- Controller actions: document the HTTP method, route template, request body type, response types, and status codes using `<remarks>` and Swagger attributes.
- Service interfaces: document the contract — preconditions, postconditions, and exception types thrown.
- Domain entities and value objects: document invariants and valid state transitions.
- Use `[ProducesResponseType]` attributes on controller actions — they feed Swashbuckle/NSwag OpenAPI generation.

```csharp
/// <summary>
/// Creates a new user account.
/// </summary>
/// <param name="request">The user creation payload.</param>
/// <returns>The created user resource.</returns>
/// <response code="201">User created successfully.</response>
/// <response code="409">Email address already registered.</response>
[HttpPost]
[ProducesResponseType(typeof(UserResponse), StatusCodes.Status201Created)]
[ProducesResponseType(StatusCodes.Status409Conflict)]
public async Task<IActionResult> CreateUser([FromBody] CreateUserRequest request) { ... }
```

## Architecture Documentation

- Document the middleware pipeline registered in `Program.cs` — list middleware in order with a one-line purpose.
- Document the service registration structure: which assemblies register which services and the lifetime (Singleton/Scoped/Transient) for non-obvious registrations.
- OpenAPI: Swashbuckle or NSwag. Document spec location and Swagger UI path in `README.md`.
- Document the authentication scheme: JWT bearer, cookie, or API key. Document the `IAuthorizationRequirement` custom policies if used.
- Clean Architecture / Onion Architecture (if applicable): document layer boundaries and the dependency rule.

## Diagram Guidance

- **Middleware pipeline:** Sequence diagram showing the `IMiddleware` chain for a typical request.
- **Layer boundaries:** C4 Component or class diagram for Clean Architecture layers.

## Dos

- XML doc comments on all public controller actions — Swashbuckle uses them for OpenAPI descriptions
- `[ProducesResponseType]` on every action — drives accurate OpenAPI response schemas
- Document `IOptions<T>` configuration classes with XML comments — they appear in generated config docs

## Don'ts

- Don't document ASP.NET built-in middleware unless the project configures it non-standardly
- Don't maintain a manual API reference alongside the OpenAPI spec — they will drift
