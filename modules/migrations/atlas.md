# Atlas Best Practices

## Overview
Atlas is a modern database schema management tool using declarative HCL or SQL schemas with automatic migration planning. Use it for teams wanting declarative schema management (define desired state, Atlas generates migrations), multi-database support (PostgreSQL, MySQL, MariaDB, SQLite, SQL Server, ClickHouse), and Terraform-style workflows. Avoid it when your ORM handles migrations adequately, or when your team prefers hand-written SQL migrations (use dbmate or Flyway).

## Conventions

### Declarative Schema (HCL)
```hcl
# schema.hcl
schema "public" {}

table "users" {
  schema = schema.public
  column "id" { type = bigserial }
  column "email" { type = varchar(255) }
  column "name" { type = varchar(255) }
  column "created_at" { type = timestamptz default = sql("NOW()") }

  primary_key { columns = [column.id] }
  index "idx_users_email" { columns = [column.email] unique = true }
}

table "orders" {
  schema = schema.public
  column "id" { type = bigserial }
  column "user_id" { type = bigint }
  column "total" { type = decimal(10, 2) }
  column "status" { type = varchar(50) default = "pending" }
  column "created_at" { type = timestamptz default = sql("NOW()") }

  primary_key { columns = [column.id] }
  foreign_key "fk_orders_user" {
    columns     = [column.user_id]
    ref_columns = [table.users.column.id]
    on_delete   = CASCADE
  }
  index "idx_orders_user_status" { columns = [column.user_id, column.status] }
}
```

### Migration Planning
```bash
# Generate migration from schema diff
atlas migrate diff add_orders \
  --dir "file://migrations" \
  --to "file://schema.hcl" \
  --dev-url "docker://postgres/16"

# Apply migrations
atlas migrate apply --url "postgres://app:pass@localhost:5432/mydb?sslmode=disable"

# Validate migrations match schema
atlas migrate lint --dir "file://migrations" --dev-url "docker://postgres/16"
```

### Versioned Migrations (SQL)
```sql
-- migrations/20260326100000_add_orders.sql
CREATE TABLE orders (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT REFERENCES users(id) ON DELETE CASCADE,
    total DECIMAL(10, 2) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

## Configuration

```hcl
# atlas.hcl
env "local" {
  src = "file://schema.hcl"
  url = "postgres://app:pass@localhost:5432/mydb?sslmode=disable"
  dev = "docker://postgres/16"
  migration { dir = "file://migrations" }
}

env "prod" {
  src = "file://schema.hcl"
  url = getenv("DATABASE_URL")
  migration { dir = "file://migrations" }
}
```

## Dos
- Use declarative schemas (HCL) for the desired state — Atlas auto-generates safe migration SQL.
- Use `--dev-url "docker://postgres/16"` for migration planning — Atlas spins up a temporary database to diff.
- Run `atlas migrate lint` in CI to catch destructive changes (data loss, breaking schema changes).
- Use `atlas migrate hash` to verify migration file integrity — detects unauthorized modifications.
- Use environments (`atlas.hcl` env blocks) to separate local, staging, and production configs.
- Use `atlas schema inspect` to generate HCL from an existing database — great for onboarding.
- Run migrations as part of CI/CD — use `atlas migrate apply` in deployment pipelines.

## Don'ts
- Don't modify applied migrations — Atlas tracks checksums; edited migrations cause apply failures.
- Don't skip `atlas migrate lint` — it catches data-loss scenarios (column drops, type changes) before they reach production.
- Don't mix declarative and versioned workflows — choose one approach per project.
- Don't run `atlas schema apply` (direct apply without versioned migrations) in production — always use versioned migrations.
- Don't ignore Atlas's destructive change warnings — they indicate potential data loss.
- Don't hardcode database URLs in `atlas.hcl` — use `getenv()` for credentials.
- Don't skip the dev-url flag — Atlas needs a clean database to compute accurate diffs.
