---
name: xmldoc
categories: [doc-generator]
languages: [csharp]
exclusive_group: csharp-doc-generator
recommendation_score: 90
detection_files: [*.csproj]
---

# xmldoc

## Overview

C# XML documentation uses `///` triple-slash comments with XML tags (`<summary>`, `<param>`, `<returns>`, `<exception>`, `<remarks>`, `<example>`, `<inheritdoc>`). Enable generation by setting `<GenerateDocumentationFile>true</GenerateDocumentationFile>` in the `.csproj` file. The compiler emits a `.xml` file alongside the assembly. Tools like DocFX or Sandcastle convert this XML into browsable HTML. `<InheritDoc>` propagates documentation from base classes and interfaces to overrides.

## Architecture Patterns

### Installation & Setup

```xml
<!-- MyLibrary.csproj -->
<PropertyGroup>
    <GenerateDocumentationFile>true</GenerateDocumentationFile>
    <!-- Treat missing XML doc as a warning (optional — escalate to error in CI) -->
    <NoWarn>$(NoWarn)</NoWarn>
    <TreatWarningsAsErrors>false</TreatWarningsAsErrors>
    <!-- CS1591: Missing XML comment for publicly visible type or member -->
    <WarningsAsErrors>CS1591</WarningsAsErrors>
</PropertyGroup>
```

**DocFX for HTML generation:**
```bash
dotnet tool install -g docfx
docfx init --quiet           # Creates docfx.json scaffold
docfx docfx.json --serve     # Build and serve locally
```

**`docfx.json` configuration:**
```json
{
  "metadata": [
    {
      "src": [{ "files": ["**/*.csproj"], "exclude": ["**/Tests/**"] }],
      "dest": "api",
      "disableGitFeatures": false,
      "disableDefaultFilter": false
    }
  ],
  "build": {
    "content": [
      { "files": ["api/**.yml", "api/index.md"] },
      { "files": ["docs/**.md", "*.md"], "exclude": ["**/bin/**", "**/obj/**"] }
    ],
    "dest": "_site",
    "globalMetadata": {
      "_appTitle": "My Library",
      "_enableSearch": true
    },
    "template": ["default", "modern"]
  }
}
```

### Rule Categories

| Category | Pattern | Pipeline Severity |
|---|---|---|
| Missing `<summary>` | Public member without `<summary>` tag | WARNING (CS1591) |
| Missing `<param>` | Public method parameter without `<param>` | WARNING |
| Missing `<returns>` | Non-void public method without `<returns>` | INFO |
| Missing `<exception>` | Method throwing a documented exception without `<exception>` | WARNING |
| Broken `<see cref="">` | Cref referencing undefined member | CRITICAL (compile error) |

### Configuration Patterns

**Standard XML documentation comment structure:**
```csharp
/// <summary>
/// Retrieves the user associated with the specified identifier.
/// </summary>
/// <remarks>
/// This method queries the primary replica. For stale-read workloads,
/// use <see cref="FindByIdAsync(Guid, CancellationToken, ReadConsistency)"/>
/// with <see cref="ReadConsistency.Eventual"/>.
/// </remarks>
/// <param name="id">
/// The unique user identifier. Must not be <see cref="Guid.Empty"/>.
/// </param>
/// <param name="cancellationToken">
/// Token to cancel the asynchronous operation.
/// </param>
/// <returns>
/// The <see cref="User"/> associated with <paramref name="id"/>,
/// or <see langword="null"/> if no user exists.
/// </returns>
/// <exception cref="ArgumentException">
/// Thrown when <paramref name="id"/> is <see cref="Guid.Empty"/>.
/// </exception>
/// <exception cref="OperationCanceledException">
/// Thrown when the operation is cancelled via <paramref name="cancellationToken"/>.
/// </exception>
/// <example>
/// <code>
/// var user = await repository.FindByIdAsync(userId, ct);
/// if (user is null) return NotFound();
/// return Ok(user);
/// </code>
/// </example>
public Task<User?> FindByIdAsync(Guid id, CancellationToken cancellationToken = default);
```

**`<inheritdoc>` for interface implementations:**
```csharp
/// <inheritdoc />
public async Task<User?> FindByIdAsync(Guid id, CancellationToken cancellationToken = default)
{
    // Implementation — docs inherited from IUserRepository.FindByIdAsync
}
```

**`<inheritdoc cref="">` for partial inheritance:**
```csharp
/// <inheritdoc cref="IUserRepository.FindByIdAsync(Guid, CancellationToken)" />
/// <remarks>
/// This override adds Redis caching with a 5-minute TTL.
/// </remarks>
public override Task<User?> FindByIdAsync(Guid id, CancellationToken cancellationToken = default)
```

**Generic type parameter documentation:**
```csharp
/// <summary>
/// A strongly-typed result wrapper.
/// </summary>
/// <typeparam name="T">
/// The type of the successful result value.
/// </typeparam>
public readonly struct Result<T>
```

**`<see langword="">` for language keywords:**
```csharp
/// Returns <see langword="true"/> if the collection is empty;
/// <see langword="false"/> otherwise.
```

### CI Integration

```yaml
# .github/workflows/docs.yml
- name: Build with XML docs
  run: dotnet build --configuration Release
  # Fails on CS1591 if <WarningsAsErrors>CS1591</WarningsAsErrors> is set

- name: Generate DocFX HTML
  run: |
    dotnet tool install -g docfx
    docfx docfx.json

- name: Upload docs
  uses: actions/upload-artifact@v4
  with:
    name: docfx-site
    path: _site/

- name: Deploy to GitHub Pages
  if: github.ref == 'refs/heads/main'
  uses: peaceiris/actions-gh-pages@v4
  with:
    github_token: ${{ secrets.GITHUB_TOKEN }}
    publish_dir: ./_site
```

**Enforce docs in CI via `.editorconfig`:**
```ini
[*.cs]
dotnet_diagnostic.CS1591.severity = warning
```

## Performance

- XML doc generation adds negligible build time — the compiler emits the `.xml` file as a side effect of compilation.
- DocFX HTML generation is the slow step (20-60s for large projects). Run it only on publish branches.
- `<GenerateDocumentationFile>true</GenerateDocumentationFile>` on all projects in a solution can produce many `.xml` files in the output. Use `docfx.json` `exclude` patterns to restrict which projects contribute to the public docs.
- `<InheritDoc>` resolution happens at DocFX processing time, not at compile time — it is fast and does not affect build performance.

## Security

- XML documentation is emitted into the `.xml` file alongside the assembly — it is visible in NuGet packages. Do not include credentials, internal URLs, or debug details in `<remarks>` or `<example>` blocks that ship in the package.
- `<see cref="..."/>` is validated at compile time — broken references are caught before deployment (treat CS1574 as an error).
- The generated HTML by DocFX is static — no runtime security surface.

## Testing

```bash
# Build with docs enabled — fails on CS1591 if configured as error
dotnet build --configuration Release

# Generate DocFX site
docfx docfx.json

# Serve locally and verify
docfx docfx.json --serve
# Opens at http://localhost:8080

# Check for CS1591 warnings without failing build
dotnet build 2>&1 | grep CS1591

# Validate cref references compile
dotnet build --no-restore 2>&1 | grep CS1574
```

## Dos

- Set `<WarningsAsErrors>CS1591</WarningsAsErrors>` in library projects — it enforces that every public API has a `<summary>` before the code can compile.
- Use `<inheritdoc />` on interface implementations to avoid duplicating documentation — DocFX and IDEs resolve the inherited text correctly.
- Use `<see cref=""/>` for all cross-references rather than plain text — they are validated at compile time and rendered as hyperlinks.
- Write `<example>` blocks with `<code>` sub-elements for concrete usage patterns — they appear in the generated docs and IDE Quick Info.
- Document `<exception>` for every exception type that callers should handle — this is the primary discoverability mechanism in a compiled language.
- Enable DocFX with the `modern` template for a responsive layout — the default template has not been updated in years.

## Don'ts

- Don't set `<GenerateDocumentationFile>true</GenerateDocumentationFile>` in test projects — it generates noise for internal test helpers.
- Don't use `<summary>See other class</summary>` — write meaningful summaries; brevity without content is worse than no doc.
- Don't skip `<typeparam>` documentation on generic types — callers need to understand the type constraints and variance contracts.
- Don't rely on Sandcastle for new projects — DocFX is the current Microsoft-maintained successor.
- Don't commit the `_site/` DocFX output directory — regenerate and publish from CI.
- Don't use `<inheritdoc />` when the override meaningfully changes behavior — document the delta explicitly rather than inheriting potentially incorrect descriptions.
