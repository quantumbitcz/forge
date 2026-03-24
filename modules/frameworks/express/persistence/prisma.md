# Express + Prisma

> Express-specific patterns for Prisma ORM. Extends generic Express conventions.
> Generic Express patterns (middleware, routing, error handling) are NOT repeated here.

## Integration Setup

```bash
npm install @prisma/client
npm install -D prisma
npx prisma init
```

`prisma/schema.prisma`:
```prisma
datasource db {
  provider = "postgresql"
  url      = env("DATABASE_URL")
}

generator client {
  provider = "prisma-client-js"
}
```

## PrismaClient Singleton

```typescript
// src/lib/prisma.ts
import { PrismaClient } from '@prisma/client';

const globalForPrisma = globalThis as unknown as { prisma: PrismaClient };

export const prisma =
  globalForPrisma.prisma ??
  new PrismaClient({ log: process.env.NODE_ENV === 'development' ? ['query'] : [] });

if (process.env.NODE_ENV !== 'production') globalForPrisma.prisma = prisma;
```

## Middleware Pattern

Attach prisma to `res.locals` or use dependency injection — do NOT import directly in route handlers:

```typescript
// src/middleware/db.ts
import { prisma } from '../lib/prisma';
import type { Request, Response, NextFunction } from 'express';

export function dbMiddleware(req: Request, res: Response, next: NextFunction) {
  res.locals.prisma = prisma;
  next();
}
```

## Error Handling

```typescript
import { PrismaClientKnownRequestError } from '@prisma/client/runtime/library';

export function prismaErrorHandler(err: unknown, req: Request, res: Response, next: NextFunction) {
  if (err instanceof PrismaClientKnownRequestError) {
    if (err.code === 'P2002') return res.status(409).json({ error: 'Unique constraint violation' });
    if (err.code === 'P2025') return res.status(404).json({ error: 'Record not found' });
  }
  next(err);
}
```

## Transactions

```typescript
const result = await prisma.$transaction(async (tx) => {
  const user = await tx.user.create({ data: { name, email } });
  await tx.auditLog.create({ data: { action: 'USER_CREATED', userId: user.id } });
  return user;
});
```

## Health Check

```typescript
app.get('/health/db', async (_req, res) => {
  try {
    await prisma.$queryRaw`SELECT 1`;
    res.json({ status: 'ok' });
  } catch {
    res.status(503).json({ status: 'error' });
  }
});
```

## Graceful Shutdown

```typescript
process.on('SIGTERM', async () => {
  await prisma.$disconnect();
  server.close(() => process.exit(0));
});
```

## Scaffolder Patterns

```yaml
patterns:
  client_singleton: "src/lib/prisma.ts"
  db_middleware: "src/middleware/db.ts"
  prisma_error_handler: "src/middleware/prismaErrorHandler.ts"
  schema: "prisma/schema.prisma"
  seed: "prisma/seed.ts"
```

## Additional Dos/Don'ts

- DO use a singleton `PrismaClient` — multiple instances exhaust connection pool
- DO use `$transaction` for multi-step writes that must be atomic
- DO handle `P2002` (unique) and `P2025` (not found) codes explicitly
- DO disconnect on process termination
- DON'T use `prisma.model.findMany()` without pagination on unbounded tables
- DON'T catch `PrismaClientKnownRequestError` in route handlers — use centralized error middleware
