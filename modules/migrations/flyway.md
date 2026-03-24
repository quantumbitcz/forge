# Flyway Best Practices

## Overview
Flyway is a SQL-first database migration tool that uses versioned migration scripts to evolve a schema incrementally. Use it for Java/Kotlin/JVM projects where SQL control is preferred over ORM-generated DDL. Avoid it when your team lacks SQL expertise or when you need complex programmatic data transformations (use Liquibase or a code-first tool instead).

## Architecture Patterns

### Directory structure
```
src/main/resources/db/migration/
├── V1__create_users.sql
├── V2__add_user_email_index.sql
├── V3__create_orders.sql
├── V4__add_order_status_enum.sql
└── R__refresh_reporting_view.sql   # Repeatable migration
```

### Naming conventions
- **Versioned:** `V{version}__{description}.sql` — runs once, in order, checksummed
- **Undo:** `U{version}__{description}.sql` — explicit rollback (Teams edition)
- **Repeatable:** `R__{description}.sql` — re-runs when checksum changes (views, functions, stored procs)
- Use double underscores; use underscores within description (no spaces or hyphens)
- Version as integer or `{major}.{minor}`: `V1__`, `V1.1__`, `V2__`

### Baselining existing databases
```bash
# Mark existing schema as V1 without running it
flyway -baselineOnMigrate=true -baselineVersion=1 migrate
```
Set `spring.flyway.baseline-on-migrate=true` in `application.properties` for Spring Boot.

## Configuration

### Spring Boot (application.yml)
```yaml
spring:
  flyway:
    enabled: true
    locations: classpath:db/migration
    baseline-on-migrate: false
    out-of-order: false        # Reject migrations applied out of version order
    validate-on-migrate: true  # Fail if checksums mismatch
    schemas: public
    placeholders:
      schema_name: myapp
```

### CI/CD (standalone)
```bash
flyway -url=jdbc:postgresql://host/db \
       -user=${DB_USER} -password=${DB_PASSWORD} \
       -locations=filesystem:./migrations \
       info   # preview pending migrations
flyway migrate
```

## Performance

### Zero-downtime migrations
Split breaking changes across two deployments:
1. **Deploy N:** Add new nullable column (non-breaking)
2. **Deploy N+1:** Backfill data, add NOT NULL constraint, drop old column

```sql
-- V10__add_display_name_nullable.sql
ALTER TABLE users ADD COLUMN display_name VARCHAR(255);

-- V11__backfill_display_name.sql (run after N+1 is live)
UPDATE users SET display_name = first_name || ' ' || last_name
WHERE display_name IS NULL;

-- V12__set_display_name_not_null.sql
ALTER TABLE users ALTER COLUMN display_name SET NOT NULL;
```

### Large table migrations (Postgres)
```sql
-- V15__add_processed_at_index.sql
-- Use CONCURRENTLY to avoid table lock
CREATE INDEX CONCURRENTLY idx_events_processed_at ON events(processed_at);
```

## Security
- Never embed credentials in `flyway.conf`; inject via environment variables or secrets manager
- Store migration files in version control; treat them as immutable once merged
- Use a dedicated migration DB user with DDL rights; the application runtime user should have DML only
- Enable `validateOnMigrate` in production to detect tampered scripts

## Testing
```bash
# Test migrations against a clean DB in CI
docker run -d --name test-db -e POSTGRES_PASSWORD=test postgres:16
flyway -url=jdbc:postgresql://localhost/postgres -user=postgres \
       -password=test migrate
# Run integration tests, then verify undo (Teams) or rollback snapshot
```
Use Testcontainers in integration tests to spin up a fresh database and apply all migrations before the test suite runs.

## Dos
- Always use `validate-on-migrate: true` in every environment
- Keep migrations small and single-purpose (one concern per file)
- Write `down` logic as a separate `U` script or document manual rollback steps in a comment
- Test migrations against a production-size data copy before rollout for large tables
- Use `flyway info` in CI to detect drift before deploying
- Pin the Flyway version in CI the same as in your application runtime
- Use placeholders for environment-specific values (schema names, table prefixes)

## Don'ts
- Never modify a migration file after it has been applied — Flyway will fail checksum validation
- Never use `flyway repair` in production without understanding what it patches
- Avoid DDL and DML in the same migration file; split structural changes from data backfills
- Don't use `out-of-order: true` in production — it hides branching conflicts
- Never drop a column in the same release that removes the application code using it; wait one release
- Avoid using `${placeholder}` for secrets inside SQL — use application-layer config instead
