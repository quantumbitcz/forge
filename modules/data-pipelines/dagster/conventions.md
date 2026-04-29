# Dagster — Asset-Based Pipelines & IO Managers

> Support tier: community

## Overview

Dagster models data pipelines as software-defined assets rather than task graphs. Each asset declares its dependencies, and Dagster infers the execution graph. IO Managers abstract storage (database, file system, cloud), enabling the same pipeline logic to run against different backends. Dagster provides a development UI (Dagit/Dagster UI), job scheduling, partitioning, and observability out of the box.

## Architecture Patterns

### Software-Defined Assets

```python
from dagster import asset, AssetExecutionContext

@asset
def raw_users(context: AssetExecutionContext) -> pd.DataFrame:
    """Extract users from source API."""
    context.log.info("Fetching users from API")
    return fetch_users_from_api()

@asset
def cleaned_users(raw_users: pd.DataFrame) -> pd.DataFrame:
    """Clean and validate user data."""
    return raw_users.dropna(subset=["email"]).drop_duplicates("user_id")

@asset
def user_metrics(cleaned_users: pd.DataFrame) -> pd.DataFrame:
    """Compute user engagement metrics."""
    return compute_metrics(cleaned_users)
```

Define each data artifact as an `@asset`. Dagster automatically builds the dependency graph from function signatures. Assets are the unit of materialization, monitoring, and lineage.

### IO Managers

```python
from dagster import IOManager, io_manager

class PostgresIOManager(IOManager):
    def handle_output(self, context, obj):
        table_name = context.asset_key.path[-1]
        obj.to_sql(table_name, engine, if_exists="replace", index=False)

    def load_input(self, context):
        table_name = context.asset_key.path[-1]
        return pd.read_sql_table(table_name, engine)

@io_manager
def postgres_io_manager():
    return PostgresIOManager()
```

Use IO Managers to decouple pipeline logic from storage implementation. Swap IO Managers between environments (in-memory for tests, Postgres for staging, Snowflake for production).

### Partitions

```python
from dagster import asset, DailyPartitionsDefinition

daily_partitions = DailyPartitionsDefinition(start_date="2024-01-01")

@asset(partitions_def=daily_partitions)
def daily_events(context: AssetExecutionContext) -> pd.DataFrame:
    date = context.partition_key
    return fetch_events_for_date(date)
```

Use partitions for time-series data. Dagster tracks materialization status per partition, enabling selective backfills and incremental processing.

## Configuration

- Define resources (database connections, API clients) as Dagster resources and inject them via `Definitions`.
- Use `EnvVar` for sensitive configuration: `resource_defs={"db": PostgresResource(host=EnvVar("DB_HOST"))}`.
- Organize assets into groups for the Dagster UI: `@asset(group_name="analytics")`.
- Use `dagster.yaml` for instance configuration (run storage, event log, compute log).
- Configure `workspace.yaml` to point at code locations — each code location is an independent Python module.

## Performance

- Use partitioned assets for large datasets — Dagster only re-materializes changed partitions.
- Leverage caching: IO Managers should skip materialization when upstream data has not changed.
- Use `@multi_asset` to produce multiple related outputs in a single computation step.
- Configure concurrency limits on assets that access rate-limited external systems.
- Use lazy loading for heavyweight dependencies — import inside asset functions, not at module level.

## Security

- Never hardcode credentials — use Dagster `EnvVar` resources for sensitive configuration.
- Scope resource permissions per environment (dev/staging/prod).
- Use Dagster Cloud's branch deployments for PR previews with isolated data.
- Audit asset materializations via the event log — Dagster tracks who triggered each materialization.

## Testing

- Test assets as plain Python functions by passing mock inputs directly.
- Use `build_asset_context()` to create test contexts with mock resources.
- Swap IO Managers for tests: use `mem_io_manager` or custom in-memory managers.
- Validate asset dependencies: `assert asset_a in asset_b.input_names`.
- Use `materialize([asset_a, asset_b], resources={"io_manager": mem_io_manager})` for integration tests.

## Dos
- Model each data artifact as an `@asset` with explicit type annotations.
- Use IO Managers to abstract storage — pipeline logic should not know about databases or file systems.
- Partition time-series assets for incremental processing and selective backfills.
- Inject dependencies via Dagster resources — never import configuration at module level.
- Group related assets for UI organization and lineage clarity.
- Use `context.log` for structured logging within assets.

## Don'ts
- Don't hardcode file paths or database connections inside asset functions — use IO Managers and resources.
- Don't create assets without type annotations — Dagster uses types for validation and UI display.
- Don't skip partitioning for time-series data — full re-materializations are wasteful and slow.
- Don't use global state (module-level variables) to share data between assets — use IO Managers or asset dependencies.
- Don't ignore the Dagster event log — it provides lineage, timing, and failure information for debugging.
- Don't define all assets in a single file — organize by domain or data layer for maintainability.
