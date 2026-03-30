# Spring + JaCoCo

> Extends `modules/code-quality/jacoco.md` with Spring Boot-specific integration.
> Generic JaCoCo conventions (counters, Gradle setup, Maven setup, CI integration) are NOT repeated here.

## Integration Setup

Wire JaCoCo into the Spring test task and exclude Spring infrastructure classes:

```kotlin
// build.gradle.kts
tasks.jacocoTestReport {
    dependsOn(tasks.test)
    classDirectories.setFrom(
        files(classDirectories.files.map {
            fileTree(it) {
                exclude(
                    "**/*Application.class",      // Spring Boot entry point
                    "**/*Application\$*.class",   // Kotlin companion / nested
                    "**/config/**",               // @Configuration classes
                    "**/generated/**",            // annotation processor output
                    "**/*MapperImpl.class",       // MapStruct generated mappers
                    "**/*_\$*.class",             // Spring proxy internals
                    "**/Q*.class",                // QueryDSL metamodel
                    "**/*_.class"                 // JPA static metamodel
                )
            }
        })
    )
}
```

## Framework-Specific Patterns

### Multi-module aggregation for Spring microservices

Spring microservice repos often have `api`, `service`, `infrastructure` modules. Create a dedicated aggregator:

```kotlin
// coverage-report/build.gradle.kts
plugins { jacoco }

dependencies {
    jacocoAggregation(project(":api"))
    jacocoAggregation(project(":service"))
    jacocoAggregation(project(":infrastructure"))
}

reporting {
    reports {
        val testCodeCoverageReport by creating(JacocoCoverageReport::class) {
            testSuiteName = "test"
        }
    }
}
```

Use Gradle's built-in `JacocoCoverageReport` DSL (Gradle 7.4+) rather than manual `additionalSourceDirs` wiring.

### Test slice coverage: `@WebMvcTest` and `@DataJpaTest`

Spring test slices load a partial context. JaCoCo execution data from slice tests and `@SpringBootTest` must be merged for accurate coverage:

```kotlin
// build.gradle.kts
tasks.jacocoTestReport {
    // Merge .exec data from all test task variants
    executionData.setFrom(
        fileTree(layout.buildDirectory) {
            include("jacoco/*.exec")
        }
    )
}
```

Register separate Gradle test tasks for slices if you split them by source set:

```kotlin
val integrationTest by tasks.registering(Test::class) {
    testClassesDirs = sourceSets["integrationTest"].output.classesDirs
    classpath = sourceSets["integrationTest"].runtimeClasspath
    extensions.configure<JacocoTaskExtension> {
        destinationFile = file("$buildDir/jacoco/integrationTest.exec")
    }
}
```

### Exclude `@Generated` classes

Mark DTO mappers and generated sources with `@Generated` (javax/jakarta) and configure JaCoCo to skip them:

```kotlin
classDirectories.setFrom(
    files(classDirectories.files.map {
        fileTree(it) { exclude("**/*\$jacoco\$*.class") }
    })
)
```

Use the annotation approach in MapStruct mappers:

```kotlin
@Mapper(componentModel = "spring")
@Generated  // javax.annotation.Generated or jakarta.annotation.Generated
interface OrderMapper { ... }
```

## Additional Dos

- Exclude `*Application.class` and `*Application$*.class` — boot entry points are not business logic.
- Merge `@WebMvcTest`, `@DataJpaTest`, and `@SpringBootTest` execution data into a single report.
- Set lower thresholds (60% branch) for `**/infrastructure/**` packages — Spring Data repositories and JPA entities are harder to branch-cover.

## Additional Don'ts

- Don't count `@Configuration` class coverage — Spring proxy wrapping makes branch coverage misleading for bean factory methods.
- Don't exclude entire `service` or `usecase` packages from thresholds — these are the highest-value coverage targets.
- Don't run JaCoCo with `@SpringBootTest` tests that hit a live database in CI without Testcontainers — flaky DB connections corrupt `.exec` data.
