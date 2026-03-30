# ASP.NET Core + Stryker

> Extends `modules/code-quality/stryker.md` with ASP.NET Core-specific integration.
> Generic Stryker conventions (installation, mutation operators, threshold configuration, CI integration) are NOT repeated here.

## Integration Setup

Install `dotnet-stryker` as a local tool so all developers and CI use the same version:

```bash
dotnet new tool-manifest   # creates .config/dotnet-tools.json
dotnet tool install dotnet-stryker
dotnet tool restore
```

Place `stryker-config.json` in each project directory that has a dedicated test project:

```json
{
  "stryker-config": {
    "project": "MyApp.Application.csproj",
    "test-projects": ["../../tests/MyApp.Application.Tests/MyApp.Application.Tests.csproj"],
    "target-framework": "net9.0",
    "mutation-level": "Standard",
    "mutate": [
      "src/**/*.cs",
      "!src/**/Migrations/**",
      "!src/**/*.g.cs",
      "!src/**/Program.cs"
    ],
    "reporters": ["html", "json", "dashboard"],
    "threshold-high": 80,
    "threshold-low": 60,
    "threshold-break": 50,
    "concurrency": 4
  }
}
```

## Framework-Specific Patterns

### Project filter — target domain and application layers

Run Stryker against `Application` and `Domain` projects, not the `Web` or `Infrastructure` projects. Controller and middleware mutation testing generates noise from HTTP-specific branching that is not meaningful business logic:

```json
{
  "stryker-config": {
    "project": "MyApp.Domain.csproj",
    "mutate": [
      "src/**/*.cs",
      "!src/**/Exceptions/**",   // exception types have trivial constructors
      "!src/**/*Options.cs"      // configuration records — no logic
    ]
  }
}
```

Create a separate `stryker-config.json` per layer — `Domain`, `Application`, `Infrastructure` — and run them independently in CI.

### `WebApplicationFactory<T>` targeting

For integration-level mutation testing of controller logic, configure the `Application` test project that uses `WebApplicationFactory<T>`:

```json
{
  "stryker-config": {
    "project": "MyApp.Web.csproj",
    "test-projects": ["../../tests/MyApp.Integration.Tests/MyApp.Integration.Tests.csproj"],
    "mutate": [
      "src/Controllers/**/*.cs",
      "src/Filters/**/*.cs",
      "src/Middleware/**/*.cs",
      "!src/**/*.g.cs"
    ],
    "threshold-break": 40,    // lower bar — integration tests are slower to write
    "concurrency": 2          // WebApplicationFactory instances are heavy
  }
}
```

Lower concurrency for `WebApplicationFactory`-based mutation runs — each concurrent mutant spawns an isolated in-process ASP.NET Core host.

### CI incremental mode

Use `--since main` to limit mutation testing to changed files in PRs:

```yaml
- name: Restore dotnet tools
  run: dotnet tool restore

- name: Run Stryker (Domain — incremental)
  run: dotnet stryker --config-file stryker-config.domain.json --since main
  working-directory: src/MyApp.Domain

- name: Run Stryker (Application — incremental)
  run: dotnet stryker --config-file stryker-config.application.json --since main
  working-directory: src/MyApp.Application

- name: Upload Stryker HTML reports
  if: always()
  uses: actions/upload-artifact@v4
  with:
    name: stryker-reports
    path: "**/StrykerOutput/**/reports/mutation-report.html"
```

## Additional Dos

- Run separate `stryker-config.json` files per layer (`Domain`, `Application`) — aggregate mutation scores hide under-tested layers when merged.
- Use `"concurrency": 2` for projects whose test suite uses `WebApplicationFactory<T>` — in-process ASP.NET Core hosts are memory-intensive; high concurrency causes test timeouts.
- Scope `mutate` to business logic files only — exclude `Controllers`, `Middleware`, `Filters`, and `Program.cs` unless you have dedicated integration mutation runs.

## Additional Don'ts

- Don't run Stryker on `Infrastructure` project without mocked dependencies — EF Core operations against a real database in mutation runs produce flaky results from partial transactions.
- Don't set `threshold-break` at 80+ for the `Web` project — controller action methods are difficult to mutation-test without `WebApplicationFactory`, and full integration runs are slow.
- Don't run Stryker on EF Core migration files — they contain generated scaffold code with no meaningful business logic to mutate.
