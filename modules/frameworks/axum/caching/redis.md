# Axum + Redis (redis-rs)

> Axum-specific Redis patterns using `redis-rs` connection manager.
> Extends generic Axum conventions.

## Integration Setup

```toml
# Cargo.toml
[dependencies]
axum = "0.8"
redis = { version = "0.27", features = ["tokio-comp", "connection-manager"] }
serde_json = "1"
tokio = { version = "1", features = ["full"] }
```

## Connection Manager Setup

```rust
use redis::aio::ConnectionManager;
use redis::Client;

pub async fn create_redis(url: &str) -> anyhow::Result<ConnectionManager> {
    let client = Client::open(url)?;
    let cm = ConnectionManager::new(client).await?;
    Ok(cm)
}
```

`ConnectionManager` automatically reconnects on dropped connections — prefer it over a raw `Connection` for long-running services.

## Redis in Axum State

```rust
#[derive(Clone)]
pub struct AppState {
    pub db: PgPool,
    pub cache: ConnectionManager,
}
```

## Cache-Aside Pattern in Handler

```rust
use redis::AsyncCommands;

async fn get_product(
    State(state): State<AppState>,
    Path(id): Path<uuid::Uuid>,
) -> Result<Json<Product>, AppError> {
    let cache_key = format!("product:{id}");
    let mut cache = state.cache.clone();

    // 1. Try cache
    if let Ok(cached) = cache.get::<_, String>(&cache_key).await {
        if let Ok(product) = serde_json::from_str::<Product>(&cached) {
            return Ok(Json(product));
        }
    }

    // 2. Load from DB
    let product = sqlx::query_as!(Product, "SELECT * FROM products WHERE id = $1", id)
        .fetch_optional(&state.db)
        .await?
        .ok_or(AppError::NotFound)?;

    // 3. Populate cache (fire-and-forget)
    if let Ok(serialized) = serde_json::to_string(&product) {
        let _: Result<(), _> = cache
            .set_ex(&cache_key, serialized, 300) // 5 minutes TTL
            .await;
    }

    Ok(Json(product))
}

async fn update_product(
    State(state): State<AppState>,
    Path(id): Path<uuid::Uuid>,
    Json(payload): Json<UpdateProductRequest>,
) -> Result<Json<Product>, AppError> {
    let product = update_product_in_db(&state.db, id, payload).await?;

    // Invalidate cache
    let _: Result<(), _> = state.cache.clone()
        .del(format!("product:{id}"))
        .await;

    Ok(Json(product))
}
```

## Scaffolder Patterns

```yaml
patterns:
  redis_setup: "src/cache/redis.rs"
  state: "src/state.rs"           # ConnectionManager added to AppState
  cache_helpers: "src/cache/helpers.rs"
```

## Additional Dos/Don'ts

- DO use `ConnectionManager` instead of `Pool` for simplicity — it handles single-connection reconnection automatically
- DO clone `ConnectionManager` per handler call — it is cheap (`Arc`-backed) and required for `&mut self` async commands
- DO treat all Redis errors as cache misses on reads — never propagate cache failures to the HTTP response
- DO set TTL on every `set_ex` call — unbounded keys exhaust memory
- DON'T block the Tokio runtime with synchronous Redis calls — always use `AsyncCommands` trait methods
- DON'T store session or auth tokens in a shared cache key without namespacing by user ID
- DON'T use `KEYS *` for pattern scans — use `SCAN` with a cursor
