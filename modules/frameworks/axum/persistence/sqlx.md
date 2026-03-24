# Axum + SQLx

> Axum-specific patterns for SQLx. Extends generic Axum conventions.
> Generic Axum patterns are NOT repeated here.

## Integration Setup

`Cargo.toml`:
```toml
[dependencies]
sqlx = { version = "0.8", features = ["runtime-tokio-rustls", "postgres", "uuid", "chrono", "migrate"] }
```

Set `DATABASE_URL` environment variable — SQLx uses it at compile time for `query!` macros.

## PgPool as Axum State

```rust
use sqlx::PgPool;

#[derive(Clone)]
pub struct AppState {
    pub db: PgPool,
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let pool = PgPool::connect_with(
        PgConnectOptions::from_str(&std::env::var("DATABASE_URL")?)?
            .application_name("my-service"),
    )
    .await?;

    // Run migrations at startup
    sqlx::migrate!("./migrations").run(&pool).await?;

    let state = AppState { db: pool };
    let app = Router::new()
        .route("/users/:id", get(get_user))
        .with_state(state);

    Ok(())
}
```

## Connection Pool Config

```rust
let pool = PgPoolOptions::new()
    .max_connections(20)
    .min_connections(2)
    .acquire_timeout(Duration::from_secs(5))
    .idle_timeout(Duration::from_secs(600))
    .connect(&database_url)
    .await?;
```

## Compile-Time Query Checking

```rust
// Checked at compile time against DATABASE_URL — schema changes break compilation
async fn get_user(
    State(state): State<AppState>,
    Path(id): Path<Uuid>,
) -> Result<Json<User>, AppError> {
    let user = sqlx::query_as!(
        User,
        "SELECT id, name, email, created_at FROM users WHERE id = $1",
        id
    )
    .fetch_optional(&state.db)
    .await?
    .ok_or(AppError::NotFound)?;

    Ok(Json(user))
}
```

## FromRow Derive

```rust
#[derive(Debug, sqlx::FromRow, serde::Serialize)]
pub struct User {
    pub id: Uuid,
    pub name: String,
    pub email: String,
    pub created_at: chrono::DateTime<chrono::Utc>,
}
```

## Transactions

```rust
async fn create_user_with_audit(pool: &PgPool, data: CreateUserDto) -> sqlx::Result<User> {
    let mut tx = pool.begin().await?;

    let user = sqlx::query_as!(
        User,
        "INSERT INTO users (name, email) VALUES ($1, $2) RETURNING id, name, email, created_at",
        data.name, data.email
    )
    .fetch_one(&mut *tx)
    .await?;

    sqlx::query!("INSERT INTO audit_logs (action, user_id) VALUES ('USER_CREATED', $1)", user.id)
        .execute(&mut *tx)
        .await?;

    tx.commit().await?;
    Ok(user)
}
```

## Scaffolder Patterns

```yaml
patterns:
  pool_setup: "src/db/pool.rs"
  model: "src/model/{entity}.rs"
  repository: "src/repository/{entity}_repository.rs"
  migrations_dir: "migrations/"
  migration: "migrations/{timestamp}_{description}.sql"
```

## Additional Dos/Don'ts

- DO use `query!` / `query_as!` macros for compile-time verification on hot paths
- DO use `query` / `query_as` (non-macro) for dynamic queries where compile-time check is impractical
- DO configure pool `acquire_timeout` to surface connection exhaustion quickly
- DON'T use `.unwrap()` on `fetch_one` — use `fetch_optional` and return `404` on `None`
- DON'T hold transactions open across HTTP round-trips
- DON'T set `DATABASE_URL` to a test DB in CI without `SQLX_OFFLINE=true` or a live DB
