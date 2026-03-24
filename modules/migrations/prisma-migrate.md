# Prisma Migrate Best Practices

## Overview
Prisma Migrate generates and applies SQL migrations by diffing your `schema.prisma` against the current database state using a shadow database. Use it for Node.js/TypeScript projects using the Prisma ORM. Avoid using `prisma migrate dev` in CI or production — use `prisma migrate deploy` there instead.

## Architecture Patterns

### Directory structure
```
prisma/
├── schema.prisma
├── seed.ts                         # Database seeding
└── migrations/
    ├── migration_lock.toml         # Locks the provider; commit this
    ├── 20240101120000_create_users/
    │   └── migration.sql
    ├── 20240115093000_add_email_index/
    │   └── migration.sql
    └── 20240201_add_custom_step/
        └── migration.sql
```

### schema.prisma essentials
```prisma
generator client {
  provider = "prisma-client-js"
}

datasource db {
  provider = "postgresql"
  url      = env("DATABASE_URL")
}

model User {
  id        Int      @id @default(autoincrement())
  email     String   @unique
  name      String?
  createdAt DateTime @default(now())
  orders    Order[]
}
```

### Migration workflow
```bash
# Development: generates migration SQL, applies it, regenerates client
prisma migrate dev --name add_user_bio

# Production / CI: applies pending migrations only (no shadow DB needed)
prisma migrate deploy

# Inspect pending migrations without applying
prisma migrate status
```

### Shadow database
Prisma uses a temporary shadow database to detect schema drift. Configure separately from the main DB:
```env
DATABASE_URL="postgresql://user:pass@localhost/myapp"
SHADOW_DATABASE_URL="postgresql://user:pass@localhost/myapp_shadow"
```
In hosted environments (e.g., PlanetScale), disable shadow DB and use `prisma migrate diff` manually.

### Custom SQL steps
Add custom SQL to a generated migration file before applying:
```sql
-- prisma/migrations/20240201_add_full_name/migration.sql
-- CreateIndex
ALTER TABLE "users" ADD COLUMN "full_name" TEXT;

-- Custom: backfill existing rows
UPDATE "users" SET "full_name" = first_name || ' ' || last_name;

-- Custom: add constraint after backfill
ALTER TABLE "users" ALTER COLUMN "full_name" SET NOT NULL;
```

### Baselining an existing database
```bash
# Mark current state as applied without running the SQL
prisma migrate resolve --applied 20240101120000_create_users
```

## Configuration

### package.json scripts
```json
{
  "scripts": {
    "db:migrate": "prisma migrate deploy",
    "db:migrate:dev": "prisma migrate dev",
    "db:seed": "prisma db seed",
    "db:reset": "prisma migrate reset",
    "db:generate": "prisma generate"
  },
  "prisma": {
    "seed": "ts-node prisma/seed.ts"
  }
}
```

### CI migration step
```yaml
- name: Run DB migrations
  run: npx prisma migrate deploy
  env:
    DATABASE_URL: ${{ secrets.DATABASE_URL }}
```

## Performance

### Zero-downtime: additive changes first
```prisma
// Deploy N: add nullable column
model User {
  displayName String?   // nullable — no lock
}
```
```sql
-- In migration file for Deploy N+1: backfill + enforce
UPDATE "users" SET "display_name" = first_name || ' ' || last_name
  WHERE "display_name" IS NULL;
ALTER TABLE "users" ALTER COLUMN "display_name" SET NOT NULL;
```

### Large table index (Postgres)
Add a custom SQL step to the generated migration:
```sql
CREATE INDEX CONCURRENTLY "idx_orders_created_at" ON "orders"("created_at");
```

## Security
- Store `DATABASE_URL` in environment variables or a secrets manager; never in `.env` committed to git
- Add `.env` to `.gitignore`; commit `.env.example` with placeholder values
- The migration runner needs DDL rights; the Prisma Client runtime user needs DML only
- `_prisma_migrations` table records applied migrations — protect it from manual edits

## Testing
```bash
# Reset to clean state and re-apply all migrations
prisma migrate reset --force   # development only

# In CI: fresh DB per test run
DATABASE_URL=postgresql://localhost/test_$(date +%s) prisma migrate deploy
```
Use Testcontainers or a dedicated test schema. Call `prisma migrate deploy` before your test suite; never `migrate dev` in CI.

## Dos
- Commit `migration_lock.toml` — it prevents accidental provider switching
- Always review generated `migration.sql` before committing; add custom SQL steps when needed
- Use `prisma migrate deploy` in all automated environments (CI, staging, production)
- Keep `prisma db seed` idempotent with upsert logic so it can be safely re-run
- Use `prisma migrate status` in health checks to detect migration drift
- Squash old migrations using `prisma migrate diff` + manual merge for long-lived projects
- Set `shadowDatabaseUrl` explicitly in shared or hosted environments

## Don'ts
- Never run `prisma migrate dev` in CI or production — it creates a shadow DB and modifies migration history
- Don't edit `migration.sql` files after they've been applied; create a new migration instead
- Avoid `prisma db push` in any environment beyond local prototyping — it bypasses migration history
- Never delete rows from `_prisma_migrations` manually
- Don't use `prisma migrate reset` in staging or production — it drops all data
- Avoid putting sensitive data in seed files committed to version control
