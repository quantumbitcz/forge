# Spring + SpotBugs

> Extends `modules/code-quality/spotbugs.md` with Spring Boot-specific integration.
> Generic SpotBugs conventions (installation, rule categories, effort/confidence levels, CI integration) are NOT repeated here.

## Integration Setup

Add FindSecBugs for Spring Security analysis alongside the base plugin:

```kotlin
// build.gradle.kts
dependencies {
    spotbugsPlugins("com.h3xstream.findsecbugs:findsecbugs-plugin:1.13.0")
}

spotbugs {
    excludeFilter.set(file("$rootDir/config/spotbugs/spotbugs-exclude.xml"))
}
```

## Framework-Specific Patterns

### Suppress `EI_EXPOSE_REP` for `@Value`-injected DTOs

Spring's `@Value` injects into fields that SpotBugs flags as `EI_EXPOSE_REP` when they are collections or arrays. Suppress at the filter level rather than per-class:

```xml
<!-- config/spotbugs/spotbugs-exclude.xml -->
<FindBugsFilter>
  <!-- @Value-injected fields are framework-managed — mutable exposure is intentional -->
  <Match>
    <Bug pattern="EI_EXPOSE_REP,EI_EXPOSE_REP2"/>
    <Class name="~.*Properties"/>
  </Match>

  <!-- Spring CGLIB proxies generate synthetic accessor methods -->
  <Match>
    <Bug pattern="UWF_UNWRITTEN_FIELD,NP_UNWRITTEN_FIELD"/>
    <Class name="~.*\$\$SpringCGLIB\$\$.*"/>
  </Match>
  <Match>
    <Bug pattern="UWF_UNWRITTEN_FIELD,NP_UNWRITTEN_FIELD"/>
    <Class name="~.*\$\$EnhancerBySpringCGLIB\$\$.*"/>
  </Match>

  <!-- Spring Data proxy implementations -->
  <Match>
    <Bug pattern="SE_NO_SERIALVERSIONID"/>
    <Class name="~.*Repository.*"/>
  </Match>
</FindBugsFilter>
```

### Exclude proxy classes from analysis

Spring generates CGLIB subclasses at runtime for `@Configuration`, `@Transactional`, and `@Async` beans. Exclude them from SpotBugs source sets:

```kotlin
tasks.withType<SpotBugsTask>().configureEach {
    classes = fileTree("$buildDir/classes/kotlin/main") {
        exclude("**/*\$\$SpringCGLIB\$\$*.class")
        exclude("**/*\$\$EnhancerBySpringCGLIB\$\$*.class")
        exclude("**/generated/**")
    }
}
```

### FindSecBugs for Spring Security

FindSecBugs adds Spring Security-specific detectors. Key patterns to enforce:

| Bug Pattern | What It Catches | Severity |
|---|---|---|
| `SPRING_CSRF_UNRESTRICTED_REQUEST_MAPPING` | `@RequestMapping` without method restriction — allows CSRF | CRITICAL |
| `PERMISSIVE_CORS` | `allowedOrigins("*")` in production `CorsConfiguration` | CRITICAL |
| `HARD_CODE_PASSWORD` | Hardcoded credentials in `@Value` defaults or config classes | CRITICAL |
| `SQL_INJECTION_SPRING_JDBC` | String-concatenated SQL in `JdbcTemplate` queries | CRITICAL |

Enable all FindSecBugs categories:

```kotlin
spotbugs {
    effort.set(Effort.MAX)
    reportLevel.set(Confidence.LOW)  // catch all FindSecBugs findings
}
```

## Additional Dos

- Exclude `**/*$$SpringCGLIB$$*.class` and `**/*$$EnhancerBySpringCGLIB$$*.class` — proxy classes are generated, not authored.
- Use `EI_EXPOSE_REP` suppression only for `*Properties` classes — not blanket DTOs.
- Enable FindSecBugs at `Confidence.LOW` — Spring Security misconfigurations are high-impact and worth the extra noise.

## Additional Don'ts

- Don't suppress `NP_NULL_ON_SOME_PATH` globally — Spring-injected fields can be null before context initialization; constructor injection eliminates this class of bug.
- Don't exclude `**/service/**` or `**/usecase/**` from SpotBugs — these contain business logic where null pointer and synchronization bugs are most costly.
- Don't skip SpotBugs for Kotlin-only modules — SpotBugs analyzes compiled bytecode, not source; Kotlin compiles to the same JVM bytecode as Java.
