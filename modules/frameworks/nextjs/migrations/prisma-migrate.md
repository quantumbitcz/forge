# Next.js + Prisma Migrate

> Next.js-specific Prisma Migrate workflow. Extends `modules/migrations/prisma-migrate.md`.
> Key difference from generic: `postinstall` script for Vercel, and deploy-hook pattern for preview environments.

## Integration Setup

```json
{
  "scripts": {
    "postinstall": "prisma generate",
    "db:migrate:deploy": "prisma migrate deploy",
    "db:migrate:dev": "prisma migrate dev",
    "db:seed": "tsx prisma/seed.ts"
  },
  "prisma": { "seed": "tsx prisma/seed.ts" }
}
```

## Framework-Specific Patterns

### Vercel deploy hook (`vercel.json`)
Run migrations before the build on every deploy:
```json
{
  "buildCommand": "prisma migrate deploy && next build"
}
```

### Shadow DB in CI (GitHub Actions)
```yaml
services:
  postgres:
    image: postgres:16
    env:
      POSTGRES_DB: app_test
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
  postgres_shadow:
    image: postgres:16
    env:
      POSTGRES_DB: app_shadow
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres

steps:
  - name: Run migrations
    run: npx prisma migrate deploy
    env:
      DATABASE_URL: postgresql://postgres:postgres@localhost/app_test
      SHADOW_DATABASE_URL: postgresql://postgres:postgres@localhost:5433/app_shadow
```

### Preview environments (Vercel)
Each preview branch gets its own database URL via Vercel environment variables.
Use `prisma migrate deploy` (not `dev`) in the build command — preview DBs may be shared.

### Seeding after migration in dev
```bash
npx prisma migrate reset   # drops, migrates, seeds — dev only
npx prisma db seed         # seed only
```

## Scaffolder Patterns
```
prisma/
  schema.prisma
  seed.ts
  migrations/
    migration_lock.toml   # commit this
    YYYYMMDDHHMMSS_name/
      migration.sql
.env.example              # DATABASE_URL placeholder (no real secrets)
.env.local                # gitignored
```

## Dos
- Set `postinstall: prisma generate` so Vercel generates the client after installing dependencies
- Use `prisma migrate deploy` in all automated environments
- Commit `migration_lock.toml` to prevent provider switching
- Use a separate `SHADOW_DATABASE_URL` in CI to isolate shadow DB operations

## Don'ts
- Don't run `prisma migrate dev` on Vercel or in CI
- Don't store `DATABASE_URL` in `.env` committed to the repo — use `.env.local` or Vercel env vars
- Don't use `prisma db push` beyond local schema prototyping
- Don't call `prisma.$connect()` / `prisma.$disconnect()` in Next.js app code
