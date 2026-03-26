# MikroORM Migrations Best Practices

## Overview
MikroORM provides built-in migration support generating TypeScript migration files from entity changes. Use it when your TypeScript backend uses MikroORM and you want schema migrations auto-generated from entity diffs. The migration tool compares current entities against the schema snapshot to produce migration SQL.

## Conventions

### Migration Generation
```bash
# Generate migration from entity diff
npx mikro-orm migration:create

# Run pending migrations
npx mikro-orm migration:up

# Rollback last migration
npx mikro-orm migration:down

# Check migration status
npx mikro-orm migration:list

# Generate initial migration from scratch
npx mikro-orm migration:create --initial
```

### Migration File Example
```typescript
import { Migration } from "@mikro-orm/migrations";

export class Migration20260326100000 extends Migration {
  async up(): Promise<void> {
    this.addSql(`
      CREATE TABLE "users" (
        "id" SERIAL PRIMARY KEY,
        "email" VARCHAR(255) NOT NULL UNIQUE,
        "name" VARCHAR(255) NOT NULL,
        "created_at" TIMESTAMPTZ NOT NULL DEFAULT NOW()
      );
    `);
    this.addSql(`CREATE INDEX "idx_users_email" ON "users" ("email");`);
  }

  async down(): Promise<void> {
    this.addSql(`DROP TABLE IF EXISTS "users";`);
  }
}
```

## Configuration

```typescript
// mikro-orm.config.ts
export default defineConfig({
  migrations: {
    path: "./src/migrations",
    pathTs: "./src/migrations",
    transactional: true,
    allOrNothing: true,
    snapshot: true
  }
});
```

## Dos
- Use `migration:create` to auto-generate migrations from entity diffs — manual SQL is error-prone.
- Enable `transactional: true` so each migration runs in a transaction and rolls back on failure.
- Enable `snapshot: true` to track schema snapshots for accurate diff generation.
- Review generated SQL before applying — auto-generated migrations can produce suboptimal DDL.
- Run `migration:list` in CI to verify all migrations are applied.
- Use `allOrNothing: true` to prevent partial migration application.
- Test migrations against a fresh database in CI — generate from scratch and verify.

## Don'ts
- Don't modify applied migrations — create new ones to fix issues.
- Don't skip reviewing generated SQL — auto-generated migrations may produce unnecessary operations.
- Don't use `SchemaGenerator.updateSchema()` in production — always use the migration system.
- Don't delete the snapshot file — it's needed for accurate diff generation.
- Don't mix manual SQL and auto-generated migrations without careful ordering.
- Don't assume entity changes always produce correct migrations — test complex refactors manually.
- Don't run migrations without `transactional: true` — partial failures leave the database in an inconsistent state.
