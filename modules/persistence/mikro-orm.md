# MikroORM Best Practices

## Overview
MikroORM is a TypeScript-first ORM with identity map, unit of work, and first-class support for PostgreSQL, MySQL, MariaDB, SQLite, and MongoDB. Use it for TypeScript backends (especially NestJS) where type safety, decorator-based entities, and automatic change tracking matter. MikroORM excels at clean repository patterns and automatic dirty checking. Avoid it for JavaScript-only projects (Sequelize is more established) or when you want schema-first development (Prisma or Drizzle fit better).

## Architecture Patterns

**Entity definition:**
```typescript
import { Entity, PrimaryKey, Property, ManyToOne, Collection, OneToMany } from "@mikro-orm/core";

@Entity()
export class User {
  @PrimaryKey()
  id!: number;

  @Property({ unique: true })
  email!: string;

  @Property()
  name!: string;

  @OneToMany(() => Order, order => order.user)
  orders = new Collection<Order>(this);

  @Property()
  createdAt = new Date();
}

@Entity()
export class Order {
  @PrimaryKey()
  id!: number;

  @ManyToOne(() => User)
  user!: User;

  @Property({ type: "decimal", precision: 10, scale: 2 })
  total!: string;
}
```

**Unit of Work (automatic change tracking):**
```typescript
const em = orm.em.fork();
const user = await em.findOneOrFail(User, { email: "alice@example.com" });
user.name = "Alice Smith";  // tracked automatically
await em.flush();  // generates UPDATE only for changed fields
```

**Repository pattern:**
```typescript
const userRepo = em.getRepository(User);
const users = await userRepo.find(
  { orders: { total: { $gte: 100 } } },
  { populate: ["orders"], orderBy: { createdAt: "DESC" }, limit: 20 }
);
```

**Query builder for complex queries:**
```typescript
const qb = em.createQueryBuilder(Order, "o");
const results = await qb
  .select(["o.userId", raw("SUM(o.total) as total_spent")])
  .groupBy("o.userId")
  .having({ total_spent: { $gte: 1000 } })
  .execute();
```

**Anti-pattern — sharing EntityManager across requests:** The EntityManager's identity map accumulates entities across the request lifecycle. Share the `orm` instance but fork `em` per request to prevent memory leaks and stale data.

## Configuration

**MikroORM config:**
```typescript
import { defineConfig } from "@mikro-orm/postgresql";

export default defineConfig({
  entities: ["./dist/entities/**/*.js"],
  entitiesTs: ["./src/entities/**/*.ts"],
  dbName: "mydb",
  host: "localhost",
  port: 5432,
  user: "app",
  password: process.env.DB_PASSWORD,
  pool: { min: 2, max: 10 },
  debug: process.env.NODE_ENV === "development",
  migrations: { path: "./src/migrations", transactional: true }
});
```

**NestJS integration:**
```typescript
@Module({
  imports: [MikroOrmModule.forRoot(), MikroOrmModule.forFeature({ entities: [User, Order] })],
})
export class AppModule {}
```

## Performance

**Use `populate` instead of lazy loading:**
```typescript
// GOOD: eager load in one query
const user = await em.findOne(User, id, { populate: ["orders"] });

// BAD: N+1 queries via lazy loading
const user = await em.findOne(User, id);
await user.orders.init();  // separate query
```

**Batch inserts:**
```typescript
const users = [new User("alice"), new User("bob")];
em.persist(users);
await em.flush();  // single INSERT with multiple rows
```

**Use `em.clear()` after bulk operations** to prevent identity map from consuming excessive memory.

## Security

Parameterized queries by default. Never use `em.execute()` with string interpolation.

**Validation with class-validator:**
```typescript
@Entity()
export class User {
  @Property()
  @IsEmail()
  email!: string;
}
```

## Testing

```typescript
const orm = await MikroORM.init({
  ...testConfig,
  allowGlobalContext: true,
  connect: false
});
const generator = orm.getSchemaGenerator();
await generator.refreshDatabase();

afterEach(async () => {
  await generator.clearDatabase();
});
```

Use a test database (PostgreSQL via Testcontainers or SQLite for fast unit tests). Fork the EntityManager per test to ensure isolation.

## Dos
- Fork the EntityManager per HTTP request — never share across requests.
- Use `populate` for eager loading — it generates efficient JOINs or batched queries.
- Use the Unit of Work pattern — modify entities and call `flush()` once, not after each change.
- Use migrations for schema changes — `SchemaGenerator` is for development only.
- Use `QueryBuilder` for complex aggregations instead of raw SQL where possible.
- Use `em.clear()` after bulk operations to prevent memory leaks in the identity map.
- Use `@Filter` decorator for global query filters (soft deletes, tenant isolation).

## Don'ts
- Don't share EntityManager across requests — it causes stale data and memory leaks.
- Don't call `flush()` multiple times in one transaction — batch changes and flush once.
- Don't use `SchemaGenerator.updateSchema()` in production — use migrations.
- Don't ignore the identity map — loading the same entity twice returns the cached instance, not a fresh query.
- Don't mix `em.execute()` with raw SQL and identity-mapped entities in the same unit of work.
- Don't lazy-load collections in loops — use `populate` to avoid N+1 queries.
- Don't use `allowGlobalContext: true` in production — it disables the per-request EntityManager safety check.
