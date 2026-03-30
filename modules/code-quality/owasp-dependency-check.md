# owasp-dependency-check

## Overview

OWASP Dependency-Check scans JVM and multi-language project dependencies against the NVD (National Vulnerability Database) and other sources to identify known CVEs. It runs as a Gradle plugin (`org.owasp.dependencycheck`), Maven plugin, CLI, or Ant task. The scanner downloads and caches the NVD data feed locally — the first run takes several minutes; subsequent runs use the cached database. Use `failBuildOnCVSS: 7` to fail builds on high/critical vulnerabilities while allowing informational and medium findings through. Generate CycloneDX SBOM alongside the vulnerability report for supply chain compliance.

## Architecture Patterns

### Installation & Setup

**Gradle (build.gradle.kts):**
```kotlin
plugins {
    id("org.owasp.dependencycheck") version "9.0.9"
}

dependencyCheck {
    failBuildOnCVSS = 7.0f
    format = "ALL"   // HTML + JSON + XML + SARIF + CSV
    suppressionFile = "config/owasp-suppressions.xml"
    nvd {
        apiKey = System.getenv("NVD_API_KEY") ?: ""
        delay = 4000   // ms between NVD API requests (rate limiting)
    }
    analyzers {
        assemblyEnabled = false   // disable if .NET assembly analysis not needed
        nuspecEnabled = false
    }
}
```

**Maven (pom.xml):**
```xml
<plugin>
  <groupId>org.owasp</groupId>
  <artifactId>dependency-check-maven</artifactId>
  <version>9.0.9</version>
  <configuration>
    <failBuildOnCVSS>7</failBuildOnCVSS>
    <suppressionFile>config/owasp-suppressions.xml</suppressionFile>
    <nvdApiKey>${env.NVD_API_KEY}</nvdApiKey>
    <formats>HTML,JSON,SARIF</formats>
  </configuration>
  <executions>
    <execution>
      <goals><goal>check</goal></goals>
    </execution>
  </executions>
</plugin>
```

### Rule Categories

| Category | Description | Pipeline Severity |
|---|---|---|
| CVSS >= 9.0 | Critical vulnerabilities | CRITICAL |
| CVSS 7.0–8.9 | High vulnerabilities (build-fail threshold) | CRITICAL |
| CVSS 4.0–6.9 | Medium vulnerabilities | WARNING |
| CVSS < 4.0 | Low / informational CVEs | INFO |
| False positives | Suppressed with justification | SCOUT-* |

### Configuration Patterns

**Suppression file (`config/owasp-suppressions.xml`):**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<suppressions xmlns="https://jeremylong.github.io/DependencyCheck/dependency-suppression.1.3.xsd">
  <!-- Suppress false positive: CVE affects different artifact with same name -->
  <suppress until="2025-12-31Z">
    <notes>False positive — CVE-2023-12345 applies to org.example:other-lib, not this artifact</notes>
    <packageUrl regex="true">^pkg:maven/com\.example/my-lib@.*$</packageUrl>
    <cve>CVE-2023-12345</cve>
  </suppress>
</suppressions>
```

**CycloneDX SBOM generation (add alongside OWASP):**
```kotlin
// build.gradle.kts — requires org.cyclonedx.bom plugin
plugins {
    id("org.cyclonedx.bom") version "1.8.2"
}

tasks.cyclonedxBom {
    setIncludeConfigs(listOf("runtimeClasspath"))
    setSchemaVersion("1.5")
    setDestination(project.file("build/reports/sbom"))
    setOutputName("bom")
    setOutputFormat("json")
}
```

### CI Integration

```yaml
# .github/workflows/security.yml
- name: OWASP Dependency-Check
  env:
    NVD_API_KEY: ${{ secrets.NVD_API_KEY }}
  run: ./gradlew dependencyCheckAnalyze

- name: Cache NVD database
  uses: actions/cache@v4
  with:
    path: ~/.gradle/dependency-check-data
    key: nvd-data-${{ hashFiles('**/build.gradle.kts') }}
    restore-keys: nvd-data-

- name: Upload SARIF to GitHub Security tab
  if: always()
  uses: github/codeql-action/upload-sarif@v3
  with:
    sarif_file: build/reports/dependency-check-report.sarif
    category: owasp-dependency-check
```

Register for a free NVD API key at https://nvd.nist.gov/developers/request-an-api-key to avoid rate limiting (50 req/30s without key vs. 100 req/30s with key). Without a key, the NVD update downloads may take 20-60 minutes.

## Performance

- Cache `~/.gradle/dependency-check-data` (or `~/.m2/repository/org/owasp`) in CI to avoid re-downloading the NVD database on every run. The database is ~200MB and updates take 5-15 minutes cold.
- Set `nvd.delay = 4000` to stay within NVD API rate limits with an API key; `6000` without a key.
- Run `dependencyCheckAnalyze` as a separate CI job from compilation and unit tests — it adds 2-5 minutes even with a warm cache.
- Use `--configuration runtimeClasspath` to scan only production dependencies; exclude `testImplementation` scope to reduce noise.
- The `assemblyEnabled` analyzer requires Mono on Linux — disable it in JVM-only projects to avoid false negatives from missing the analyzer.

## Security

- Store `NVD_API_KEY` as a CI secret, never in source code or `gradle.properties` committed to the repository.
- Review all suppressions during PR review — each suppression must include a `notes` field explaining the justification and an `until` expiry date.
- Set `failBuildOnCVSS = 7.0` as a minimum; consider `6.0` for security-sensitive services handling PII or financial data.
- Run dependency-check on the final assembled artifact (fat JAR, Docker image layer) in addition to source-level scanning — transitive dependencies added during packaging may be missed.
- Combine with `dependencyUpdates` (Gradle Versions Plugin) to identify outdated dependencies beyond known CVEs.
- Review the generated SBOM (CycloneDX JSON) before each release and store it as a release artifact for compliance.

## Testing

```bash
# Gradle: run the check
./gradlew dependencyCheckAnalyze

# Update NVD database without analyzing
./gradlew dependencyCheckUpdate

# Purge stale local database and re-download
./gradlew dependencyCheckPurge dependencyCheckUpdate

# Maven equivalent
mvn dependency-check:check
mvn dependency-check:update-only

# Generate SBOM (with cyclonedx plugin)
./gradlew cyclonedxBom
```

## Dos

- Pin the plugin version (`9.0.9`) and review changelogs on upgrade — NVD feed format changes have broken older plugin versions.
- Set `failBuildOnCVSS = 7.0` in Gradle/Maven config and enforce it in CI — a suppression file tracks accepted risks explicitly.
- Register an NVD API key and store it as a CI secret to avoid 503 errors during NVD database updates.
- Include an `until` expiry date on every suppression entry — suppressions without expiry become permanent blind spots.
- Cache the NVD database between CI runs — cold runs without cache block PRs for 10+ minutes.
- Generate a CycloneDX SBOM and attach it to release artifacts for supply chain transparency and compliance (SOC 2, FedRAMP).

## Don'ts

- Don't suppress CVEs without a `notes` justification and an `until` date — vague suppressions make audits impossible.
- Don't run dependency-check without an NVD API key in CI environments — unauthenticated requests are heavily rate-limited and frequently fail.
- Don't set `failBuildOnCVSS` above 9.0 — that would only block critical CVEs and miss the majority of exploitable high-severity findings.
- Don't disable the analyzer for a dependency type (e.g., `retireJsEnabled = false`) without a documented reason — disabling analyzers creates blind spots.
- Don't skip the `dependencyCheckAnalyze` step on release branches — these are the highest-risk builds.
- Don't rely solely on OWASP Dependency-Check for container image scanning — pair with Trivy or Snyk container scanning for OS-level packages.
