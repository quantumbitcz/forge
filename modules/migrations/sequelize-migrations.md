# Sequelize Migrations Best Practices

## Overview
Sequelize CLI provides migration support for Sequelize ORM projects. Use it when your Node.js application uses Sequelize for database access and you want migrations tightly integrated with your ORM models. Migrations are JavaScript files with `up` and `down` functions using Sequelize's `QueryInterface`.

## Conventions

### Migration File Structure
```bash
migrations/
├── 20260326100000-create-users.js
├── 20260326100100-create-orders.js
└── 20260326100200-add-email-index.js
```

### Migration Example
```javascript
module.exports = {
  async up(queryInterface, Sequelize) {
    await queryInterface.createTable("users", {
      id: { type: Sequelize.INTEGER, autoIncrement: true, primaryKey: true },
      email: { type: Sequelize.STRING(255), allowNull: false, unique: true },
      name: { type: Sequelize.STRING(255), allowNull: false },
      created_at: { type: Sequelize.DATE, defaultValue: Sequelize.fn("NOW") },
      updated_at: { type: Sequelize.DATE, defaultValue: Sequelize.fn("NOW") }
    });
    await queryInterface.addIndex("users", ["email"]);
  },

  async down(queryInterface) {
    await queryInterface.dropTable("users");
  }
};
```

### Commands
```bash
npx sequelize-cli migration:generate --name add-users-table
npx sequelize-cli db:migrate
npx sequelize-cli db:migrate:undo
npx sequelize-cli db:migrate:undo:all
npx sequelize-cli db:migrate:status
```

## Configuration

```javascript
// .sequelizerc
const path = require("path");
module.exports = {
  config: path.resolve("config", "database.js"),
  "models-path": path.resolve("src", "models"),
  "migrations-path": path.resolve("migrations"),
  "seeders-path": path.resolve("seeders")
};
```

## Dos
- Always write both `up` and `down` methods — rollback support is essential for safe deployments.
- Use `queryInterface.sequelize.transaction` for multi-step migrations to ensure atomicity.
- Test migrations against a fresh database and via rollback-then-reapply before merging.
- Use `addIndex` / `removeIndex` in separate migrations from table creation for clarity.
- Keep migrations small and focused — one logical schema change per migration file.
- Use `db:migrate:status` in CI to verify all migrations are applied before tests.
- Use timestamps in filenames (default) to avoid merge conflicts.

## Don'ts
- Don't modify already-applied migrations — create new ones to alter the schema.
- Don't use `sync({ force: true })` or `sync({ alter: true })` in production — always use migrations.
- Don't put seed data in migrations — use seeders (`db:seed:all`) for test/demo data.
- Don't skip the `down` method — CI and development depend on reversible migrations.
- Don't use raw SQL in migrations unless `QueryInterface` doesn't support the operation.
- Don't assume migration order across branches — timestamp collisions need manual resolution.
- Don't reference model definitions in migrations — models change over time; migrations should be self-contained.
