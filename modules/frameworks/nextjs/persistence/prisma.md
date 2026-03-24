# Next.js + Prisma

> Next.js-specific Prisma patterns. Extends generic prisma-migrate conventions.
> Hot-reload dev installs multiple PrismaClient instances — use the global singleton to prevent exhausting the connection pool.

## Integration Setup

```bash
npm install @prisma/client
npm install -D prisma
npx prisma init
```

Add a `postinstall` script so Vercel and CI generate the client after `npm ci`:
```json
{ "scripts": { "postinstall": "prisma generate" } }
```

## Framework-Specific Patterns

### Global singleton (required in Next.js dev mode)
```typescript
// lib/prisma.ts
import { PrismaClient } from '@prisma/client';

const globalForPrisma = globalThis as unknown as { prisma: PrismaClient };

export const prisma =
  globalForPrisma.prisma ??
  new PrismaClient({ log: process.env.NODE_ENV === 'development' ? ['query'] : [] });

if (process.env.NODE_ENV !== 'production') globalForPrisma.prisma = prisma;
```

### Server Actions with Prisma
```typescript
// app/users/actions.ts
'use server';
import { prisma } from '@/lib/prisma';
import { revalidatePath } from 'next/cache';

export async function createUser(data: { name: string; email: string }) {
  const user = await prisma.user.create({ data });
  revalidatePath('/users');
  return user;
}
```

### Route Handlers
```typescript
// app/api/users/route.ts
import { NextRequest, NextResponse } from 'next/server';
import { prisma } from '@/lib/prisma';

export async function GET() {
  const users = await prisma.user.findMany({ orderBy: { createdAt: 'desc' } });
  return NextResponse.json(users);
}

export async function POST(req: NextRequest) {
  const body = await req.json();
  const user = await prisma.user.create({ data: body });
  return NextResponse.json(user, { status: 201 });
}
```

## Scaffolder Patterns
```
prisma/
  schema.prisma
  seed.ts
  migrations/
lib/
  prisma.ts           # singleton
app/
  api/
    [resource]/
      route.ts        # Route Handler using prisma
  [resource]/
    actions.ts        # Server Actions using prisma
```

## Dos
- Always use the `globalThis` singleton — Next.js hot reload creates new module instances
- Call `prisma.$disconnect()` in long-running scripts (not in app code — connection is managed by pool)
- Use Server Actions for mutations; Route Handlers for external API consumers
- Call `revalidatePath` or `revalidateTag` in Server Actions after mutations

## Don'ts
- Don't instantiate `new PrismaClient()` directly in Server Components or Route Handlers
- Don't use `prisma migrate dev` in Vercel or CI — use `prisma migrate deploy`
- Don't expose raw Prisma errors to the client; map them to typed error responses
- Don't use `prisma.$executeRaw` with string interpolation — use tagged template literals
