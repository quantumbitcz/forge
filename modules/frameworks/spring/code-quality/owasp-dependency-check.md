# Spring + OWASP Dependency Check

> Extends `modules/code-quality/owasp-dependency-check.md` with Spring Boot-specific integration.
> Generic OWASP Dependency Check conventions (installation, NVD feed, CVSS thresholds, CI integration) are NOT repeated here.

## Integration Setup

Wire dependency-check into the Spring Boot Gradle build. The Spring Boot BOM centralizes versions — scan the resolved classpath, not the BOM entries:

```kotlin
// build.gradle.kts
plugins {
    id("org.owasp.dependencycheck") version "10.0.4"
}

dependencyCheck {
    failBuildOnCVSS = 7.0f          // fail on HIGH+ vulnerabilities
    formats = listOf("HTML", "JSON")
    outputDirectory = "$buildDir/reports/dependency-check"
    suppressionFile = "$rootDir/config/dependency-check-suppressions.xml"
    scanConfigurations = listOf(     // only scan runtime dependencies
        "runtimeClasspath",
        "compileClasspath"
    )
    nvd {
        apiKey = System.getenv("NVD_API_KEY") ?: ""
        delay = 4000
    }
}
```

## Framework-Specific Patterns

### BOM handling

Spring Boot BOM manages hundreds of transitive dependencies. Dependency Check resolves the full classpath — it correctly scans all BOM-managed versions. No special BOM configuration is needed, but pin the Spring Boot version precisely to get accurate CVE matches:

```kotlin
// settings.gradle.kts
pluginManagement {
    plugins {
        id("org.springframework.boot") version "3.3.4"  // pin exact, not range
    }
}
```

CVE false positives from the BOM's `spring-boot-dependencies` artifact itself (not your code) can be suppressed:

```xml
<!-- config/dependency-check-suppressions.xml -->
<suppressions>
  <!-- spring-boot-dependencies BOM is a POM-only artifact; the CVE is on a specific starter -->
  <suppress>
    <notes>BOM artifact, not a runtime dependency</notes>
    <gav regex="true">^org\.springframework\.boot:spring-boot-dependencies:.*$</gav>
    <cpe>cpe:/a:pivotal_software:spring_framework</cpe>
  </suppress>
</suppressions>
```

### Exclude test-scope dependencies

Spring Boot test starters (`spring-boot-starter-test`, `testcontainers`, `mockito-core`) are test-only. Exclude test configurations from the scan to avoid false positives and noise:

```kotlin
dependencyCheck {
    scanConfigurations = listOf("runtimeClasspath", "compileClasspath")
    // Omit: testRuntimeClasspath, testCompileClasspath
}
```

### False positive suppressions for Spring libraries

Common Spring-adjacent false positives from NVD's CPE matching:

```xml
<suppressions>
  <!-- Tomcat embedded in Spring Boot — different CPE than standalone Tomcat -->
  <suppress until="2025-12-31Z">
    <notes>Embedded Tomcat 10.x — tracked, not exploitable via Spring Boot's embedded setup</notes>
    <gav regex="true">^org\.apache\.tomcat\.embed:.*:10\.\d+\.\d+$</gav>
    <cvssBelow>7</cvssBelow>
  </suppress>

  <!-- netty-tcnative — transitive via Spring WebFlux Netty; not directly exposed -->
  <suppress>
    <notes>Native transport not configured — CVE requires native SSL usage</notes>
    <packageUrl regex="true">^pkg:maven/io\.netty/netty-tcnative.*$</packageUrl>
    <cve>CVE-2023-XXXX</cve>
  </suppress>
</suppressions>
```

Always include a `until` date on CVSS-based suppressions to force periodic review.

## Additional Dos

- Scope scans to `runtimeClasspath` and `compileClasspath` only — test dependencies should not block production deployments.
- Add `until` dates to all suppressions — Spring releases patch versions frequently; re-evaluate suppressions each minor release.
- Store `NVD_API_KEY` in CI secrets; NVD rate-limits unauthenticated requests heavily.

## Additional Don'ts

- Don't suppress findings by `cpe` alone without a `notes` element — suppressions without rationale are ignored during security reviews.
- Don't use CVSS threshold below 7.0 for Spring Boot services that handle untrusted input — accept some noise rather than ship with HIGH vulnerabilities.
- Don't skip the scan in CI for cost/speed — cache the NVD feed (`data/` directory) across runs to keep scan time under 60 seconds.
