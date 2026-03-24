# Liquibase with Spring

## Integration Setup

```kotlin
// build.gradle.kts
implementation("org.liquibase:liquibase-core")
```

```yaml
# application.yml
spring:
  liquibase:
    enabled: true
    change-log: classpath:db/changelog/db.changelog-master.yaml
    contexts: ${SPRING_PROFILES_ACTIVE:default}
    default-schema: public
    drop-first: false              # Never true outside local dev
    clear-checksums: false
```

## Framework-Specific Patterns

### Master Changelog Structure

```yaml
# db/changelog/db.changelog-master.yaml
databaseChangeLog:
  - include:
      file: db/changelog/changes/0001-create-orders.yaml
  - include:
      file: db/changelog/changes/0002-add-customer-email-index.yaml
```

Prefer YAML or XML changelogs over SQL — they support rollback definitions natively.

### Contexts per Profile

```yaml
# db/changelog/changes/0002-seed-test-data.yaml
databaseChangeLog:
  - changeSet:
      id: seed-test-data
      author: team
      context: test,local        # Only runs when context matches profile
      changes:
        - insert:
            tableName: customers
            columns:
              - column: { name: id, value: "00000000-0000-0000-0000-000000000001" }
              - column: { name: email, value: "test@example.com" }
```

Pass active contexts via `spring.liquibase.contexts` (maps to `SPRING_PROFILES_ACTIVE` by convention).

### Rollback Definitions

```yaml
- changeSet:
    id: add-status-column
    author: team
    changes:
      - addColumn:
          tableName: orders
          columns:
            - column: { name: status, type: VARCHAR(50), defaultValue: "PENDING" }
    rollback:
      - dropColumn:
          tableName: orders
          columnName: status
```

### @LiquibaseTest for Integration Tests

```kotlin
// build.gradle.kts (test)
testImplementation("org.liquibase.ext:liquibase-spring-test:4.29.0")

@SpringBootTest
@LiquibaseTest   // Reverts all changesets after each test
class OrderRepositoryTest { ... }
```

## Scaffolder Patterns

```yaml
patterns:
  master_changelog: "src/main/resources/db/changelog/db.changelog-master.yaml"
  changeset_dir: "src/main/resources/db/changelog/changes/"
  changeset_file: "src/main/resources/db/changelog/changes/{NNNN}-{description}.yaml"
```

## Additional Dos/Don'ts

- DO define `rollback` blocks for every `changeSet` — enables `liquibase rollback` in emergencies
- DO use contexts to isolate seed data from schema changes
- DO pin `liquibase-core` version explicitly — Spring Boot's managed version may lag
- DON'T set `drop-first: true` outside of local developer databases
- DON'T edit applied changeSets — Liquibase validates checksums and will refuse to run
