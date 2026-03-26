# Sequelize Best Practices

## Overview
Sequelize is a promise-based Node.js ORM supporting PostgreSQL, MySQL, MariaDB, SQLite, and SQL Server. Use it for Express/NestJS backends needing a mature, feature-rich ORM with migrations, associations, and transaction support. Avoid Sequelize for new TypeScript projects where Prisma or Drizzle offer better type safety, or for applications needing raw query performance (use Knex or native drivers).

## Architecture Patterns

**Model definition (class-based):**
```typescript
import { DataTypes, Model } from "sequelize";

class User extends Model {
  declare id: number;
  declare email: string;
  declare passwordHash: string;
}

User.init({
  id: { type: DataTypes.INTEGER, autoIncrement: true, primaryKey: true },
  email: { type: DataTypes.STRING(255), allowNull: false, unique: true },
  passwordHash: { type: DataTypes.STRING(255), allowNull: false }
}, { sequelize, tableName: "users", timestamps: true, underscored: true });
```

**Associations:**
```typescript
User.hasMany(Order, { foreignKey: "userId", as: "orders" });
Order.belongsTo(User, { foreignKey: "userId", as: "user" });
Order.hasMany(OrderItem, { foreignKey: "orderId", as: "items" });
```

**Eager loading with includes:**
```typescript
const users = await User.findAll({
  include: [{ model: Order, as: "orders", include: [{ model: OrderItem, as: "items" }] }],
  where: { email: { [Op.like]: "%@example.com" } },
  order: [["createdAt", "DESC"]],
  limit: 20
});
```

**Transactions:**
```typescript
await sequelize.transaction(async (t) => {
  const order = await Order.create({ userId, total: 0 }, { transaction: t });
  await OrderItem.bulkCreate(items.map(i => ({ ...i, orderId: order.id })), { transaction: t });
  await order.update({ total: items.reduce((s, i) => s + i.price * i.qty, 0) }, { transaction: t });
});
```

**Anti-pattern — using `findAll` without `limit` on large tables:** Sequelize loads all results into memory. Always paginate with `limit` and `offset` (or cursor-based pagination for better performance).

## Configuration

**Connection setup:**
```typescript
import { Sequelize } from "sequelize";

const sequelize = new Sequelize(process.env.DATABASE_URL, {
  dialect: "postgres",
  pool: { max: 20, min: 5, acquire: 30000, idle: 10000 },
  logging: process.env.NODE_ENV === "development" ? console.log : false,
  dialectOptions: {
    ssl: process.env.NODE_ENV === "production" ? { rejectUnauthorized: true } : false
  }
});
```

**Migration setup (Sequelize CLI):**
```bash
npx sequelize-cli migration:generate --name add-users-table
npx sequelize-cli db:migrate
npx sequelize-cli db:migrate:undo
```

## Performance

**Use `attributes` to select only needed columns:**
```typescript
const users = await User.findAll({ attributes: ["id", "email"] });
```

**Bulk operations for batch writes:**
```typescript
await User.bulkCreate(users, { updateOnDuplicate: ["email", "name"] });
```

**Raw queries for complex operations:**
```typescript
const [results] = await sequelize.query(
  "SELECT u.id, COUNT(o.id) as order_count FROM users u LEFT JOIN orders o ON u.id = o.user_id GROUP BY u.id",
  { type: QueryTypes.SELECT }
);
```

**Index definitions in models:**
```typescript
User.init({ /* fields */ }, {
  sequelize,
  indexes: [
    { fields: ["email"], unique: true },
    { fields: ["created_at"] },
    { fields: ["status", "created_at"] }
  ]
});
```

## Security

**Parameterized queries (built-in):** Sequelize parameterizes all queries by default. Never use `sequelize.literal()` with user input.

**Input validation at model level:**
```typescript
email: {
  type: DataTypes.STRING,
  validate: { isEmail: true, notEmpty: true }
}
```

**Scopes for row-level filtering:**
```typescript
User.addScope("active", { where: { deletedAt: null } });
User.scope("active").findAll();
```

## Testing

Use **Testcontainers** or an in-memory SQLite for fast unit tests:
```typescript
const testSequelize = new Sequelize("sqlite::memory:", { logging: false });

beforeEach(async () => {
  await testSequelize.sync({ force: true });
});
```

For integration tests, use the same database engine as production (PostgreSQL via Testcontainers). Test transactions, associations, and constraint violations explicitly.

## Dos
- Use `underscored: true` for snake_case column names matching database conventions.
- Use transactions for multi-table operations — Sequelize's managed transactions auto-rollback on error.
- Use `bulkCreate` with `updateOnDuplicate` for upsert patterns instead of find-then-update loops.
- Define indexes in model definitions to keep them version-controlled alongside the schema.
- Use scopes for reusable query filters (soft deletes, tenant isolation, status filtering).
- Use migrations for all schema changes — never use `sync({ alter: true })` in production.
- Enable query logging in development to catch N+1 queries and unnecessary joins.

## Don'ts
- Don't use `sync({ force: true })` in production — it drops and recreates tables, losing all data.
- Don't use `sequelize.literal()` with user-supplied input — it bypasses parameterization and enables SQL injection.
- Don't load entire tables without `limit` — Sequelize loads all results into memory.
- Don't use `findAll` inside a loop — batch with `findAll({ where: { id: ids } })` instead.
- Don't mix raw queries and model queries in the same transaction without careful ordering.
- Don't skip `paranoid: true` for soft-delete models — hard deletes lose audit trails.
- Don't define associations in both directions redundantly — define once and use `as` aliases.
