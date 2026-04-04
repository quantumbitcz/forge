---
name: coverlet
categories: [coverage]
languages: [csharp]
exclusive_group: csharp-coverage
recommendation_score: 90
detection_files: [*.csproj, coverlet.runsettings]
---

# coverlet

## Overview

Coverlet is the cross-platform .NET coverage tool available as a VSTest data collector (`coverlet.collector`) or a standalone global tool (`coverlet.console`). The collector approach integrates cleanly with `dotnet test --collect:"XPlat Code Coverage"` and generates Cobertura XML or LCOV. Use `--threshold 80` to fail the build when coverage drops. For multi-project solutions, use `ReportGenerator` to merge Cobertura reports from multiple test projects into a single view. Coverlet supports line, branch, and method coverage metrics.

## Architecture Patterns

### Installation & Setup

**Collector (recommended — integrated with `dotnet test`):**
```bash
# Add to test project
dotnet add package coverlet.collector
```

```xml
<!-- MyApp.Tests/MyApp.Tests.csproj -->
<ItemGroup>
  <PackageReference Include="coverlet.collector" Version="6.*" />
  <PackageReference Include="Microsoft.NET.Test.Sdk" Version="17.*" />
</ItemGroup>
```

```bash
# Run tests with Cobertura output
dotnet test \
  --collect:"XPlat Code Coverage" \
  --results-directory ./coverage \
  -- DataCollectionRunSettings.DataCollectors.DataCollector.Configuration.Format=cobertura

# Run with threshold (fail if below 80%)
dotnet test \
  --collect:"XPlat Code Coverage" \
  --results-directory ./coverage \
  -- DataCollectionRunSettings.DataCollectors.DataCollector.Configuration.Format=cobertura \
     DataCollectionRunSettings.DataCollectors.DataCollector.Configuration.Threshold=80 \
     DataCollectionRunSettings.DataCollectors.DataCollector.Configuration.ThresholdType=line \
     DataCollectionRunSettings.DataCollectors.DataCollector.Configuration.ThresholdStat=total
```

**Global tool (standalone CLI):**
```bash
dotnet tool install --global coverlet.console
```

```bash
coverlet ./MyApp.Tests/bin/Debug/net8.0/MyApp.Tests.dll \
  --target "dotnet" \
  --targetargs "test MyApp.Tests --no-build" \
  --format cobertura \
  --output coverage/ \
  --threshold 80 \
  --threshold-type line \
  --exclude "[*]MyApp.Migrations*" \
  --exclude "[*]MyApp.Generated*"
```

**`coverlet.runsettings` file (collector config):**
```xml
<?xml version="1.0" encoding="utf-8"?>
<RunSettings>
  <DataCollectionRunSettings>
    <DataCollectors>
      <DataCollector friendlyName="XPlat Code Coverage">
        <Configuration>
          <Format>cobertura,lcov</Format>
          <Exclude>[*]*.Migrations.*,[*]*.Generated.*,[*]*.g.cs</Exclude>
          <ExcludeByFile>**/*.g.cs,**/Migrations/**</ExcludeByFile>
          <ExcludeByAttribute>GeneratedCode,CompilerGeneratedAttribute,ExcludeFromCodeCoverage</ExcludeByAttribute>
          <IncludeTestAssembly>false</IncludeTestAssembly>
          <SingleHit>false</SingleHit>
          <UseSourceLink>true</UseSourceLink>
          <Threshold>80</Threshold>
          <ThresholdType>line</ThresholdType>
          <ThresholdStat>total</ThresholdStat>
        </Configuration>
      </DataCollector>
    </DataCollectors>
  </DataCollectionRunSettings>
</RunSettings>
```

```bash
dotnet test --settings coverlet.runsettings --results-directory ./coverage
```

### Rule Categories

| Metric | `ThresholdType` value | Notes |
|---|---|---|
| Line coverage | `line` | Source lines executed |
| Branch coverage | `branch` | True/false branches |
| Method coverage | `method` | Methods entered |
| Threshold scope | `ThresholdStat` | `total`, `average`, or `minimum` |

### Configuration Patterns

**Multi-project solution with ReportGenerator:**
```bash
# Run tests for all test projects
dotnet test MySolution.sln \
  --collect:"XPlat Code Coverage" \
  --results-directory ./coverage \
  --settings coverlet.runsettings

# Merge all Cobertura XMLs into one report
dotnet tool install --global dotnet-reportgenerator-globaltool

reportgenerator \
  -reports:"coverage/**/coverage.cobertura.xml" \
  -targetdir:"coverage/report" \
  -reporttypes:"Html;Cobertura;lcov" \
  -classfilters:"-*.Migrations.*;-*.Generated.*"

open coverage/report/index.html
```

**Excluding via `[ExcludeFromCodeCoverage]` attribute:**
```csharp
using System.Diagnostics.CodeAnalysis;

[ExcludeFromCodeCoverage]
public class ApplicationDbContextFactory : IDesignTimeDbContextFactory<ApplicationDbContext>
{
    // EF Core scaffold helpers — not unit testable
}
```

**Threshold enforcement per metric:**
```bash
coverlet ./tests/bin/Debug/net8.0/Tests.dll \
  --target dotnet --targetargs "test --no-build" \
  --threshold 80 --threshold-type line \
  --threshold 70 --threshold-type branch \
  --threshold 85 --threshold-type method \
  --format cobertura --output ./coverage/
```

### CI Integration

```yaml
# .github/workflows/test.yml
- name: Run tests with coverage
  run: |
    dotnet test --settings coverlet.runsettings --results-directory ./coverage

- name: Generate combined report
  run: |
    dotnet tool install --global dotnet-reportgenerator-globaltool
    reportgenerator \
      -reports:"coverage/**/coverage.cobertura.xml" \
      -targetdir:"coverage/report" \
      -reporttypes:"Cobertura;lcov"

- name: Upload to Codecov
  uses: codecov/codecov-action@v4
  with:
    files: coverage/report/lcov.info
    fail_ci_if_error: true

- name: Upload HTML report
  if: always()
  uses: actions/upload-artifact@v4
  with:
    name: coverage-report
    path: coverage/report/
```

## Performance

- The VSTest collector (`coverlet.collector`) has lower startup overhead than the global tool — prefer it for standard `dotnet test` workflows.
- `dotnet test` generates a new `coverage.cobertura.xml` per test project per run — use `ReportGenerator` to merge them rather than processing multiple XML files in CI.
- Coverage instrumentation adds 10-30% to test execution time — disable for unit test runs during local development, enable only for CI or pre-merge.
- `--threshold` check in the coverlet CLI adds negligible time but fails fast — useful to short-circuit CI before generating HTML reports.
- Use `--no-build` with the global tool CLI when tests are already built to skip redundant compilation.

## Security

- `coverage.cobertura.xml` contains file paths and line counts — safe as CI artifact.
- `[ExcludeFromCodeCoverage]` should not be used to hide security-critical code from coverage — only use for generated or infrastructure classes.
- ReportGenerator HTML embeds source code — do not publish reports publicly for proprietary applications.

## Testing

```bash
# Run with collector
dotnet test --collect:"XPlat Code Coverage" --results-directory ./coverage

# Run with settings file
dotnet test --settings coverlet.runsettings --results-directory ./coverage

# Global tool
coverlet ./tests/bin/Debug/net8.0/Tests.dll \
  --target dotnet --targetargs "test --no-build" \
  --format cobertura --threshold 80

# Generate HTML with ReportGenerator
reportgenerator -reports:"coverage/**/coverage.cobertura.xml" \
  -targetdir:"coverage/html" -reporttypes:Html
open coverage/html/index.html

# Print summary from Cobertura XML
python3 -c "
import xml.etree.ElementTree as ET
tree = ET.parse('coverage/report/Cobertura.xml')
root = tree.getroot()
print(f'Line rate: {float(root.attrib[\"line-rate\"]) * 100:.1f}%')
"
```

## Dos

- Use `coverlet.runsettings` XML file for complex exclusion rules — it is version-controlled and consistent across local and CI runs.
- Use `[ExcludeFromCodeCoverage]` on generated classes, scaffold helpers, and EF migration scaffolds — attribute-based exclusion is cleaner than glob patterns.
- Use `ReportGenerator` to merge Cobertura XMLs from multiple test projects — multi-project solutions need aggregate coverage, not per-project silos.
- Set both `line` and `branch` thresholds — line coverage alone misses untaken conditional paths.
- Use `UseSourceLink=true` in collector configuration for cloud-hosted repos to produce clickable source links in HTML reports.
- Pin `coverlet.collector` version in `csproj` — patch releases occasionally change threshold behavior.

## Don'ts

- Don't use `IncludeTestAssembly=true` — test assembly code is not production code and inflates coverage numbers.
- Don't skip `[ExcludeFromCodeCoverage]` on EF Core migrations — they are auto-generated and untestable without a live database.
- Don't rely on the Cobertura report path being stable across dotnet versions — the GUID-based subdirectory changes per run; use `coverage/**/coverage.cobertura.xml` glob in ReportGenerator.
- Don't set `ThresholdStat=minimum` for large solutions — one poorly covered test project will always fail the build. Use `total` for the solution-wide threshold.
- Don't add coverage-generated directories (`coverage/`, `TestResults/`) to version control — they change on every run.
