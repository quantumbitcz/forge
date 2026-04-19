# Scenario 03 — Spring Boot 2.7 → 3.3 migration

Upgrade the Gradle project from Spring Boot 2.7.18 + Kotlin 1.9 to Spring Boot 3.3.x + Kotlin 1.9 + Java 17.

Required changes:
- `build.gradle.kts` bumps spring-boot, spring-dependency-management, Kotlin jvm target to 17.
- `javax.*` imports → `jakarta.*` where required by 3.x.
- `@ConfigurationProperties(prefix = ...)` usage reviewed for constructor-binding migration.
- `./gradlew test` must pass against the new versions.

Pipeline mode: `migration`.
