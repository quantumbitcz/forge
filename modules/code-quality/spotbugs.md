# spotbugs

## Overview

Bytecode-level bug pattern detector for Java (and Kotlin-compiled JVM code). SpotBugs analyzes compiled `.class` files rather than source, enabling it to catch real bugs — null pointer dereferences, incorrect synchronization, resource leaks, infinite recursive loops — that source-level tools miss. It is the successor to FindBugs. Use SpotBugs for production Java code where correctness matters; pair it with FindSecBugs plugin for security-specific patterns. Unlike PMD (AST-based), SpotBugs requires compilation first.

## Architecture Patterns

### Installation & Setup

**Gradle (`com.github.spotbugs` plugin, current: 6.x):**

```kotlin
// build.gradle.kts
plugins {
    id("com.github.spotbugs") version "6.1.7"
}

spotbugs {
    toolVersion.set("4.8.6")
    ignoreFailures.set(false)
    showStackTraces.set(false)
    showProgress.set(false)
    effort.set(Effort.MAX)         // DEFAULT, MORE, MAX — higher = slower but more findings
    reportLevel.set(Confidence.DEFAULT)  // HIGH (least noisy), DEFAULT (medium), LOW (most)
    excludeFilter.set(file("$rootDir/config/spotbugs/spotbugs-exclude.xml"))
    maxHeapSize.set("1g")
}

tasks.withType<SpotBugsTask>().configureEach {
    reports.create("html") { required.set(true) }
    reports.create("xml") { required.set(true) }
    // SARIF support in spotbugs 4.8+:
    reports.create("sarif") { required.set(false) }
}

// Optional: add FindSecBugs for security rules
dependencies {
    spotbugsPlugins("com.h3xstream.findsecbugs:findsecbugs-plugin:1.13.0")
    spotbugsPlugins("com.mebigfatguy.sb-contrib:sb-contrib:7.6.4")
}
```

**Maven (`spotbugs-maven-plugin`):**

```xml
<!-- pom.xml -->
<plugin>
    <groupId>com.github.spotbugs</groupId>
    <artifactId>spotbugs-maven-plugin</artifactId>
    <version>4.8.6.6</version>
    <configuration>
        <effort>Max</effort>
        <threshold>Low</threshold>
        <failOnError>true</failOnError>
        <excludeFilterFile>config/spotbugs/spotbugs-exclude.xml</excludeFilterFile>
        <plugins>
            <plugin>
                <groupId>com.h3xstream.findsecbugs</groupId>
                <artifactId>findsecbugs-plugin</artifactId>
                <version>1.13.0</version>
            </plugin>
        </plugins>
    </configuration>
    <executions>
        <execution>
            <goals><goal>check</goal></goals>
        </execution>
    </executions>
</plugin>
```

### Rule Categories

SpotBugs organizes bugs into categories. Pipeline severity mapping:

| Category | Abbrev | What It Catches | Pipeline Severity |
|---|---|---|---|
| Correctness | `CORRECTNESS` | Null dereferences, infinite loops, impossible downcasts, format string errors | CRITICAL |
| Bad Practice | `BAD_PRACTICE` | `equals()` without `hashCode()`, empty `catch` blocks, ignored return values | WARNING |
| Performance | `PERFORMANCE` | Inefficient String operations, boxing in hot loops, unnecessary object creation | WARNING |
| Security | `SECURITY` | SQL injection via string concat, weak crypto, hardcoded credentials | CRITICAL |
| Dodgy Code | `STYLE` | Dead stores, useless self-assignment, check for null after dereference | WARNING |
| Multithreaded Correctness | `MT_CORRECTNESS` | Mutable statics, wrong lock, spinlock on `this` | CRITICAL |
| Experimental | `EXPERIMENTAL` | Heuristic checks with higher false positive rate | INFO |

Confidence levels: **HIGH** = very likely a real bug, **NORMAL** = probably a bug, **LOW** = possible but often a false positive.

### Configuration Patterns

Exclude file at `config/spotbugs/spotbugs-exclude.xml`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<FindBugsFilter
    xmlns="https://github.com/spotbugs/filter/3.0.0"
    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
    xsi:schemaLocation="https://github.com/spotbugs/filter/3.0.0 https://raw.githubusercontent.com/spotbugs/spotbugs/master/spotbugs/etc/findbugsfilter.xsd">

    <!-- Exclude all findings in generated code -->
    <Match>
        <Source name="~.*[\\/]generated[\\/].*"/>
    </Match>

    <!-- Exclude test classes from MT_CORRECTNESS (tests often use shared state intentionally) -->
    <Match>
        <Class name="~.*Test"/>
        <Bug category="MT_CORRECTNESS"/>
    </Match>

    <!-- Exclude specific known false positive: Lombok-generated equals -->
    <Match>
        <Bug pattern="HE_EQUALS_USE_HASHCODE"/>
        <Class name="~.*\.domain\..*"/>
    </Match>

    <!-- Exclude EI_EXPOSE_REP2 for DTOs/records (intentional exposure) -->
    <Match>
        <Bug pattern="EI_EXPOSE_REP2"/>
        <Class name="~.*Dto"/>
    </Match>

</FindBugsFilter>
```

Suppress inline in Java with `@SuppressWarnings`:
```java
@SuppressWarnings("SpotBugs")                     // suppress all SpotBugs on method
@SuppressWarnings("NP_NULL_ON_SOME_PATH")         // suppress specific pattern
public void process(@Nullable String input) { ... }
```

Or use the SpotBugs annotation:
```java
import edu.umd.cs.findbugs.annotations.SuppressFBWarnings;

@SuppressFBWarnings(value = "NP_NULL_ON_SOME_PATH", justification = "Null checked by caller contract")
public void process(String input) { ... }
```

Add `spotbugs-annotations` as `compileOnly` dependency:
```kotlin
dependencies {
    compileOnly("com.github.spotbugs:spotbugs-annotations:4.8.6")
}
```

### CI Integration

```yaml
# .github/workflows/quality.yml
- name: Run SpotBugs
  run: ./gradlew spotbugsMain spotbugsTest --continue

- name: Upload SpotBugs SARIF
  if: always()
  uses: github/codeql-action/upload-sarif@v3
  with:
    sarif_file: build/reports/spotbugs/main.sarif

- name: Upload SpotBugs HTML report
  if: always()
  uses: actions/upload-artifact@v4
  with:
    name: spotbugs-report
    path: build/reports/spotbugs/
```

SpotBugs runs after compilation — place it after `compileJava`/`compileKotlin` in CI steps.

## Performance

- `effort = MAX` adds ~30% analysis time over `DEFAULT` but finds more correctness bugs. Use `MAX` in CI, `DEFAULT` for local quick checks.
- `reportLevel = HIGH` (only high-confidence bugs) reduces noise and analysis time by ~20%.
- SpotBugs is single-threaded by design — no parallelism flag. On large projects (500k+ bytecode), analysis can take 2-5 minutes.
- Use `maxHeapSize = "2g"` for projects with >1000 classes to avoid `OutOfMemoryError` during analysis.
- SpotBugs is much slower than Checkstyle or PMD because it analyzes bytecode including data flow — plan for it in CI time budgets.

## Security

SpotBugs + FindSecBugs plugin (`findsecbugs-plugin`) covers OWASP Top 10 patterns in Java:
- `SQL_INJECTION_JDBC` — string concatenation in JDBC queries → CRITICAL
- `WEAK_TRUST_MANAGER` — accepts all SSL certificates → CRITICAL
- `PREDICTABLE_RANDOM` — `java.util.Random` used for security purposes → CRITICAL
- `HARD_CODE_PASSWORD` — string literals in password fields → CRITICAL
- `PATH_TRAVERSAL_IN` — unvalidated file paths from user input → CRITICAL
- `XSS_SERVLET` — unsanitized output to HTTP response → CRITICAL
- `CIPHER_INTEGRITY` — ECB mode or no padding integrity → WARNING

Always pair SpotBugs with `findsecbugs-plugin` for any production Java application.

## Testing

```bash
# Gradle: run SpotBugs analysis
./gradlew spotbugsMain

# Maven: run SpotBugs
mvn spotbugs:check

# SpotBugs GUI (inspect findings interactively):
./gradlew spotbugsMain
java -jar ~/.gradle/caches/.../spotbugs-*.jar build/reports/spotbugs/main.xml

# Verify exclude filter works:
./gradlew spotbugsMain --info | grep "Excluded"
```

Establish a baseline for gradual adoption:
```kotlin
spotbugs {
    ignoreFailures.set(true)    // warn-only during onboarding
    reportLevel.set(Confidence.HIGH)   // start with only high-confidence findings
}
```

## Dos

- Always add `findsecbugs-plugin` — the base SpotBugs security category is sparse; FindSecBugs covers OWASP Top 10 comprehensively.
- Set `effort = MAX` in CI — it uses interprocedural analysis and catches null dereferences that DEFAULT misses.
- Use `@SuppressFBWarnings` with a `justification` field (not `@SuppressWarnings`) — the justification is visible in SpotBugs reports and documents intent.
- Exclude generated sources in `spotbugs-exclude.xml` using `<Source>` element pattern matching.
- Treat `MT_CORRECTNESS` findings as CRITICAL — concurrent correctness bugs are nearly impossible to reproduce under test.
- Upload SARIF to GitHub Security tab — SpotBugs findings appear as Code Scanning alerts with file/line annotations on PRs.
- Add `spotbugs-annotations` as `compileOnly` for the `@SuppressFBWarnings` annotation without runtime overhead.

## Don'ts

- Don't skip SpotBugs because "Kotlin is null-safe" — Kotlin interop with Java code can still produce `NullPointerException` that SpotBugs catches.
- Don't use `reportLevel = LOW` in CI — it floods reports with false positives and trains developers to ignore findings.
- Don't run SpotBugs before compilation — it analyses bytecode and silently produces empty results if `.class` files are missing.
- Don't ignore `CORRECTNESS` category findings — these are real bugs with high confidence, not style issues.
- Don't suppress `EI_EXPOSE_REP` blanket-wide — mutable field exposure through getters is a real encapsulation bug; suppress per-class with justification.
- Don't exclude entire packages from SpotBugs analysis — use category-specific exclusions to keep coverage where it matters.
