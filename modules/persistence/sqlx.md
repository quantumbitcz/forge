# SQLx Best Practices

## Overview
SQLx is a Rust async SQL library with compile-time checked queries. Use it when you want raw SQL control with strong type safety — queries are verified against a live database at compile time via the `sqlx-data.json` offline cache, catching type mismatches before you ship. Prefer it over Diesel when your queries are complex joins, CTEs, or window functions that don't map naturally to a query DSL.

## Architecture Patterns

### Compile-time checked queries
```rust
// Checked at compile time against the database schema
let user = sqlx::query_as!(
    User,
    r#"SELECT id, email, created_at FROM users WHERE id = $1"#,
    user_id
)
.fetch_optional(&pool)
.await?;
```

### FromRow derive for result mapping
```rust
#[derive(sqlx::FromRow, Debug, Clone)]
pub struct User {
    pub id: Uuid,
    pub email: String,
    pub created_at: DateTime<Utc>,
}

#[derive(sqlx::FromRow)]
pub struct UserSummary {
    pub id: Uuid,
    pub email: String,
}
```

### Repository with connection pool
```rust
pub struct UserRepository {
    pool: PgPool,
}

impl UserRepository {
    pub async fn find_by_id(&self, id: Uuid) -> Result<Option<User>> {
        sqlx::query_as!(
            User,
            "SELECT id, email, created_at FROM users WHERE id = $1",
            id
        )
        .fetch_optional(&self.pool)
        .await
        .map_err(Into::into)
    }

    pub async fn insert(&self, id: Uuid, email: &str) -> Result<User> {
        sqlx::query_as!(
            User,
            "INSERT INTO users (id, email) VALUES ($1, $2) RETURNING *",
            id,
            email
        )
        .fetch_one(&self.pool)
        .await
        .map_err(Into::into)
    }
}
```

### Transactions
```rust
let mut tx = pool.begin().await?;

sqlx::query!("INSERT INTO accounts (id, balance) VALUES ($1, $2)", id, 0)
    .execute(&mut *tx)
    .await?;

sqlx::query!("INSERT INTO audit_log (account_id, event) VALUES ($1, $2)", id, "created")
    .execute(&mut *tx)
    .await?;

tx.commit().await?;
```

## Configuration

```toml
# Cargo.toml
[dependencies]
sqlx = { version = "0.8", features = ["postgres", "uuid", "chrono", "runtime-tokio"] }
```

```bash
# Generate offline cache for CI (no live DB needed at compile time)
cargo sqlx prepare --database-url $DATABASE_URL
# Commit .sqlx/ directory to VCS
```

```rust
// Connection pool setup (e.g., in main.rs or app state)
let pool = PgPoolOptions::new()
    .max_connections(10)
    .min_connections(2)
    .acquire_timeout(Duration::from_secs(5))
    .connect(&database_url)
    .await?;
```

## Performance

- Use `fetch_one` / `fetch_optional` / `fetch_all` appropriately — avoid fetching all rows when you only need one.
- Use `query_scalar!` for single-value queries (counts, exists checks) to avoid row mapping overhead.
- Stream large result sets with `fetch()` (returns a `Stream`) instead of `fetch_all()` to avoid loading everything into memory.
- Batch inserts with `UNNEST` or `INSERT ... SELECT` rather than looping individual inserts.

```rust
// Streaming large result sets
let mut stream = sqlx::query_as!(Event, "SELECT * FROM events ORDER BY created_at")
    .fetch(&pool);

while let Some(event) = stream.try_next().await? {
    process(event).await?;
}

// Scalar query
let count: i64 = sqlx::query_scalar!("SELECT COUNT(*) FROM users")
    .fetch_one(&pool)
    .await?
    .unwrap_or(0);
```

## Security

- Always use parameterized queries (`$1`, `$2` placeholders) — never interpolate user input into SQL strings.
- Use `SQLX_OFFLINE=true` in CI to prevent accidental connection to production databases.
- Apply role-based access at the DB level; the application user should not have DDL privileges.
- Store `DATABASE_URL` in environment variables or a secrets manager; never hardcode in source.

## Testing

```rust
#[sqlx::test]
async fn test_insert_and_find(pool: PgPool) {
    // sqlx::test automatically runs migrations and wraps in a transaction
    let repo = UserRepository::new(pool);
    let id = Uuid::new_v4();

    repo.insert(id, "test@example.com").await.unwrap();
    let found = repo.find_by_id(id).await.unwrap();

    assert!(found.is_some());
    assert_eq!(found.unwrap().email, "test@example.com");
}
```

The `#[sqlx::test]` macro spins up an isolated database per test, runs migrations, and rolls back after completion — no test pollution.

## Dos
- Commit the `.sqlx/` offline cache directory so CI can compile without a live database.
- Use `#[sqlx::test]` for repository-level tests — each test gets an isolated schema.
- Use `query_as!` and `FromRow` for typed result mapping; avoid raw `Row` access except for truly dynamic queries.
- Set `max_connections` and `acquire_timeout` on the pool to bound resource usage.
- Use `fetch()` with `StreamExt::try_next()` for large result sets to limit memory usage.

## Don'ts
- Don't use `query()` with string formatting of user input — always use bind parameters.
- Don't share a `sqlx::Transaction` across `await` points in different tasks.
- Don't forget to call `tx.commit()` — a dropped transaction silently rolls back.
- Don't use `SQLX_OFFLINE=false` in production CI — compile against the offline cache, not a live DB.
- Don't use `.fetch_all()` on unbounded result sets — stream instead.
