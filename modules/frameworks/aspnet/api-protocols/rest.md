# ASP.NET REST — API Protocol Binding

## Integration Setup
- .NET 8+: use Minimal APIs as default; fall back to `[ApiController]` for complex routing needs
- Add `Swashbuckle.AspNetCore` or `Microsoft.AspNetCore.OpenApi` (native .NET 9) for OpenAPI
- Validation: `FluentValidation.AspNetCore`; register validators with `builder.Services.AddValidatorsFromAssembly`
- `ProblemDetails` middleware: `builder.Services.AddProblemDetails()` + `app.UseExceptionHandler()`

## Framework-Specific Patterns
- Minimal API: `app.MapGet("/api/v1/users/{id}", async (Guid id, IUserService svc) => ...)`; group with `RouteGroupBuilder`
- Controller API: `[ApiController] [Route("api/v1/[controller]")]`; use `ActionResult<T>` return type
- Model binding: `[FromBody]`, `[FromRoute]`, `[FromQuery]`; framework validates `[Required]` / `[Range]` annotations automatically
- `ProblemDetails` for errors: `TypedResults.Problem(...)` in Minimal APIs; `ValidationProblem()` for 422
- Global exception handling: `IExceptionHandler` (implement + register) or `UseExceptionHandler("/error")`
- Content negotiation: `AddControllers().AddXmlSerializerFormatters()` if XML required; default is JSON

## Scaffolder Patterns
```
src/
  Api/
    Endpoints/               # Minimal API extension methods per resource
      UserEndpoints.cs       # static class with MapGroup + MapGet/Post/etc.
    Controllers/             # (if using controller-based)
      UsersController.cs
  Application/
    Users/
      Commands/CreateUser/
        CreateUserCommand.cs
        CreateUserCommandValidator.cs  # FluentValidation
  Infrastructure/
    ExceptionHandler.cs      # IExceptionHandler impl
```

## Dos
- Return `TypedResults.*` in Minimal APIs (e.g., `TypedResults.Ok`, `TypedResults.Created`) for OpenAPI inference
- Register `AddProblemDetails()` and let it handle unhandled exceptions as RFC 7807 responses
- Use `IValidator<T>` from FluentValidation injected into the endpoint handler for explicit validation
- Version the API via route prefix (`/v1/`, `/v2/`) or with `Asp.Versioning.Http`

## Don'ts
- Don't return `object` or anonymous types from Minimal APIs — use typed returns for OpenAPI accuracy
- Don't use `[HttpGet]` alongside Minimal APIs in the same project — pick one style per service
- Don't throw exceptions for expected business failures — return problem details or result types
- Don't skip `[ProducesResponseType]` / `Produces<T>()` — OpenAPI consumers depend on this
