# Express + Prisma Migrate

> Express-specific patterns for Prisma Migrate. Extends generic Express conventions.
> Prisma client setup is covered in `persistence/prisma.md`. Not repeated here.

## dev vs deploy

| Command | When to use |
|---------|-------------|
| `prisma migrate dev` | Local development — creates migration files, applies, generates client |
| `prisma migrate deploy` | CI/CD and production — applies existing migration files only, never creates new ones |
| `prisma migrate reset` | Local reset only — drops DB, re-applies all migrations |

Never run `migrate dev` or `migrate reset` in production or shared environments.

## Shadow Database in CI

Prisma `migrate dev` requires a shadow database for drift detection. Configure it explicitly:

```env
# .env.ci
DATABASE_URL="postgresql://user:pass@localhost:5432/myapp"
SHADOW_DATABASE_URL="postgresql://user:pass@localhost:5432/myapp_shadow"
```

`prisma/schema.prisma`:
```prisma
datasource db {
  provider          = "postgresql"
  url               = env("DATABASE_URL")
  shadowDatabaseUrl = env("SHADOW_DATABASE_URL")
}
```

CI step (GitHub Actions):
```yaml
- name: Run migrations
  run: npx prisma migrate deploy
  env:
    DATABASE_URL: ${{ secrets.DATABASE_URL }}
```

## Baseline for Existing Database

When adding Prisma Migrate to an existing database:

```bash
# 1. Generate initial migration SQL without running it
npx prisma migrate diff \
  --from-empty \
  --to-schema-datamodel prisma/schema.prisma \
  --script > prisma/migrations/0001_init/migration.sql

# 2. Mark as already applied (baseline), so Prisma doesn't re-run it
npx prisma migrate resolve --applied 0001_init
```

This tells Prisma the current DB state is already at `0001_init`.

## Startup Migration in Express

For staging/preview deployments only — not recommended for high-availability production:

```typescript
// src/lib/migrate.ts
import { execFile } from 'child_process';
import { promisify } from 'util';

const execFileAsync = promisify(execFile);

export async function runMigrations(): Promise<void> {
  if (process.env.RUN_MIGRATIONS !== 'true') return;
  console.log('Running Prisma migrations...');
  await execFileAsync('npx', ['prisma', 'migrate', 'deploy']);
}
```

## Package.json Scripts

```json
{
  "prisma:migrate": "prisma migrate dev --name",
  "prisma:deploy": "prisma migrate deploy",
  "prisma:studio": "prisma studio",
  "prisma:generate": "prisma generate",
  "prisma:reset": "prisma migrate reset"
}
```

## Scaffolder Patterns

```yaml
patterns:
  schema: "prisma/schema.prisma"
  migrations_dir: "prisma/migrations/"
  migration_file: "prisma/migrations/{timestamp}_{name}/migration.sql"
  migrate_helper: "src/lib/migrate.ts"
```

## Additional Dos/Don'ts

- DO commit all files under `prisma/migrations/` to version control
- DO use `migrate deploy` in all non-local environments
- DO configure `shadowDatabaseUrl` in CI to avoid permission errors
- DON'T delete or edit committed migration files — create a new migration to correct mistakes
- DON'T run `prisma db push` in shared environments — it bypasses the migration history
- DON'T run `migrate dev` in Docker containers that lack a shadow DB connection
