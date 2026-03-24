# Express + PostgreSQL (node-postgres)

> Express database patterns with `pg` (node-postgres): pool middleware, `req.db` injection, and transaction helpers.

## Integration Setup

```bash
npm install pg
npm install -D @types/pg
```

```typescript
// src/db/pool.ts
import { Pool } from 'pg';

export const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  max: 20,
  idleTimeoutMillis: 30_000,
  connectionTimeoutMillis: 2_000,
  ssl: process.env.DB_SSL === 'true' ? { rejectUnauthorized: false } : undefined,
});

pool.on('error', (err) => {
  console.error('Unexpected idle client error', err);
});
```

## Framework-Specific Patterns

### Pool middleware — `req.db` pattern
Attach a pool client to `res.locals` so handlers receive a managed connection:
```typescript
// src/middleware/db.ts
import { pool } from '../db/pool';
import type { Request, Response, NextFunction } from 'express';

export async function dbMiddleware(req: Request, res: Response, next: NextFunction) {
  res.locals.db = pool;  // pass pool (not a checked-out client) for simple queries
  next();
}
```

Extend Express `Locals` type:
```typescript
// src/types/express.d.ts
import type { Pool } from 'pg';
declare global {
  namespace Express {
    interface Locals { db: Pool }
  }
}
```

### Transaction helper
```typescript
// src/db/transaction.ts
import { pool } from './pool';

export async function withTransaction<T>(fn: (client: import('pg').PoolClient) => Promise<T>): Promise<T> {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const result = await fn(client);
    await client.query('COMMIT');
    return result;
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
}
```

### Usage in a route
```typescript
// src/routes/orders.ts
import { withTransaction } from '../db/transaction';

router.post('/', async (req, res, next) => {
  try {
    const order = await withTransaction(async (client) => {
      const { rows: [o] } = await client.query(
        'INSERT INTO orders (user_id, total) VALUES ($1, $2) RETURNING *',
        [req.body.userId, req.body.total]
      );
      await client.query('UPDATE users SET order_count = order_count + 1 WHERE id = $1', [req.body.userId]);
      return o;
    });
    res.status(201).json(order);
  } catch (err) {
    next(err);
  }
});
```

## Scaffolder Patterns
```
src/
  db/
    pool.ts             # Pool singleton
    transaction.ts      # withTransaction helper
  middleware/
    db.ts               # attach pool to res.locals
  types/
    express.d.ts        # augment Express.Locals
  routes/
    users.ts            # use res.locals.db or withTransaction
```

## Dos
- Use parameterized queries (`$1`, `$2`) exclusively — never string interpolation
- Always `release()` a checked-out client in a `finally` block
- Set `max`, `idleTimeoutMillis`, and `connectionTimeoutMillis` explicitly for production
- Use `withTransaction` for any multi-statement operations that must be atomic

## Don'ts
- Don't create a new `Pool` per request — one pool for the application lifetime
- Don't use `client.query` directly in route handlers — go through the transaction helper or `res.locals.db`
- Don't expose raw `pg` error messages to the client (`error.detail` may contain data)
- Don't skip `pool.on('error', ...)` — unhandled idle errors crash the process
