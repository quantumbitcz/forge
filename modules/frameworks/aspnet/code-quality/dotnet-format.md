# ASP.NET Core + dotnet-format

> Extends `modules/code-quality/dotnet-format.md` with ASP.NET Core-specific integration.
> Generic dotnet-format conventions (sub-commands, `.editorconfig` setup, CI integration) are NOT repeated here.

## Integration Setup

Place the `.editorconfig` at the solution root so it covers all projects — `Web`, `Application`, `Domain`, `Infrastructure`, and test projects. The solution-level config applies to all `.cs` files unless overridden:

```bash
# Format the solution (all projects)
dotnet format MyApp.sln --verify-no-changes

# Exclude generated and migration files solution-wide
dotnet format MyApp.sln --exclude "**/Migrations/**" --exclude "**/*.g.cs"
```

## Framework-Specific Patterns

### ASP.NET Core-specific `.editorconfig` rules

```ini
[*.cs]
# File-scoped namespaces (mandatory for .NET 6+ projects)
csharp_style_namespace_declarations = file_scoped:warning

# Primary constructors for simple services (C# 12+)
csharp_style_prefer_primary_constructors = true:suggestion

# Prefer pattern matching for null checks in controllers
csharp_style_prefer_pattern_matching = true:suggestion
csharp_prefer_simple_null_check = true:suggestion

# Async suffix enforcement (IDE0030 — rename async methods)
dotnet_diagnostic.VSTHRD200.severity = warning   # Use "Async" suffix for async methods

# Using directives outside namespace (controllers import many aspnet namespaces)
csharp_using_directive_placement = outside_namespace:warning
dotnet_sort_system_directives_first = true

[*Controller.cs]
# Controllers — relax complexity rules (action method per endpoint)
dotnet_diagnostic.CA1822.severity = none         # controller actions can't be static

[*Tests.cs]
# Test files — allow underscores in method names
dotnet_diagnostic.CA1707.severity = none
csharp_style_namespace_declarations = file_scoped:suggestion
```

### Excluding EF Core Migrations

EF Core generates migration files (`*_MigrationName.cs`, `ApplicationDbContextModelSnapshot.cs`) that use positional formatting incompatible with standard `.editorconfig` rules. Exclude them explicitly:

```bash
dotnet format MyApp.sln \
  --exclude "**/Migrations/**" \
  --exclude "**/*Snapshot.cs" \
  --verify-no-changes
```

Never apply `dotnet format style` or `dotnet format analyzers` to migration files — EF Core regenerates them with its own formatting on the next `dotnet ef migrations add`.

### Pre-commit scoping to changed files

In ASP.NET Core solutions with many projects, scope the pre-commit hook to changed `.cs` files only:

```bash
#!/usr/bin/env bash
staged=$(git diff --cached --name-only --diff-filter=ACM | grep '\.cs$' | grep -v Migrations | grep -v '\.g\.cs$')
if [ -n "$staged" ]; then
  dotnet format --include $staged
  echo "$staged" | xargs git add
fi
```

## Additional Dos

- Exclude `**/Migrations/**` from all `dotnet format` runs — EF Core migration files use generated formatting that conflicts with `.editorconfig` rules.
- Set `csharp_style_namespace_declarations = file_scoped:warning` for all ASP.NET Core projects — file-scoped namespaces reduce indentation in controller and service files by one level.
- Run `dotnet format whitespace --verify-no-changes` as a fast first gate in CI — it catches the most common formatting issues in under 10 seconds.

## Additional Don'ts

- Don't run `dotnet format analyzers` on `*Controller.cs` files with `CA1822` enabled — controller action methods cannot be static, and the analyzer fix introduces breaking changes.
- Don't apply `dotnet format` to auto-generated OpenAPI/Swagger scaffold files (`*.NSwag.cs`, `*Client.cs`) — they are regenerated from the OpenAPI spec and manual formatting is lost.
- Don't set `csharp_new_line_before_open_brace = none` — ASP.NET Core controller and middleware classes have nested `using` + `try/catch` blocks where brace placement critically affects readability.
