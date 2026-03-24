# Axum + Diesel Migrations

> Axum-specific patterns for Diesel migrations. Extends generic Axum conventions.
> Diesel persistence setup is covered in `persistence/diesel.md`. Not repeated here.

## Integration Setup

```bash
cargo install diesel_cli --no-default-features --features postgres
diesel setup   # creates migrations/ directory and diesel.toml
```

`diesel.toml`:
```toml
[print_schema]
file = "src/schema.rs"
custom_type_derives = ["diesel::query_builder::QueryId"]
```

## Creating Migrations

```bash
diesel migration generate create_users
# Creates:
#   migrations/{timestamp}_create_users/up.sql
#   migrations/{timestamp}_create_users/down.sql
```

`up.sql`:
```sql
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    email TEXT NOT NULL UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

`down.sql`:
```sql
DROP TABLE users;
```

## Embed Migrations in Binary

Use `diesel_migrations` to bundle SQL files into the compiled binary:

```toml
[dependencies]
diesel_migrations = "2.2"
```

```rust
// src/db/migrations.rs
use diesel_migrations::{embed_migrations, EmbeddedMigrations, MigrationHarness};

pub const MIGRATIONS: EmbeddedMigrations = embed_migrations!("migrations");

pub fn run_migrations(conn: &mut PgConnection) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    conn.run_pending_migrations(MIGRATIONS)?;
    Ok(())
}
```

## Run at Startup

```rust
#[tokio::main]
async fn main() {
    // Run migrations using a dedicated sync connection (migrations are sync)
    let mut conn = PgConnection::establish(&database_url).expect("Failed to connect for migrations");
    run_migrations(&mut conn).expect("Migration failed");

    // Then create the async pool for the app
    let pool = create_pool(&database_url);
    // ...
}
```

## CI Verification

```bash
# Verify no pending migrations (redo all, check for errors)
diesel migration redo

# Or with a fresh database in CI:
diesel database reset
diesel migration run
```

GitHub Actions step:
```yaml
- name: Check migrations
  run: |
    diesel migration run
    diesel print-schema > /tmp/schema.rs
    diff src/schema.rs /tmp/schema.rs || (echo "schema.rs is out of date" && exit 1)
```

## Scaffolder Patterns

```yaml
patterns:
  migrations_module: "src/db/migrations.rs"
  migration_up: "migrations/{timestamp}_{name}/up.sql"
  migration_down: "migrations/{timestamp}_{name}/down.sql"
  schema: "src/schema.rs"
  diesel_config: "diesel.toml"
```

## Additional Dos/Don'ts

- DO embed migrations in the binary so deployment is a single artifact
- DO always write a correct `down.sql` — rollback capability is required
- DO run `diesel print-schema` after every migration and commit updated `schema.rs`
- DON'T edit `schema.rs` manually — always regenerate it with `diesel print-schema`
- DON'T run migration and async pool setup with the same connection object
- DON'T use `diesel database reset` in production — it drops and recreates the DB
