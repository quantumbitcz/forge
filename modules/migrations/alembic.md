# Alembic Best Practices

## Overview
Alembic is the migration tool for SQLAlchemy, designed for Python projects. Use it when your project uses SQLAlchemy ORM or Core and you want schema changes derived from model definitions. Avoid relying solely on `--autogenerate` for production migrations — always review and adjust the generated output before committing.

## Architecture Patterns

### Directory structure
```
alembic/
├── env.py                  # Migration environment (imports your models)
├── script.py.mako          # Template for new revisions
└── versions/
    ├── 20240101_abc123_create_users.py
    ├── 20240115_def456_add_email_index.py
    └── 20240201_ghi789_create_orders.py
alembic.ini
```

### Revision naming
Configure `file_template` in `alembic.ini` for date-prefixed names:
```ini
file_template = %%(year)d%%(month).2d%%(day).2d_%%(rev)s_%%(slug)s
```

### env.py — import your models
```python
from myapp.models import Base   # ensures all models are registered
target_metadata = Base.metadata
```

### Autogenerate workflow
```bash
alembic revision --autogenerate -m "add user profile columns"
# ALWAYS review the generated file before committing
alembic upgrade head
```

### Typical revision file
```python
"""add user profile columns

Revision ID: def456abc789
Revises: abc123def456
Create Date: 2024-01-15
"""
from alembic import op
import sqlalchemy as sa

def upgrade() -> None:
    op.add_column("users", sa.Column("bio", sa.Text(), nullable=True))
    op.add_column("users", sa.Column("avatar_url", sa.String(512), nullable=True))

def downgrade() -> None:
    op.drop_column("users", "avatar_url")
    op.drop_column("users", "bio")
```

### Data migrations with op.execute()
```python
def upgrade() -> None:
    # Add column
    op.add_column("users", sa.Column("full_name", sa.String(255), nullable=True))
    # Backfill data
    op.execute("UPDATE users SET full_name = first_name || ' ' || last_name")
    # Apply constraint after backfill
    op.alter_column("users", "full_name", nullable=False)

def downgrade() -> None:
    op.drop_column("users", "full_name")
```

### Batch operations (SQLite ALTER TABLE workaround)
```python
with op.batch_alter_table("users") as batch_op:
    batch_op.add_column(sa.Column("phone", sa.String(20), nullable=True))
    batch_op.create_index("idx_users_phone", ["phone"])
```

### Branching and merging
```bash
alembic branches          # show diverged heads
alembic merge -m "merge feature branches" abc123 def456
alembic upgrade head      # applies all heads including merge
```

## Configuration

### alembic.ini
```ini
[alembic]
script_location = alembic
sqlalchemy.url = postgresql+asyncpg://%(DB_USER)s:%(DB_PASSWORD)s@%(DB_HOST)s/%(DB_NAME)s
```

### Async support (env.py)
```python
from sqlalchemy.ext.asyncio import AsyncEngine

def run_migrations_online() -> None:
    connectable = engine_from_config(config.get_section(config.config_ini_section),
                                     prefix="sqlalchemy.", poolclass=pool.NullPool)
    with connectable.connect() as connection:
        context.configure(connection=connection, target_metadata=target_metadata)
        with context.begin_transaction():
            context.run_migrations()
```

## Performance

### Zero-downtime: decouple DDL from constraint enforcement
```python
def upgrade() -> None:
    # Step 1: nullable column (deploy N)
    op.add_column("orders", sa.Column("region", sa.String(50), nullable=True))

def upgrade() -> None:
    # Step 2: backfill + enforce (deploy N+1)
    op.execute("UPDATE orders SET region = 'default' WHERE region IS NULL")
    op.alter_column("orders", "region", nullable=False)
```

### Offline mode (generate SQL without DB connection)
```bash
alembic upgrade head --sql > migration.sql   # review before applying
```

## Security
- Store DB credentials in environment variables, not in `alembic.ini`
- Use `%(DB_PASSWORD)s` interpolation from env in `alembic.ini`
- Restrict the migration user to DDL operations; the app user needs DML only

## Testing
```bash
# Verify upgrade + downgrade round-trip in CI
alembic upgrade head
alembic downgrade base
alembic upgrade head
```
Use `pytest-alembic` or Testcontainers with a fresh PostgreSQL container for each CI run. Test that `downgrade` and re-`upgrade` produces identical schema.

## Dos
- Always write a `downgrade()` function, even for irreversible migrations (raise an error with explanation)
- Review `--autogenerate` output before committing — it misses server defaults, check constraints, and custom types
- Use `op.execute()` with raw SQL for data migrations; keep them idempotent
- Use batch mode for any SQLite schema changes
- Pin Alembic version in `requirements.txt` to avoid autogenerate behavior drift
- Run `alembic check` in CI to detect un-migrated model changes
- Use `include_schemas=True` in `env.py` for multi-schema databases

## Don'ts
- Never delete a revision file after it has been applied to any environment
- Don't run `alembic upgrade head` with an unreviewed autogenerated file in production
- Avoid mixing business logic Python code in migration files — keep migrations as pure schema/data operations
- Don't rely on `alembic downgrade base` as a first-class rollback strategy in production; have a snapshot/point-in-time restore plan
- Avoid using `server_default` in models expecting autogenerate to detect it consistently — always verify
- Never share a single migration head across multiple long-lived feature branches without merging
