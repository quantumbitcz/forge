# dbmate Best Practices

## Overview
dbmate is a lightweight, language-agnostic database migration tool written in Go. Use it for polyglot teams needing a single migration tool across PostgreSQL, MySQL, MariaDB, SQLite, and ClickHouse regardless of application language. dbmate excels at simplicity (plain SQL files, no ORM dependency) and Docker-friendly workflows. Avoid it when your ORM has built-in migrations (EF Core, Django, Prisma) and you prefer keeping schema and code together.

## Conventions

### Migration File Structure
```bash
db/migrations/
├── 20260326100000_create_users.sql
├── 20260326100100_create_orders.sql
├── 20260326100200_add_users_email_index.sql
└── 20260326100300_add_order_status.sql
```

### Migration File Format
```sql
-- migrate:up
CREATE TABLE users (
    id BIGSERIAL PRIMARY KEY,
    email VARCHAR(255) NOT NULL UNIQUE,
    name VARCHAR(255) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_users_email ON users(email);

-- migrate:down
DROP TABLE IF EXISTS users;
```

### Commands
```bash
# Create a new migration
dbmate new add_orders_table

# Run pending migrations
dbmate up

# Rollback last migration
dbmate rollback

# Show migration status
dbmate status

# Dump schema
dbmate dump
```

## Configuration

```bash
# .env
DATABASE_URL="postgres://app:pass@localhost:5432/mydb?sslmode=require"

# Or via CLI flags
dbmate --url "postgres://..." --migrations-dir "./db/migrations" up
```

```yaml
# .dbmate.yml (optional)
url: "${DATABASE_URL}"
migrations-dir: "./db/migrations"
schema-file: "./db/schema.sql"
no-dump-schema: false
strict: true
```

## Dos
- Use plain SQL for migrations — dbmate is language-agnostic by design, keep it that way.
- Always write both `migrate:up` and `migrate:down` sections — even if the down migration is a no-op with a comment.
- Use `dbmate dump` to generate `schema.sql` — commit it for code review visibility of schema changes.
- Use `dbmate wait` in Docker entrypoints to wait for the database before running migrations.
- Use timestamp-based filenames (default) — they prevent merge conflicts better than sequential numbers.
- Run migrations in CI/CD before deployment — never manually in production.
- Use `--strict` mode to fail on out-of-order migrations — prevents missed migrations in team environments.

## Don'ts
- Don't modify already-applied migrations — create a new migration to alter previous changes.
- Don't use `dbmate` alongside ORM-managed migrations on the same database — pick one tool.
- Don't skip the `down` migration — it's essential for rollback and development iteration.
- Don't put seed data in migrations — use a separate seed mechanism.
- Don't use database-specific syntax without documenting it — if you switch databases, migrations will break.
- Don't run `dbmate rollback` in production without testing — verify the down migration works first.
- Don't forget to commit `schema.sql` — it provides a full schema snapshot for review.
