# NestJS + TypeORM Migrations

> NestJS-specific TypeORM migration workflow. Extends `modules/migrations/typeorm-migrations.md`.
> Key addition: a separate `datasource.ts` CLI config decoupled from the NestJS DI container.

## Integration Setup

```bash
npm install @nestjs/typeorm typeorm pg
```

Add CLI scripts to `package.json`:
```json
{
  "scripts": {
    "migration:generate": "typeorm -d dist/datasource.js migration:generate src/migrations/$npm_config_name",
    "migration:run":      "typeorm -d dist/datasource.js migration:run",
    "migration:revert":   "typeorm -d dist/datasource.js migration:revert",
    "migration:create":   "typeorm migration:create src/migrations/$npm_config_name"
  }
}
```

## Framework-Specific Patterns

### `datasource.ts` — standalone CLI config
```typescript
// src/datasource.ts  (not imported by AppModule — CLI only)
import { DataSource } from 'typeorm';
import * as dotenv from 'dotenv';
dotenv.config();

export default new DataSource({
  type: 'postgres',
  url: process.env.DATABASE_URL,
  entities: ['src/**/*.entity{.ts,.js}'],
  migrations: ['src/migrations/*{.ts,.js}'],
});
```

### Generating a migration
```bash
npm run build                           # compile to dist/ first
npm run migration:generate --name=AddUserBio
# Inspect src/migrations/<timestamp>-AddUserBio.ts before committing
```

### Running migrations in NestJS bootstrap
```typescript
// main.ts
async function bootstrap() {
  const app = await NestFactory.create(AppModule);
  const dataSource = app.get(DataSource);
  await dataSource.runMigrations();     // run pending migrations on startup
  await app.listen(3000);
}
```

### CI step
```yaml
- name: Run migrations
  run: npm run build && npm run migration:run
  env:
    DATABASE_URL: ${{ secrets.DATABASE_URL }}
```

## Scaffolder Patterns
```
src/
  datasource.ts           # CLI-only DataSource
  migrations/
    <timestamp>-Init.ts
    <timestamp>-AddUserBio.ts
  app.module.ts           # TypeOrmModule.forRootAsync (no synchronize)
```

## Dos
- Keep `datasource.ts` independent of NestJS DI — use `dotenv.config()` directly
- Always build before running `migration:generate` so entity decorators are compiled
- Review generated migration SQL before committing — TypeORM can generate destructive changes
- Run `dataSource.runMigrations()` in bootstrap for zero-downtime deploys in K8s init containers

## Don'ts
- Don't use `synchronize: true` outside local development
- Don't import `datasource.ts` into `AppModule` — it duplicates the connection
- Don't skip the review of generated migration files before applying them
- Don't run `migration:revert` in production without a rollback plan
