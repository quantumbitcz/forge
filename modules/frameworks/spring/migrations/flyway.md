# Flyway with Spring

## Integration Setup

```kotlin
// build.gradle.kts
implementation("org.flywaydb:flyway-core")
implementation("org.flywaydb:flyway-database-postgresql") // Flyway 10+
```

```yaml
# application.yml
spring:
  flyway:
    enabled: true
    locations: classpath:db/migration
    baseline-on-migrate: false       # true only when adding Flyway to an existing schema
    out-of-order: false
    validate-on-migrate: true
    clean-disabled: true             # Prevent accidental schema wipe in production
    placeholders:
      schema: public
```

## Framework-Specific Patterns

### Migration Naming Convention

```
V{version}__{description}.sql
src/main/resources/db/migration/
  V1__create_orders_table.sql
  V2__add_customer_email_index.sql
  R__refresh_sales_view.sql          # Repeatable migration (R prefix)
```

### Flyway Callbacks as Spring Beans

```kotlin
@Component
class FlywayCleanupCallback : Callback {
    override fun supports(event: Event, context: Context) =
        event == Event.AFTER_MIGRATE

    override fun canHandleInTransaction(event: Event, context: Context) = true

    override fun handle(event: Event, context: Context) {
        // Runs after every migration — e.g., refresh materialized views
    }
}
```

Spring auto-detects `Callback` beans and registers them with Flyway.

### @FlywayTest for Integration Tests

```kotlin
// build.gradle.kts (test)
testImplementation("org.flywaydb.flyway-test-extensions:flyway-spring-test:10.0.0")

@SpringBootTest
@FlywayTest   // Rolls back to clean state before each test
class OrderRepositoryTest { ... }
```

### Baseline on Migrate (existing schemas)

Set `baseline-on-migrate: true` and `baseline-version: 1` only when first introducing Flyway to a database that already has objects. Remove after the first successful run.

## Scaffolder Patterns

```yaml
patterns:
  migration_dir: "src/main/resources/db/migration/"
  migration_file: "src/main/resources/db/migration/V{version}__{description}.sql"
  callback: "src/main/kotlin/{package}/config/Flyway{Name}Callback.kt"
```

## Additional Dos/Don'ts

- DO keep `clean-disabled: true` in all non-local environments
- DO use `validate-on-migrate: true` to catch checksum drift early
- DO apply `CREATE INDEX CONCURRENTLY` in a repeatable migration or a dedicated step (not transactional)
- DON'T modify existing migration files after they have been applied — create a new version instead
- DON'T use `out-of-order: true` in production; it masks branching mistakes
