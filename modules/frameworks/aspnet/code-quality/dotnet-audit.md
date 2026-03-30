# ASP.NET Core + dotnet-audit

> Extends `modules/code-quality/dotnet-audit.md` with ASP.NET Core-specific integration.
> Generic dotnet-audit conventions (`dotnet list package --vulnerable`, NuGetAudit setup, Dependabot configuration) are NOT repeated here.

## Integration Setup

Enable `NuGetAudit` in `Directory.Build.props` at the solution root so all ASP.NET Core projects — including test projects — are covered:

```xml
<!-- Directory.Build.props -->
<Project>
  <PropertyGroup>
    <NuGetAudit>true</NuGetAudit>
    <NuGetAuditMode>all</NuGetAuditMode>
    <NuGetAuditLevel>moderate</NuGetAuditLevel>  <!-- lower threshold for auth/crypto packages -->
  </PropertyGroup>
</Project>
```

Use Central Package Management to prevent unreviewed version bumps:

```xml
<!-- Directory.Packages.props -->
<Project>
  <PropertyGroup>
    <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
  </PropertyGroup>
  <ItemGroup>
    <PackageVersion Include="Microsoft.AspNetCore.Authentication.JwtBearer" Version="9.0.0" />
    <PackageVersion Include="Microsoft.EntityFrameworkCore.SqlServer" Version="9.0.0" />
    <PackageVersion Include="Microsoft.AspNetCore.Identity.EntityFrameworkCore" Version="9.0.0" />
  </ItemGroup>
</Project>
```

## Framework-Specific Patterns

### High-priority ASP.NET Core packages

Certain ASP.NET Core packages are direct security attack surfaces — treat their vulnerabilities as CRITICAL regardless of CVSS score:

| Package | Why It's High Priority |
|---|---|
| `Microsoft.AspNetCore.Authentication.*` | Auth middleware — exploits allow authentication bypass |
| `Microsoft.AspNetCore.Identity.*` | Identity system — password hash and token vulnerabilities |
| `Microsoft.EntityFrameworkCore.*` | SQL injection via LINQ-to-SQL translation bugs |
| `System.IdentityModel.Tokens.Jwt` | JWT validation — signature bypass vulnerabilities |
| `Microsoft.AspNetCore.DataProtection` | Data protection keys — exploits expose encrypted data |

For these packages, set `<NuGetAuditLevel>low</NuGetAuditLevel>` project-locally if the solution-wide level is `high`:

```xml
<!-- Auth.csproj or Identity.csproj -->
<PropertyGroup>
  <NuGetAuditLevel>low</NuGetAuditLevel>
</PropertyGroup>
```

### Suppression policy for ASP.NET Core patches

ASP.NET Core releases security patches frequently. When a fix is available, suppress only with a deadline:

```xml
<!-- Suppress only when fix is not yet released and risk is accepted -->
<PropertyGroup>
  <!--
    NU1903: GHSA-xxxx-yyyy-zzzz
    Package: Microsoft.AspNetCore.Authentication.JwtBearer 8.0.x
    Affects: JWT token validation under specific clock-skew conditions
    Mitigated: Custom token validation params override the vulnerable path
    Review by: 2025-03-01
    Tracking: https://github.com/dotnet/aspnetcore/issues/XXXXX
  -->
  <NoWarn>$(NoWarn);NU1903</NoWarn>
</PropertyGroup>
```

### CI gate for ASP.NET Core security

```yaml
- name: Audit NuGet packages (high + critical)
  run: |
    dotnet list MySolution.sln package --vulnerable --include-transitive --format json \
      | tee nuget-audit.json
    # Fail on HIGH+ in auth/JWT/EF packages specifically
    if dotnet list MySolution.sln package --vulnerable --include-transitive 2>&1 \
      | grep -E "(high|critical)" | grep -iE "(identity|authentication|jwt|dataprotection|entityframework)"; then
      echo "High/critical vulnerability in security-critical ASP.NET Core package"
      exit 1
    fi
```

## Additional Dos

- Set `<NuGetAuditLevel>moderate</NuGetAuditLevel>` for `Authentication`, `Identity`, and `DataProtection` projects — moderate CVEs in these packages can become CRITICAL in an HTTP-facing application.
- Use Central Package Management for all `Microsoft.AspNetCore.*` packages — framework packages must be upgraded atomically to avoid partial version mismatches that silently break auth middleware.
- Scan `runtimeClasspath` and `compileClasspath` only — test-only packages do not ship with the application and should not block production deployments.

## Additional Don'ts

- Don't suppress `NU1903`/`NU1904` for `Microsoft.AspNetCore.Authentication.*` without a documented mitigation — authentication bypass vulnerabilities are CRITICAL for any internet-facing service.
- Don't treat `moderate` severity findings in EF Core as low-risk — LINQ-to-SQL translation bugs can produce unexpected query shapes that bypass access control.
- Don't use `<NuGetAuditMode>direct</NuGetAuditMode>` for ASP.NET Core solutions — the framework's transitive dependency graph includes dozens of security-critical packages that are never direct dependencies.
