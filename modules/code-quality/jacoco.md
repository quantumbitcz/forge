# jacoco

## Overview

JaCoCo (Java Code Coverage) measures instruction, branch, line, method, class, and complexity coverage for JVM languages. Integrates with Gradle via the `jacoco` plugin and Maven via `jacoco-maven-plugin`. Generates HTML, XML, and CSV reports; XML is the canonical format consumed by CI dashboards, Sonar, and Codecov. Enforce thresholds with `violationRules` (Gradle) or `check` goal (Maven) — fail the build when coverage drops below a configured minimum. Aggregated multi-module reports require a dedicated aggregator subproject.

## Architecture Patterns

### Installation & Setup

**Gradle (Kotlin DSL):**
```kotlin
// build.gradle.kts
plugins {
    jacoco
}

jacoco {
    toolVersion = "0.8.12"
}

tasks.test {
    useJUnitPlatform()
    finalizedBy(tasks.jacocoTestReport)
}

tasks.jacocoTestReport {
    dependsOn(tasks.test)
    reports {
        xml.required = true      // for CI/Sonar ingestion
        html.required = true     // human-readable
        csv.required = false
    }
    // Exclude generated sources, Hilt/Dagger, data binding
    classDirectories.setFrom(
        files(classDirectories.files.map {
            fileTree(it) {
                exclude(
                    "**/generated/**",
                    "**/R.class",
                    "**/R$*.class",
                    "**/*_MembersInjector.class",
                    "**/*_Factory.class",
                    "**/databinding/**",
                    "**/BuildConfig.class"
                )
            }
        })
    )
}

tasks.jacocoTestCoverageVerification {
    violationRules {
        rule {
            limit {
                minimum = "0.80".toBigDecimal()  // 80% instruction coverage
            }
        }
        rule {
            element = "CLASS"
            excludes = listOf("*.generated.*", "*.dto.*")
            limit {
                counter = "BRANCH"
                minimum = "0.70".toBigDecimal()
            }
        }
    }
}

tasks.check {
    dependsOn(tasks.jacocoTestCoverageVerification)
}
```

**Maven:**
```xml
<!-- pom.xml -->
<plugin>
  <groupId>org.jacoco</groupId>
  <artifactId>jacoco-maven-plugin</artifactId>
  <version>0.8.12</version>
  <executions>
    <execution>
      <id>prepare-agent</id>
      <goals><goal>prepare-agent</goal></goals>
    </execution>
    <execution>
      <id>report</id>
      <phase>verify</phase>
      <goals><goal>report</goal></goals>
    </execution>
    <execution>
      <id>check</id>
      <phase>verify</phase>
      <goals><goal>check</goal></goals>
      <configuration>
        <rules>
          <rule>
            <limits>
              <limit>
                <counter>INSTRUCTION</counter>
                <value>COVEREDRATIO</value>
                <minimum>0.80</minimum>
              </limit>
              <limit>
                <counter>BRANCH</counter>
                <value>COVEREDRATIO</value>
                <minimum>0.70</minimum>
              </limit>
            </limits>
          </rule>
        </rules>
        <excludes>
          <exclude>**/generated/**</exclude>
          <exclude>**/*Dto.class</exclude>
        </excludes>
      </configuration>
    </execution>
  </executions>
</plugin>
```

### Rule Categories

| Counter | Measures | Recommended Minimum |
|---|---|---|
| `INSTRUCTION` | Bytecode instructions executed | 80% |
| `BRANCH` | Taken/not-taken branches (if/switch) | 70% |
| `LINE` | Source lines touched | 80% |
| `METHOD` | Methods entered at least once | 85% |
| `CLASS` | Classes loaded | 90% |
| `COMPLEXITY` | Cyclomatic complexity paths | 70% |

### Configuration Patterns

**Multi-module aggregation (Gradle):**
```kotlin
// aggregator/build.gradle.kts (standalone module with no sources)
plugins { jacoco }

tasks.register<JacocoReport>("jacocoAggregatedReport") {
    dependsOn(subprojects.map { it.tasks.withType<Test>() })
    additionalSourceDirs.setFrom(subprojects.flatMap { it.sourceSets.main.get().allSource.srcDirs })
    sourceDirectories.setFrom(subprojects.flatMap { it.sourceSets.main.get().allSource.srcDirs })
    classDirectories.setFrom(subprojects.flatMap {
        it.tasks.withType<JacocoReport>().flatMap { r -> r.classDirectories }
    })
    executionData.setFrom(subprojects.flatMap {
        it.tasks.withType<Test>().map { t -> t.extensions.getByType<JacocoTaskExtension>().destinationFile!! }
    }.filter { it.exists() })
    reports { xml.required = true; html.required = true }
}
```

**Exclusions for common generated code patterns:**
```kotlin
// Common exclusions: Lombok, MapStruct, Protobuf, Spring Data, JPA metamodel
exclude(
    "**/lombok/**",
    "**/*MapperImpl.class",
    "**/*Proto.class",
    "**/Q*.class",               // QueryDSL
    "**/*_.class",               // JPA metamodel
    "**/configuration/**",       // Spring @Configuration classes
    "**/Application.class"
)
```

### CI Integration

```yaml
# .github/workflows/test.yml
- name: Test with coverage
  run: ./gradlew test jacocoTestReport jacocoTestCoverageVerification

- name: Upload coverage to Codecov
  uses: codecov/codecov-action@v4
  with:
    files: build/reports/jacoco/test/jacocoTestReport.xml
    fail_ci_if_error: true

- name: Upload JaCoCo HTML report
  if: always()
  uses: actions/upload-artifact@v4
  with:
    name: jacoco-report
    path: build/reports/jacoco/test/html/
```

## Performance

- JaCoCo instruments bytecode at load time via a Java agent — adds 10-30% to test execution time. Acceptable for CI; avoid on performance benchmarks.
- Use `jacocoTestReport` only after `test` completes — the `finalizedBy` pattern avoids re-running tests.
- For large multi-module projects, run `jacocoAggregatedReport` in a dedicated CI step rather than per-module to reduce report generation overhead.
- Offline instrumentation (`jacoco:instrument` Maven goal) is faster than the agent for projects with many classloaders (e.g., OSGi, custom classloaders).

## Security

- JaCoCo execution data (`.exec` files) contains class names and instruction counts — no source code. Safe to store as CI artifacts.
- Do not include JaCoCo agent (`-javaagent`) in production JVM flags — it adds startup overhead and writes `.exec` files to disk.
- Coverage reports in HTML format do not expose secret values — they reflect source line execution, not variable contents.

## Testing

```bash
# Gradle: run tests + generate report + enforce thresholds
./gradlew test jacocoTestReport jacocoTestCoverageVerification

# Maven: full verify lifecycle includes coverage check
mvn verify

# View HTML report locally
open build/reports/jacoco/test/html/index.html

# Print coverage summary (Gradle)
./gradlew test jacocoTestReport --rerun-tasks

# Check execution data exists (non-empty = tests ran)
ls -lh build/jacoco/test.exec
```

## Dos

- Enable both `xml` and `html` reports — XML for CI ingestion, HTML for developer inspection.
- Enforce thresholds via `violationRules`/`check` goal — a report that never fails teaches nothing.
- Exclude generated code (Lombok, MapStruct, QueryDSL, Protobuf) — they inflate line counts and obscure real coverage gaps.
- Wire `jacocoTestCoverageVerification` into the `check` lifecycle task so `./gradlew check` enforces coverage.
- Use `INSTRUCTION` counter as the primary threshold — it is more granular than `LINE` and handles Kotlin/Groovy single-expression functions correctly.
- For multi-module projects, add an aggregator module for the project-wide coverage view alongside per-module reports.

## Don'ts

- Don't set thresholds to 100% — untestable infrastructure code (main entry points, DI config) makes 100% unreachable without meaningless tests.
- Don't exclude entire packages from coverage checks without a documented reason — exclusions hide real gaps.
- Don't rely on line coverage alone — a method can have 100% line coverage but 0% branch coverage if `if` conditions are never false.
- Don't run JaCoCo on integration tests that hit live databases without mocking — flaky tests corrupt `.exec` data and cause false threshold failures.
- Don't commit `.exec` binary files to version control — they are large and change on every test run.
