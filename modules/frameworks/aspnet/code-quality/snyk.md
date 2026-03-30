# ASP.NET Core + Snyk

> Extends `modules/code-quality/snyk.md` with ASP.NET Core-specific integration.
> Generic Snyk conventions (installation, `.snyk` policy file, SARIF output, CI integration) are NOT repeated here.

## Integration Setup

Point Snyk at the solution file for full transitive dependency coverage across all ASP.NET Core projects:

```bash
# Scan all projects in the solution
snyk test --file=MySolution.sln --severity-threshold=high

# Monitor on main branch merges
snyk monitor --file=MySolution.sln --org=my-org --project-name=my-aspnet-service
```

For multi-project solutions, use `--all-projects` to generate a separate Snyk project per `.csproj`:

```bash
snyk test --all-projects --detection-depth=5 --severity-threshold=high
```

## Framework-Specific Patterns

### NuGet-specific Snyk configuration

ASP.NET Core uses NuGet as its package manager. Snyk reads `packages.lock.json` (lockfile mode) or resolves from `*.csproj`/`Directory.Packages.props`:

```bash
# Enable lockfile for deterministic dependency resolution
dotnet restore --use-lock-file

# Snyk resolves the lockfile — more accurate than .csproj scanning
snyk test --file=packages.lock.json
```

Enable NuGet lockfiles in `Directory.Build.props` to ensure Snyk scans the resolved versions, not declared version ranges:

```xml
<PropertyGroup>
  <RestorePackagesWithLockFile>true</RestorePackagesWithLockFile>
</PropertyGroup>
```

### `.snyk` policy for ASP.NET Core false positives

Common ASP.NET Core false positives from Snyk's NuGet scanning:

```yaml
# .snyk
version: v1.25.0
ignore:
  SNYK-DOTNET-MICROSOFTASPNETCOREHTTPCONNECTIONS-XXXXXX:
    - "*":
        reason: "SignalR transport vulnerability — SignalR not used in this service"
        expires: "2026-01-01T00:00:00.000Z"
  SNYK-DOTNET-SYSTEMTEXTJSON-XXXXXX:
    - "*":
        reason: "ReDoS in JSON deserializer — inputs validated upstream before deserialization"
        expires: "2026-01-01T00:00:00.000Z"
patch: {}
```

### Snyk Code (SAST) for ASP.NET Core

Snyk Code detects ASP.NET Core-specific patterns including unvalidated model binding, missing `[Authorize]` on endpoints, and raw SQL in repository methods:

```bash
# SAST scan — requires Snyk Code plan
snyk code test --severity-threshold=high --sarif-file-output=snyk-code.sarif
```

Key Snyk Code rules for ASP.NET Core:
- `CSharp/SqlInjection` — string interpolation in `DbCommand` or `SqlConnection`
- `CSharp/XSS` — unencoded output in Razor views or raw response writes
- `CSharp/InsecureDeserialization` — `JsonConvert.DeserializeObject` with untrusted input
- `CSharp/OpenRedirect` — `Redirect()` calls with unvalidated `returnUrl` parameters

## Additional Dos

- Enable `RestorePackagesWithLockFile=true` in `Directory.Build.props` — Snyk's NuGet scanning is more accurate against a lockfile than against version ranges in `.csproj` files.
- Run `snyk test --all-projects` for monorepo ASP.NET Core solutions — per-project snapshots in the Snyk dashboard make it easier to track which service introduced a vulnerability.
- Scan the container image with `snyk container test` in addition to `snyk test` — ASP.NET Core deployments on `mcr.microsoft.com/dotnet/aspnet` base images can have OS-level vulnerabilities not visible in NuGet scanning.

## Additional Don'ts

- Don't ignore Snyk findings for `Microsoft.AspNetCore.Authentication.*` or `System.IdentityModel.Tokens.Jwt` without a security team sign-off — JWT and auth package vulnerabilities can enable authentication bypass.
- Don't use `snyk test --file=*.csproj` for multi-project solutions without `--all-projects` — single-project scanning misses cross-project transitive dependency paths.
- Don't skip `snyk code test` for controller files handling user input — SAST catches ASP.NET-specific injection patterns that dependency scanning cannot detect.
