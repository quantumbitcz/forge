# PostgreSQL with Spring

## Integration Setup

```kotlin
// build.gradle.kts
implementation("org.springframework.boot:spring-boot-starter-data-jpa")
implementation("org.postgresql:postgresql")
implementation("org.flywaydb:flyway-core")
testImplementation("org.testcontainers:postgresql")
```

```yaml
# application.yml
spring:
  datasource:
    url: jdbc:postgresql://${DB_HOST:localhost}:5432/${DB_NAME}
    username: ${DB_USER}
    password: ${DB_PASSWORD}
    hikari:
      maximum-pool-size: 10
      minimum-idle: 2
      connection-timeout: 30000
      idle-timeout: 600000
      max-lifetime: 1800000
      connection-test-query: SELECT 1
```

## Framework-Specific Patterns

### HikariCP Pool Tuning
Set `maximum-pool-size` to `(core_count * 2) + effective_spindle_count`. For cloud DBs, keep it low (5-10) to avoid exhausting server connections.

### PostgreSQL Advisory Locks
Use advisory locks for distributed coordination without a separate locking service:

```kotlin
@Transactional
fun withAdvisoryLock(lockId: Long, block: () -> Unit) {
    jdbcTemplate.execute("SELECT pg_advisory_xact_lock($lockId)")
    block()
    // Lock released automatically at transaction end
}
```

### Testcontainers PostgreSQL

```kotlin
@TestConfiguration
class PostgresTestConfig {
    @Bean
    @ServiceConnection
    fun postgresContainer(): PostgreSQLContainer<*> =
        PostgreSQLContainer("postgres:16-alpine")
            .withReuse(true)
}
```

Use `@ServiceConnection` (Spring Boot 3.1+) — no manual `DataSource` override needed.

## Scaffolder Patterns

```yaml
patterns:
  datasource_config: "src/main/resources/application.yml"
  testcontainers_config: "src/test/kotlin/{package}/config/PostgresTestConfig.kt"
  db_init: "src/main/resources/db/migration/V1__init.sql"
```

## Additional Dos/Don'ts

- DO set `connectionTimeout` and `maxLifetime` to avoid stale connections in containerized environments
- DO use `@ServiceConnection` with Testcontainers instead of manual `@DynamicPropertySource`
- DO set `schema` in Hikari config when using non-public schemas
- DON'T use `spring.jpa.hibernate.ddl-auto=update` in production — use Flyway/Liquibase
- DON'T exceed the PostgreSQL `max_connections` limit; leave headroom for admin connections
