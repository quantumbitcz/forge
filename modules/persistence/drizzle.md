# Drizzle ORM Best Practices

## Overview
Drizzle is a TypeScript-first ORM that defines schema in TypeScript and generates fully typed queries with zero runtime overhead. Use it for TypeScript projects (especially serverless/edge) where you want SQL-close querying with compile-time type safety. Avoid it for teams that prefer schema-first approaches like Prisma, or when you need a mature migration ecosystem with visual tooling.

## Architecture Patterns

### Schema in TypeScript
```typescript
// schema.ts — single source of truth for all tables
import { pgTable, serial, varchar, numeric, integer,
         timestamp, index } from "drizzle-orm/pg-core";

export const users = pgTable("users", {
  id:        serial("id").primaryKey(),
  email:     varchar("email", { length: 255 }).notNull().unique(),
  name:      varchar("name",  { length: 100 }).notNull(),
  createdAt: timestamp("created_at").defaultNow().notNull(),
}, (table) => ({
  emailIdx: index("users_email_idx").on(table.email),
}));

export const orders = pgTable("orders", {
  id:         serial("id").primaryKey(),
  userId:     integer("user_id").notNull().references(() => users.id, { onDelete: "cascade" }),
  total:      numeric("total", { precision: 10, scale: 2 }).notNull(),
  status:     varchar("status", { length: 20 }).notNull().default("pending"),
  createdAt:  timestamp("created_at").defaultNow().notNull(),
}, (table) => ({
  userStatusIdx: index("orders_user_status_idx").on(table.userId, table.status),
}));
```

### Repository Pattern
```typescript
import { db } from "./db";
import { orders, users } from "./schema";
import { eq, desc, and } from "drizzle-orm";

export class OrderRepository {
  async findById(id: number) {
    return db.query.orders.findFirst({
      where: eq(orders.id, id),
      with: { user: { columns: { id: true, email: true } } },
    });
  }

  async findByUserId(userId: number, limit = 20) {
    return db
      .select({
        id:     orders.id,
        total:  orders.total,
        status: orders.status,
      })
      .from(orders)
      .where(eq(orders.userId, userId))
      .orderBy(desc(orders.createdAt))
      .limit(limit);
  }

  async updateStatus(id: number, status: string) {
    const [updated] = await db
      .update(orders)
      .set({ status })
      .where(eq(orders.id, id))
      .returning();
    return updated;
  }
}
```

### Relational Queries API
```typescript
// Define relations for the relational query API
import { relations } from "drizzle-orm";

export const usersRelations = relations(users, ({ many }) => ({
  orders: many(orders),
}));

export const ordersRelations = relations(orders, ({ one }) => ({
  user: one(users, { fields: [orders.userId], references: [users.id] }),
}));

// Type-safe nested query
const result = await db.query.users.findMany({
  with: {
    orders: {
      where: eq(orders.status, "pending"),
      columns: { id: true, total: true },
    },
  },
});
```

## Configuration

```typescript
// db.ts
import { drizzle } from "drizzle-orm/node-postgres";
import { Pool }    from "pg";
import * as schema from "./schema";

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  max:              10,
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 5000,
});

export const db = drizzle(pool, { schema, logger: process.env.NODE_ENV === "development" });
```

```typescript
// drizzle.config.ts — migration config
import { defineConfig } from "drizzle-kit";

export default defineConfig({
  schema:    "./src/schema.ts",
  out:       "./drizzle",
  dialect:   "postgresql",
  dbCredentials: { url: process.env.DATABASE_URL! },
  verbose:   true,
  strict:    true,
});
```

## Performance

### Prepared Statements
```typescript
// Prepared statements: compiled once, reused many times
import { placeholder } from "drizzle-orm";

const prepared = db.query.orders.findMany({
  where: eq(orders.userId, placeholder("userId")),
  limit: placeholder("limit"),
}).prepare("find_user_orders");

// Reuse in hot paths
const results = await prepared.execute({ userId: 42, limit: 20 });
```

### Batch Operations
```typescript
// Insert many rows
await db.insert(users).values([
  { email: "a@test.com", name: "Alice" },
  { email: "b@test.com", name: "Bob" },
]);

// Batch update with CASE (custom SQL)
import { sql } from "drizzle-orm";
await db.update(orders)
  .set({ status: sql`CASE WHEN total > 100 THEN 'premium' ELSE status END` })
  .where(eq(orders.userId, userId));
```

### Push vs Migration Workflows
```bash
# Development: push schema changes directly (no migration files)
npx drizzle-kit push

# Production: generate and review SQL migration files
npx drizzle-kit generate
npx drizzle-kit migrate   # apply pending migrations
```

## Security

```typescript
// SAFE: all Drizzle operators (eq, like, inArray) are parameterized
db.select().from(users).where(eq(users.email, userInput))

// SAFE: sql template tag for raw expressions — values are bound params
import { sql } from "drizzle-orm";
db.select().from(users).where(sql`lower(email) = lower(${userInput})`)

// UNSAFE: never concatenate user input into the sql tag's string part
// db.select().from(users).where(sql`email = '${userInput}'`)  // injection!
```

## Testing

```typescript
import { drizzle } from "drizzle-orm/node-postgres";
import { migrate }  from "drizzle-orm/node-postgres/migrator";

describe("OrderRepository", () => {
  let db: ReturnType<typeof drizzle>;

  beforeAll(async () => {
    // Testcontainers: start postgres, run migrations
    const container = await new PostgreSqlContainer("postgres:16-alpine").start();
    const pool = new Pool({ connectionString: container.getConnectionUri() });
    db = drizzle(pool, { schema });
    await migrate(db, { migrationsFolder: "./drizzle" });
  });

  it("findById returns null for unknown id", async () => {
    const repo = new OrderRepository(db);
    expect(await repo.findById(999)).toBeUndefined();
  });

  it("updateStatus returns updated row", async () => {
    const [order] = await db.insert(orders).values({ userId: 1, total: "50.00" }).returning();
    const updated = await new OrderRepository(db).updateStatus(order.id, "shipped");
    expect(updated.status).toBe("shipped");
  });
});
```

## Dos
- Define your full schema in TypeScript — it is the migration source of truth.
- Use `db.query.*` relational API for nested data; use `db.select()` builder for projections and aggregations.
- Use prepared statements for queries executed on every request — avoids per-call planning overhead.
- Use `drizzle-kit generate` + `drizzle-kit migrate` in production; use `push` only in development.
- Use `returning()` after `insert`/`update`/`delete` to avoid a second `SELECT` round-trip.
- Set strict TypeScript mode — Drizzle's type inference depends on strict null checks.
- Add composite indexes via the table callback in `pgTable` for multi-column filter patterns.

## Don'ts
- Don't use `drizzle-kit push` in production — it does not create migration files and can cause data loss.
- Don't build raw SQL strings with user input inside `sql` template tag's static part.
- Don't call the relational API (`db.query.*`) without defining relations in `*Relations` objects.
- Don't use `db.select().from(table)` without a `.where()` clause on large tables — full scan.
- Don't forget `{ onDelete: "cascade" }` or `"restrict"` on FK references — defaults allow orphans.
- Don't share a single database connection (not pool) across concurrent requests.
- Don't ignore TypeScript errors from Drizzle's inferred types — they indicate schema-code mismatches.
