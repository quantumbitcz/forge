# ASP.NET Core + Coverlet

> Extends `modules/code-quality/coverlet.md` with ASP.NET Core-specific integration.
> Generic Coverlet conventions (collector setup, threshold configuration, ReportGenerator, CI integration) are NOT repeated here.

## Integration Setup

ASP.NET Core solutions typically have three test project types: unit tests, integration tests using `WebApplicationFactory<T>`, and end-to-end tests. Collect coverage from all three and merge for an accurate aggregate:

```xml
<!-- MyApp.IntegrationTests/MyApp.IntegrationTests.csproj -->
<ItemGroup>
  <PackageReference Include="coverlet.collector" Version="6.*" />
  <PackageReference Include="Microsoft.AspNetCore.Mvc.Testing" Version="9.*" />
  <PackageReference Include="Microsoft.NET.Test.Sdk" Version="17.*" />
</ItemGroup>
```

```bash
# Run all test projects with coverage collection
dotnet test MySolution.sln \
  --settings coverlet.runsettings \
  --results-directory ./coverage
```

## Framework-Specific Patterns

### `WebApplicationFactory<T>` integration test coverage

`WebApplicationFactory<T>` starts the full ASP.NET Core pipeline in-process. Coverlet instruments the production assemblies referenced by the factory — integration tests produce accurate controller and middleware coverage:

```csharp
// IntegrationTests/WebAppFactory.cs
public class WebAppFactory : WebApplicationFactory<Program>
{
    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.ConfigureTestServices(services =>
        {
            // Replace infrastructure with test doubles
            services.RemoveAll<IOrderRepository>();
            services.AddSingleton<IOrderRepository, InMemoryOrderRepository>();
        });
    }
}
```

Coverage from `WebApplicationFactory` tests flows into the same Cobertura XML as unit tests — no extra configuration needed beyond `--collect:"XPlat Code Coverage"`.

### `[ExcludeFromCodeCoverage]` for generated and infrastructure classes

Apply `[ExcludeFromCodeCoverage]` to ASP.NET Core infrastructure that is framework-managed or untestable without a live environment:

```csharp
using System.Diagnostics.CodeAnalysis;

[ExcludeFromCodeCoverage]
public class Program { }   // ASP.NET Core entry point — framework-managed

[ExcludeFromCodeCoverage]
public class ApplicationDbContext : DbContext { }   // EF Core context — tested via integration

[ExcludeFromCodeCoverage]
public sealed class ConfigureSwaggerOptions : IConfigureOptions<SwaggerGenOptions> { }  // Swagger setup
```

Also exclude via `coverlet.runsettings`:

```xml
<Configuration>
  <ExcludeByAttribute>GeneratedCode,CompilerGenerated,ExcludeFromCodeCoverage</ExcludeByAttribute>
  <ExcludeByFile>**/Migrations/**,**/*.g.cs,**/Program.cs</ExcludeByFile>
  <Exclude>[*]*.Migrations.*,[*]*.Generated.*,[*]*ConfigureSwaggerOptions</Exclude>
</Configuration>
```

### Multi-project aggregation

ASP.NET Core solutions with `Web`, `Application`, `Domain`, `Infrastructure` projects need per-layer coverage merged:

```bash
# Generate aggregate HTML report
reportgenerator \
  -reports:"coverage/**/coverage.cobertura.xml" \
  -targetdir:"coverage/report" \
  -reporttypes:"Html;Cobertura;lcov" \
  -classfilters:"-*.Migrations.*;-*Program;-*DbContext;-*.Generated.*"
```

Set lower branch-coverage thresholds for `Infrastructure` layer code — repository implementations and EF Core mapping configs are harder to branch-cover without a live database.

## Additional Dos

- Run `WebApplicationFactory<T>` integration tests with coverage enabled — they exercise controller routing, middleware pipeline, and filter execution that unit tests never reach.
- Apply `[ExcludeFromCodeCoverage]` to `Program.cs` and EF Core `DbContext` — these classes are framework-managed entry points, not business logic.
- Aggregate coverage across `Web`, `Application`, and `Domain` projects — per-project silos make the domain layer appear under-covered when integration tests are the primary test vehicle.

## Additional Don'ts

- Don't set a high branch-coverage threshold for `Infrastructure` project — Entity Framework repositories have many code paths that only execute with a live database, making branch coverage misleading in unit test runs.
- Don't exclude the `Application` layer from coverage thresholds — service and use case classes are the highest-value coverage targets; they must remain in scope.
- Don't omit `WebApplicationFactory<T>` tests from coverage collection — running them without coverage misses the most realistic test execution paths through the HTTP pipeline.
