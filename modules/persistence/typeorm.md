# TypeORM Best Practices

## Overview
TypeORM is a mature ORM for TypeScript/Node.js supporting both Active Record and Data Mapper patterns. Use it for NestJS or TypeScript projects needing a full-featured ORM with migration generation and multiple database backends. Prefer Data Mapper pattern in all new code — Active Record couples entities to the database framework and makes testing harder.

## Architecture Patterns

### Entity with Data Mapper
```typescript
import { Entity, PrimaryGeneratedColumn, Column, ManyToOne,
         OneToMany, CreateDateColumn, Index, JoinColumn } from "typeorm";

@Entity("users")
export class User {
  @PrimaryGeneratedColumn()
  id: number;

  @Column({ unique: true, length: 255 })
  @Index()
  email: string;

  @Column({ length: 100 })
  name: string;

  @CreateDateColumn({ name: "created_at" })
  createdAt: Date;

  @OneToMany(() => Order, (order) => order.user)
  orders: Order[];
}

@Entity("orders")
@Index(["userId", "status"])
export class Order {
  @PrimaryGeneratedColumn()
  id: number;

  @Column({ name: "user_id" })
  userId: number;

  @ManyToOne(() => User, (user) => user.orders, { onDelete: "CASCADE" })
  @JoinColumn({ name: "user_id" })
  user: User;

  @Column("decimal", { precision: 10, scale: 2 })
  total: number;

  @Column({ default: "pending", length: 20 })
  status: string;
}
```

### Repository Pattern (Data Mapper)
```typescript
import { Injectable } from "@nestjs/common";
import { InjectRepository } from "@nestjs/typeorm";
import { Repository } from "typeorm";

@Injectable()
export class OrderRepository {
  constructor(
    @InjectRepository(Order)
    private readonly repo: Repository<Order>
  ) {}

  async findByIdWithUser(id: number): Promise<Order | null> {
    return this.repo.findOne({
      where: { id },
      relations: { user: true },
    });
  }

  async findByCustomer(userId: number): Promise<Order[]> {
    return this.repo
      .createQueryBuilder("order")
      .leftJoinAndSelect("order.user", "user")
      .where("order.userId = :userId", { userId })
      .orderBy("order.createdAt", "DESC")
      .getMany();
  }
}
```

### QueryBuilder for Complex Queries
```typescript
// Pagination with total count in a single round-trip
async findPaginated(page: number, limit: number): Promise<[Order[], number]> {
  return this.repo
    .createQueryBuilder("order")
    .leftJoinAndSelect("order.user", "user")
    .leftJoinAndSelect("order.items", "item")
    .where("order.status != :status", { status: "cancelled" })
    .orderBy("order.createdAt", "DESC")
    .skip((page - 1) * limit)
    .take(limit)
    .getManyAndCount();  // tuple: [rows, total]
}
```

## Configuration

```typescript
// data-source.ts
import { DataSource } from "typeorm";

export const AppDataSource = new DataSource({
  type:        "postgres",
  url:         process.env.DATABASE_URL,
  entities:    ["dist/**/*.entity.js"],
  migrations:  ["dist/migrations/*.js"],
  synchronize: false,              // NEVER true in production
  logging:     process.env.NODE_ENV === "development" ? ["query"] : ["error"],
  poolSize:    10,
  extra: {
    max:               10,
    idleTimeoutMillis: 30000,
    connectionTimeoutMillis: 5000,
  },
});
```

## Performance

### Eager vs Lazy vs Join Loading
```typescript
// Eager loading on entity — loads on every findOne/findMany (dangerous on large graphs)
@OneToMany(() => Order, (o) => o.user, { eager: true })
orders: Order[];  // avoid unless always needed

// Explicit join with QueryBuilder — best for controlled loading
const users = await userRepo
  .createQueryBuilder("user")
  .leftJoinAndSelect("user.orders", "order",
                     "order.status = :status", { status: "pending" })
  .getMany();

// Lazy loading (Promises) — TypeORM lazy relations are Promises
// Avoid: produces N+1 if accessed in loops; use QueryBuilder joins instead
```

### Batch Inserts and Upserts
```typescript
// insert().values() — bypasses entity lifecycle hooks (faster for bulk)
await dataSource.createQueryBuilder()
  .insert()
  .into(Order)
  .values(orders)
  .orUpdate(["status", "total"], ["id"])  // upsert by PK
  .execute();

// save() with array — uses entity lifecycle but batches by default
await orderRepo.save(orders, { chunk: 100 });
```

### Migration Generation
```bash
# Generate migration from entity diff
npx typeorm migration:generate src/migrations/AddOrderIndex -d dist/data-source.js

# Run pending migrations
npx typeorm migration:run -d dist/data-source.js

# Revert last migration
npx typeorm migration:revert -d dist/data-source.js
```

## Security

```typescript
// SAFE: QueryBuilder always parameterizes :param bindings
repo.createQueryBuilder("order")
    .where("order.userId = :userId", { userId: userInput })

// SAFE: repository methods are always safe
repo.findOne({ where: { email: userInput } })

// UNSAFE: never interpolate user input into QueryBuilder strings
// .where(`order.status = '${userInput}'`)  // SQL injection!

// Row-level security: always scope to tenant
repo.createQueryBuilder("order")
    .where("order.tenantId = :tid", { tid: currentTenant.id })
    .andWhere("order.id = :id", { id: requestedId })
```

## Testing

```typescript
// Unit test with mock repository
describe("OrderService", () => {
  let service: OrderService;
  let repo: jest.Mocked<Repository<Order>>;

  beforeEach(async () => {
    const module = await Test.createTestingModule({
      providers: [
        OrderService,
        { provide: getRepositoryToken(Order),
          useValue: { findOne: jest.fn(), save: jest.fn() } },
      ],
    }).compile();
    service = module.get(OrderService);
    repo    = module.get(getRepositoryToken(Order));
  });

  it("returns null for unknown order", async () => {
    repo.findOne.mockResolvedValue(null);
    expect(await service.findById(999)).toBeNull();
  });
});

// Integration test with Testcontainers
describe("OrderRepository integration", () => {
  let dataSource: DataSource;
  beforeAll(async () => {
    const pg = await new PostgreSqlContainer("postgres:16-alpine").start();
    dataSource = new DataSource({
      type: "postgres", url: pg.getConnectionUri(),
      entities: [Order, User], synchronize: true,
    });
    await dataSource.initialize();
  });
  afterAll(() => dataSource.destroy());
});
```

## Dos
- Use Data Mapper pattern exclusively — inject `Repository<T>` via DI, not `BaseEntity` inheritance.
- Use `createQueryBuilder` for complex queries with joins, subqueries, or aggregations.
- Set `synchronize: false` in production — use `migration:generate` + `migration:run` instead.
- Use `getManyAndCount()` for paginated endpoints to get total count in one query.
- Add `@Index` decorators (or composite `@Index([...])` on entity class) for frequently filtered columns.
- Use `orUpdate` in `insert()` for idempotent upsert operations.
- Keep migrations in version control and review them before applying to production.

## Don'ts
- Don't use `synchronize: true` in production — it will silently drop/alter columns.
- Don't use Active Record pattern (`BaseEntity`) in NestJS applications — tightly couples entities to TypeORM.
- Don't use `{ eager: true }` on relations without understanding the query cost.
- Don't use lazy relations (Promises) in async code without careful N+1 management.
- Don't interpolate user input into QueryBuilder `where()` strings — use bound parameters.
- Don't use `save()` on detached entities for bulk updates — use `update()` or `createQueryBuilder().update()`.
- Don't skip `@Index` on foreign key columns — TypeORM does not add them automatically.
