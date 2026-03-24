# TypeORM Migrations

> Generic TypeORM migration patterns for any Node.js project. Framework-specific extensions live in the relevant framework binding (e.g., `modules/frameworks/nestjs/migrations/typeorm-migrations.md`).

## Overview
TypeORM generates SQL migration files by diffing your entity definitions against the database schema. Use a standalone `DataSource` config for CLI operations so it is decoupled from any framework DI container.

## Architecture Patterns

### `datasource.ts` — standalone CLI config
```typescript
// datasource.ts (project root or src/)
import { DataSource } from 'typeorm';
import * as dotenv from 'dotenv';
dotenv.config();

export default new DataSource({
  type: 'postgres',
  url: process.env.DATABASE_URL,
  entities: ['src/**/*.entity{.ts,.js}'],
  migrations: ['src/migrations/*{.ts,.js}'],
  migrationsTableName: 'migrations',
});
```

### Migration workflow
```bash
# Generate: diff entities vs. current DB → write migration file
typeorm -d dist/datasource.js migration:generate src/migrations/AddUserBio

# Run: apply all pending migrations
typeorm -d dist/datasource.js migration:run

# Revert: undo the last applied migration
typeorm -d dist/datasource.js migration:revert

# Show status: list applied and pending
typeorm -d dist/datasource.js migration:show
```

### Generated migration structure
```typescript
// src/migrations/1711000000000-AddUserBio.ts
import { MigrationInterface, QueryRunner } from 'typeorm';

export class AddUserBio1711000000000 implements MigrationInterface {
  async up(queryRunner: QueryRunner) {
    await queryRunner.query(`ALTER TABLE "user" ADD "bio" character varying`);
  }

  async down(queryRunner: QueryRunner) {
    await queryRunner.query(`ALTER TABLE "user" DROP COLUMN "bio"`);
  }
}
```

## Configuration

### `package.json` scripts
```json
{
  "scripts": {
    "migration:generate": "typeorm -d dist/datasource.js migration:generate src/migrations/$npm_config_name",
    "migration:run":      "typeorm -d dist/datasource.js migration:run",
    "migration:revert":   "typeorm -d dist/datasource.js migration:revert"
  }
}
```

### CI step
```yaml
- name: Run DB migrations
  run: npm run build && typeorm -d dist/datasource.js migration:run
  env:
    DATABASE_URL: ${{ secrets.DATABASE_URL }}
```

## Dos
- Keep `datasource.ts` independent of your DI framework; load env with `dotenv.config()`
- Always compile to `dist/` before running the CLI (`npm run build`)
- Review every generated `migration.sql` for destructive operations before committing
- Always implement the `down()` method to support rollback
- Use `migrationsTableName` to avoid clashes in shared schemas

## Don'ts
- Don't use `synchronize: true` outside local development prototyping
- Don't edit migration files after they've been applied to any shared environment
- Don't rely on `migration:revert` in production without a tested rollback procedure
- Don't run `migration:generate` against a production database
