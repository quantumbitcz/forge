# Prisma Best Practices

## Overview
Prisma is a schema-first TypeScript ORM with auto-generated, type-safe client code. Use it for Node.js/TypeScript projects where developer ergonomics and type safety on database queries matter. Avoid it for applications needing complex raw SQL with full type safety (consider Drizzle or kysely), or for projects where schema-first workflows conflict with existing migration infrastructure.

## Architecture Patterns

### Schema-First Design
```prisma
// schema.prisma
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
  name      String
  createdAt DateTime @default(now()) @map("created_at")
  orders    Order[]

  @@map("users")
  @@index([email])
}

model Order {
  id         Int      @id @default(autoincrement())
  userId     Int      @map("user_id")
  total      Decimal  @db.Decimal(10, 2)
  status     String   @default("pending")
  createdAt  DateTime @default(now()) @map("created_at")
  user       User     @relation(fields: [userId], references: [id], onDelete: Cascade)
  items      OrderItem[]

  @@map("orders")
  @@index([userId, status])
}
```

### Repository Pattern
```typescript
// Wrap PrismaClient — never import it directly in business logic
export class OrderRepository {
  constructor(private readonly prisma: PrismaClient) {}

  async findByIdWithItems(id: number): Promise<OrderWithItems | null> {
    return this.prisma.order.findUnique({
      where: { id },
      include: {
        items: { include: { product: true } },
        user:  { select: { id: true, email: true } },
      },
    });
  }

  async findByCustomer(userId: number, limit = 20): Promise<Order[]> {
    return this.prisma.order.findMany({
      where: { userId },
      orderBy: { createdAt: "desc" },
      take: limit,
      select: { id: true, total: true, status: true, createdAt: true },
    });
  }
}
```

### Transactions
```typescript
// Interactive transaction for complex multi-step operations
async function placeOrder(dto: CreateOrderDto): Promise<Order> {
  return prisma.$transaction(async (tx) => {
    const user = await tx.user.findUniqueOrThrow({ where: { id: dto.userId } });

    const order = await tx.order.create({
      data: {
        userId: user.id,
        total:  dto.total,
        items:  { create: dto.items },
      },
    });

    await tx.inventory.updateMany({
      where: { productId: { in: dto.items.map(i => i.productId) } },
      data:  { reserved: { increment: 1 } },
    });

    return order;
  });
}
```

## Configuration

```typescript
// prisma.ts — singleton pattern for Next.js / Node.js
import { PrismaClient } from "@prisma/client";

const globalForPrisma = globalThis as unknown as { prisma: PrismaClient };

export const prisma =
  globalForPrisma.prisma ??
  new PrismaClient({
    log: process.env.NODE_ENV === "development"
      ? ["query", "warn", "error"]
      : ["warn", "error"],
  });

if (process.env.NODE_ENV !== "production") {
  globalForPrisma.prisma = prisma;
}
```

## Performance

### Relation Queries — include vs select
```typescript
// include: loads all columns of relation + nested — can be heavy
const withItems = await prisma.order.findMany({ include: { items: true } });

// select: precise projection — load only what you need
const slim = await prisma.order.findMany({
  select: {
    id:    true,
    total: true,
    items: { select: { productId: true, quantity: true } },
  },
});

// N+1 anti-pattern: never call prisma inside a loop
// Fix: use include/select with nested relations in a single query
```

### Batch Operations
```typescript
// createMany — single INSERT (no nested creates)
await prisma.user.createMany({
  data: users,
  skipDuplicates: true,
});

// $transaction with array for atomic batch (no interactive TX overhead)
await prisma.$transaction([
  prisma.order.updateMany({ where: { status: "pending" }, data: { status: "expired" } }),
  prisma.auditLog.create({ data: { action: "expire_orders", count: pendingCount } }),
]);
```

### Connection Pooling
```
# .env — use PgBouncer / Prisma Accelerate for serverless
DATABASE_URL="postgresql://user:pass@pgbouncer:6432/db?pgbouncer=true"
DIRECT_URL="postgresql://user:pass@postgres:5432/db"  # for migrations
```

```prisma
datasource db {
  provider  = "postgresql"
  url       = env("DATABASE_URL")
  directUrl = env("DIRECT_URL")
}
```

## Security

```typescript
// SAFE: Prisma Client always parameterizes — no injection via where/data
prisma.user.findMany({ where: { email: userInput } })

// Raw SQL escape hatch — use Prisma.sql tag for safe interpolation
import { Prisma } from "@prisma/client";
const users = await prisma.$queryRaw<User[]>(
  Prisma.sql`SELECT * FROM users WHERE email = ${userInput}`
);

// UNSAFE: never use $queryRawUnsafe with user input
// await prisma.$queryRawUnsafe(`SELECT * FROM users WHERE email = '${userInput}'`)
```

## Testing

```typescript
// Jest + @prisma/client mock
import { mockDeep, mockReset } from "jest-mock-extended";

const prismaMock = mockDeep<PrismaClient>();
jest.mock("../prisma", () => ({ prisma: prismaMock }));

beforeEach(() => mockReset(prismaMock));

test("findByIdWithItems returns null for unknown id", async () => {
  prismaMock.order.findUnique.mockResolvedValue(null);
  const repo = new OrderRepository(prismaMock);
  expect(await repo.findByIdWithItems(999)).toBeNull();
});

// Integration test with Testcontainers + prisma migrate deploy
describe("OrderRepository integration", () => {
  let prisma: PrismaClient;
  beforeAll(async () => {
    // container.getConnectionUri() → set DATABASE_URL, run prisma migrate deploy
    prisma = new PrismaClient({ datasources: { db: { url: container.getConnectionUri() } } });
    await prisma.$connect();
  });
  afterAll(() => prisma.$disconnect());
});
```

## Dos
- Use `select` over `include` to project only needed fields — prevents over-fetching.
- Use `prisma.$transaction(async (tx) => {...})` for multi-step operations that must be atomic.
- Create a singleton `PrismaClient` instance — multiple instances exhaust the connection pool.
- Use `Prisma.sql` tagged template for safe raw queries instead of `$queryRawUnsafe`.
- Run `prisma migrate deploy` (not `prisma db push`) in production — push is destructive.
- Add `directUrl` to `datasource` when using PgBouncer/Prisma Accelerate — migrations need a direct connection.
- Use `skipDuplicates: true` in `createMany` when upserting seed or import data.

## Don'ts
- Don't call Prisma queries inside loops — causes N+1; use `include` or `findMany` with `in` filter.
- Don't use `$queryRawUnsafe` with user-supplied data — SQL injection risk.
- Don't use `prisma db push` in production — it can silently drop columns.
- Don't instantiate `PrismaClient` per request in serverless environments — creates connection exhaustion.
- Don't use `deleteMany({})` without a `where` clause in production code — truncates the table.
- Don't ignore Prisma's generated types — they are the contract between schema and application code.
- Don't commit `prisma/migrations/` as unreviewed — migration files modify production schema.
