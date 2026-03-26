# SeaORM Best Practices

## Overview
SeaORM is an async-first ORM for Rust built on top of SQLx, supporting PostgreSQL, MySQL, MariaDB, and SQLite. Use it for Rust web backends (Actix Web, Axum, Rocket) needing a full-featured ORM with migrations, relations, and code generation. SeaORM excels at compile-time type safety and async query building. Avoid it for simple applications where SQLx raw queries suffice, or for embedded/no-std environments.

## Architecture Patterns

**Entity definition (generated or hand-written):**
```rust
use sea_orm::entity::prelude::*;

#[derive(Clone, Debug, PartialEq, DeriveEntityModel)]
#[sea_orm(table_name = "users")]
pub struct Model {
    #[sea_orm(primary_key)]
    pub id: i32,
    #[sea_orm(unique)]
    pub email: String,
    pub name: String,
    pub created_at: DateTimeWithTimeZone,
}

#[derive(Copy, Clone, Debug, EnumIter, DeriveRelation)]
pub enum Relation {
    #[sea_orm(has_many = "super::order::Entity")]
    Orders,
}

impl Related<super::order::Entity> for Entity {
    fn to() -> RelationDef {
        Relation::Orders.def()
    }
}

impl ActiveModelBehavior for ActiveModel {}
```

**Querying with filters:**
```rust
let users = user::Entity::find()
    .filter(user::Column::Email.contains("@example.com"))
    .order_by_desc(user::Column::CreatedAt)
    .limit(20)
    .all(&db)
    .await?;
```

**Insert and update:**
```rust
let new_user = user::ActiveModel {
    email: Set("alice@example.com".to_string()),
    name: Set("Alice".to_string()),
    ..Default::default()
};
let result = user::Entity::insert(new_user).exec_with_returning(&db).await?;

let mut user: user::ActiveModel = user::Entity::find_by_id(1).one(&db).await?.unwrap().into();
user.name = Set("Alice Smith".to_string());
user.update(&db).await?;
```

**Transactions:**
```rust
let txn = db.begin().await?;
let order = order::ActiveModel { user_id: Set(user_id), total: Set(Decimal::ZERO), ..Default::default() };
let order = order::Entity::insert(order).exec_with_returning(&txn).await?;
txn.commit().await?;
```

**Anti-pattern — loading all columns when only a few are needed:** Use custom select structs or `into_tuple()` for partial selects to reduce data transfer.

## Configuration

**Database connection:**
```rust
use sea_orm::{Database, ConnectOptions};
use std::time::Duration;

let mut opt = ConnectOptions::new("postgres://app:pass@localhost/mydb");
opt.max_connections(20)
   .min_connections(5)
   .connect_timeout(Duration::from_secs(5))
   .idle_timeout(Duration::from_secs(600))
   .sqlx_logging(cfg!(debug_assertions));

let db = Database::connect(opt).await?;
```

**Migration setup (sea-orm-cli):**
```bash
sea-orm-cli migrate generate add_users_table
sea-orm-cli migrate up
sea-orm-cli generate entity -o entity/src --with-serde both
```

## Performance

**Partial selects:**
```rust
#[derive(FromQueryResult)]
struct UserSummary {
    id: i32,
    email: String,
}

let summaries = user::Entity::find()
    .select_only()
    .column(user::Column::Id)
    .column(user::Column::Email)
    .into_model::<UserSummary>()
    .all(&db).await?;
```

**Batch inserts:**
```rust
let models: Vec<user::ActiveModel> = data.into_iter()
    .map(|u| user::ActiveModel { email: Set(u.email), name: Set(u.name), ..Default::default() })
    .collect();
user::Entity::insert_many(models).exec_without_returning(&db).await?;
```

**Pagination:**
```rust
let paginator = user::Entity::find().paginate(&db, 50);
let total_pages = paginator.num_pages().await?;
let page = paginator.fetch_page(0).await?;
```

## Security

SeaORM uses parameterized queries via SQLx — all values are bind parameters. Never use `Statement::from_string()` with user input.

**Connection string from environment:**
```rust
let database_url = std::env::var("DATABASE_URL").expect("DATABASE_URL must be set");
```

## Testing

```rust
#[cfg(test)]
mod tests {
    use sea_orm::{DbBackend, MockDatabase};

    #[tokio::test]
    async fn test_find_user() {
        let db = MockDatabase::new(DbBackend::Postgres)
            .append_query_results([[user::Model {
                id: 1,
                email: "test@example.com".into(),
                name: "Test".into(),
                created_at: chrono::Utc::now().into(),
            }]])
            .into_connection();

        let result = user::Entity::find_by_id(1).one(&db).await.unwrap();
        assert_eq!(result.unwrap().email, "test@example.com");
    }
}
```

For integration tests, use Testcontainers with a real PostgreSQL instance. Run migrations before tests. SeaORM's `MockDatabase` is useful for unit tests but doesn't validate SQL correctness.

## Dos
- Use `sea-orm-cli generate entity` to generate entities from existing schemas — keeps code in sync.
- Use transactions for multi-table operations — SeaORM's `begin()`/`commit()` pattern is clean.
- Use `into_model::<CustomStruct>()` for partial selects to reduce data transfer.
- Use `insert_many()` for batch inserts — it generates a single multi-row INSERT.
- Use migrations (`sea-orm-cli migrate`) for all schema changes in production.
- Use `#[sea_orm(default_value = "...")]` for database defaults instead of application-level defaults.
- Enable SQLx logging in development to catch N+1 queries.

## Don'ts
- Don't use `Statement::from_string()` with user input — it bypasses parameterization.
- Don't load all columns when only a few are needed — use partial selects.
- Don't skip migrations — `sea-orm-cli` migrations are versioned and reversible.
- Don't use `MockDatabase` as a substitute for integration tests — it doesn't validate SQL.
- Don't ignore connection pool settings — default pool sizes may be too small for production.
- Don't use blocking database operations in async contexts — SeaORM is async-first for a reason.
- Don't define relations without foreign key constraints in the database — the ORM trusts the schema.
