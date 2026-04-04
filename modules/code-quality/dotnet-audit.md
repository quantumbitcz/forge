---
name: dotnet-audit
categories: [security-scanner]
languages: [csharp]
exclusive_group: none
recommendation_score: 90
detection_files: [*.csproj, global.json]
---

# dotnet-audit

## Overview

`dotnet list package --vulnerable` is the built-in .NET CLI command for scanning NuGet dependencies against the NuGet vulnerability database (sourced from GitHub Advisory Database and OSV). It requires no additional installation — available in .NET 5+ SDK. Use `--include-transitive` to scan the full dependency graph including indirect dependencies. Suppress known false positives with `<NoWarn>` in `.csproj` files (documented with justification). Pair with Dependabot or Renovate for automated patch PRs.

## Architecture Patterns

### Installation & Setup

Built into the .NET SDK — no additional packages required:

```bash
# Scan direct dependencies only
dotnet list package --vulnerable

# Scan direct + transitive (recommended)
dotnet list package --vulnerable --include-transitive

# Scan in JSON format for machine parsing
dotnet list package --vulnerable --include-transitive --format json

# For a specific project file
dotnet list MyProject/MyProject.csproj package --vulnerable --include-transitive

# For a solution (scans all projects)
dotnet list MySolution.sln package --vulnerable --include-transitive
```

**`Directory.Build.props` for audit enforcement across all projects:**
```xml
<!-- Directory.Build.props (solution root) -->
<Project>
  <PropertyGroup>
    <!-- Fail restore if any package with known vulnerability is used -->
    <NuGetAudit>true</NuGetAudit>
    <NuGetAuditMode>all</NuGetAuditMode>       <!-- direct | all -->
    <NuGetAuditLevel>high</NuGetAuditLevel>    <!-- low | moderate | high | critical -->
  </PropertyGroup>
</Project>
```

With `<NuGetAudit>true</NuGetAudit>`, `dotnet restore` will print warnings for vulnerable packages. Set `<NuGetAuditMode>all</NuGetAuditMode>` to include transitive dependencies.

### Rule Categories

| Severity | CVSS Range | NuGetAuditLevel | Pipeline Severity |
|---|---|---|---|
| critical | 9.0–10.0 | critical | CRITICAL |
| high | 7.0–8.9 | high | CRITICAL |
| moderate | 4.0–6.9 | moderate | WARNING |
| low | 0.1–3.9 | low | INFO |

### Configuration Patterns

**Suppressing known false positives with `<NoWarn>` (add to `.csproj`):**
```xml
<!-- MyProject.csproj -->
<PropertyGroup>
  <!--
    NU1903: Suppress audit warning for GHSA-xxxx-yyyy-zzzz
    Reason: Only affects Windows desktop targets; this project targets Linux.
    Review by: 2025-06-01
    Tracking: https://github.com/org/repo/issues/1234
  -->
  <NoWarn>$(NoWarn);NU1903</NoWarn>
</PropertyGroup>
```

Note: `NU1900`-`NU1904` are NuGet audit warning codes. Use specific codes rather than suppressing all `NU1900+` warnings.

**Central Package Management (CPM) with vulnerability scanning:**
```xml
<!-- Directory.Packages.props -->
<Project>
  <PropertyGroup>
    <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
    <NuGetAudit>true</NuGetAudit>
    <NuGetAuditMode>all</NuGetAuditMode>
    <NuGetAuditLevel>high</NuGetAuditLevel>
  </PropertyGroup>
  <ItemGroup>
    <!-- Pin versions centrally to prevent unaudited upgrades -->
    <PackageVersion Include="Microsoft.AspNetCore.Authentication.JwtBearer" Version="8.0.5" />
  </ItemGroup>
</Project>
```

### CI Integration

```yaml
# .github/workflows/security.yml
- name: Setup .NET
  uses: actions/setup-dotnet@v4
  with:
    dotnet-version: "8.x"

- name: Restore packages
  run: dotnet restore

- name: Check for vulnerable packages (high + critical)
  run: |
    dotnet list package --vulnerable --include-transitive --format json > nuget-audit.json
    cat nuget-audit.json
    # Fail if any high/critical advisories found
    if dotnet list package --vulnerable --include-transitive 2>&1 | grep -E "(high|critical)"; then
      echo "High or critical vulnerabilities found"
      exit 1
    fi

- name: Upload vulnerability report
  if: always()
  uses: actions/upload-artifact@v4
  with:
    name: nuget-audit-report
    path: nuget-audit.json
```

**Using `dotnet-outdated` for outdated package detection (complement to vulnerability scanning):**
```bash
dotnet tool install --global dotnet-outdated-tool
dotnet outdated --include-auto-referenced
```

**GitHub Dependabot configuration (`.github/dependabot.yml`):**
```yaml
version: 2
updates:
  - package-ecosystem: "nuget"
    directory: "/"
    schedule:
      interval: "weekly"
    open-pull-requests-limit: 10
    reviewers:
      - "security-team"
```

## Performance

- `dotnet list package --vulnerable` requires a network call to the NuGet vulnerability endpoint — takes 3-8 seconds depending on the number of packages and network latency.
- `--include-transitive` increases scan time proportionally to the transitive dependency graph size — large .NET solutions with hundreds of transitive deps may take 15-30 seconds.
- `dotnet restore` caches packages in `~/.nuget/packages` — cache this directory in CI to speed up both restore and audit. The NuGet vulnerability database is fetched separately.
- For solutions with many projects, run the audit at the solution level (`dotnet list MySolution.sln package --vulnerable`) rather than per-project to get a consolidated report.

## Security

- `<NuGetAudit>true</NuGetAudit>` in `Directory.Build.props` ensures `dotnet restore` itself warns on vulnerable packages — developers see security warnings during development, not only in CI.
- Every `<NoWarn>` suppression targeting NuGet audit codes must include a comment with: the advisory ID, justification, review date, and a tracking issue link.
- Prioritize fixing transitive vulnerabilities in core infrastructure packages (ASP.NET Core, Entity Framework Core, JWT libraries) — these are high-impact attack surfaces.
- For .NET Framework projects (not .NET Core/5+), `dotnet list package --vulnerable` is not available — use OWASP Dependency-Check or Snyk as alternatives.
- Enable `<NuGetAuditMode>all</NuGetAuditMode>` — direct-only auditing misses the majority of vulnerabilities which are in transitive dependencies.

## Testing

```bash
# Scan direct dependencies
dotnet list package --vulnerable

# Scan all dependencies (recommended)
dotnet list package --vulnerable --include-transitive

# JSON format for programmatic processing
dotnet list package --vulnerable --include-transitive --format json

# Scan specific project
dotnet list src/Api/Api.csproj package --vulnerable --include-transitive

# Scan solution
dotnet list MyApp.sln package --vulnerable --include-transitive

# Check NuGetAudit is enabled via restore
dotnet restore --verbosity normal 2>&1 | grep -i "vulnerab"

# Verify outdated packages
dotnet outdated
```

## Dos

- Enable `<NuGetAudit>true</NuGetAudit>` in `Directory.Build.props` — it integrates vulnerability scanning into the restore step so developers see warnings during development.
- Always use `--include-transitive` — the majority of vulnerabilities are in transitive dependencies, not direct ones.
- Set `<NuGetAuditLevel>high</NuGetAuditLevel>` in `Directory.Build.props` to fail restores on high/critical vulnerabilities in development and CI.
- Document every `<NoWarn>` suppression with advisory ID, justification, and a review date in a comment — suppressions without context are a future audit liability.
- Use Central Package Management (`Directory.Packages.props`) to pin all package versions — it prevents silent transitive upgrades that could introduce new vulnerabilities.

## Don'ts

- Don't use `<NoWarn>NU1900</NoWarn>` (blanket suppression of all audit warnings) — suppress only specific advisory codes (`NU1901`-`NU1904`) with justification.
- Don't skip `--include-transitive` in CI — direct-only scanning misses the majority of real-world vulnerabilities.
- Don't rely solely on `dotnet list package --vulnerable` for .NET Framework projects — it requires .NET 5+ SDK. Use OWASP Dependency-Check as a fallback.
- Don't ignore `moderate` severity findings in ASP.NET applications handling authentication or authorization — moderate-severity CVEs in security middleware can be critical.
- Don't use `dotnet restore` with `--no-dependencies` in CI security scans — it skips dependency resolution and prevents vulnerability detection.
- Don't disable Dependabot/Renovate auto-update PRs — automated dependency updates are the most reliable way to stay ahead of known vulnerabilities.
