# Axum + PostgreSQL (sqlx PgPool)

> Axum-specific patterns for PostgreSQL using `sqlx::PgPool` as Axum state.
> Generic SQLx query patterns are in `persistence/sqlx.md`.

## Integration Setup

```toml
# Cargo.toml
[dependencies]
axum = "0.8"
sqlx = { version = "0.8", features = ["runtime-tokio-rustls", "postgres", "uuid", "chrono", "migrate"] }
tokio = { version = "1", features = ["full"] }
```

Set `DATABASE_URL` in the environment — SQLx uses it at compile time for `query!` macros.

## PgPool as Axum State

```rust
use sqlx::PgPool;
use sqlx::postgres::{PgConnectOptions, PgPoolOptions};
use std::str::FromStr;

#[derive(Clone)]
pub struct AppState {
    pub db: PgPool,
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let opts = PgConnectOptions::from_str(&std::env::var("DATABASE_URL")?)?
        .application_name("my-service");

    let pool = PgPoolOptions::new()
        .max_connections(20)
        .min_connections(2)
        .acquire_timeout(std::time::Duration::from_secs(5))
        .idle_timeout(std::time::Duration::from_secs(600))
        .connect_with(opts)
        .await?;

    // Run embedded migrations before serving traffic
    sqlx::migrate!("./migrations").run(&pool).await?;

    let state = AppState { db: pool };
    let app = Router::new()
        .route("/users/:id", get(get_user))
        .with_state(state);

    let listener = tokio::net::TcpListener::bind("0.0.0.0:8080").await?;
    axum::serve(listener, app).await?;
    Ok(())
}
```

## Extracting Pool in Handlers

```rust
use axum::extract::State;

async fn get_user(
    State(state): State<AppState>,
    Path(id): Path<uuid::Uuid>,
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

## Connection Config Notes

- `acquire_timeout`: surface connection exhaustion quickly rather than hanging requests
- `idle_timeout`: release idle connections after 10 minutes to avoid PostgreSQL's `idle` connection limit
- `application_name`: visible in `pg_stat_activity` for query attribution
- `min_connections`: pre-warm the pool on startup to avoid cold-start latency on first requests

## Scaffolder Patterns

```yaml
patterns:
  state: "src/state.rs"
  pool_setup: "src/db/pool.rs"
  model: "src/model/{entity}.rs"
  repository: "src/repository/{entity}_repository.rs"
  migrations_dir: "migrations/"
```

## Additional Dos/Don'ts

- DO run `sqlx::migrate!` at startup before `axum::serve` — no traffic before schema is ready
- DO use `fetch_optional` over `fetch_one` for lookups by ID and map `None` to `AppError::NotFound`
- DO derive `Clone` on `AppState` — Axum requires it because state is shared across handler clones
- DON'T hold a `PgConnection` checked out from the pool across an `await` that does I/O unrelated to the DB
- DON'T hardcode pool sizes — read `DATABASE_MAX_CONNECTIONS` from the environment with a sensible default
- DON'T disable SSL (`sslmode=disable`) in production — use `sslmode=require` or `verify-full`
