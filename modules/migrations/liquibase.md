# Liquibase Best Practices

## Overview
Liquibase is a database-agnostic migration tool supporting YAML, XML, JSON, and SQL changelog formats. Use it when you need multi-database portability, rollback scripting built into the same file, or fine-grained context/label targeting for environment-specific migrations. Avoid SQL format when you need database portability — use YAML or XML instead.

## Architecture Patterns

### Directory structure
```
src/main/resources/db/changelog/
├── db.changelog-master.yaml        # Root changelog (includes only)
├── migrations/
│   ├── 0001-create-users.yaml
│   ├── 0002-add-email-index.yaml
│   └── 0003-create-orders.yaml
└── data/
    └── 0100-seed-reference-data.yaml
```

### Master changelog (YAML)
```yaml
databaseChangeLog:
  - include:
      file: migrations/0001-create-users.yaml
      relativeToChangelogFile: true
  - include:
      file: migrations/0002-add-email-index.yaml
      relativeToChangelogFile: true
```

### Changeset structure
```yaml
databaseChangeLog:
  - changeSet:
      id: 0001-create-users
      author: alice
      labels: core, users
      context: "!test"
      changes:
        - createTable:
            tableName: users
            columns:
              - column:
                  name: id
                  type: BIGINT
                  autoIncrement: true
                  constraints:
                    primaryKey: true
              - column:
                  name: email
                  type: VARCHAR(255)
                  constraints:
                    nullable: false
                    unique: true
      rollback:
        - dropTable:
            tableName: users
```

### Contexts and labels
- **Contexts:** target environments (`dev`, `prod`, `!test` means "not test")
- **Labels:** feature toggles and release grouping (`labels: payments-v2`)
- Run only relevant changesets: `liquibase --contexts=prod update`

## Configuration

### Spring Boot (application.yml)
```yaml
spring:
  liquibase:
    change-log: classpath:db/changelog/db.changelog-master.yaml
    contexts: ${LIQUIBASE_CONTEXTS:dev}
    enabled: true
    drop-first: false
```

### Preconditions (guard before applying)
```yaml
preConditions:
  - onFail: MARK_RAN
  - not:
      tableExists:
        tableName: users
```

## Performance

### Zero-downtime: add nullable column first
```yaml
- changeSet:
    id: 0010-add-bio-nullable
    author: bob
    changes:
      - addColumn:
          tableName: users
          columns:
            - column:
                name: bio
                type: TEXT
```

### Large-table index with SQL raw
```sql
-- changeset alice:0015-concurrent-index dbms:postgresql runInTransaction:false
CREATE INDEX CONCURRENTLY idx_orders_created ON orders(created_at);
-- rollback DROP INDEX CONCURRENTLY idx_orders_created;
```

### Diff generation
```bash
liquibase --referenceUrl=jdbc:postgresql://prod/db \
          --referenceUsername=${PROD_USER} \
          --url=jdbc:postgresql://localhost/db \
          diff
```

## Security
- Inject credentials via `LIQUIBASE_COMMAND_URL`, `LIQUIBASE_COMMAND_USERNAME`, `LIQUIBASE_COMMAND_PASSWORD` env vars
- Never store credentials in `liquibase.properties`
- Restrict the migration DB user to DDL; use a separate runtime user for DML
- Commit changelogs to version control; treat applied changesets as immutable

## Testing
```bash
# Verify rollback works before applying
liquibase updateTestingRollback   # applies then immediately rolls back and re-applies

# Preview SQL without executing
liquibase updateSQL > pending.sql
```
In CI, run `liquibase updateTestingRollback` against a Testcontainers database to verify every changeset's rollback block is correct.

## Dos
- Always include a `rollback` block in every changeset
- Use `id: {sequential-number}-{description}` for readable DATABASECHANGELOG entries
- Use `contexts` to gate environment-specific or test-data changesets
- Use `runInTransaction: false` for operations that can't run inside a transaction (e.g., `CREATE INDEX CONCURRENTLY`)
- Use `preconditions` with `onFail: MARK_RAN` for idempotent changesets
- Run `liquibase validate` in CI before deploying
- Use `dbms:` attribute on changesets that are database-specific

## Don'ts
- Never edit a changeset that has already been applied — Liquibase tracks checksums and will fail
- Don't mix DDL and large DML data migrations in the same changeset
- Avoid XML format for new projects — YAML is more readable and diff-friendly
- Never use `runAlways: true` on structural changesets; reserve it for procedures and views
- Don't rely on implicit rollback for complex changes — always write explicit rollback blocks
- Avoid putting environment secrets in changelog files or `liquibase.properties`
