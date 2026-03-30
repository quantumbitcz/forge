# roslyn-analyzers

## Overview

C# static analysis platform built on the Roslyn compiler SDK. The primary package is `Microsoft.CodeAnalysis.NetAnalyzers` (included in .NET 5+ SDK by default), which provides ~200 rules from CA (Code Analysis) categories. Additional analyzer packages extend coverage: `Microsoft.CodeAnalysis.BannedApiAnalyzers`, `Roslynator.Analyzers`, `SonarAnalyzer.CSharp`. Severity is configured via `.editorconfig` (preferred) or `<AnalysisLevel>` and `<TreatWarningsAsErrors>` in `.csproj`. Roslyn analyzers run during compilation — no separate tool invocation needed.

## Architecture Patterns

### Installation & Setup

`Microsoft.CodeAnalysis.NetAnalyzers` is bundled with the .NET SDK from .NET 5+ — no installation needed for the built-in set:

```bash
# Verify SDK-bundled analyzers are active
dotnet build --verbosity=normal 2>&1 | grep -i "CA\d"

# Add additional analyzers as NuGet packages
dotnet add package Roslynator.Analyzers --version 4.12.*
dotnet add package Microsoft.CodeAnalysis.BannedApiAnalyzers --version 3.11.*
dotnet add package SonarAnalyzer.CSharp --version 10.*

# Run analysis without building (requires .NET 6+)
dotnet build -p:RunAnalyzersDuringBuild=true
```

For CI, trigger analysis as part of the build:
```bash
dotnet build --configuration Release /p:TreatWarningsAsErrors=true
```

### Rule Categories

| Category | Prefix | What It Checks | Pipeline Severity |
|---|---|---|---|
| Design | `CA1000-CA1200` | API design: nested types, static members, base class usage | WARNING |
| Reliability | `CA2000-CA2009` | IDisposable, finalizers, threading, async void | CRITICAL |
| Security | `CA2100-CA2155` | SQL injection, XSS, crypto weaknesses, XML injection | CRITICAL |
| Performance | `CA1800-CA1870` | Unnecessary casts, string concatenation, LINQ inefficiency | WARNING |
| Maintainability | `CA1500-CA1512` | Avoid excessive complexity, dead code | WARNING |
| Naming | `CA1700-CA1727` | Pascal/camel case, abbreviations, Hungarian notation | WARNING |
| Usage | `CA2200-CA2243` | Proper disposal, correct override patterns | WARNING |
| Globalization | `CA1300-CA1311` | Culture-invariant comparisons, format strings | WARNING |

### Configuration Patterns

`.editorconfig` (preferred — applies per file glob):

```ini
# .editorconfig
root = true

[*.cs]
# Set analysis level
dotnet_analyzer_diagnostic.severity = warning

# Disable specific rules
dotnet_diagnostic.CA1062.severity = none       # ValidateArgumentsOfPublicMethods — disabled for internal projects
dotnet_diagnostic.CA1014.severity = none       # MarkAssembliesWithClsCompliant — rarely relevant

# Escalate critical rules to error
dotnet_diagnostic.CA2100.severity = error      # ReviewSqlQueriesForSecurityVulnerabilities
dotnet_diagnostic.CA2201.severity = error      # DoNotRaiseReservedExceptionTypes
dotnet_diagnostic.CA2000.severity = error      # DisposeObjectsBeforeLosingScope
dotnet_diagnostic.CA1849.severity = error      # CallAsyncMethodsWhenInAsyncContext

# Performance rules
dotnet_diagnostic.CA1822.severity = warning    # MarkMembersAsStatic
dotnet_diagnostic.CA1851.severity = error      # PossibleMultipleEnumerations

# Naming
dotnet_diagnostic.CA1707.severity = warning    # IdentifiersShouldNotContainUnderscores (except test methods)

[*Tests.cs]
# Relax rules for test files
dotnet_diagnostic.CA1707.severity = none       # test method names use underscores
dotnet_diagnostic.CA1062.severity = none
```

`.csproj` level settings:

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net9.0</TargetFramework>

    <!-- Enable latest analysis rules for the target framework -->
    <AnalysisLevel>latest-recommended</AnalysisLevel>

    <!-- Treat all analyzer warnings as errors in Release builds -->
    <TreatWarningsAsErrors Condition="'$(Configuration)'=='Release'">true</TreatWarningsAsErrors>

    <!-- Suppress specific warnings project-wide (prefer .editorconfig) -->
    <NoWarn>CA1014;CA1062</NoWarn>

    <!-- Enable nullable reference types (works with analyzer rules) -->
    <Nullable>enable</Nullable>

    <!-- Enable all warnings (disables code analysis suppression) -->
    <EnableTreatWarningsAsErrors>true</EnableTreatWarningsAsErrors>
  </PropertyGroup>

  <ItemGroup>
    <!-- Additional analyzer packages -->
    <PackageReference Include="Roslynator.Analyzers" Version="4.12.*">
      <PrivateAssets>all</PrivateAssets>
      <IncludeAssets>runtime; build; native; contentfiles; analyzers</IncludeAssets>
    </PackageReference>
  </ItemGroup>
</Project>
```

Banned API analyzer configuration (`BannedSymbols.txt`):
```
T:System.Threading.Thread;Use Task-based async instead of raw Thread
M:System.Console.WriteLine;Use ILogger instead of Console.WriteLine in production
T:System.Web.HttpContext;Inject IHttpContextAccessor instead
```

Inline suppression:
```csharp
#pragma warning disable CA2100 // ReviewSqlQueriesForSecurityVulnerabilities — parameterized query, safe
var command = new SqlCommand($"SELECT * FROM {tableName}", connection);
#pragma warning restore CA2100

[SuppressMessage("Security", "CA2100", Justification = "Query is parameterized")]
private void ExecuteQuery(string sql) { ... }
```

### CI Integration

```yaml
# .github/workflows/quality.yml
- name: Build with analyzers
  run: dotnet build --configuration Release /p:TreatWarningsAsErrors=true

- name: Run dotnet format (check only)
  run: dotnet format --verify-no-changes --severity warn
```

For SARIF output (uploads to GitHub Security tab):
```yaml
- name: Build with SARIF
  run: |
    dotnet build /p:RunAnalyzersDuringBuild=true \
      /p:ErrorLog=analysis-results.sarif \
      /p:ContinueOnError=true

- name: Upload SARIF
  uses: github/codeql-action/upload-sarif@v3
  with:
    sarif_file: analysis-results.sarif
```

## Performance

- Roslyn analyzers run inside the compiler process — there is no separate analysis step. Build time overhead is typically 10-20% for the bundled NetAnalyzers.
- Third-party analyzers (Roslynator, SonarAnalyzer) can add 30-50% to build time — evaluate the trade-off for large solutions.
- `<RunAnalyzersDuringBuild>false</RunAnalyzersDuringBuild>` disables analyzer execution without removing packages — useful to speed up local `dotnet watch` cycles while keeping CI analysis active.
- Incremental build cache: Roslyn caches per-file analysis results. Clean builds (`dotnet clean`) invalidate the cache — run incremental builds in CI by preserving the `obj/` directory between runs.
- For solutions with many projects, consider enabling analyzers only on non-test projects: set `<RunAnalyzersDuringBuild>` to false in test project files.

## Security

The `CA2100-CA2155` security rules are critical for C# applications:

- `CA2100` — detects string concatenation in SQL command constructors; require parameterized queries.
- `CA2109` — detects visible event handlers that should be secured.
- `CA2119` — methods satisfying private interface methods should not be public.
- `CA5350/CA5351` — use of broken cryptographic algorithms (`DES`, `RC2`, `MD5`).
- `CA5360-CA5399` — use of insecure `XmlReader` settings (XXE), weak random number generators, insecure deserializers.
- `CA2153` — catching `CorruptedStateException` can hide memory corruption.

With `<Nullable>enable</Nullable>`, nullable reference type warnings (`CS8600-CS8629`) work alongside analyzers to eliminate entire categories of null-dereference vulnerabilities at compile time.

## Testing

```bash
# Build with analysis (default in .NET 5+ SDK)
dotnet build

# Build with warnings-as-errors
dotnet build /p:TreatWarningsAsErrors=true

# Suppress analysis during build (faster local iteration)
dotnet build /p:RunAnalyzersDuringBuild=false

# Format check (uses Roslyn formatter)
dotnet format --verify-no-changes

# Apply formatting
dotnet format

# List installed analyzer packages
dotnet list package --include-transitive | grep -i analyzer

# Run analysis in isolation (Roslyn tools)
dotnet tool install -g dotnet-suggest
```

## Dos

- Use `.editorconfig` for severity configuration rather than `.csproj` `<NoWarn>` — `.editorconfig` supports file-glob patterns, enabling different severities for test vs. production code.
- Set `<AnalysisLevel>latest-recommended</AnalysisLevel>` in new projects — it activates the full recommended rule set for the current .NET SDK version.
- Enable `<Nullable>enable</Nullable>` alongside analyzers — nullable reference types and `CA1062` (validate public arguments) work together to enforce null safety at compile time.
- Escalate `CA2100` (SQL injection), `CA2000` (disposal), and `CA5350`/`CA5351` (weak crypto) to `error` severity — these are critical security rules that must not be suppressed with warnings.
- Use `#pragma warning disable` with a justification comment rather than project-wide `<NoWarn>` — suppression context makes the exception visible during code review.
- Add `Microsoft.CodeAnalysis.BannedApiAnalyzers` with a `BannedSymbols.txt` to enforce project-specific restrictions (e.g., no raw `Thread`, no `Console.WriteLine` in library code).

## Don'ts

- Don't set `<NoWarn>` to suppress all CA rules in `.csproj` — it silently disables security and reliability analysis for the entire project.
- Don't disable `CA2000` (dispose objects before losing scope) without thorough review — IDisposable resource leaks in ASP.NET Core cause connection pool exhaustion under load.
- Don't rely on `[SuppressMessage]` attributes in production code for security rules — they are permanent and survive refactoring. Use `#pragma warning disable/restore` with explanatory comments instead.
- Don't configure `<TreatWarningsAsErrors>true</TreatWarningsAsErrors>` unconditionally in Debug builds — it slows inner-loop development. Apply only in Release or CI builds.
- Don't add analyzer NuGet packages as regular dependencies — always use `<PrivateAssets>all</PrivateAssets>` and `<IncludeAssets>analyzers</IncludeAssets>` to prevent them from becoming transitive dependencies for consumers.
- Don't skip `.editorconfig` from version control — without it, every developer's IDE applies different default severities, creating inconsistent build behavior.
