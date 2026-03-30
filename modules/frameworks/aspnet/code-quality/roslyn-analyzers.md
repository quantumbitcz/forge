# ASP.NET Core + Roslyn Analyzers

> Extends `modules/code-quality/roslyn-analyzers.md` with ASP.NET Core-specific integration.
> Generic Roslyn conventions (rule categories, `.editorconfig` setup, CI integration) are NOT repeated here.

## Integration Setup

Add `Microsoft.AspNetCore.Analyzers` alongside the SDK-bundled analyzers — it ships as part of the ASP.NET Core shared framework and requires no separate NuGet reference in SDK-style projects targeting `net6.0`+:

```xml
<!-- Web.csproj -->
<PropertyGroup>
  <TargetFramework>net9.0</TargetFramework>
  <AnalysisLevel>latest-recommended</AnalysisLevel>
  <Nullable>enable</Nullable>
  <!-- Escalate ASP.NET Core-specific rules to error -->
  <WarningsAsErrors>ASP0001;ASP0006;ASP0014;ASP0019;CA2100;CA2000</WarningsAsErrors>
</PropertyGroup>
```

For the `[ApiController]` middleware ordering and route diagnostics in `.editorconfig`:

```ini
[*.cs]
dotnet_diagnostic.ASP0001.severity = error    # AuthorizeAttribute applied to action conflicts with controller-level
dotnet_diagnostic.ASP0006.severity = error    # Do not use IActionResult for WebAPI — use ActionResult<T>
dotnet_diagnostic.ASP0014.severity = error    # Suggest using top-level route registrations
dotnet_diagnostic.ASP0018.severity = warning  # Unused route parameter
dotnet_diagnostic.ASP0019.severity = error    # Use IHeaderDictionary.Append instead of .Add

[*Tests.cs]
dotnet_diagnostic.CA1707.severity = none
dotnet_diagnostic.CA2000.severity = none      # IDisposable resource tracking unreliable in test hosts
```

## Framework-Specific Patterns

### `[ApiController]` enforcement

`ASP0006` enforces `ActionResult<T>` return types on Web API controllers. Pair with `[ProducesResponseType]` for complete OpenAPI schema generation:

```csharp
[ApiController]
[Route("api/[controller]")]
public class OrdersController : ControllerBase
{
    [HttpGet("{id:guid}")]
    [ProducesResponseType<OrderResponse>(StatusCodes.Status200OK)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status404NotFound)]
    public async Task<ActionResult<OrderResponse>> GetOrder(Guid id, CancellationToken ct) { ... }
}
```

Avoid `IActionResult` on Web API actions — it erases the response type from OpenAPI schema generation and suppresses analyzer type-narrowing.

### Middleware ordering diagnostics

`ASP0014` fires when middleware is registered in incorrect order (e.g., `UseAuthorization` before `UseAuthentication`, `UseStaticFiles` after `UseRouting`). Enable `error` severity in `Program.cs`-adjacent configs:

```ini
[Program.cs]
dotnet_diagnostic.ASP0014.severity = error
dotnet_diagnostic.ASP0017.severity = error    # Route parameter missing from action signature
```

### BannedApiAnalyzers for ASP.NET Core

Add a `BannedSymbols.txt` targeting ASP.NET-specific anti-patterns:

```
M:Microsoft.AspNetCore.Http.HttpContext.get_User;Inject ClaimsPrincipal via IHttpContextAccessor, not HttpContext directly in services
T:Microsoft.AspNetCore.Mvc.Controller;Use ControllerBase for API controllers — Controller adds View support you don't need
M:System.Threading.Thread.Sleep;Use Task.Delay in async ASP.NET Core code
```

## Additional Dos

- Escalate `ASP0006` to `error` — `IActionResult` return types on Web API controllers break Swagger schema generation.
- Use `[ProducesResponseType<T>]` on every public controller action — it documents the contract and satisfies analyzer requirements.
- Enable `CA2000` (dispose objects) as an error in production projects — request-scoped `DbContext` and `HttpClient` leaks cause connection pool exhaustion.

## Additional Don'ts

- Don't suppress `ASP0001` (conflicting auth attributes) — it indicates a genuine security misconfiguration where controller-level `[Authorize]` is bypassed by action-level `[AllowAnonymous]` or vice versa.
- Don't apply `[SuppressMessage]` on security rules in controllers — ASP.NET route handlers are the primary attack surface; suppressions here require a security review comment.
- Don't configure `<RunAnalyzersDuringBuild>false</RunAnalyzersDuringBuild>` in the main web project — ASP.NET analyzers run at compile time with negligible overhead compared to the MSBuild startup cost.
