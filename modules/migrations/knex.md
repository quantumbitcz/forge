# Knex Migrations Best Practices

## Overview
Knex is a SQL query builder for Node.js that includes a migration and seed system. Use it for Node.js projects that need SQL control without a full ORM, or as the migration layer beneath ORMs like Objection.js. Avoid it when your project is already on Prisma or TypeORM — use those tools' native migration systems instead.

## Architecture Patterns

### Directory structure
```
db/
├── knexfile.ts          # Connection and migration config
├── migrations/
│   ├── 20240101120000_create_users.ts
│   ├── 20240115093000_add_email_index.ts
│   └── 20240201_add_orders.ts
└── seeds/
    ├── 01_reference_data.ts
    └── 02_test_users.ts
```

### knexfile.ts
```typescript
import type { Knex } from "knex";

const config: { [key: string]: Knex.Config } = {
  development: {
    client: "postgresql",
    connection: process.env.DATABASE_URL,
    migrations: { directory: "./db/migrations", extension: "ts" },
    seeds: { directory: "./db/seeds" },
  },
  production: {
    client: "postgresql",
    connection: process.env.DATABASE_URL,
    pool: { min: 2, max: 10 },
    migrations: { directory: "./db/migrations", extension: "ts" },
  },
};

export default config;
```

### Migration file anatomy
```typescript
// db/migrations/20240101120000_create_users.ts
import type { Knex } from "knex";

export async function up(knex: Knex): Promise<void> {
  await knex.schema.createTable("users", (table) => {
    table.increments("id").primary();
    table.string("email", 255).notNullable().unique();
    table.string("name", 255).nullable();
    table.timestamp("created_at").defaultTo(knex.fn.now());
    table.timestamp("updated_at").defaultTo(knex.fn.now());
  });
}

export async function down(knex: Knex): Promise<void> {
  await knex.schema.dropTableIfExists("users");
}
```

### Transaction-wrapped migration
```typescript
export async function up(knex: Knex): Promise<void> {
  await knex.transaction(async (trx) => {
    await trx.schema.addColumn("users", "full_name", (col) =>
      col.string("full_name", 255).nullable()
    );
    await trx("users").update({
      full_name: knex.raw("first_name || ' ' || last_name"),
    });
  });
}
```

### Data migration with raw SQL
```typescript
export async function up(knex: Knex): Promise<void> {
  await knex.schema.table("orders", (table) => {
    table.string("region", 50).nullable();
  });
  await knex.raw(
    "UPDATE orders SET region = 'default' WHERE region IS NULL"
  );
  await knex.schema.alterTable("orders", (table) => {
    table.string("region", 50).notNullable().alter();
  });
}
```

## Configuration

### CLI workflow
```bash
# Create new migration (timestamp-prefixed)
knex migrate:make create_users --knexfile db/knexfile.ts

# Apply all pending migrations
knex migrate:latest --knexfile db/knexfile.ts

# Roll back the last batch
knex migrate:rollback --knexfile db/knexfile.ts

# Roll back all migrations
knex migrate:rollback --all --knexfile db/knexfile.ts

# Check migration status
knex migrate:status --knexfile db/knexfile.ts
```

### package.json scripts
```json
{
  "scripts": {
    "db:migrate": "knex migrate:latest",
    "db:rollback": "knex migrate:rollback",
    "db:seed": "knex seed:run",
    "db:status": "knex migrate:status"
  }
}
```

## Performance

### Zero-downtime: nullable column first, then constraint
```typescript
// Migration 1: add nullable (non-locking)
await knex.schema.table("users", (t) => t.text("bio").nullable());

// Migration 2 (next deploy): enforce constraint
await knex.raw("ALTER TABLE users ALTER COLUMN bio SET NOT NULL");
```

### Large-table index (Postgres)
```typescript
export async function up(knex: Knex): Promise<void> {
  await knex.raw(
    "CREATE INDEX CONCURRENTLY idx_events_ts ON events(created_at)"
  );
}
export async function down(knex: Knex): Promise<void> {
  await knex.raw("DROP INDEX CONCURRENTLY idx_events_ts");
}
```

## Security
- Store `DATABASE_URL` in environment variables; never hardcode credentials in `knexfile.ts`
- Use a dedicated migration DB user with DDL rights; app runtime user gets DML only
- Commit migration files; treat applied files as immutable

## Testing
```bash
# In CI: fresh database, apply all migrations, run tests, then rollback
DATABASE_URL=postgresql://localhost/test knex migrate:latest
# ... run test suite ...
DATABASE_URL=postgresql://localhost/test knex migrate:rollback --all
```
Verify rollback with `migrate:rollback` after `migrate:latest` in CI to ensure `down()` is correct.

## Dos
- Always implement `down()` — test it before merging
- Wrap multi-step migrations (DDL + data) in a transaction when the DB supports transactional DDL (Postgres)
- Use `knex migrate:status` in app startup health checks to detect pending migrations
- Use timestamp prefixes (default) for migration file names to avoid ordering conflicts across branches
- Keep seed files idempotent using `onConflict().merge()` or `onConflict().ignore()`
- Separate test seeds from production seeds using environment-gated knexfile config

## Don'ts
- Never edit a migration file after it has been applied — Knex tracks checksums via `knex_migrations` table
- Don't use `migrate:rollback --all` in production — it undoes every migration
- Avoid putting business logic or application imports in migration files
- Don't skip `down()` even for "irreversible" changes — document the manual steps as a comment and throw an error
- Never rely on ORM model state inside migrations — use raw `knex.schema` and `knex.raw` to avoid coupling
- Avoid using `knex seed:run` in production with test data seeds
