# Express + Drizzle ORM

> Express-specific patterns for Drizzle ORM. Extends generic Express conventions.
> Generic Express patterns are NOT repeated here.

## Integration Setup

```bash
npm install drizzle-orm postgres
npm install -D drizzle-kit @types/pg
```

`drizzle.config.ts`:
```typescript
import type { Config } from 'drizzle-kit';

export default {
  schema: './src/db/schema.ts',
  out: './drizzle',
  dialect: 'postgresql',
  dbCredentials: { url: process.env.DATABASE_URL! },
} satisfies Config;
```

## Schema Definition

```typescript
// src/db/schema.ts
import { pgTable, uuid, text, timestamp } from 'drizzle-orm/pg-core';

export const users = pgTable('users', {
  id: uuid('id').defaultRandom().primaryKey(),
  name: text('name').notNull(),
  email: text('email').notNull().unique(),
  createdAt: timestamp('created_at').defaultNow().notNull(),
});

export type User = typeof users.$inferSelect;
export type NewUser = typeof users.$inferInsert;
```

## Database Client

```typescript
// src/db/client.ts
import { drizzle } from 'drizzle-orm/postgres-js';
import postgres from 'postgres';
import * as schema from './schema';

const sql = postgres(process.env.DATABASE_URL!);
export const db = drizzle(sql, { schema });
```

## Schema Push vs Migrate

| Command | Use case |
|---------|----------|
| `npx drizzle-kit push` | Local dev — applies schema directly, no migration files |
| `npx drizzle-kit generate` + `npx drizzle-kit migrate` | Production — creates SQL migration files |

Never use `push` in production or shared environments.

## Prepared Statements

```typescript
import { eq } from 'drizzle-orm';
import { db } from '../db/client';
import { users } from '../db/schema';

// Prepared statement — compiled once, reused
const getUserById = db.select().from(users)
  .where(eq(users.id, sql.placeholder('id')))
  .prepare('get_user_by_id');

// Usage in handler
const user = await getUserById.execute({ id: req.params.id });
```

## Transaction Helper

```typescript
export async function withTransaction<T>(
  fn: (tx: typeof db) => Promise<T>
): Promise<T> {
  return db.transaction(fn);
}

// Usage
const result = await withTransaction(async (tx) => {
  const [user] = await tx.insert(users).values({ name, email }).returning();
  await tx.insert(auditLogs).values({ action: 'USER_CREATED', userId: user.id });
  return user;
});
```

## Scaffolder Patterns

```yaml
patterns:
  schema: "src/db/schema.ts"
  client: "src/db/client.ts"
  drizzle_config: "drizzle.config.ts"
  migrations_dir: "drizzle/"
  repository: "src/repository/{entity}.repository.ts"
```

## Additional Dos/Don'ts

- DO use `drizzle-kit generate` + `migrate` for production, never `push`
- DO co-locate `$inferSelect` / `$inferInsert` types with schema definitions
- DO use prepared statements for hot-path queries
- DON'T share a single `postgres()` connection across worker threads — create per-worker
- DON'T use `db.execute(sql\`raw\`)` when the typed query builder covers the use case
