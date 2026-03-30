# Jetpack Compose + OWASP Dependency-Check

> Extends `modules/code-quality/owasp-dependency-check.md` with Jetpack Compose-specific integration.
> Generic OWASP Dependency-Check conventions are NOT repeated here.

## Integration Setup

```kotlin
// build.gradle.kts
plugins {
    id("org.owasp.dependencycheck") version "9.0.9"
}

dependencyCheck {
    failBuildOnCVSS = 7.0f
    format = "ALL"
    suppressionFile = "config/owasp-suppressions.xml"
    nvd {
        apiKey = System.getenv("NVD_API_KEY") ?: ""
        delay = 4000
    }
    analyzers {
        // Android projects don't use .NET or Ruby
        assemblyEnabled = false
        nuspecEnabled = false
        rubygemsEnabled = false
        // Enable AAR scanning — Android Archive files contain dependencies
        experimentalEnabled = true
    }
    // Scan all Android configurations
    scanConfigurations = listOf(
        "releaseRuntimeClasspath",
        "debugRuntimeClasspath"
    )
}
```

## Framework-Specific Patterns

### Android-Specific Dependency Configurations

Android builds have multiple configurations (`debugRuntimeClasspath`, `releaseRuntimeClasspath`, `androidTestRuntimeClasspath`). Scan at minimum the `releaseRuntimeClasspath` — this is what ships:

```kotlin
dependencyCheck {
    // Focus on production release dependencies
    scanConfigurations = listOf("releaseRuntimeClasspath")
    // Exclude test-only configurations from the CVSS threshold
    skipConfigurations = listOf(
        "androidTestRuntimeClasspath",
        "testRuntimeClasspath"
    )
}
```

### Common Suppressions for Android/Compose

Several transitive Jetpack dependencies generate false positives against unrelated CVEs. Suppress with justification:

```xml
<!-- config/owasp-suppressions.xml -->
<suppressions>
  <!-- androidx.* CVEs matched by CPE to unrelated Apache projects -->
  <suppress>
    <notes>False positive — CPE match against Apache Commons, not Android core.</notes>
    <packageUrl regex="true">^pkg:maven/androidx\..*$</packageUrl>
    <cve>CVE-2021-XXXXX</cve>
  </suppress>
</suppressions>
```

### AAR and Transitive Dependency Scanning

Jetpack Compose pulls in a large transitive graph. Enable `experimentalEnabled = true` to scan AARs (Android Archive files), not just JARs — Compose dependencies are distributed as AARs.

### CI Integration

Run dependency check weekly (not on every PR) and separately from unit tests:

```yaml
# .github/workflows/security.yml
on:
  schedule:
    - cron: "0 6 * * 1"   # Monday 06:00 UTC
  workflow_dispatch:

jobs:
  dependency-check:
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with: { java-version: "17", distribution: temurin }
      - name: Cache NVD database
        uses: actions/cache@v4
        with:
          path: ~/.gradle/dependency-check-data
          key: nvd-${{ github.run_id }}
          restore-keys: nvd-
      - name: OWASP Dependency Check
        env:
          NVD_API_KEY: ${{ secrets.NVD_API_KEY }}
        run: ./gradlew dependencyCheckAnalyze --no-daemon
      - name: Upload report
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: dependency-check-report
          path: build/reports/dependency-check-report.*
```

## Additional Dos

- Cache `~/.gradle/dependency-check-data` in CI — the NVD database download is 200+ MB and takes 5+ minutes without a cache.
- Set `NVD_API_KEY` as a CI secret — unauthenticated NVD API calls are heavily rate-limited.
- Scan `releaseRuntimeClasspath` as the primary target — it represents what ships to users.
- Review Compose and AndroidX transitive dependencies specifically — the large dependency graph increases CVE exposure surface.

## Additional Don'ts

- Don't run dependency check on every PR — the NVD database download makes it impractical for fast feedback.
- Don't suppress CVEs without a `<notes>` element explaining the justification and a review date.
- Don't use `assemblyEnabled = true` on Android-only projects — it adds overhead with no benefit.
- Don't skip `androidTestRuntimeClasspath` entirely from scanning — test dependencies can be exploited in CI/CD attack vectors.
