# ASP.NET Core + OAuth2 / JWT (Microsoft.Identity)

> ASP.NET Core-specific patterns for JWT bearer auth with Microsoft.Identity / Entra ID. Extends generic ASP.NET conventions.

## Integration Setup

```bash
dotnet add package Microsoft.AspNetCore.Authentication.JwtBearer
# For Entra ID / Azure AD (optional):
dotnet add package Microsoft.Identity.Web
```

```csharp
// Program.cs — generic JWT bearer (any OIDC-compliant IdP)
builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(options =>
    {
        options.Authority = builder.Configuration["Auth:Authority"];   // issuer
        options.Audience  = builder.Configuration["Auth:Audience"];
        options.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuer           = true,
            ValidateAudience         = true,
            ValidateLifetime         = true,
            ValidateIssuerSigningKey = true,
            ClockSkew                = TimeSpan.FromSeconds(30),
        };
        options.Events = new JwtBearerEvents
        {
            OnAuthenticationFailed = ctx =>
            {
                ctx.Response.StatusCode = 401;
                return Task.CompletedTask;
            }
        };
    });

builder.Services.AddAuthorization(options =>
{
    options.AddPolicy("AdminOnly",    p => p.RequireRole("admin"));
    options.AddPolicy("PremiumUsers", p => p.RequireClaim("subscription", "premium"));
});
```

For Entra ID (Microsoft.Identity.Web):

```csharp
builder.Services.AddMicrosoftIdentityWebApiAuthentication(builder.Configuration, "AzureAd");
// appsettings.json: "AzureAd": { "Instance": "https://login.microsoftonline.com/", "TenantId": "...", "ClientId": "..." }
```

## Framework-Specific Patterns

```csharp
// Controllers/UsersController.cs
[ApiController]
[Route("api/[controller]")]
[Authorize]
public class UsersController : ControllerBase
{
    [HttpGet("me")]
    public IActionResult Me()
    {
        var sub = User.FindFirstValue(ClaimTypes.NameIdentifier) ?? User.FindFirstValue("sub");
        return Ok(new { sub });
    }

    [HttpDelete("{id:guid}")]
    [Authorize(Policy = "AdminOnly")]
    public async Task<IActionResult> Delete(Guid id) { ... }
}
```

Custom claims transformation:

```csharp
// Infrastructure/Auth/RoleClaimsTransformer.cs
public class RoleClaimsTransformer : IClaimsTransformation
{
    public Task<ClaimsPrincipal> TransformAsync(ClaimsPrincipal principal)
    {
        // Map token roles claim to ASP.NET ClaimTypes.Role
        var roles = principal.FindAll("roles").Select(c => c.Value);
        var identity = new ClaimsIdentity();
        foreach (var role in roles)
            identity.AddClaim(new Claim(ClaimTypes.Role, role));
        principal.AddIdentity(identity);
        return Task.FromResult(principal);
    }
}

// Registration
builder.Services.AddSingleton<IClaimsTransformation, RoleClaimsTransformer>();
```

## Scaffolder Patterns

```
Application/
  Auth/
    RoleClaimsTransformer.cs    # IClaimsTransformation implementation
    PolicyNames.cs              # const string AdminOnly = "AdminOnly"; ...
Infrastructure/
  DependencyInjection.cs        # AddAuthentication + AddAuthorization wiring
```

## Dos

- Use `[Authorize]` on the controller class and `[AllowAnonymous]` on public endpoints — opt-out model reduces missed auth
- Use policy-based authorization (`RequireRole`, `RequireClaim`) instead of role strings in attributes
- Implement `IClaimsTransformation` to normalize third-party token claims to ASP.NET `ClaimTypes`
- Set `ClockSkew` to 30 seconds or less — the default 5-minute window is too permissive

## Don'ts

- Don't use `app.UseAuthentication()` without `app.UseAuthorization()` — both are required and order matters
- Don't store tokens in `TempData` or `ViewBag` — always read from the `Authorization` header
- Don't hard-code audience or authority strings — read from configuration for environment portability
- Don't skip adding `app.UseAuthentication()` / `app.UseAuthorization()` in the middleware pipeline (must come after routing, before endpoint mapping)
