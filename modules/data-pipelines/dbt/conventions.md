# dbt — Data Transformation & Testing

> Support tier: community

## Overview

dbt (data build tool) transforms data in the warehouse using SQL SELECT statements. Models define transformations, tests validate data quality, and documentation lives alongside code. dbt compiles SQL, manages dependencies between models, and executes transformations in the target warehouse (Snowflake, BigQuery, Redshift, Postgres, Databricks). dbt Core is open-source CLI; dbt Cloud adds scheduling, CI, and IDE.

## Architecture Patterns

### Model Layers

```
models/
  staging/           # 1:1 with source tables, renaming & type casting only
    stg_users.sql
    stg_orders.sql
  intermediate/      # Business logic joins and aggregations
    int_user_orders.sql
  marts/             # Final consumption tables for BI/analytics
    dim_users.sql
    fct_orders.sql
```

Follow the staging -> intermediate -> marts pattern. Staging models clean raw source data. Intermediate models apply business logic. Marts are the final tables consumed by BI tools and applications.

### Model Definition

```sql
-- models/staging/stg_users.sql
WITH source AS (
    SELECT * FROM {{ source('raw', 'users') }}
),
renamed AS (
    SELECT
        id AS user_id,
        email,
        created_at,
        COALESCE(updated_at, created_at) AS updated_at
    FROM source
)
SELECT * FROM renamed
```

Use CTEs for readability. Reference sources with `{{ source() }}` and upstream models with `{{ ref() }}`. Never use hardcoded table names — always use `ref()` or `source()` for dependency tracking.

### Schema Tests

```yaml
# models/staging/schema.yml
version: 2
models:
  - name: stg_users
    description: "Cleaned user data from the raw users table."
    columns:
      - name: user_id
        description: "Unique user identifier."
        tests:
          - unique
          - not_null
      - name: email
        description: "User email address."
        tests:
          - not_null
          - unique
```

Every model must have a schema YAML file with at minimum `unique` and `not_null` tests on primary keys. Add `accepted_values`, `relationships`, and custom tests for business logic validation.

### Sources

```yaml
# models/staging/sources.yml
version: 2
sources:
  - name: raw
    schema: raw_data
    tables:
      - name: users
        loaded_at_field: _loaded_at
        freshness:
          warn_after: {count: 12, period: hour}
          error_after: {count: 24, period: hour}
```

Declare all source tables with freshness checks. Use `dbt source freshness` in CI to detect stale data before running transformations.

## Configuration

- `dbt_project.yml`: project name, version, model paths, materialization defaults.
- `profiles.yml`: warehouse connection configuration (per environment). Never commit to Git — use `~/.dbt/profiles.yml` or environment variables.
- Set default materializations per directory: `staging: view`, `intermediate: ephemeral` or `view`, `marts: table` or `incremental`.
- Use `vars` in `dbt_project.yml` for environment-specific configuration (date ranges, feature flags).
- Configure `packages.yml` for dbt packages (dbt_utils, dbt_expectations, etc.) and run `dbt deps` to install.

## Performance

- Use `incremental` materialization for large fact tables — only process new/changed rows.
- Partition incremental models by date for efficient merge operations.
- Use `ephemeral` materialization for intermediate CTEs that do not need their own table.
- Limit `SELECT *` to staging models only — marts and intermediate models should list columns explicitly for schema stability.
- Use `dbt build --select <model>+` to run only the changed model and its downstream dependents.
- Monitor warehouse query costs: large cross-joins and full table scans in dbt models are common cost drivers.

## Security

- Never commit `profiles.yml` with credentials to Git — use environment variables or a secrets manager.
- Use dbt exposures to document which dashboards and applications consume each model.
- Restrict warehouse permissions: dbt should have `CREATE`, `INSERT`, `SELECT` on target schemas but not `DROP DATABASE`.
- Use `{{ env_var('DB_PASSWORD') }}` in `profiles.yml` for credential injection.
- Audit column-level access: ensure PII columns are masked or excluded in mart models.

## Testing

- Run `dbt test` in CI for every PR that modifies model SQL or schema YAML.
- Add `unique` and `not_null` tests on every primary key.
- Use `dbt_expectations` package for advanced tests (row count ranges, column value distributions).
- Test source freshness with `dbt source freshness` before running transformations.
- Use `dbt build` (models + tests together) rather than separate `dbt run` + `dbt test` to catch issues faster.
- Write custom tests for complex business rules: `tests/assert_positive_revenue.sql`.

## Dos
- Follow the staging/intermediate/marts layer convention for model organization.
- Use `{{ ref() }}` and `{{ source() }}` for all table references — never hardcode schema.table names.
- Add `unique` and `not_null` tests on primary keys for every model.
- Document every model and column in `schema.yml` files.
- Use `incremental` materialization for large tables to reduce warehouse costs.
- Declare sources with freshness checks in `sources.yml`.
- List columns explicitly in intermediate and mart models — avoid `SELECT *` beyond staging.

## Don'ts
- Don't use `SELECT *` in intermediate or mart models — it hides schema changes and breaks downstream consumers.
- Don't hardcode table names — use `{{ ref() }}` for models and `{{ source() }}` for raw tables.
- Don't skip schema tests — untested models can silently propagate data quality issues.
- Don't commit `profiles.yml` with database credentials to Git.
- Don't create models without `schema.yml` documentation — undocumented models are unusable by other teams.
- Don't use `table` materialization for frequently updated large datasets — use `incremental` instead.
- Don't run `dbt run` without `dbt test` — always validate data quality after transformation.
