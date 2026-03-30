# ASP.NET Core + XML Documentation

> Extends `modules/code-quality/xmldoc.md` with ASP.NET Core-specific integration.
> Generic XML doc conventions (`<summary>`, `<inheritdoc>`, DocFX setup, CI integration) are NOT repeated here.

## Integration Setup

Enable XML doc generation in the web project and feed the `.xml` output to Swashbuckle/NSwag for OpenAPI schema enrichment:

```xml
<!-- Web.csproj -->
<PropertyGroup>
  <GenerateDocumentationFile>true</GenerateDocumentationFile>
  <!-- Enforce docs on public controller actions and service interfaces -->
  <WarningsAsErrors>CS1591</WarningsAsErrors>
  <!-- Suppress for test and generated types -->
  <NoWarn>CS1591</NoWarn>  <!-- override per-file in .editorconfig instead -->
</PropertyGroup>
```

Wire the XML file into Swashbuckle in `Program.cs`:

```csharp
builder.Services.AddSwaggerGen(options =>
{
    var xmlFile = $"{Assembly.GetExecutingAssembly().GetName().Name}.xml";
    var xmlPath = Path.Combine(AppContext.BaseDirectory, xmlFile);
    options.IncludeXmlComments(xmlPath, includeControllerXmlComments: true);
});
```

## Framework-Specific Patterns

### Controller action documentation

Document every public controller action with `<summary>`, `<param>`, and `<response>` tags. Swashbuckle maps `<response>` to the OpenAPI `responses` object:

```csharp
/// <summary>
/// Creates a new order for the authenticated user.
/// </summary>
/// <param name="request">The order creation payload. Line items must be non-empty.</param>
/// <param name="cancellationToken">Cancellation token for the async operation.</param>
/// <returns>The created order with its assigned identifier.</returns>
/// <response code="201">Order created successfully.</response>
/// <response code="400">Validation failed — see ProblemDetails for field errors.</response>
/// <response code="401">Authentication required.</response>
[HttpPost]
[ProducesResponseType<CreateOrderResponse>(StatusCodes.Status201Created)]
[ProducesResponseType<ProblemDetails>(StatusCodes.Status400BadRequest)]
[ProducesResponseType(StatusCodes.Status401Unauthorized)]
public async Task<ActionResult<CreateOrderResponse>> CreateOrder(
    [FromBody] CreateOrderRequest request,
    CancellationToken cancellationToken)
{ ... }
```

### Swagger integration — `<remarks>` for extended descriptions

Use `<remarks>` to provide Swagger UI extended descriptions, including authentication requirements and rate limits:

```csharp
/// <summary>
/// Retrieves paginated order history for the authenticated user.
/// </summary>
/// <remarks>
/// Requires Bearer token authentication. Results are ordered by creation date descending.
/// Rate limit: 100 requests per minute per user.
/// </remarks>
```

### Response type documentation for `ProblemDetails`

Document all `ProblemDetails` response types with the error context to improve API consumer experience in Swagger UI:

```csharp
/// <response code="422">
/// Unprocessable entity — business rule violation.
/// See <c>ProblemDetails.Extensions["errors"]</c> for field-level details.
/// </response>
```

### Suppressing CS1591 for non-public and infrastructure types

Use `.editorconfig` to suppress `CS1591` for infrastructure classes that do not appear in the public API surface:

```ini
[**/Infrastructure/**/*.cs]
dotnet_diagnostic.CS1591.severity = none

[**/Migrations/**/*.cs]
dotnet_diagnostic.CS1591.severity = none

[**/*DbContext.cs]
dotnet_diagnostic.CS1591.severity = none
```

## Additional Dos

- Call `options.IncludeXmlComments(xmlPath, includeControllerXmlComments: true)` — without the second parameter, controller-level `<summary>` tags are omitted from the Swagger UI tag descriptions.
- Document `<response>` codes for every status code declared in `[ProducesResponseType]` — Swashbuckle uses the XML response description as the OpenAPI response description.
- Enable `CS1591` as a warning (not error) in development builds — missing docs should be visible in IDE but not block local `dotnet run`.

## Additional Don'ts

- Don't set `<GenerateDocumentationFile>true</GenerateDocumentationFile>` in test projects — test helper classes generate CS1591 noise for internal types that don't need API documentation.
- Don't skip `<response>` documentation for `400` and `422` responses — these are the codes API consumers handle most; undocumented error shapes increase integration friction.
- Don't use `/// <summary>See controller.</summary>` on action methods — Swagger UI displays this verbatim; unhelpful summaries are worse than no documentation for API consumers.
