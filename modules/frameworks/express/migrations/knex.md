# Express + Knex Migrations

> Express-specific patterns for Knex.js migrations. Extends generic Express conventions.
> Generic Express patterns are NOT repeated here.

## Integration Setup

```bash
npm install knex pg
npm install -D @types/knex ts-node
```

## knexfile.ts

```typescript
// knexfile.ts
import type { Knex } from 'knex';

const base: Knex.Config = {
  client: 'pg',
  migrations: { tableName: 'knex_migrations', directory: './src/migrations' },
  seeds: { directory: './src/seeds' },
};

const config: Record<string, Knex.Config> = {
  development: {
    ...base,
    connection: process.env.DATABASE_URL,
  },
  test: {
    ...base,
    connection: process.env.TEST_DATABASE_URL,
  },
  production: {
    ...base,
    connection: {
      connectionString: process.env.DATABASE_URL,
      ssl: { rejectUnauthorized: true },
    },
    pool: { min: 2, max: 10 },
  },
};

export default config;
```

## Migration File Pattern

```typescript
// src/migrations/20240315120000_create_users.ts
import type { Knex } from 'knex';

export async function up(knex: Knex): Promise<void> {
  await knex.schema.createTable('users', (table) => {
    table.uuid('id').primary().defaultTo(knex.fn.uuid());
    table.string('name').notNullable();
    table.string('email').notNullable().unique();
    table.timestamps(true, true);
  });
}

export async function down(knex: Knex): Promise<void> {
  await knex.schema.dropTableIfExists('users');
}
```

## Seed Files

```typescript
// src/seeds/01_users.ts
import type { Knex } from 'knex';

export async function seed(knex: Knex): Promise<void> {
  await knex('users').del();
  await knex('users').insert([
    { name: 'Alice', email: 'alice@example.com' },
  ]);
}
```

## CLI Integration

`package.json` scripts:
```json
{
  "migrate:latest": "knex --knexfile knexfile.ts migrate:latest",
  "migrate:rollback": "knex --knexfile knexfile.ts migrate:rollback",
  "migrate:make": "knex --knexfile knexfile.ts migrate:make",
  "seed:run": "knex --knexfile knexfile.ts seed:run"
}
```

Run via `ts-node`: add `-r ts-node/register` flag or use `tsx` as the runner.

## Run Migrations at Startup

```typescript
// src/lib/db.ts
import knex from 'knex';
import knexConfig from '../../knexfile';

const env = process.env.NODE_ENV ?? 'development';
export const db = knex(knexConfig[env]);

export async function runMigrations(): Promise<void> {
  await db.migrate.latest();
}
```

## Scaffolder Patterns

```yaml
patterns:
  knexfile: "knexfile.ts"
  db_client: "src/lib/db.ts"
  migration: "src/migrations/{timestamp}_{description}.ts"
  seed: "src/seeds/{order}_{description}.ts"
```

## Additional Dos/Don'ts

- DO use timestamped migration filenames (Knex auto-generates these via `migrate:make`)
- DO run `migrate.latest()` at app startup in development and staging environments
- DO separate seed files with numeric prefixes to control order
- DON'T modify an already-run migration — create a new one
- DON'T use `migrate.latest()` in production startup without a deployment lock strategy
