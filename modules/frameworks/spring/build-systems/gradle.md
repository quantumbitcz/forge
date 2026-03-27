# Gradle with Spring

> Extends `modules/build-systems/gradle.md` with Spring Boot Gradle plugin patterns.
> Generic Gradle conventions (task lifecycle, dependency configurations, build cache) are NOT repeated here.

## Integration Setup

```kotlin
// build.gradle.kts
plugins {
    id("org.springframework.boot") version "3.4.3"
    id("io.spring.dependency-management") version "1.1.7"
    kotlin("jvm") version "2.1.10"
    kotlin("plugin.spring") version "2.1.10"
    kotlin("plugin.jpa") version "2.1.10"  // if using JPA
}

dependencyManagement {
    imports {
        mavenBom("org.springframework.cloud:spring-cloud-dependencies:2024.0.1")
    }
}
```

The `io.spring.dependency-management` plugin imports the Spring Boot BOM automatically, so starter dependencies need no version. Use it for transitive alignment across all Spring modules.

## Framework-Specific Patterns

### Layered JAR Support

```kotlin
// build.gradle.kts
tasks.named<org.springframework.boot.gradle.tasks.bundling.BootJar>("bootJar") {
    layered {
        application {
            intoLayer("spring-boot-loader")
            intoLayer("application")
        }
        dependencies {
            intoLayer("snapshot-dependencies") {
                include("*:*:*SNAPSHOT")
            }
            intoLayer("dependencies")
        }
        layerOrder = listOf(
            "dependencies",
            "spring-boot-loader",
            "snapshot-dependencies",
            "application"
        )
    }
}
```

Layered JARs enable Docker layer caching: dependency layers change rarely, application layer changes on every build.

### Test Suites with Spring Boot Test

```kotlin
// build.gradle.kts
testing {
    suites {
        val integrationTest by registering(JvmTestSuite::class) {
            useJUnitJupiter()
            dependencies {
                implementation(project())
                implementation("org.springframework.boot:spring-boot-starter-test")
                implementation("org.springframework.boot:spring-boot-testcontainers")
                implementation("org.testcontainers:postgresql")
            }
            targets {
                all {
                    testTask.configure {
                        shouldRunAfter(tasks.named("test"))
                    }
                }
            }
        }
    }
}

tasks.named("check") {
    dependsOn(testing.suites.named("integrationTest"))
}
```

### Spring Boot Version Catalog

```toml
# gradle/libs.versions.toml
[versions]
spring-boot = "3.4.3"
spring-dependency-management = "1.1.7"
spring-cloud = "2024.0.1"
testcontainers = "1.20.5"

[plugins]
spring-boot = { id = "org.springframework.boot", version.ref = "spring-boot" }
spring-dependency-management = { id = "io.spring.dependency-management", version.ref = "spring-dependency-management" }

[libraries]
spring-boot-starter-web = { module = "org.springframework.boot:spring-boot-starter-web" }
spring-boot-starter-test = { module = "org.springframework.boot:spring-boot-starter-test" }
spring-boot-testcontainers = { module = "org.springframework.boot:spring-boot-testcontainers" }
testcontainers-postgresql = { module = "org.testcontainers:postgresql", version.ref = "testcontainers" }
```

No version on starter libraries when using the dependency-management plugin -- the BOM resolves them.

### Build Configuration for Spring Profiles

```kotlin
// build.gradle.kts
tasks.named<org.springframework.boot.gradle.tasks.run.BootRun>("bootRun") {
    systemProperty("spring.profiles.active", project.findProperty("profile") ?: "local")
    jvmArgs = listOf("-XX:+AllowEnhancedClassRedefinition")  // for DevTools
}
```

Run with `./gradlew bootRun -Pprofile=dev`.

## Scaffolder Patterns

```yaml
patterns:
  build_file: "build.gradle.kts"
  settings_file: "settings.gradle.kts"
  version_catalog: "gradle/libs.versions.toml"
  gradle_properties: "gradle.properties"
```

## Additional Dos

- DO use the `io.spring.dependency-management` plugin for BOM alignment across all modules
- DO configure `bootJar` layering for optimal Docker image caching
- DO separate unit and integration test suites with `testing.suites`
- DO use Gradle version catalogs (`libs.versions.toml`) for Spring dependency versions
- DO set `bootJar.enabled = false` and `jar.enabled = true` on library subprojects

## Additional Don'ts

- DON'T specify versions on Spring Boot starter dependencies -- the BOM manages them
- DON'T use `bootJar` on library modules that aren't runnable applications
- DON'T mix `spring-boot-dependencies` BOM import with explicit starter versions
- DON'T skip `kotlin("plugin.spring")` -- Spring needs `open` classes for proxying
